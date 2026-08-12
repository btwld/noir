import 'dart:typed_data';

import 'plan.dart';

final class ArtifactNormalizationException implements Exception {
  const ArtifactNormalizationException(this.message);

  final String message;

  @override
  String toString() => 'Artifact normalization failed: $message';
}

Uint8List canonicalizeArtifactIdentifiers(
  Uint8List input,
  NativeBuildTarget target,
) {
  final bytes = Uint8List.fromList(input);
  switch (target.format) {
    case NativeArtifactFormat.elf:
      return bytes;
    case NativeArtifactFormat.machO:
      _canonicalizeMachOUuid(bytes, target);
    case NativeArtifactFormat.coff:
      _canonicalizePeBuildMetadata(bytes, target);
  }
  return bytes;
}

void _canonicalizeMachOUuid(Uint8List bytes, NativeBuildTarget target) {
  final binary = _BinaryView(bytes, target);
  binary.requireRange(0, 32, 'Mach-O header');
  if (binary.uint32(0) != 0xfeedfacf) {
    binary.fail('expected a little-endian 64-bit Mach-O header');
  }
  final expectedCpuType = switch (target.architecture) {
    NativeArchitecture.x86_64 => 0x01000007,
    NativeArchitecture.aarch64 => 0x0100000c,
  };
  if (binary.uint32(4) != expectedCpuType) {
    binary.fail('Mach-O CPU type does not match ${target.architecture.name}');
  }

  final commandCount = binary.uint32(16);
  final commandBytes = binary.uint32(20);
  binary.requireRange(32, commandBytes, 'Mach-O load commands');
  final commandsEnd = 32 + commandBytes;
  var cursor = 32;
  var uuidCount = 0;
  for (var index = 0; index < commandCount; index += 1) {
    binary.requireRange(cursor, 8, 'Mach-O load command $index');
    final command = binary.uint32(cursor);
    final commandSize = binary.uint32(cursor + 4);
    if (commandSize < 8 || commandSize % 8 != 0) {
      binary.fail('Mach-O load command $index has an invalid size');
    }
    if (cursor > commandsEnd - commandSize) {
      binary.fail('Mach-O load command $index exceeds sizeofcmds');
    }
    if (command == 0x1b) {
      if (commandSize != 24) {
        binary.fail('LC_UUID must have the exact 24-byte shape');
      }
      bytes.fillRange(cursor + 8, cursor + 24, 0);
      uuidCount += 1;
    }
    cursor += commandSize;
  }
  if (cursor != commandsEnd) {
    binary.fail('Mach-O load commands do not consume sizeofcmds');
  }
  if (uuidCount != 1) {
    binary.fail('expected exactly one LC_UUID; found $uuidCount');
  }
}

