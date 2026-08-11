// ignore_for_file: unreachable_from_main

import 'dart:convert';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';
import 'package:noir/src/ffi/abi_contract.dart';

const openTuiNativeAssetName = 'src/ffi/native_asset_bindings.dart';
const _manifestPath = 'native_manifest.json';

Future<void> main(List<String> args) async {
  await build(args, buildOpenTuiNativeAsset);
}

Future<void> buildOpenTuiNativeAsset(
  BuildInput input,
  BuildOutputBuilder output, {
  NativeAssetBuildEnvironment environment = const NativeAssetBuildEnvironment(),
}) async {
  if (!input.config.buildCodeAssets) {
    return;
  }

  final manifest = NativeManifest.fromFile(
    File.fromUri(input.packageRoot.resolve(_manifestPath)),
  );
  final entry = manifest.entryFor(
    input.config.code.targetOS,
    input.config.code.targetArchitecture,
  );
  final library = await resolveNativeAsset(
    packageRoot: input.packageRoot,
    entry: entry,
    environment: environment,
  );

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: openTuiNativeAssetName,
      linkMode: DynamicLoadingBundled(),
      file: library,
    ),
  );
}

/// Resolves the bundled OpenTUI binary for [entry] and verifies its SHA-256.
///
/// The published package ships prebuilt, SHA-256-verified binaries for every
/// supported target, so the bundled binary is the single supported resolution
/// path. A missing file means a corrupt or unmaterialized checkout rather than
/// a recoverable condition, so it fails loudly.
Future<Uri> resolveNativeAsset({
  required Uri packageRoot,
  required NativeManifestEntry entry,
  NativeAssetBuildEnvironment environment = const NativeAssetBuildEnvironment(),
}) async {
  final bundled = packageRoot.resolve(entry.path);
  if (!environment.fileExists(bundled)) {
    throw NativeAssetBuildException(
      'No bundled OpenTUI binary for ${entry.key} at ${entry.path}. '
      'The package ships prebuilt binaries for all supported targets '
      '(macos/linux/windows on x64/arm64); a missing file indicates a corrupt '
      'or unmaterialized checkout.',
    );
  }
  await environment.verifySha256(bundled, entry.sha256);
  return bundled;
}

final class NativeManifest {
  NativeManifest._(this.abiVersion, this.assets);

  factory NativeManifest.fromJson(Map<String, Object?> json) {
    final abiVersion = json['abiVersion'];
    final assetsJson = json['assets'];
    if (abiVersion is! int || assetsJson is! Map<String, Object?>) {
      throw const NativeAssetBuildException(
        'native_manifest.json must contain abiVersion and assets.',
      );
    }
    if (abiVersion != expectedOpenTuiAbiVersion) {
      throw NativeAssetBuildException(
        'native_manifest.json ABI version $abiVersion does not match '
        'Dart ABI $expectedOpenTuiAbiVersion.',
      );
    }

    return NativeManifest._(
      abiVersion,
      assetsJson.map((key, value) {
        if (value is! Map<String, Object?>) {
          throw NativeAssetBuildException('Manifest entry $key must be a map.');
        }
        return MapEntry(key, NativeManifestEntry.fromJson(key, value));
      }),
    );
  }

  factory NativeManifest.fromFile(File file) {
    if (!file.existsSync()) {
      throw NativeAssetBuildException('Missing native manifest: ${file.path}');
    }
    return NativeManifest.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  final int abiVersion;
  final Map<String, NativeManifestEntry> assets;

  NativeManifestEntry entryFor(OS os, Architecture architecture) {
    final key = '${_manifestOs(os)}-${_manifestArch(architecture)}';
    final entry = assets[key];
    if (entry == null) {
      throw NativeAssetBuildException(
        'No OpenTUI native asset manifest entry for $key.',
      );
    }
    return entry;
  }
}

final class NativeManifestEntry {
  const NativeManifestEntry({
    required this.key,
    required this.os,
    required this.arch,
    required this.path,
    required this.url,
    required this.archivePath,
    required this.minimumOsVersion,
    required this.sha256,
  });

  factory NativeManifestEntry.fromJson(String key, Map<String, Object?> json) {
    final os = json['os'];
    final arch = json['arch'];
    final path = json['path'];
    final url = json['url'];
    final archivePath = json['archivePath'];
    final minimumOsVersion = json['minimumOsVersion'];
    final sha256 = json['sha256'];
    if (os is! String ||
        arch is! String ||
        path is! String ||
        url is! String ||
        archivePath is! String ||
        sha256 is! String) {
      throw NativeAssetBuildException('Manifest entry $key is incomplete.');
    }
    if (os == 'macos') {
      if (minimumOsVersion is! String ||
          !RegExp(r'^\d+\.\d+$').hasMatch(minimumOsVersion) ||
          minimumOsVersion != '15.0') {
        throw NativeAssetBuildException(
          'Manifest entry $key must declare minimumOsVersion 15.0.',
        );
      }
    } else if (json.containsKey('minimumOsVersion')) {
      throw NativeAssetBuildException(
        'Manifest entry $key must not declare minimumOsVersion.',
      );
    }
    return NativeManifestEntry(
      key: key,
      os: os,
      arch: arch,
      path: path,
      url: Uri.parse(url),
      archivePath: archivePath,
      minimumOsVersion: minimumOsVersion as String?,
      sha256: sha256,
    );
  }

  final String key;
  final String os;
  final String arch;
  final String path;

  /// Provenance: the upstream source the bundled binary was published from.
  /// Recorded for auditability and `scripts/fetch_opentui_binaries.dart`;
  /// the build hook resolves the bundled file, not this URL.
  final Uri url;
  final String archivePath;
  final String? minimumOsVersion;
  final String sha256;
}

class NativeAssetBuildEnvironment {
  const NativeAssetBuildEnvironment();

  bool fileExists(Uri uri) => File.fromUri(uri).existsSync();

  Future<void> verifySha256(Uri uri, String expected) async {
    final file = File.fromUri(uri);
    if (!file.existsSync()) {
      throw NativeAssetBuildException('Native binary is missing: ${file.path}');
    }
    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (actual != expected) {
      throw NativeAssetIntegrityException(
        'SHA-256 mismatch for ${file.path}: expected $expected, got $actual.',
      );
    }
  }
}

class NativeAssetBuildException implements Exception {
  const NativeAssetBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NativeAssetIntegrityException extends NativeAssetBuildException {
  const NativeAssetIntegrityException(super.message);
}

String _manifestOs(OS os) {
  if (os == OS.macOS) return 'macos';
  if (os == OS.linux) return 'linux';
  if (os == OS.windows) return 'windows';
  throw NativeAssetBuildException('Unsupported target OS: ${os.name}.');
}

String _manifestArch(Architecture architecture) {
  if (architecture == Architecture.arm64) return 'arm64';
  if (architecture == Architecture.x64) return 'x64';
  throw NativeAssetBuildException(
    'Unsupported target architecture: ${architecture.name}.',
  );
}
