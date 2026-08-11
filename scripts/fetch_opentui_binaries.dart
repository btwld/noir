#!/usr/bin/env dart
// ignore_for_file: cascade_invocations

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:noir/src/ffi/abi_contract.dart';

const _manifestPath = 'native_manifest.json';
const _downloadBaseUrl =
    'https://raw.githubusercontent.com/leoafarias/opentui/'
    'ddbc9edf81a1fa89961135ab0481df15054ed4b0/dart-native-assets';

const _targets = [
  _NativeTarget('macos', 'x64', 'libopentui.dylib'),
  _NativeTarget('macos', 'arm64', 'libopentui.dylib'),
  _NativeTarget('linux', 'x64', 'libopentui.so'),
  _NativeTarget('linux', 'arm64', 'libopentui.so'),
  _NativeTarget('windows', 'x64', 'libopentui.dll'),
  _NativeTarget('windows', 'arm64', 'libopentui.dll'),
];

/// Verifies or refreshes the native asset manifest from checked-in binaries.
///
/// Usage:
///   dart run scripts/fetch_opentui_binaries.dart [--verify-only] [--verify-urls]
///
/// The build hook is the runtime distribution path. This script is developer
/// tooling for keeping native_manifest.json aligned with `native/<os>/<arch>/`.
void main(List<String> args) async {
  final verifyOnly = args.contains('--verify-only');
  final verifyUrls = args.contains('--verify-urls');
  final unknownArgs = args
      .where((arg) => arg != '--verify-only' && arg != '--verify-urls')
      .toList();
  if (unknownArgs.isNotEmpty) {
    stderr.writeln('Unknown option(s): ${unknownArgs.join(', ')}');
    exit(64);
  }

  final tool = _NativeManifestTool();
  try {
    if (verifyOnly) {
      await tool.verifyManifest();
    } else {
      await tool.refreshManifest();
    }
    if (verifyUrls) {
      await tool.verifyManifestUrls();
    }
  } catch (error) {
    stderr.writeln('Native manifest check failed: $error');
    exit(1);
  }
}

final class _NativeManifestTool {
  Future<void> refreshManifest() async {
    final entries = <String, Object?>{};
    var totalSize = 0;

    for (final target in _targets) {
      final file = File(target.path);
      if (!file.existsSync()) {
        throw StateError('Missing native binary: ${target.path}');
      }
      totalSize += file.lengthSync();
      entries[target.key] = {
        'os': target.os,
        'arch': target.arch,
        'path': target.path,
        'url': '$_downloadBaseUrl/${target.assetPath}',
        'archivePath': '',
        'minimumOsVersion': ?target.minimumOsVersion,
        'sha256': await _sha256(file),
      };
    }

    final manifest = {
      'abiVersion': expectedOpenTuiAbiVersion,
      'assets': entries,
    };
    await File(_manifestPath).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    stdout.writeln('Updated $_manifestPath for ${_targets.length} binaries.');
    stdout.writeln('Total binary size: ${_formatBytes(totalSize)}');
  }

  Future<void> verifyManifest() async {
    final manifestFile = File(_manifestPath);
    if (!manifestFile.existsSync()) {
      throw StateError('Missing $_manifestPath');
    }

    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    if (manifest['abiVersion'] != expectedOpenTuiAbiVersion) {
      throw StateError(
        'Expected abiVersion $expectedOpenTuiAbiVersion, '
        'found ${manifest['abiVersion']}',
      );
    }
    final assets = manifest['assets'];
    if (assets is! Map<String, Object?>) {
      throw StateError('$_manifestPath assets must be a map');
    }
    final expectedKeys = _targets.map((target) => target.key).toSet();
    final actualKeys = assets.keys.toSet();
    final unexpectedKeys = actualKeys.difference(expectedKeys);
    if (unexpectedKeys.isNotEmpty) {
      throw StateError(
        'Unexpected manifest entries: ${unexpectedKeys.join(', ')}',
      );
    }

    for (final target in _targets) {
      final entry = assets[target.key];
      if (entry is! Map<String, Object?>) {
        throw StateError('Missing manifest entry ${target.key}');
      }
      if (entry['os'] != target.os) {
        throw StateError('Manifest entry ${target.key} has wrong os');
      }
      if (entry['arch'] != target.arch) {
        throw StateError('Manifest entry ${target.key} has wrong arch');
      }
      if (entry['path'] != target.path) {
        throw StateError('Manifest entry ${target.key} has wrong path');
      }
      if (entry['url'] != '$_downloadBaseUrl/${target.assetPath}') {
        throw StateError('Manifest entry ${target.key} has wrong url');
      }
      if (entry['archivePath'] != '') {
        throw StateError('Manifest entry ${target.key} must use direct URL');
      }
      if (target.minimumOsVersion case final minimumOsVersion?) {
        if (entry['minimumOsVersion'] != minimumOsVersion) {
          throw StateError(
            'Manifest entry ${target.key} must declare minimumOsVersion '
            '$minimumOsVersion',
          );
        }
      } else if (entry.containsKey('minimumOsVersion')) {
        throw StateError(
          'Manifest entry ${target.key} must not declare minimumOsVersion',
        );
      }
      final file = File(target.path);
      if (!file.existsSync()) {
        throw StateError('Missing native binary: ${target.path}');
      }
      final expectedHash = entry['sha256'];
      final actualHash = await _sha256(file);
      if (expectedHash != actualHash) {
        throw StateError(
          'SHA-256 mismatch for ${target.path}: '
          'expected $expectedHash, got $actualHash',
        );
      }
    }

    stdout.writeln('Verified $_manifestPath and ${_targets.length} binaries.');
  }

  Future<void> verifyManifestUrls() async {
    final manifestFile = File(_manifestPath);
    if (!manifestFile.existsSync()) {
      throw StateError('Missing $_manifestPath');
    }

    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    final assets = manifest['assets'];
    if (assets is! Map<String, Object?>) {
      throw StateError('$_manifestPath assets must be a map');
    }

    final client = HttpClient();
    try {
      for (final target in _targets) {
        final entry = assets[target.key];
        if (entry is! Map<String, Object?>) {
          throw StateError('Missing manifest entry ${target.key}');
        }
        final url = entry['url'];
        final expectedHash = entry['sha256'];
        if (url is! String || expectedHash is! String) {
          throw StateError(
            'Manifest entry ${target.key} must contain url and sha256',
          );
        }

        final request = await client.getUrl(Uri.parse(url));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok) {
          throw StateError(
            'Manifest URL for ${target.key} returned HTTP '
            '${response.statusCode}: $url',
          );
        }

        final bytes = await response.fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
        final actualHash = sha256.convert(bytes).toString();
        if (actualHash != expectedHash) {
          throw StateError(
            'Manifest URL SHA-256 mismatch for ${target.key}: '
            'expected $expectedHash, got $actualHash',
          );
        }
      }
    } finally {
      client.close();
    }

    stdout.writeln(
      'Verified ${_targets.length} manifest download URLs and hashes.',
    );
  }

  Future<String> _sha256(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

final class _NativeTarget {
  const _NativeTarget(this.os, this.arch, this.fileName);

  final String os;
  final String arch;
  final String fileName;

  String get key => '$os-$arch';
  String get path => 'native/$os/$arch/$fileName';
  String get assetPath => '$os/$arch/$fileName';
  String? get minimumOsVersion => os == 'macos' ? '15.0' : null;
}
