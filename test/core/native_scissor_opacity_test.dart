// Behavioural proof for the newly bound native clip and opacity stacks.
//
// `opentui_abi_signature_test.dart` proves the prototypes match the pinned Zig
// ABI. That is a static check: it cannot tell whether the call actually reaches
// the right native function or whether the arguments land in the right slots.
// These tests exercise each binding against the bundled library and assert on
// real buffer contents.
//
// Noir's own clip seam stays in Dart (`Buffer.clipped`). These bindings exist so
// a `noir_ffi` consumer can reach the native stacks; nothing in the framework
// pushes them.

import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/buffer.dart' show debugResolveBufferCell;
import 'package:test/test.dart';

const _fg = Color.white;
const _bg = Color.black;
const _red = Color.red;

void main() {
  late Renderer renderer;
  late Buffer buffer;
  late OpenTuiBindings raw;
  late OptimizedBufferHandle handle;

  setUp(() {
    renderer = Renderer.create(8, 4, testing: true);
    buffer = renderer.nextBuffer;
    raw = OpenTuiBindings();
    handle = buffer.handle;
    buffer.clear(_bg);
  });

  tearDown(() => renderer.dispose());

  String rowText(int y) {
    final row = StringBuffer();
    for (var x = 0; x < 8; x++) {
      row.write(debugResolveBufferCell(buffer, y * 8 + x));
    }
    return row.toString();
  }

  group('native scissor stack', () {
    test('confines writes to the pushed rectangle', () {
      raw.bufferPushScissorRect(handle, 0, 0, 8, 2);
      addTearDown(() => raw.bufferClearScissorRects(handle));

      raw.bufferDrawText(handle, 'INSIDE', 0, 1, _fg, null, 0);
      raw.bufferDrawText(handle, 'OUTSIDE', 0, 3, _fg, null, 0);

      expect(rowText(1), 'INSIDE  ', reason: 'row 1 is inside the scissor');
      expect(
        rowText(3).trim(),
        isEmpty,
        reason: 'row 3 is outside the scissor and must be dropped',
      );
    });

    test('popping restores the previous clip', () {
      raw.bufferPushScissorRect(handle, 0, 0, 8, 2);
      raw.bufferDrawText(handle, 'DROPPED', 0, 3, _fg, null, 0);
      expect(rowText(3).trim(), isEmpty);

      raw.bufferPopScissorRect(handle);
      raw.bufferDrawText(handle, 'KEPT', 0, 3, _fg, null, 0);
      expect(
        rowText(3),
        'KEPT    ',
        reason: 'the pop must restore unclipped writing',
      );
    });

    test('clearing drops every pushed rectangle', () {
      raw
        ..bufferPushScissorRect(handle, 0, 0, 8, 1)
        ..bufferPushScissorRect(handle, 0, 0, 4, 1)
        ..bufferClearScissorRects(handle)
        ..bufferDrawText(handle, 'ALL', 0, 3, _fg, null, 0);

      expect(rowText(3), 'ALL     ');
    });

    test('rejects an out-of-domain rectangle before the native call', () {
      expect(
        () => raw.bufferPushScissorRect(handle, 0, 0, -1, 4),
        throwsA(isA<RangeError>()),
        reason: 'width is u32 in the pinned ABI',
      );
      expect(
        () => raw.bufferPushScissorRect(handle, 0x80000000, 0, 4, 4),
        throwsA(isA<RangeError>()),
        reason: 'x is i32 in the pinned ABI',
      );
    });
  });

  group('native opacity stack', () {
    test('a fully transparent push drops the write', () {
      raw.bufferPushOpacity(handle, 0);
      addTearDown(() => raw.bufferClearOpacity(handle));

      raw.bufferDrawText(handle, 'GHOST', 0, 0, _fg, _red, 0);
      expect(rowText(0).trim(), isEmpty);
    });

    test('popping restores full opacity', () {
      raw
        ..bufferPushOpacity(handle, 0)
        ..bufferPopOpacity(handle)
        ..bufferDrawText(handle, 'SOLID', 0, 0, _fg, _red, 0);

      expect(rowText(0), 'SOLID   ');
    });

    test('rejects an opacity outside the unit range', () {
      for (final invalid in <double>[-0.1, 1.1, double.nan]) {
        expect(
          () => raw.bufferPushOpacity(handle, invalid),
          throwsA(isA<RangeError>()),
          reason: '$invalid is outside 0.0..1.0',
        );
      }
    });
  });
}
