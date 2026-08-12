import 'package:noir/src/ffi/abi_contract.dart';
import 'package:test/test.dart';

import '../../../scripts/native_build/inspect.dart';
import '../../../scripts/native_build/plan.dart';

void main() {
  final linuxX64 = nativeBuildTargets.first;
  final macArm64 = nativeBuildTargets.singleWhere(
    (target) => target.name == 'aarch64-macos',
  );

  test('accepts exact format, machine, exports, floor, and clean strings', () {
    expect(
      () => inspectArtifact(
        ArtifactInspection(
          target: linuxX64,
          executableFileNames: <String>['libopentui.so'],
          fileHeaderOutput: _header(linuxX64),
          exportOutput: _exports(),
          versionOutput: '',
          printableStrings: '/lib64/ld-linux-x86-64.so.2\nOpenTUI\n',
          forbiddenPathFragments: const <String>[
            '/build/noir-root-a',
            '/opt/repro/noir-root-b',
          ],
        ),
      ),
      returnsNormally,
    );
    expect(
      () => inspectArtifact(
        ArtifactInspection(
          target: macArm64,
          executableFileNames: <String>['libopentui.dylib'],
          fileHeaderOutput: _header(macArm64),
          exportOutput: _exports(leadingUnderscore: true),
          versionOutput: 'cmd LC_BUILD_VERSION\nminos 15.0\nsdk 15.4\n',
          printableStrings: '/usr/lib/libSystem.B.dylib\nOpenTUI\n',
          forbiddenPathFragments: const <String>[],
        ),
      ),
      returnsNormally,
    );
  });

  test('rejects missing and extra executable outputs', () {
    for (final files in <List<String>>[
      <String>[],
      <String>['libopentui.so', 'unexpected'],
    ]) {
      expect(
        () =>
            inspectArtifact(_inspection(linuxX64, executableFileNames: files)),
        throwsA(isA<ArtifactInspectionException>()),
      );
    }
  });

  test('rejects wrong format and wrong architecture', () {
    expect(
      () => inspectArtifact(
        _inspection(
          linuxX64,
          fileHeaderOutput: 'Format: Mach-O 64-bit x86-64\nArch: x86_64\n',
        ),
      ),
      throwsA(isA<ArtifactInspectionException>()),
    );
    expect(
      () => inspectArtifact(
        _inspection(
          linuxX64,
          fileHeaderOutput: 'Format: elf64-littleaarch64\nArch: aarch64\n',
        ),
      ),
      throwsA(isA<ArtifactInspectionException>()),
    );
  });

  test('rejects incomplete exact exports', () {
    final incomplete = requiredOpenTuiNativeSymbolNames.skip(1).join('\n');
    expect(
      () => inspectArtifact(_inspection(linuxX64, exportOutput: incomplete)),
      throwsA(isA<ArtifactInspectionException>()),
    );
  });

  test('rejects a macOS floor other than 15.0', () {
    for (final output in <String>[
      'MinVersion: 14.0\nSDK: 15.4\n',
      'MinVersion: 14.0\nSDK Version: 15.0\n',
    ]) {
      expect(
        () => inspectArtifact(_inspection(macArm64, versionOutput: output)),
        throwsA(isA<ArtifactInspectionException>()),
      );
    }
  });

  test('rejects build paths, home paths, drive paths, and debug sources', () {
    for (final leak in <String>[
      '/build/noir-root-a/opentui/lib.zig',
      '/Users/builder/noir/file.zig',
      '/home/builder/cache/object.o',
      '/opt/unreviewed/libevil.dylib',
      r'C:\build\opentui\lib.zig',
      '/tmp/noir-native-build-123/lib.zig:42',
    ]) {
      expect(
        () =>
            inspectArtifact(_inspection(linuxX64, printableStrings: '$leak\n')),
        throwsA(isA<ArtifactInspectionException>()),
        reason: leak,
      );
    }
  });

  test('allows URL schemes without treating their suffix as a drive path', () {
    expect(
      () => inspectArtifact(
        _inspection(
          linuxX64,
          printableStrings:
              'https://github.com/ziglang/zig-bootstrap\nOpenTUI\n',
        ),
      ),
      returnsNormally,
    );
  });

  test('allows only OpenTUI testing renderer references to /dev/null', () {
    expect(
      () => inspectArtifact(
        _inspection(
          linuxX64,
          printableStrings:
              '/dev/null\n'
              'Failed to open /dev/null, falling back to stdout\n',
        ),
      ),
      returnsNormally,
    );
    for (final path in <String>['/dev/null/child', '/dev/nullish']) {
      expect(
        () =>
            inspectArtifact(_inspection(linuxX64, printableStrings: '$path\n')),
        throwsA(isA<ArtifactInspectionException>()),
        reason: path,
      );
    }
  });

  test('allows only reviewed Zig Linux runtime paths', () {
    expect(
      () => inspectArtifact(
        _inspection(
          linuxX64,
          printableStrings:
              '/proc//proc/self/fd/\n'
              '/proc/self/fd/\n'
              '/proc/self/exe\n'
              '/usr/lib/debug\n'
              '/4/I\n'
              '/mem\n'
              '/u&^Y\n'
              '/yox\n',
        ),
      ),
      returnsNormally,
    );
    for (final path in <String>[
      '/proc/self/exe/child',
      '/proc/self/fd/secret',
      '/usr/lib/debug/evil',
    ]) {
      expect(
        () =>
            inspectArtifact(_inspection(linuxX64, printableStrings: '$path\n')),
        throwsA(isA<ArtifactInspectionException>()),
        reason: path,
      );
    }
  });

  test('rejects nonidentical or incomplete root hash tables', () {
    final rootA = <String, String>{
      for (final target in nativeBuildTargets)
        target.name: 'hash-${target.name}',
    };
    final rootB = Map<String, String>.of(rootA);
    expect(() => verifyIdenticalArtifacts(rootA, rootB), returnsNormally);

    rootB[linuxX64.name] = 'different';
    expect(
      () => verifyIdenticalArtifacts(rootA, rootB),
      throwsA(isA<ArtifactInspectionException>()),
    );
    rootB.remove(linuxX64.name);
    expect(
      () => verifyIdenticalArtifacts(rootA, rootB),
      throwsA(isA<ArtifactInspectionException>()),
    );
  });
}

