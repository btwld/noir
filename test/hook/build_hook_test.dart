import 'dart:async';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  test('macOS JIT loads the unchanged official library in place', () async {
    await testCodeBuildHook(
      linkingEnabled: false,
      targetOS: OS.macOS,
      mainMethod: hook.main,
      check: (input, output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final asset = assets.single;
        expect(asset.id, 'package:noir/${hook.openTuiNativeAssetName}');
        final linkMode = asset.linkMode;
        expect(linkMode, isA<DynamicLoadingSystem>());
        expect(asset.file, isNull);
        expect(
          File.fromUri((linkMode as DynamicLoadingSystem).uri).existsSync(),
          isTrue,
        );
      },
    );
  });

  test('linked macOS apps derive only a bundle output copy', () async {
    final official = File(
      'native/macos/${Architecture.current == Architecture.arm64 ? 'arm64' : 'x64'}/libopentui.dylib',
    );
    final manifest = hook.NativeManifest.fromFile(File('native_manifest.json'));
    final manifestEntry = manifest.entryFor(OS.macOS, Architecture.current);
    final officialHashBefore = sha256.convert(official.readAsBytesSync());
    expect(officialHashBefore.toString(), manifestEntry.sha256);

    await testCodeBuildHook(
      linkingEnabled: true,
      targetOS: OS.macOS,
      mainMethod: hook.main,
      check: (input, output) {
        final code = output.assets.code.single;
        expect(code.linkMode, isA<DynamicLoadingBundled>());
        expect(code.file, isNotNull);
        final bundled = File.fromUri(code.file!);
        expect(bundled.existsSync(), isTrue);
        expect(
          sha256.convert(bundled.readAsBytesSync()),
          isNot(officialHashBefore),
        );
      },
    );
    expect(sha256.convert(official.readAsBytesSync()), officialHashBefore);
  });

  test('manifest records every supported binary', () {
    final manifest = hook.NativeManifest.fromFile(File('native_manifest.json'));
    expect(manifest.schemaVersion, 1);
    expect(manifest.repository, Uri.https('github.com', '/anomalyco/opentui'));
    expect(manifest.tag, 'v0.5.1');
    expect(manifest.commit, 'ad9a818d7a9d73f3386e92a445d0feb4b395c69e');

    for (final key in [
      'macos-arm64',
      'macos-x64',
      'linux-arm64',
      'linux-x64',
      'windows-arm64',
      'windows-x64',
    ]) {
      final entry = manifest.assets[key];
      expect(entry, isNotNull, reason: key);
      expect(entry!.sha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(entry.path, startsWith('native/'));
      expect(entry.archiveUrl.scheme, 'https');
      expect(entry.archiveSha256, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(entry.archiveMember, isNotEmpty);
    }
  });

  test('SHA tamper fails loudly', () async {
    final temp = await _createTempDir('opentui_sha_test_');

    final file = File('${temp.path}/libopentui.dylib');
    await file.writeAsString('tampered');
    final expected = sha256.convert('expected'.codeUnits).toString();

    await expectLater(
      hook.NativeAssetBuildEnvironment().verifySha256(file.uri, expected),
      throwsA(
        isA<hook.NativeAssetBuildException>().having(
          (error) => error.message,
          'message',
          contains('SHA-256 mismatch'),
        ),
      ),
    );
  });

  test('manifest schema mismatch fails loudly', () {
    expect(
      () => hook.NativeManifest.fromJson({
        'schemaVersion': 2,
        'repository': 'https://github.com/anomalyco/opentui',
        'tag': 'v0.5.1',
        'commit': 'ad9a818d7a9d73f3386e92a445d0feb4b395c69e',
        'assets': <String, Object?>{},
      }),
      throwsA(
        isA<hook.NativeAssetBuildException>().having(
          (error) => error.message,
          'message',
          contains('schema version'),
        ),
      ),
    );
  });

  test('macOS manifest entries require the current deployment floor', () {
    expect(
      () => hook.NativeManifestEntry.fromJson(
        'macos-arm64',
        _entryJson(os: 'macos', arch: 'arm64'),
      ),
      throwsA(isA<hook.NativeAssetBuildException>()),
    );
  });

  test('manifest rejects invalid or misplaced deployment floors', () {
    for (final minimum in <Object?>[13, '13', '13.0.0', '12.0', '15.0']) {
      expect(
        () => hook.NativeManifestEntry.fromJson(
          'macos-x64',
          _entryJson(os: 'macos', arch: 'x64', minimumOsVersion: minimum),
        ),
        throwsA(isA<hook.NativeAssetBuildException>()),
        reason: 'minimumOsVersion=$minimum',
      );
    }
    expect(
      () => hook.NativeManifestEntry.fromJson(
        'linux-x64',
        _entryJson(
          os: 'linux',
          arch: 'x64',
          minimumOsVersion: '13.0',
          minimumGlibcVersion: '2.17',
        ),
      ),
      throwsA(isA<hook.NativeAssetBuildException>()),
    );
  });

  test('manifest accepts canonical platform floors', () {
    expect(
      () => hook.NativeManifestEntry.fromJson(
        'macos-arm64',
        _entryJson(os: 'macos', arch: 'arm64', minimumOsVersion: '13.0'),
      ),
      returnsNormally,
    );
    expect(
      () => hook.NativeManifestEntry.fromJson(
        'linux-x64',
        _entryJson(os: 'linux', arch: 'x64', minimumGlibcVersion: '2.17'),
      ),
      returnsNormally,
    );
  });

  test('missing bundled binary fails loudly', () async {
    final temp = await _createTempDir('opentui_missing_test_');

    await expectLater(
      hook.resolveNativeAsset(packageRoot: temp.uri, entry: _entry()),
      throwsA(
        isA<hook.NativeAssetBuildException>().having(
          (error) => error.message,
          'message',
          contains('No bundled OpenTUI binary'),
        ),
      ),
    );
  });
}

Future<Directory> _createTempDir(String prefix) async {
  final temp = await Directory.systemTemp.createTemp(prefix);
  addTearDown(() => temp.deleteSync(recursive: true));
  return temp;
}

hook.NativeManifestEntry _entry() => hook.NativeManifestEntry(
  key: 'macos-arm64',
  os: 'macos',
  arch: 'arm64',
  path: 'native/macos/arm64/libopentui.dylib',
  archiveUrl: Uri.parse('https://example.invalid/opentui.zip'),
  archiveSha256: '1' * 64,
  archiveMember: 'libopentui.dylib',
  minimumOsVersion: '13.0',
  minimumGlibcVersion: null,
  sha256: '0' * 64,
);

Map<String, Object?> _entryJson({
  required String os,
  required String arch,
  Object? minimumOsVersion,
  Object? minimumGlibcVersion,
}) => {
  'os': os,
  'arch': arch,
  'path': 'native/$os/$arch/libopentui',
  'archiveUrl': 'https://example.invalid/opentui.zip',
  'archiveSha256': '1' * 64,
  'archiveMember': os == 'windows' ? 'opentui.dll' : 'libopentui',
  'sha256': '0' * 64,
  'minimumOsVersion': ?minimumOsVersion,
  'minimumGlibcVersion': ?minimumGlibcVersion,
};
