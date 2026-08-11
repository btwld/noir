import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:noir/src/ffi/abi_contract.dart';
import 'package:test/test.dart';

import '../../hook/build.dart' as hook;

void main() {
  test('build hook emits bundled CodeAsset for current platform', () async {
    await testCodeBuildHook(
      mainMethod: hook.main,
      check: (input, output) {
        final assets = output.assets.code;
        expect(assets, hasLength(1));
        final asset = assets.single;
        expect(asset.id, 'package:noir/${hook.openTuiNativeAssetName}');
        expect(asset.linkMode, isA<DynamicLoadingBundled>());
        expect(asset.file, isNotNull);
        expect(File.fromUri(asset.file!).existsSync(), isTrue);
      },
    );
  });

  test('manifest records every supported binary', () {
    final manifest = hook.NativeManifest.fromFile(File('native_manifest.json'));
    expect(manifest.abiVersion, expectedOpenTuiAbiVersion);

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
      expect(entry.url.scheme, 'https');
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

  test('manifest ABI mismatch fails loudly', () {
    expect(
      () => hook.NativeManifest.fromJson({
        'abiVersion': expectedOpenTuiAbiVersion + 1,
        'assets': <String, Object?>{},
      }),
      throwsA(
        isA<hook.NativeAssetBuildException>().having(
          (error) => error.message,
          'message',
          contains('does not match Dart ABI'),
        ),
      ),
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
  url: Uri.parse('https://example.invalid/libopentui.dylib'),
  archivePath: '',
  sha256: '0' * 64,
);