void _canonicalizePeBuildMetadata(Uint8List bytes, NativeBuildTarget target) {
  final binary = _BinaryView(bytes, target);
  binary.requireRange(0, 0x40, 'DOS header');
  if (binary.uint16(0) != 0x5a4d) {
    binary.fail('expected an MZ header');
  }
  final peOffset = binary.uint32(0x3c);
  binary.requireRange(peOffset, 24, 'PE signature and COFF header');
  if (binary.uint32(peOffset) != 0x00004550) {
    binary.fail('expected a PE signature');
  }

  final coffOffset = peOffset + 4;
  final expectedMachine = switch (target.architecture) {
    NativeArchitecture.x86_64 => 0x8664,
    NativeArchitecture.aarch64 => 0xaa64,
  };
  if (binary.uint16(coffOffset) != expectedMachine) {
    binary.fail('PE machine does not match ${target.architecture.name}');
  }
  final sectionCount = binary.uint16(coffOffset + 2);
  if (sectionCount == 0) {
    binary.fail('PE image has no sections');
  }
  final optionalSize = binary.uint16(coffOffset + 16);
  final optionalOffset = coffOffset + 20;
  binary.requireRange(optionalOffset, optionalSize, 'PE optional header');
  if (optionalSize < 168 || binary.uint16(optionalOffset) != 0x20b) {
    binary.fail('expected a PE32+ optional header with data directories');
  }
  if (binary.uint32(optionalOffset + 64) != 0) {
    binary.fail('cannot canonicalize a PE image with a nonzero checksum');
  }
  if (binary.uint32(optionalOffset + 108) < 7) {
    binary.fail('PE image has no debug data-directory slot');
  }

  final debugDirectoryOffset = optionalOffset + 160;
  final debugRva = binary.uint32(debugDirectoryOffset);
  final debugSize = binary.uint32(debugDirectoryOffset + 4);
  if (debugRva == 0 || debugSize == 0) {
    binary.fail('PE image has no active debug directory');
  }

  final sectionTableOffset = optionalOffset + optionalSize;
  binary.requireRange(
    sectionTableOffset,
    sectionCount * 40,
    'PE section table',
  );
  _PeSection? buildIdSection;
  for (var index = 0; index < sectionCount; index += 1) {
    final offset = sectionTableOffset + index * 40;
    if (!_matchesBuildIdName(bytes, offset)) {
      continue;
    }
    if (buildIdSection != null) {
      binary.fail('PE image has more than one .buildid section');
    }
    buildIdSection = _PeSection(
      virtualSize: binary.uint32(offset + 8),
      virtualAddress: binary.uint32(offset + 12),
      rawSize: binary.uint32(offset + 16),
      rawOffset: binary.uint32(offset + 20),
    );
  }
  if (buildIdSection == null) {
    binary.fail('PE image has no .buildid section');
  }
  final section = buildIdSection;
  if (section.virtualSize == 0 || section.rawSize == 0) {
    binary.fail('PE .buildid section is empty');
  }
  binary.requireRange(section.rawOffset, section.rawSize, 'PE .buildid data');
  final debugDelta = debugRva - section.virtualAddress;
  if (debugDelta < 0 ||
      debugDelta > section.rawSize - debugSize ||
      debugDelta > section.virtualSize - debugSize) {
    binary.fail('PE debug directory is not contained in .buildid');
  }

  bytes
    ..fillRange(coffOffset + 4, coffOffset + 8, 0)
    ..fillRange(debugDirectoryOffset, debugDirectoryOffset + 8, 0)
    ..fillRange(section.rawOffset, section.rawOffset + section.rawSize, 0);
}

bool _matchesBuildIdName(Uint8List bytes, int offset) {
  const expected = <int>[0x2e, 0x62, 0x75, 0x69, 0x6c, 0x64, 0x69, 0x64];
  for (var index = 0; index < expected.length; index += 1) {
    if (bytes[offset + index] != expected[index]) {
      return false;
    }
  }
  return true;
}

final class _PeSection {
  const _PeSection({
    required this.virtualSize,
    required this.virtualAddress,
    required this.rawSize,
    required this.rawOffset,
  });

  final int virtualSize;
  final int virtualAddress;
  final int rawSize;
  final int rawOffset;
}

final class _BinaryView {
  _BinaryView(this.bytes, this.target) : data = ByteData.sublistView(bytes);

  final Uint8List bytes;
  final NativeBuildTarget target;
  final ByteData data;

  int uint16(int offset) {
    requireRange(offset, 2, '16-bit field');
    return data.getUint16(offset, Endian.little);
  }

  int uint32(int offset) {
    requireRange(offset, 4, '32-bit field');
    return data.getUint32(offset, Endian.little);
  }

  void requireRange(int offset, int length, String label) {
    if (offset < 0 || length < 0 || offset > bytes.length - length) {
      fail('$label exceeds the artifact boundary');
    }
  }

  Never fail(String message) {
    throw ArtifactNormalizationException('${target.name}: $message');
  }
}
