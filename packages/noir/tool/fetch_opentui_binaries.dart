#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

const _manifestPath = 'native_manifest.json';
const _schemaVersion = 1;
const _repository = 'https://github.com/anomalyco/opentui';
const _tag = 'v0.5.1';
const _commit = 'ad9a818d7a9d73f3386e92a445d0feb4b395c69e';
const _maximumArchiveBytes = 64 * 1024 * 1024;
const _usage =
    'Usage: dart run tool/fetch_opentui_binaries.dart '
    '<--verify-only|--verify-upstream|--refresh-from-upstream>';

const _targets = <_NativeTarget>[
  _NativeTarget(
    os: 'macos',
    arch: 'arm64',
    path: 'native/macos/arm64/libopentui.dylib',
    archiveName: 'opentui-native-v0.5.1-darwin-arm64.zip',
    archiveSha256:
        '4318f9a545b765698a4d43b3d90b0fd501717edcd442e6efe24453e164ecd122',
    archiveMember: 'libopentui.dylib',
    librarySha256:
        '196d4994f8ff02a2b8c6e5581eadf315040ff8cfdb487791a7f7ec01669ee10f',
    minimumOsVersion: '13.0',
  ),
  _NativeTarget(
    os: 'macos',
    arch: 'x64',
    path: 'native/macos/x64/libopentui.dylib',
    archiveName: 'opentui-native-v0.5.1-darwin-x64.zip',
    archiveSha256:
        '804c1c45b058c6251cbb3019ffba6e422451be18ad11325b1b896601d9f07a61',
    archiveMember: 'libopentui.dylib',
    librarySha256:
        '6de2ff94531ecef296a7d7cb5bb299bb6ee3763f3f6a8b9fefbaf2c706e4304c',
    minimumOsVersion: '13.0',
  ),
  _NativeTarget(
    os: 'linux',
    arch: 'arm64',
    path: 'native/linux/arm64/libopentui.so',
    archiveName: 'opentui-native-v0.5.1-linux-arm64.zip',
    archiveSha256:
        'edc644e32c1532d065af72bcd0f3bbaf2393a2d923e70870ac71f4580b223a0e',
    archiveMember: 'libopentui.so',
    librarySha256:
        '378de47d86f187f565798f0d4da831db5fa75be19574dae0e0b04f5df4316794',
    minimumGlibcVersion: '2.17',
  ),
  _NativeTarget(
    os: 'linux',
    arch: 'x64',
    path: 'native/linux/x64/libopentui.so',
    archiveName: 'opentui-native-v0.5.1-linux-x64.zip',
    archiveSha256:
        'd1b760cf568dc46fd377c83308ebcb9c08e91cbe3f9d688a4b4403bfe0c411de',
    archiveMember: 'libopentui.so',
    librarySha256:
        '8db7922e8e765015a0a95a2d7bc5b12af9cce2a3dc78479a381edf81bd922807',
    minimumGlibcVersion: '2.17',
  ),
  _NativeTarget(
    os: 'windows',
    arch: 'arm64',
    path: 'native/windows/arm64/libopentui.dll',
    archiveName: 'opentui-native-v0.5.1-windows-arm64.zip',
    archiveSha256:
        '6bff48a5c0ec85f476e3873962852954c21f7f9037315f9c23cdb39f4016eac6',
    archiveMember: 'opentui.dll',
    librarySha256:
        'f7f98743f98d0f95583160fb31cb76adee951a1eb0f67fd489cc841c44d0c402',
  ),
  _NativeTarget(
    os: 'windows',
    arch: 'x64',
    path: 'native/windows/x64/libopentui.dll',
    archiveName: 'opentui-native-v0.5.1-windows-x64.zip',
    archiveSha256:
        'df0521164cf1257d8c7a8e215f3e291064141ec18c6b7d8fe36f5d74798693af',
    archiveMember: 'opentui.dll',
    librarySha256:
        '8c8b15103d70373c0e1313bd0a51fee360c66280ca063cc19936d8d20cd167c7',
  ),
];

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !const <String>{
        '--verify-only',
        '--verify-upstream',
        '--refresh-from-upstream',
      }.contains(args.single)) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final tool = _NativeAssetTool();
  try {
    switch (args.single) {
      case '--verify-only':
        await tool.verifyLocal();
      case '--verify-upstream':
        await tool.verifyUpstream();
      case '--refresh-from-upstream':
        await tool.refreshFromUpstream();
    }
  } catch (error) {
    stderr.writeln('OpenTUI asset operation failed: $error');
    exitCode = 1;
  }
}

final class _NativeAssetTool {
  Future<void> verifyLocal() async {
    await _readAndValidateManifest();
    for (final target in _targets) {
      final file = File(target.path);
      if (!file.existsSync()) {
        throw StateError('Missing native binary: ${target.path}');
      }
      await _verifyHash(
        file.readAsBytesSync(),
        target.librarySha256,
        target.path,
      );
    }
    stdout.writeln('Verified $_manifestPath and ${_targets.length} binaries.');
  }

  Future<void> verifyUpstream() async {
    await _readAndValidateManifest();
    for (final target in _targets) {
      await _downloadAndExtract(target);
      stdout.writeln('Verified upstream archive for ${target.key}.');
    }
  }

