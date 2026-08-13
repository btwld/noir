import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../helpers/opentui_v051_contract.dart';

const _commit = 'ad9a818d7a9d73f3386e92a445d0feb4b395c69e';
const _repository = 'https://github.com/anomalyco/opentui';
const _uucodeCommit = '84ceda8561a17ba4a9b96ac5c583f779660bbd4e';

const _expectedAssets = <String, Map<String, String>>{
  'macos-arm64': {
    'archive': 'opentui-native-v0.5.1-darwin-arm64.zip',
    'archiveSha256':
        '4318f9a545b765698a4d43b3d90b0fd501717edcd442e6efe24453e164ecd122',
    'member': 'libopentui.dylib',
    'sha256':
        '196d4994f8ff02a2b8c6e5581eadf315040ff8cfdb487791a7f7ec01669ee10f',
  },
  'macos-x64': {
    'archive': 'opentui-native-v0.5.1-darwin-x64.zip',
    'archiveSha256':
        '804c1c45b058c6251cbb3019ffba6e422451be18ad11325b1b896601d9f07a61',
    'member': 'libopentui.dylib',
    'sha256':
        '6de2ff94531ecef296a7d7cb5bb299bb6ee3763f3f6a8b9fefbaf2c706e4304c',
  },
  'linux-arm64': {
    'archive': 'opentui-native-v0.5.1-linux-arm64.zip',
    'archiveSha256':
        'edc644e32c1532d065af72bcd0f3bbaf2393a2d923e70870ac71f4580b223a0e',
    'member': 'libopentui.so',
    'sha256':
        '378de47d86f187f565798f0d4da831db5fa75be19574dae0e0b04f5df4316794',
  },
  'linux-x64': {
    'archive': 'opentui-native-v0.5.1-linux-x64.zip',
    'archiveSha256':
        'd1b760cf568dc46fd377c83308ebcb9c08e91cbe3f9d688a4b4403bfe0c411de',
    'member': 'libopentui.so',
    'sha256':
        '8db7922e8e765015a0a95a2d7bc5b12af9cce2a3dc78479a381edf81bd922807',
  },
  'windows-arm64': {
    'archive': 'opentui-native-v0.5.1-windows-arm64.zip',
    'archiveSha256':
        '6bff48a5c0ec85f476e3873962852954c21f7f9037315f9c23cdb39f4016eac6',
    'member': 'opentui.dll',
    'sha256':
        'f7f98743f98d0f95583160fb31cb76adee951a1eb0f67fd489cc841c44d0c402',
  },
  'windows-x64': {
    'archive': 'opentui-native-v0.5.1-windows-x64.zip',
    'archiveSha256':
        'df0521164cf1257d8c7a8e215f3e291064141ec18c6b7d8fe36f5d74798693af',
    'member': 'opentui.dll',
    'sha256':
        '8c8b15103d70373c0e1313bd0a51fee360c66280ca063cc19936d8d20cd167c7',
  },
};

