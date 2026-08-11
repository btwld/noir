import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('TextBuffer lifecycle', () {
    test('dispose releases native storage and is idempotent', () {
      final buffer = TextBuffer.create()
        ..writeChunk('abc', Color.white, Color.black, 0);

      expect(buffer.dispose, returnsNormally);
      expect(buffer.dispose, returnsNormally);
    });

    test('operations fail after dispose', () {
      final buffer = TextBuffer.create()..dispose();

      expect(() => buffer.length, throwsStateError);
      expect(
        () => buffer.setCell(-1, '', Color.white, Color.black, -1),
        throwsStateError,
      );
      expect(
        () => buffer.writeChunk('x', Color.white, Color.black, -1),
        throwsStateError,
      );
      expect(
        () => buffer.setSelection(-1, 0x100000000, Color.blue, Color.yellow),
        throwsStateError,
      );
      expect(buffer.finalizeLineInfo, throwsStateError);
      expect(buffer.getDirectAccess, throwsStateError);
    });

    test('line metadata comes from native TextBuffer APIs', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer
        ..writeChunk('A\nBB', Color.white, Color.black, 0)
        ..finalizeLineInfo();

      expect(buffer.lineCount, 2);
      expect(buffer.lineStarts, [0, 2]);
      expect(buffer.lineWidths, [1, 2]);
    });

    test('direct access is available for native-owned empty buffers', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      final direct = buffer.getDirectAccess();

      expect(direct.length, 0);
      expect(direct.encodedCells, isEmpty);
      expect(direct.foregrounds, isEmpty);
      expect(direct.backgrounds, isEmpty);
      expect(direct.attributes, isEmpty);
    });

    test('length tracks logical cells from creation through reset', () {
      final buffer = TextBuffer.create(widthMethod: WidthMethod.wcwidth);
      addTearDown(buffer.dispose);

      expect(buffer.length, 0);
      buffer.writeChunk('abc', Color.white, Color.black, 0);
      expect(buffer.length, 3);

      buffer.setCell(5, 'Z', Color.white, Color.black, 0);
      expect(buffer.length, 6);

      buffer.reset();
      expect(buffer.length, 0);
      expect(buffer.getDirectAccess().length, 0);
    });

    test('direct access reads non-empty native TextBuffer views', () {
      const foreground = Color(0.25, 0.5, 0.75);
      const background = Color(0.1, 0.2, 0.3);
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer.writeChunk('A', foreground, background, 7);
      final direct = buffer.getDirectAccess();

      expect(direct.length, 1);
      expect(direct.encodedCells, [65]);
      expect(direct.attributes, [7]);
      expect(direct.foregrounds[0], closeTo(foreground.r, 1e-6));
      expect(direct.foregrounds[1], closeTo(foreground.g, 1e-6));
      expect(direct.foregrounds[2], closeTo(foreground.b, 1e-6));
      expect(direct.foregrounds[3], closeTo(foreground.a, 1e-6));
      expect(direct.backgrounds[0], closeTo(background.r, 1e-6));
      expect(direct.backgrounds[1], closeTo(background.g, 1e-6));
      expect(direct.backgrounds[2], closeTo(background.b, 1e-6));
      expect(direct.backgrounds[3], closeTo(background.a, 1e-6));
    });

    test('writeChunk validates its unsigned attribute mask before writing', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      for (final attributes in [-1, 0x100]) {
        expect(
          () => buffer.writeChunk('x', Color.white, Color.black, attributes),
          throwsA(_rangeNamed('attributes')),
        );
      }
      expect(buffer.length, 0);

      buffer
        ..writeChunk('A', Color.white, Color.black, 0)
        ..writeChunk('B', Color.white, Color.black, 0xFF);
      expect(buffer.getDirectAccess().attributes, [0, 0xFF]);
    });

    test('selection is ordered u32 and may select later writes', () {
      final renderer = Renderer.create(4, 1, testing: true);
      final buffer = TextBuffer.create()
        ..writeChunk('A', Color.white, Color.black, 0);
      addTearDown(renderer.dispose);
      addTearDown(buffer.dispose);

      const outside = [-1, 0x100000000];
      _expectBounds('start', outside, (value) {
        buffer.setSelection(value, 1, Color.blue, Color.yellow);
      });
      _expectBounds('end', outside, (value) {
        buffer.setSelection(0, value, Color.blue, Color.yellow);
      });
      expect(
        () => buffer.setSelection(3, 2, Color.blue, Color.yellow),
        throwsA(
          _argumentNamed('end', 2, 'must be greater than or equal to start'),
        ),
      );

      buffer
        ..setSelection(1, 1, Color.blue, Color.yellow)
        ..setSelection(1, 3, Color.blue, Color.yellow)
        ..writeChunk('BC', Color.white, Color.black, 0);
      final output = renderer.nextBuffer..drawTextBuffer(buffer, 0, 0);
      final direct = output.getDirectAccess();
      expect(direct.getBackground(0, 0), Color.black);
      expect(direct.getBackground(1, 0), Color.blue);
      expect(direct.getForeground(1, 0), Color.yellow);
      expect(direct.getBackground(2, 0), Color.blue);
    });

    test('setCell writes through the native TextBuffer ABI', () {
      const foreground = Color.yellow;
      const background = Color.blue;
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer.setCell(2, 'Z', foreground, background, 9);
      final direct = buffer.getDirectAccess();

      expect(direct.length, 3);
      expect(direct.encodedCells, [32, 32, 90]);
      expect(direct.attributes, [0, 0, 9]);
      expect(direct.foregrounds[8], closeTo(foreground.r, 1e-6));
      expect(direct.foregrounds[9], closeTo(foreground.g, 1e-6));
      expect(direct.foregrounds[10], closeTo(foreground.b, 1e-6));
      expect(direct.foregrounds[11], closeTo(foreground.a, 1e-6));
      expect(direct.backgrounds[8], closeTo(background.r, 1e-6));
      expect(direct.backgrounds[9], closeTo(background.g, 1e-6));
      expect(direct.backgrounds[10], closeTo(background.b, 1e-6));
      expect(direct.backgrounds[11], closeTo(background.a, 1e-6));
    });

    test('validates scalars and widths before exposing encoded cells', () {
      final renderer = Renderer.create(3, 1, testing: true);
      final textBuffer = TextBuffer.create();
      addTearDown(renderer.dispose);
      addTearDown(textBuffer.dispose);

      for (final scalar in [
        '',
        'AB',
        String.fromCharCode(0xD800),
        String.fromCharCode(0xDC00),
      ]) {
        expect(
          () => textBuffer.setCell(0, scalar, Color.white, Color.black, 0),
          throwsA(
            isA<ArgumentError>().having(
              (error) => error.name,
              'name',
              'scalar',
            ),
          ),
          reason: 'code units ${scalar.codeUnits}',
        );
      }
      for (final index in [-1, 0x100000000]) {
        expect(
          () => textBuffer.setCell(index, 'Z', Color.white, Color.black, 0),
          throwsA(
            isA<RangeError>().having((error) => error.name, 'name', 'index'),
          ),
        );
      }
      for (final attributes in [-1, 0x10000]) {
        expect(
          () =>
              textBuffer.setCell(0, 'Z', Color.white, Color.black, attributes),
          throwsA(
            isA<RangeError>().having(
              (error) => error.name,
              'name',
              'attributes',
            ),
          ),
        );
      }
      expect(textBuffer.length, 0, reason: 'invalid values must not reach FFI');
      textBuffer
        ..setCell(0, 'Z', Color.white, Color.black, 0)
        ..setCell(1, '😀', Color.white, Color.black, 0);
      expect(textBuffer.getDirectAccess().encodedCells, [90, 0x1F600]);

      textBuffer
        ..reset()
        ..writeChunk('中A', Color.white, Color.black, 0);
      final words = textBuffer.getDirectAccess().encodedCells;
      expect(words.map((word) => word & 0xC0000000), [
        0x80000000,
        0xC0000000,
        0,
      ]);
      expect(words[2], 65);

      textBuffer
        ..reset()
        ..writeChunk('ABC', Color.white, Color.black, 0)
        ..setSelection(1, 2, Color.blue, Color.yellow);
      final buffer = renderer.nextBuffer..drawTextBuffer(textBuffer, 0, 0);
      final direct = buffer.getDirectAccess();
      expect(direct.getBackground(0, 0), Color.black);
      expect(direct.getBackground(1, 0), Color.blue);
      expect(direct.getForeground(1, 0), Color.yellow);
      expect(direct.getBackground(2, 0), Color.black);
    });

    test('base and clipped draws validate lifecycles before fixed widths', () {
      final renderer = Renderer.create(3, 1, testing: true);
      final source = TextBuffer.create()
        ..writeChunk('A', Color.white, Color.black, 0)
        ..finalizeLineInfo();
      addTearDown(renderer.dispose);
      addTearDown(source.dispose);
      Buffer clipped(Buffer buffer) =>
          buffer.clipped(clipX: 0, clipY: 0, clipWidth: 2, clipHeight: 1);
      final root = renderer.nextBuffer;
      final view = clipped(root);

      void draw(Buffer buffer, List<int?> values) => buffer.drawTextBuffer(
        source,
        values[0]!,
        values[1]!,
        clipX: values[2],
        clipY: values[3],
        clipWidth: values[4],
        clipHeight: values[5],
      );

      const minI32 = -0x80000000;
      const maxI32 = 0x7FFFFFFF;
      const i32Outside = [-0x80000001, 0x80000000];
      const u32Outside = [-1, 0x100000000];
      final boundaries = <(String, List<int>, int)>[
        ('x', i32Outside, 0),
        ('y', i32Outside, 1),
        ('clipX', i32Outside, 2),
        ('clipY', i32Outside, 3),
        ('clipWidth', u32Outside, 4),
        ('clipHeight', u32Outside, 5),
      ];
      for (final buffer in [root, view]) {
        draw(buffer, [minI32, maxI32, -1, 0, 0, 0xFFFFFFFF]);
        draw(buffer, [maxI32, minI32, maxI32, -1, 0xFFFFFFFF, 0]);
        for (final (name, outside, slot) in boundaries) {
          _expectBounds(name, outside, (value) {
            final values = <int?>[0, 0, null, null, null, null];
            draw(buffer, values..[slot] = value);
          });
        }
      }

      final disposedSource = TextBuffer.create()..dispose();
      renderer.render(force: true, autoFlush: false);
      for (final destination in [root, view]) {
        expect(
          () => destination.drawTextBuffer(disposedSource, 0x80000000, 0),
          throwsA(_stateContaining('Buffer has been invalidated')),
        );
      }
      final freshRoot = renderer.nextBuffer;
      final freshView = clipped(freshRoot);
      for (final destination in [freshRoot, freshView]) {
        expect(
          () => destination.drawTextBuffer(disposedSource, 0x80000000, 0),
          throwsA(_stateContaining('TextBuffer is disposed')),
        );
      }
    });

    test('guarded raw TextBuffer widths reject before native invocation', () {
      final bindings = OpenTuiBindings();
      final renderer = Renderer.create(3, 1, testing: true);
      final textBuffer = TextBuffer.create();
      final byte = calloc<Uint8>()..value = 65;
      addTearDown(renderer.dispose);
      addTearDown(textBuffer.dispose);
      addTearDown(() => calloc.free(byte));
      final textHandle = textBuffer.handle;
      final bufferHandle = renderer.nextBuffer.handle;

      final raw = bindings;
      final handle = textHandle;
      const fg = Color.white;
      const bg = Color.black;
      void setCell(int index, int code, int attrs) =>
          raw.textBufferSetCell(handle, index, code, fg, bg, attrs);
      void writeString(int attrs) =>
          raw.textBufferWriteChunk(handle, 'x', fg, bg, attrs);
      void writeBytes(int length, int attrs) =>
          raw.textBufferWriteUtf8Chunk(handle, byte, length, fg, bg, attrs);
      void selection(int start, int end) => raw.textBufferSetSelection(
        handle,
        start,
        end,
        Color.blue,
        Color.yellow,
      );
      void draw(int x, int y, int clipX, int clipY, int width, int height) =>
          raw.bufferDrawTextBuffer(
            bufferHandle,
            handle,
            x,
            y,
            clipX,
            clipY,
            width,
            height,
            false,
          );

      const u32Outside = [-1, 0x100000000];
      _expectBounds('abiLength', u32Outside, (value) {
        bindings.createTextBuffer(value, 0);
      });
      _expectBounds('index', u32Outside, (value) => setCell(value, 65, 0));
      _expectBounds('charCode', u32Outside, (value) => setCell(0, value, 0));
      _expectBounds('textLen', u32Outside, (value) => writeBytes(value, 0));
      _expectBounds('start', u32Outside, (value) => selection(value, 0));
      _expectBounds('end', u32Outside, (value) => selection(0, value));
      _expectBounds(
        'clipWidth',
        u32Outside,
        (value) => draw(0, 0, 0, 0, value, 0),
      );
      _expectBounds(
        'clipHeight',
        u32Outside,
        (value) => draw(0, 0, 0, 0, 0, value),
      );
      const u8Outside = [-1, 0x100];
      _expectBounds('widthMethod', u8Outside, (value) {
        bindings.createTextBuffer(0, value);
      });
      _expectBounds('attributes', u8Outside, writeString);
      _expectBounds('attributes', u8Outside, (value) => writeBytes(1, value));
      _expectBounds('attributes', const [-1, 0x10000], (value) {
        setCell(0, 65, value);
      });
      const i32Outside = [-0x80000001, 0x80000000];
      _expectBounds('x', i32Outside, (value) => draw(value, 0, 0, 0, 0, 0));
      _expectBounds('y', i32Outside, (value) => draw(0, value, 0, 0, 0, 0));
      _expectBounds('clipX', i32Outside, (value) => draw(0, 0, value, 0, 0, 0));
      _expectBounds('clipY', i32Outside, (value) => draw(0, 0, 0, value, 0, 0));

      for (final range in const [(9, 2), (2, 2), (2, 0xFFFFFFFF)]) {
        selection(range.$1, range.$2);
      }
      draw(
        -0x80000000,
        0x7FFFFFFF,
        -0x80000000,
        0x7FFFFFFF,
        0xFFFFFFFF,
        0xFFFFFFFF,
      );
      draw(0x7FFFFFFF, -0x80000000, 0x7FFFFFFF, -0x80000000, 0, 0);
    });
  });

  group('TextBuffer line-metadata staleness', () {
    test('writeChunk marks line metadata stale until finalizeLineInfo', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer.writeChunk('A\nB', Color.white, Color.black, 0);
      expect(
        () => buffer.lineCount,
        throwsA(_stateContaining('finalizeLineInfo')),
      );
      expect(
        () => buffer.lineStarts,
        throwsA(_stateContaining('finalizeLineInfo')),
      );
      expect(
        () => buffer.lineWidths,
        throwsA(_stateContaining('finalizeLineInfo')),
      );

      buffer.finalizeLineInfo();
      expect(buffer.lineCount, 2);
      expect(buffer.lineStarts, [0, 2]);
      expect(buffer.lineWidths, [1, 1]);

      buffer.writeChunk('C', Color.white, Color.black, 0);
      expect(
        () => buffer.lineCount,
        throwsA(_stateContaining('finalizeLineInfo')),
      );
    });

    test('setCell marks line metadata stale until finalizeLineInfo', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer.setCell(0, 'Z', Color.white, Color.black, 0);
      expect(
        () => buffer.lineCount,
        throwsA(_stateContaining('finalizeLineInfo')),
      );

      buffer.finalizeLineInfo();
      expect(buffer.lineCount, 1);
    });

    test('reset restores line-metadata reads without finalizeLineInfo', () {
      final buffer = TextBuffer.create();
      addTearDown(buffer.dispose);

      buffer.writeChunk('A\nB', Color.white, Color.black, 0);
      expect(
        () => buffer.lineCount,
        throwsA(_stateContaining('finalizeLineInfo')),
      );

      buffer.reset();
      expect(buffer.lineCount, 1);
      expect(buffer.lineStarts, [0]);
      expect(buffer.lineWidths, [0]);
    });

    test('clipped draws reject stale sources and accept finalized ones', () {
      final renderer = Renderer.create(3, 1, testing: true);
      final source = TextBuffer.create()
        ..writeChunk('A', Color.white, Color.black, 0);
      addTearDown(renderer.dispose);
      addTearDown(source.dispose);

      final view = renderer.nextBuffer.clipped(
        clipX: 0,
        clipY: 0,
        clipWidth: 2,
        clipHeight: 1,
      );
      expect(
        () => view.drawTextBuffer(source, 0, 0),
        throwsA(_stateContaining('finalizeLineInfo')),
      );

      source.finalizeLineInfo();
      expect(() => view.drawTextBuffer(source, 0, 0), returnsNormally);
    });
  });
}

Matcher _rangeNamed(String name) =>
    isA<RangeError>().having((error) => error.name, 'name', name);

Matcher _argumentNamed(String name, Object? value, String message) =>
    isA<ArgumentError>()
        .having((error) => error.name, 'name', name)
        .having((error) => error.invalidValue, 'invalidValue', value)
        .having((error) => error.message, 'message', message);

Matcher _stateContaining(String text) => isA<StateError>().having(
  (error) => error.message,
  'message',
  contains(text),
);

void _expectBounds(String name, List<int> values, void Function(int) invoke) {
  for (final value in values) {
    expect(() => invoke(value), throwsA(_rangeNamed(name)));
  }
}
