import 'package:test/test.dart';

import '../../../scripts/native_build/plan.dart';

void main() {
  test('plans exactly the approved six targets and queries', () {
    expect(nativeBuildTargets.map((target) => target.name), <String>[
      'x86_64-linux',
      'aarch64-linux',
      'x86_64-macos',
      'aarch64-macos',
      'x86_64-windows',
      'aarch64-windows',
    ]);
    expect(nativeBuildTargets.map((target) => target.zigTargetQuery), <String>[
      'x86_64-linux',
      'aarch64-linux',
      'x86_64-macos.15.0',
      'aarch64-macos.15.0',
      'x86_64-windows',
      'aarch64-windows',
    ]);
    expect(nativeBuildTargets.map((target) => target.outputFileName), <String>[
      'libopentui.so',
      'libopentui.so',
      'libopentui.dylib',
      'libopentui.dylib',
      'libopentui.dll',
      'libopentui.dll',
    ]);
    expect(
      nativeBuildTargets.map((target) => target.buildOutputFileName),
      <String>[
        'libopentui.so',
        'libopentui.so',
        'libopentui.dylib',
        'libopentui.dylib',
        'opentui.dll',
        'opentui.dll',
      ],
    );
    expect(
      nativeBuildTargets.map((target) => target.buildAuxiliaryFileNames),
      <List<String>>[
        const <String>[],
        const <String>[],
        const <String>[],
        const <String>[],
        const <String>['opentui.pdb'],
        const <String>['opentui.pdb'],
      ],
    );
  });

  test('reverses only root B and isolates every root path', () {
    expect(nativeBuildRoots, hasLength(2));
    final rootA = nativeBuildRoots[0];
    final rootB = nativeBuildRoots[1];

    expect(rootA.label, 'root-a');
    expect(rootA.sourceMount, '/build/noir-root-a/opentui');
    expect(rootB.label, 'root-b');
    expect(rootB.sourceMount, '/opt/repro/noir-root-b/opentui');
    expect(rootA.targets, nativeBuildTargets);
    expect(rootB.targets, nativeBuildTargets.reversed);

    expect(rootA.outputMount, isNot(rootB.outputMount));
    expect(rootA.cacheMount, isNot(rootB.cacheMount));
    expect(rootA.globalCacheMount, isNot(rootB.globalCacheMount));
    for (final root in nativeBuildRoots) {
      expect(root.outputMount, contains(root.label));
      expect(root.cacheMount, contains(root.label));
      expect(root.globalCacheMount, contains(root.label));
    }
  });
}