void main() {
  test('pins canonical OpenTUI v0.5.1 without the legacy Go package', () {
    expect(
      File('.gitmodules').readAsStringSync(),
      contains('url = https://github.com/anomalyco/opentui.git'),
    );
    expect(
      Process.runSync('git', [
        '-C',
        'external/opentui',
        'rev-parse',
        'HEAD',
      ]).stdout.toString().trim(),
      _commit,
    );
    expect(Directory('external/opentui/packages/go').existsSync(), isFalse);
  });

  test('Unicode widths pin OpenTUI v0.5.1 uucode data exactly', () {
    final dependency = File(
      'external/opentui/packages/core/src/zig/build.zig.zon',
    ).readAsStringSync();
    final table = File(
      'lib/src/core/unicode_width_table.dart',
    ).readAsStringSync();

    expect(dependency, contains('uucode/archive/$_uucodeCommit.tar.gz'));
    expect(table, contains(_uucodeCommit));
    expect(table, contains('Unicode 16.0'));
    expect(table, isNot(contains('termunicode')));
  });

  test('manifest identifies canonical source and exact official archives', () {
    final manifest =
        jsonDecode(File('native_manifest.json').readAsStringSync())
            as Map<String, Object?>;

    expect(manifest['schemaVersion'], 1);
    expect(manifest, isNot(contains('abiVersion')));
    expect(manifest['repository'], _repository);
    expect(manifest['tag'], 'v0.5.1');
    expect(manifest['commit'], _commit);

    final assets = manifest['assets']! as Map<String, Object?>;
    expect(assets.keys, unorderedEquals(_expectedAssets.keys));
    for (final MapEntry(key: key, value: expected) in _expectedAssets.entries) {
      final asset = assets[key]! as Map<String, Object?>;
      final archive = expected['archive']!;
      expect(
        asset['archiveUrl'],
        'https://github.com/anomalyco/opentui/releases/download/v0.5.1/'
        '$archive',
        reason: key,
      );
      expect(asset['archiveSha256'], expected['archiveSha256'], reason: key);
      expect(asset['archiveMember'], expected['member'], reason: key);
      expect(asset['sha256'], expected['sha256'], reason: key);
      if (key.startsWith('macos-')) {
        expect(asset['minimumOsVersion'], '13.0', reason: key);
      }
      if (key.startsWith('linux-')) {
        expect(asset['minimumGlibcVersion'], '2.17', reason: key);
      }
    }
  });

  test('asset tool is explicit and fail-closed', () {
    final source = File(
      'scripts/fetch_opentui_binaries.dart',
    ).readAsStringSync();
    for (final mode in <String>[
      '--verify-only',
      '--verify-upstream',
      '--refresh-from-upstream',
    ]) {
      expect(source, contains(mode), reason: mode);
    }
    expect(source, isNot(contains('--verify-urls')));

    final result = Process.runSync('dart', [
      'run',
      'scripts/fetch_opentui_binaries.dart',
    ]);
    expect(result.exitCode, 64);
    expect(result.stderr.toString(), contains('Usage:'));
  });

  test('Noir-owned header drives both binding paths', () {
    const headerPath = 'native/opentui_v0_5_1.h';
    final header = File(headerPath).readAsStringSync();
    for (final configPath in <String>[
      'ffigen_dynamic.yaml',
      'ffigen_native_assets.yaml',
    ]) {
      final config = File(configPath).readAsStringSync();
      expect(config, contains(headerPath), reason: configPath);
      expect(config, isNot(contains('packages/go')), reason: configPath);
    }
    for (final signature in <String>[
      'OpenTuiHandle createRenderer(',
      'uint8_t render(',
      'OpenTuiHandle getNextBuffer(',
      'const uint16_t *fg',
      'uint32_t attributes',
      'void setCursorStyleOptions(',
    ]) {
      expect(header, contains(signature), reason: signature);
    }
    expect(header, isNot(contains('TextBuffer')));
    expect(header, isNot(contains('otui_dart_')));
  });

  test('selected header exports agree with the pinned Zig ABI', () {
    final zig = File(
      'external/opentui/packages/core/src/zig/lib.zig',
    ).readAsStringSync();
    final handles = File(
      'external/opentui/packages/core/src/zig/handles.zig',
    ).readAsStringSync();
    final header = File('native/opentui_v0_5_1.h').readAsStringSync();

    expect(handles, contains('pub const Handle = u32;'));
    for (final symbol in selectedOpenTuiV051Symbols) {
      expect(
        zig,
        matches(RegExp('export fn\\s+$symbol\\s*\\(')),
        reason: 'Pinned Zig source is missing selected export $symbol',
      );
      expect(
        header,
        matches(RegExp('\\b$symbol\\s*\\(')),
        reason: 'Noir header is missing selected export $symbol',
      );
    }

    final normalizedZig = _normalizeWhitespace(zig);
    for (final signature in <String>[
      _joined(<String>[
        'export fn createRenderer( width: u32, height: u32, ',
        'bufferedDestinationKind: u8, remoteModeValue: u8, ',
        'feedPtr: ?*native_span_feed.Stream, ) NativeHandle',
      ]),
      'export fn render(renderer_handle: NativeHandle, force: bool) u8',
      'export fn bufferGetFgPtr(buffer_handle: NativeHandle) ?[*]RGBA',
      'export fn bufferGetBgPtr(buffer_handle: NativeHandle) ?[*]RGBA',
      'export fn bufferGetAttributesPtr(buffer_handle: NativeHandle) ?[*]u32',
      _joined(<String>[
        'pub const CursorStyleOptions = extern struct { style: u8, ',
        'blinking: u8, color: ?[*]const u16, cursor: u8, };',
      ]),
      _joined(<String>[
        'export fn setCursorStyleOptions(renderer_handle: NativeHandle, ',
        'options: *const CursorStyleOptions) void',
      ]),
    ]) {
      expect(normalizedZig, contains(signature), reason: signature);
    }
  });

  test('fork-only build and Go parity systems are absent', () {
    for (final path in <String>[
      'scripts/build_opentui_candidates.dart',
      'scripts/native_build',
      'scripts/run_go_snapshot.sh',
      'bin/parity_compare.dart',
      'test/scripts/native_build',
      'test/parity',
      'test/fixtures/go_snapshot',
    ]) {
      expect(
        FileSystemEntity.typeSync(path),
        FileSystemEntityType.notFound,
        reason: path,
      );
    }
    expect(
      File('dart_test.yaml').readAsStringSync(),
      isNot(contains('restricted-process-lifecycle')),
    );
  });

  test('tracked source rejects fork identity and fork-only ABI names', () {
    final tracked = (Process.runSync('git', ['ls-files']).stdout as String)
        .split('\n')
        .where(
          (path) =>
              path.isNotEmpty &&
              path !=
                  'test/architecture/upstream_opentui_v051_migration_test.dart',
        );
    final forbidden = <String>[
      _join('github.com/', 'leoafarias/opentui'),
      _join('github.com/', 'sst/opentui'),
      _join('ddbc9edf81a1fa89961135ab', '0481df15054ed4b0'),
      _join('external/opentui/packages/', 'go'),
      _join('otui_dart_', 'abi_version'),
      _join('otui_dart_', 'build_info'),
      _join('otui_dart_', 'last_error'),
      _join('otui_dart_', 'clear_error'),
    ];

    for (final path in tracked) {
      final type = FileSystemEntity.typeSync(path);
      if (type != FileSystemEntityType.file) continue;
      final bytes = File(path).readAsBytesSync();
      if (bytes.contains(0)) continue;
      final source = utf8.decode(bytes, allowMalformed: true);
      for (final stale in forbidden) {
        expect(source, isNot(contains(stale)), reason: '$path: $stale');
      }
    }
  });

  test('published notices include every official archive license', () {
    final notices = File('THIRD_PARTY_NOTICES.md').readAsStringSync();
    for (final license in <String>[
      'OpenTUI',
      'Wuffs',
      'libwebp',
      'stb',
      'Little CMS',
      'uucode',
      'Unicode data',
    ]) {
      expect(notices, contains(license), reason: license);
    }
  });

  test('public docs retain the pinned leading-zero-width limitation', () {
    for (final path in <String>['README.md', 'TODO.md']) {
      final source = File(path).readAsStringSync();
      expect(source, contains('bufferDrawText'), reason: path);
      expect(source, contains('zero-width'), reason: path);
      expect(source, contains('UTF-8 continuation'), reason: path);
    }
  });
}

String _join(String first, String second) => '$first$second';

String _joined(List<String> segments) => segments.join();

String _normalizeWhitespace(String source) =>
    source.replaceAll(RegExp(r'\s+'), ' ');
