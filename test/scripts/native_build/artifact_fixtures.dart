import 'dart:typed_data';

Uint8List minimalMachOArtifact({required int cpuType}) {
  final bytes = Uint8List(64);
  final data = ByteData.sublistView(bytes)
    ..setUint32(0, 0xfeedfacf, Endian.little)
    ..setUint32(4, cpuType, Endian.little)
    ..setUint32(16, 1, Endian.little)
    ..setUint32(20, 24, Endian.little)
    ..setUint32(32, 0x1b, Endian.little)
    ..setUint32(36, 24, Endian.little);
  for (var index = 0; index < 16; index += 1) {
    data.setUint8(40 + index, index + 1);
  }
  bytes.fillRange(56, 64, 0xa5);
  return bytes;
}

Uint8List minimalPeArtifact({required int machine}) {
  const peOffset = 0x80;
  const coffOffset = peOffset + 4;
  const optionalOffset = coffOffset + 20;
  const optionalSize = 0xf0;
  const sectionOffset = optionalOffset + optionalSize;
  const buildIdOffset = 0x200;
  final bytes = Uint8List(0x400);
  ByteData.sublistView(bytes)
    ..setUint16(0, 0x5a4d, Endian.little)
    ..setUint32(0x3c, peOffset, Endian.little)
    ..setUint32(peOffset, 0x00004550, Endian.little)
    ..setUint16(coffOffset, machine, Endian.little)
    ..setUint16(coffOffset + 2, 1, Endian.little)
    ..setUint32(coffOffset + 4, 0x12345678, Endian.little)
    ..setUint16(coffOffset + 16, optionalSize, Endian.little)
    ..setUint16(optionalOffset, 0x20b, Endian.little)
    ..setUint32(optionalOffset + 108, 16, Endian.little)
    ..setUint32(optionalOffset + 160, 0x1000, Endian.little)
    ..setUint32(optionalOffset + 164, 56, Endian.little)
    ..setUint32(sectionOffset + 8, 92, Endian.little)
    ..setUint32(sectionOffset + 12, 0x1000, Endian.little)
    ..setUint32(sectionOffset + 16, 0x200, Endian.little)
    ..setUint32(sectionOffset + 20, buildIdOffset, Endian.little);
  bytes.setRange(sectionOffset, sectionOffset + 8, '.buildid'.codeUnits);
  bytes.fillRange(buildIdOffset, bytes.length, 0x5a);
  return bytes;
}
