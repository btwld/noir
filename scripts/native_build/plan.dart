enum NativeArtifactFormat { elf, machO, coff }

enum NativeArchitecture { x86_64, aarch64 }

final class NativeBuildTarget {
  const NativeBuildTarget({
    required this.name,
    required this.zigTargetQuery,
    required this.outputFileName,
    required this.format,
    required this.architecture,
  });

  final String name;
  final String zigTargetQuery;
  final String outputFileName;
  final NativeArtifactFormat format;
  final NativeArchitecture architecture;

  bool get isMacOs => format == NativeArtifactFormat.machO;

  String get buildOutputFileName => switch (format) {
    NativeArtifactFormat.coff => 'opentui.dll',
    _ => outputFileName,
  };

  List<String> get buildAuxiliaryFileNames => switch (format) {
    NativeArtifactFormat.coff => const <String>['opentui.pdb'],
    _ => const <String>[],
  };
}

const List<NativeBuildTarget> nativeBuildTargets = <NativeBuildTarget>[
  NativeBuildTarget(
    name: 'x86_64-linux',
    zigTargetQuery: 'x86_64-linux',
    outputFileName: 'libopentui.so',
    format: NativeArtifactFormat.elf,
    architecture: NativeArchitecture.x86_64,
  ),
  NativeBuildTarget(
    name: 'aarch64-linux',
    zigTargetQuery: 'aarch64-linux',
    outputFileName: 'libopentui.so',
    format: NativeArtifactFormat.elf,
    architecture: NativeArchitecture.aarch64,
  ),
  NativeBuildTarget(
    name: 'x86_64-macos',
    zigTargetQuery: 'x86_64-macos.15.0',
    outputFileName: 'libopentui.dylib',
    format: NativeArtifactFormat.machO,
    architecture: NativeArchitecture.x86_64,
  ),
  NativeBuildTarget(
    name: 'aarch64-macos',
    zigTargetQuery: 'aarch64-macos.15.0',
    outputFileName: 'libopentui.dylib',
    format: NativeArtifactFormat.machO,
    architecture: NativeArchitecture.aarch64,
  ),
  NativeBuildTarget(
    name: 'x86_64-windows',
    zigTargetQuery: 'x86_64-windows',
    outputFileName: 'libopentui.dll',
    format: NativeArtifactFormat.coff,
    architecture: NativeArchitecture.x86_64,
  ),
  NativeBuildTarget(
    name: 'aarch64-windows',
    zigTargetQuery: 'aarch64-windows',
    outputFileName: 'libopentui.dll',
    format: NativeArtifactFormat.coff,
    architecture: NativeArchitecture.aarch64,
  ),
];

final class NativeBuildRoot {
  const NativeBuildRoot({
    required this.label,
    required this.sourceMount,
    required this.outputMount,
    required this.cacheMount,
    required this.globalCacheMount,
    required this.targets,
  });

  final String label;
  final String sourceMount;
  final String outputMount;
  final String cacheMount;
  final String globalCacheMount;
  final Iterable<NativeBuildTarget> targets;

  String get prefixPath => '$outputMount/prefix';
}

final List<NativeBuildRoot> nativeBuildRoots = <NativeBuildRoot>[
  const NativeBuildRoot(
    label: 'root-a',
    sourceMount: '/build/noir-root-a/opentui',
    outputMount: '/work/root-a/output',
    cacheMount: '/work/root-a/cache',
    globalCacheMount: '/work/root-a/global-cache',
    targets: nativeBuildTargets,
  ),
  NativeBuildRoot(
    label: 'root-b',
    sourceMount: '/opt/repro/noir-root-b/opentui',
    outputMount: '/work/root-b/output',
    cacheMount: '/work/root-b/cache',
    globalCacheMount: '/work/root-b/global-cache',
    targets: nativeBuildTargets.reversed,
  ),
];
