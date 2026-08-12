import 'dart:typed_data';

import 'package:test/test.dart';

import '../../../scripts/native_build/normalize.dart';
import '../../../scripts/native_build/plan.dart';
import 'artifact_fixtures.dart';

void main() {
  final macX64 = nativeBuildTargets.singleWhere(
    (target) => target.name == 'x86_64-macos',
  );
  final windowsX64 = nativeBuildTargets.singleWhere(
    (target) => target.name == 'x86_64-windows',
  );
  final windowsArm64 = nativeBuildTargets.singleWhere(
    (target) => target.name == 'aarch64-windows',
  );

  test('canonicalizes only the Mach-O LC_UUID payload', () {
    final input = minimalMachOArtifact(cpuType: 0x01000007);
    final expected = Uint8List.fromList(input)..fillRange(40, 56, 0);

    expect(canonicalizeArtifactIdentifiers(input, macX64), expected);
  });

  test('canonicalizes only PE timestamp and debug-build metadata', () {
    final input = minimalPeArtifact(machine: 0x8664);
    final expected = Uint8List.fromList(input)
      ..fillRange(0x88, 0x8c, 0)
      ..fillRange(0x138, 0x140, 0)
      ..fillRange(0x200, 0x400, 0);

    expect(canonicalizeArtifactIdentifiers(input, windowsX64), expected);
  });

  test('leaves ELF bytes unchanged', () {
    final linuxX64 = nativeBuildTargets.singleWhere(
      (target) => target.name == 'x86_64-linux',
    );
    final input = Uint8List.fromList(<int>[0x7f, 0x45, 0x4c, 0x46]);

    expect(canonicalizeArtifactIdentifiers(input, linuxX64), input);
  });

  test('fails closed on missing records, invalid ranges, and drift', () {
    final missingUuid = minimalMachOArtifact(cpuType: 0x01000007);
    ByteData.sublistView(missingUuid)
      ..setUint32(16, 0, Endian.little)
      ..setUint32(20, 0, Endian.little);
    final missingBuildId = minimalPeArtifact(machine: 0x8664)
      ..setRange(0x188, 0x190, '.text\x00\x00\x00'.codeUnits);
    final invalidDebugRange = minimalPeArtifact(machine: 0x8664);
    ByteData.sublistView(
      invalidDebugRange,
    ).setUint32(0x138, 0x2000, Endian.little);
    final nonzeroChecksum = minimalPeArtifact(machine: 0x8664);
    ByteData.sublistView(nonzeroChecksum).setUint32(0xd8, 1, Endian.little);

    for (final attempt in <void Function()>[
      () => canonicalizeArtifactIdentifiers(missingUuid, macX64),
      () => canonicalizeArtifactIdentifiers(missingBuildId, windowsX64),
      () => canonicalizeArtifactIdentifiers(invalidDebugRange, windowsX64),
      () => canonicalizeArtifactIdentifiers(nonzeroChecksum, windowsX64),
      () => canonicalizeArtifactIdentifiers(
        minimalPeArtifact(machine: 0x8664),
        windowsArm64,
      ),
    ]) {
      expect(attempt, throwsA(isA<ArtifactNormalizationException>()));
    }
  });
}
