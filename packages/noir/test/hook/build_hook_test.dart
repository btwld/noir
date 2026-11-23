import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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

  test('JIT hook declares manifest and selected binary dependencies', () async {
    await testCodeBuildHook(
      linkingEnabled: false,
      targetOS: OS.macOS,
      mainMethod: hook.main,
      check: (input, output) {
        final arch = Architecture.current == Architecture.arm64
            ? 'arm64'
            : 'x64';

        expect(output.dependencies, [
          input.packageRoot.resolve('native_manifest.json'),
          input.packageRoot.resolve('native/macos/$arch/libopentui.dylib'),
        ]);
      },
    );
  });

  test('Linux JIT loads the unchanged official library in place', () async {
    await testCodeBuildHook(
      linkingEnabled: false,
      targetOS: OS.linux,
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

  test('Windows JIT loads the unchanged official library in place', () async {
    await testCodeBuildHook(
      linkingEnabled: false,
      targetOS: OS.windows,
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
        final segments = code.file!.pathSegments;
        expect(segments.sublist(segments.length - 2), [
          'macos-${manifestEntry.arch}',
          'libopentui.dylib',
        ]);
        expect(
          sha256.convert(bundled.readAsBytesSync()),
          isNot(officialHashBefore),
        );
      },
    );
    expect(sha256.convert(official.readAsBytesSync()), officialHashBefore);
  });

  for (final (arch, minimumSpareBytes) in const [('x64', 8), ('arm64', 24)]) {
    test('macOS $arch bundle copy fits the dart build install name with at '
        'least $minimumSpareBytes spare bytes', () {
      final bytes = File(
        'native/macos/$arch/libopentui.dylib',
      ).readAsBytesSync();
      hook.stripOptionalMacOSLoadCommands(bytes);

      final headroom = hook.MacOSInstallNameHeadroom.of(
        bytes,
        installName: '@rpath/lib/libopentui.dylib',
      );
      expect(headroom.margin, greaterThanOrEqualTo(minimumSpareBytes));
    });
  }

  group('install-name headroom mirrors install_name_tool', () {
    test('an exact fit is allowed and reserves room for a signature', () {
      final bytes = _machO(firstSectionOffset: 256);
      hook.stripOptionalMacOSLoadCommands(bytes);

      final headroom = hook.MacOSInstallNameHeadroom.of(
        bytes,
        installName: '@rpath/lib/libopentui.dylib',
      );
      expect(headroom.reservesCodeSignature, isTrue);
      expect(headroom.requiredBytes, 256);
      expect(headroom.availableBytes, 256);
      expect(headroom.margin, 0);
    });

    test('a signed library gets no signature reserve', () {
      final bytes = _machO(firstSectionOffset: 256, signed: true);
      hook.stripOptionalMacOSLoadCommands(bytes);

      final headroom = hook.MacOSInstallNameHeadroom.of(
        bytes,
        installName: '@rpath/lib/libopentui.dylib',
      );
      expect(headroom.reservesCodeSignature, isFalse);
      expect(headroom.margin, 0);
    });

    test('a library without room fails clearly and writes nothing', () async {
      final temp = await _createTempDir('opentui_headroom_test_');
      final source = File('${temp.path}/source.dylib')
        ..writeAsBytesSync(_machO(firstSectionOffset: 256));
      final destination = temp.uri.resolve(
        'macos-x64/macos-x64-libopentui.dylib',
      );

      await expectLater(
        hook.prepareMacOSBundleLibrary(source.uri, destination),
        throwsA(
          isA<hook.NativeAssetBuildException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('"@rpath/lib/macos-x64-libopentui.dylib"'),
              contains('needs 264 bytes'),
              contains('16 bytes install_name_tool reserves'),
              contains('only 256 are available'),
              contains('-headerpad_max_install_names'),
              contains('https://github.com/btwld/noir/issues/139'),
            ),
          ),
        ),
      );
      expect(File.fromUri(destination).existsSync(), isFalse);
    });
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

/// A minimal thin x86_64 Mach-O dylib whose first section starts at
/// [firstSectionOffset]: `LC_ID_DYLIB` (48 bytes), one `LC_SEGMENT_64` with
/// one section (152 bytes), `LC_SOURCE_VERSION` (16 bytes), and optionally
/// `LC_CODE_SIGNATURE` (16 bytes).
Uint8List _machO({required int firstSectionOffset, bool signed = false}) {
  const installName = '@rpath/libx.dylib';
  final bytes = Uint8List(firstSectionOffset + 16);
  final data = ByteData.sublistView(bytes);
  var offset = 32;
  var commandCount = 0;
  void command(int type, int size) {
    data
      ..setUint32(offset, type, Endian.little)
      ..setUint32(offset + 4, size, Endian.little);
    commandCount++;
  }

  command(0x0D, 48);
  data.setUint32(offset + 8, 24, Endian.little);
  bytes.setAll(offset + 24, installName.codeUnits);
  offset += 48;

  command(0x19, 152);
  data
    ..setUint64(offset + 48, bytes.length, Endian.little)
    ..setUint32(offset + 64, 1, Endian.little)
    ..setUint64(offset + 72 + 40, 16, Endian.little)
    ..setUint32(offset + 72 + 48, firstSectionOffset, Endian.little);
  offset += 152;

  command(0x2A, 16);
  offset += 16;

  if (signed) {
    command(0x1D, 16);
    offset += 16;
  }

  data
    ..setUint32(0, 0xFEEDFACF, Endian.little)
    ..setUint32(4, 0x01000007, Endian.little)
    ..setUint32(12, 6, Endian.little)
    ..setUint32(16, commandCount, Endian.little)
    ..setUint32(20, offset - 32, Endian.little);
  return bytes;
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
