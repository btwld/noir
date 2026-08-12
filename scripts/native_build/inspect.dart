import 'package:noir/src/ffi/abi_contract.dart';

import 'plan.dart';

final class ArtifactInspection {
  const ArtifactInspection({
    required this.target,
    required this.executableFileNames,
    required this.fileHeaderOutput,
    required this.exportOutput,
    required this.versionOutput,
    required this.printableStrings,
    required this.forbiddenPathFragments,
  });

  final NativeBuildTarget target;
  final List<String> executableFileNames;
  final String fileHeaderOutput;
  final String exportOutput;
  final String versionOutput;
  final String printableStrings;
  final List<String> forbiddenPathFragments;
}

final class ArtifactInspectionException implements Exception {
  const ArtifactInspectionException(this.message);

  final String message;

  @override
  String toString() => 'Artifact inspection failed: $message';
}

void inspectArtifact(ArtifactInspection inspection) {
  final target = inspection.target;
  if (inspection.executableFileNames.length != 1 ||
      inspection.executableFileNames.single != target.outputFileName) {
    throw ArtifactInspectionException(
      '${target.name} must contain exactly ${target.outputFileName}; found '
      '${inspection.executableFileNames.join(', ')}',
    );
  }

  final header = inspection.fileHeaderOutput.toLowerCase();
  final expectedFormats = switch (target.format) {
    NativeArtifactFormat.elf => const <String>['format: elf'],
    NativeArtifactFormat.machO => const <String>['format: mach-o'],
    NativeArtifactFormat.coff => const <String>['format: coff'],
  };
  if (!expectedFormats.every(header.contains)) {
    throw ArtifactInspectionException('${target.name} has the wrong format');
  }
  final expectedArchitectureTokens = switch (target.architecture) {
    NativeArchitecture.x86_64 => const <String>['x86_64', 'x86-64'],
    NativeArchitecture.aarch64 => const <String>['aarch64', 'arm64'],
  };
  if (!expectedArchitectureTokens.any(header.contains)) {
    throw ArtifactInspectionException(
      '${target.name} has the wrong architecture',
    );
  }
  if (target.format == NativeArtifactFormat.coff) {
    if (!RegExp(
          r'timedatestamp:.*\(0x0\)',
          caseSensitive: false,
        ).hasMatch(inspection.fileHeaderOutput) ||
        !RegExp(
          r'debugdirectory\s*\[\s*\]',
          caseSensitive: false,
        ).hasMatch(inspection.fileHeaderOutput)) {
      throw ArtifactInspectionException(
        '${target.name} retains noncanonical PE build metadata',
      );
    }
  }

  final exports = inspection.exportOutput
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .map((line) => line.split(RegExp(r'\s+')).last)
      .map((symbol) => symbol.startsWith('_') ? symbol.substring(1) : symbol)
      .toSet();
  final missingExports = requiredOpenTuiNativeSymbolNames
      .where((symbol) => !exports.contains(symbol))
      .toList();
  if (missingExports.isNotEmpty) {
    throw ArtifactInspectionException(
      '${target.name} is missing exports: ${missingExports.join(', ')}',
    );
  }

  if (target.isMacOs) {
    if (!RegExp(
      r'(?:minos\s+|(?:minversion|minimumosversion):\s*)'
      r'15\.0(?:\.0)?(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(inspection.versionOutput)) {
      throw ArtifactInspectionException(
        '${target.name} does not declare the macOS 15.0 floor',
      );
    }
    if (!RegExp(
      r'uuid\s+00000000-0000-0000-0000-000000000000',
      caseSensitive: false,
    ).hasMatch(inspection.versionOutput)) {
      throw ArtifactInspectionException(
        '${target.name} retains a noncanonical Mach-O UUID',
      );
    }
  }

  _rejectPathLeaks(inspection);
}

void _rejectPathLeaks(ArtifactInspection inspection) {
  const generalLeaks = <String>['/Users/', '/home/', '/root/', '/tmp/'];
  for (final fragment in <String>[
    ...inspection.forbiddenPathFragments,
    ...generalLeaks,
  ]) {
    if (inspection.printableStrings.contains(fragment)) {
      throw ArtifactInspectionException(
        '${inspection.target.name} contains forbidden path $fragment',
      );
    }
  }
  final windowsBuildPath = RegExp(
    '(?:^|[^A-Za-z0-9])'
    r'[A-Za-z]:[\\/](?!Windows[\\/]System32[\\/])',
    multiLine: true,
  );
  if (windowsBuildPath.hasMatch(inspection.printableStrings)) {
    throw ArtifactInspectionException(
      '${inspection.target.name} contains a Windows build path',
    );
  }
  const reviewedAbsolutePaths = <String>{
    // OpenTUI's testing renderer discards output through this device.
    '/dev/null',
    // Zig's Linux runtime resolves its executable and optional debug data.
    // The first value is a linker-coalesced pair of procfs string literals.
    '/proc//proc/self/fd/',
    '/proc/self/exe',
    '/proc/self/fd/',
    '/usr/lib/debug',
    '/lib/ld-linux-aarch64.so.1',
    '/lib64/ld-linux-x86-64.so.2',
    // Mach-O records these exact system loader dependencies in load commands.
    '/usr/lib/dyld',
    '/usr/lib/libSystem.B.dylib',
  };
  final plausibleAbsolutePath = RegExp('^/[A-Za-z][A-Za-z0-9._-]{2,}/');
  final absolutePath = RegExp(
    r'(?:^|\s)(/[^\s,;:!?]+)(?=[\s,;:!?]|$)',
    multiLine: true,
  );
  for (final match in absolutePath.allMatches(inspection.printableStrings)) {
    final path = match.group(1)!;
    if (!plausibleAbsolutePath.hasMatch(path)) {
      continue;
    }
    if (!reviewedAbsolutePaths.contains(path)) {
      throw ArtifactInspectionException(
        '${inspection.target.name} contains unreviewed absolute path $path',
      );
    }
  }
  final absoluteDebugSource = RegExp(
    r'(?:^|\s)(?:/[A-Za-z0-9_.-]+)+/[^\s]+\.(?:zig|c|cc|cpp|h|hpp)(?::\d+)?',
    multiLine: true,
  );
  if (absoluteDebugSource.hasMatch(inspection.printableStrings)) {
    throw ArtifactInspectionException(
      '${inspection.target.name} contains an absolute debug-source path',
    );
  }
}

void verifyIdenticalArtifacts(
  Map<String, String> rootA,
  Map<String, String> rootB,
) {
  final expected = nativeBuildTargets.map((target) => target.name).toSet();
  if (rootA.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(rootA.keys.toSet()).isNotEmpty ||
      rootB.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(rootB.keys.toSet()).isNotEmpty) {
    throw const ArtifactInspectionException(
      'both roots must contain exactly the approved target hash table',
    );
  }
  for (final target in expected) {
    if (rootA[target] != rootB[target]) {
      throw ArtifactInspectionException(
        '$target differs between root A and root B',
      );
    }
  }
}