ArtifactInspection _inspection(
  NativeBuildTarget target, {
  List<String>? executableFileNames,
  String? fileHeaderOutput,
  String? exportOutput,
  String? versionOutput,
  String printableStrings = 'OpenTUI\n',
}) => ArtifactInspection(
  target: target,
  executableFileNames: executableFileNames ?? <String>[target.outputFileName],
  fileHeaderOutput: fileHeaderOutput ?? _header(target),
  exportOutput: exportOutput ?? _exports(),
  versionOutput: versionOutput ?? (target.isMacOs ? 'MinVersion: 15.0\n' : ''),
  printableStrings: printableStrings,
  forbiddenPathFragments: const <String>[
    '/build/noir-root-a',
    '/opt/repro/noir-root-b',
  ],
);

String _header(NativeBuildTarget target) => switch (target.name) {
  'x86_64-linux' => 'Format: elf64-x86-64\nArch: x86_64\n',
  'aarch64-linux' => 'Format: elf64-littleaarch64\nArch: aarch64\n',
  'x86_64-macos' => 'Format: Mach-O 64-bit x86-64\nArch: x86_64\n',
  'aarch64-macos' => 'Format: Mach-O arm64\nArch: aarch64\n',
  'x86_64-windows' => 'Format: COFF-x86-64\nArch: x86_64\n',
  'aarch64-windows' => 'Format: COFF-ARM64\nArch: aarch64\n',
  _ => throw StateError('unexpected fixture target'),
};

String _exports({bool leadingUnderscore = false}) =>
    requiredOpenTuiNativeSymbolNames
        .map((symbol) => '00000000 T ${leadingUnderscore ? '_' : ''}$symbol')
        .join('\n');