  Future<void> refreshFromUpstream() async {
    await _readAndValidateManifest();
    final verifiedLibraries = <_NativeTarget, Uint8List>{};
    for (final target in _targets) {
      verifiedLibraries[target] = await _downloadAndExtract(target);
    }

    final stagedFiles = <File>[];
    try {
      for (final entry in verifiedLibraries.entries) {
        final destination = File(entry.key.path);
        await destination.parent.create(recursive: true);
        final staged = File(
          '${destination.path}.staged-$pid-${DateTime.now().microsecondsSinceEpoch}',
        );
        await staged.writeAsBytes(entry.value, flush: true);
        await _verifyHash(
          await staged.readAsBytes(),
          entry.key.librarySha256,
          staged.path,
        );
        stagedFiles.add(staged);
      }

      for (var index = 0; index < _targets.length; index += 1) {
        await stagedFiles[index].rename(_targets[index].path);
      }
    } finally {
      for (final staged in stagedFiles) {
        if (staged.existsSync()) staged.deleteSync();
      }
    }

    await verifyLocal();
    stdout.writeln('Refreshed ${_targets.length} official OpenTUI libraries.');
  }

  Future<Map<String, Object?>> _readAndValidateManifest() async {
    final file = File(_manifestPath);
    if (!file.existsSync()) throw StateError('Missing $_manifestPath');
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Manifest root must be a JSON object.');
    }
    const rootKeys = <String>{
      'schemaVersion',
      'repository',
      'tag',
      'commit',
      'assets',
    };
    if (!decoded.keys.toSet().containsAll(rootKeys) ||
        !rootKeys.containsAll(decoded.keys)) {
      throw FormatException('Manifest root keys must be exactly $rootKeys.');
    }
    if (decoded['schemaVersion'] != _schemaVersion ||
        decoded['repository'] != _repository ||
        decoded['tag'] != _tag ||
        decoded['commit'] != _commit) {
      throw const FormatException(
        'Manifest source identity does not match canonical OpenTUI v0.5.1.',
      );
    }
    final assets = decoded['assets'];
    if (assets is! Map<String, Object?> ||
        assets.keys.toSet().length != _targets.length ||
        !assets.keys.toSet().containsAll(
          _targets.map((target) => target.key),
        )) {
      throw const FormatException(
        'Manifest assets do not match supported targets.',
      );
    }
    for (final target in _targets) {
      final entry = assets[target.key];
      if (entry is! Map<String, Object?>) {
        throw FormatException(
          'Manifest entry ${target.key} must be an object.',
        );
      }
      target.validateManifestEntry(entry);
    }
    return decoded;
  }

  Future<Uint8List> _downloadAndExtract(_NativeTarget target) async {
    final archiveBytes = await _download(target.archiveUrl);
    await _verifyHash(
      archiveBytes,
      target.archiveSha256,
      target.archiveUrl.toString(),
    );

    final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    final members = archive.files
        .where((file) => file.name == target.archiveMember && file.isFile)
        .toList(growable: false);
    if (members.length != 1) {
      throw StateError(
        'Expected exactly one ${target.archiveMember} in ${target.archiveName}, '
        'found ${members.length}.',
      );
    }
    final libraryBytes = members.single.readBytes();
    if (libraryBytes == null) {
      throw StateError('Could not read ${target.archiveMember}.');
    }
    await _verifyHash(
      libraryBytes,
      target.librarySha256,
      '${target.archiveName}:${target.archiveMember}',
    );
    return libraryBytes;
  }

  Future<Uint8List> _download(Uri uri) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'HTTP ${response.statusCode} while downloading $uri',
          uri: uri,
        );
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
        if (builder.length > _maximumArchiveBytes) {
          throw StateError('Archive exceeds $_maximumArchiveBytes bytes: $uri');
        }
      }
      return builder.takeBytes();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _verifyHash(
    List<int> bytes,
    String expected,
    String source,
  ) async {
    final actual = sha256.convert(bytes).toString();
    if (actual != expected) {
      throw StateError(
        'SHA-256 mismatch for $source: expected $expected, got $actual',
      );
    }
  }
}

final class _NativeTarget {
  const _NativeTarget({
    required this.os,
    required this.arch,
    required this.path,
    required this.archiveName,
    required this.archiveSha256,
    required this.archiveMember,
    required this.librarySha256,
    this.minimumOsVersion,
    this.minimumGlibcVersion,
  });

  final String os;
  final String arch;
  final String path;
  final String archiveName;
  final String archiveSha256;
  final String archiveMember;
  final String librarySha256;
  final String? minimumOsVersion;
  final String? minimumGlibcVersion;

  String get key => '$os-$arch';
  Uri get archiveUrl => Uri.parse(
    'https://github.com/anomalyco/opentui/releases/download/$_tag/$archiveName',
  );

  void validateManifestEntry(Map<String, Object?> entry) {
    final expected = <String, Object?>{
      'os': os,
      'arch': arch,
      'path': path,
      'archiveUrl': archiveUrl.toString(),
      'archiveSha256': archiveSha256,
      'archiveMember': archiveMember,
      'sha256': librarySha256,
      'minimumOsVersion': ?minimumOsVersion,
      'minimumGlibcVersion': ?minimumGlibcVersion,
    };
    if (entry.length != expected.length ||
        !entry.keys.toSet().containsAll(expected.keys)) {
      throw FormatException('Manifest entry $key has unexpected fields.');
    }
    for (final expectedEntry in expected.entries) {
      if (entry[expectedEntry.key] != expectedEntry.value) {
        throw FormatException(
          'Manifest entry $key has invalid ${expectedEntry.key}.',
        );
      }
    }
  }
}
