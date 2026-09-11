import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/renderer.dart' show createRendererForTesting;
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:test/test.dart';

const _fg = Color.white;
const _bg = Color.black;
final _box = BoxOptions();
const _u32Outside = [-1, 0x100000000];
const _i32Outside = [-0x80000001, 0x80000000];

void main() {
  group('Buffer validity', () {
    test(
      'renderer.render() invalidates both root buffer and clipped views',
      () {
        final renderer = Renderer.create(20, 5, testing: true);
        addTearDown(renderer.dispose);

        final root = renderer.nextBuffer;
        final view = root.clipped(
          clipX: 0,
          clipY: 0,
          clipWidth: 10,
          clipHeight: 2,
        );

        // Both should be valid before render.
        expect(root.isInvalidated, isFalse);
        expect(view.isInvalidated, isFalse);
        root.drawText('hi', 0, 0, Color.white); // does not throw

        renderer.render(force: true);

        expect(
          root.isInvalidated,
          isTrue,
          reason: 'root buffer must invalidate after render',
        );
        expect(
          view.isInvalidated,
          isTrue,
          reason: 'clipped view must share parent validity',
        );

        expect(
          () => root.drawText('x', 0, 0, Color.white),
          throwsA(isA<StateError>()),
        );
        expect(
          () => view.drawText('x', 0, 0, Color.white),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('renderer.resize() invalidates the active buffer', () {
      final renderer = Renderer.create(20, 5, testing: true);
      addTearDown(renderer.dispose);

      final root = renderer.nextBuffer;
      renderer.resize(40, 10);

      expect(root.isInvalidated, isTrue);
      expect(() => root.clear(Color.black), throwsA(isA<StateError>()));

      // Fresh buffer after resize is fine.
      expect(() => renderer.nextBuffer.clear(Color.black), returnsNormally);
    });

    test('renderer.dispose() invalidates the active buffer', () {
      final renderer = Renderer.create(20, 5, testing: true);
      final root = renderer.nextBuffer;
      final view = root.clipped(
        clipX: 0,
        clipY: 0,
        clipWidth: 5,
        clipHeight: 5,
      );

      renderer.dispose();

      expect(root.isInvalidated, isTrue);
      expect(view.isInvalidated, isTrue);
    });

    test('renderer disposal closes non-frame buffer wrappers too', () {
      final renderer = Renderer.create(20, 5, testing: true);
      final current = renderer.debugCurrentBuffer;
      final access = current.getDirectAccess();

      renderer.dispose();

      expect(current.isInvalidated, isTrue);
      expect(() => current.clear(Color.black), throwsA(isA<StateError>()));
      expect(() => access.getChar(0, 0), throwsA(isA<StateError>()));
    });

    test('render and resize invalidate current-buffer wrappers', () {
      final renderer = Renderer.create(20, 5, testing: true);
      addTearDown(renderer.dispose);

      final beforeRender = renderer.debugCurrentBuffer;
      renderer.render(force: true);
      expect(beforeRender.isInvalidated, isTrue);

      final beforeResize = renderer.debugCurrentBuffer;
      renderer.resize(10, 2);
      expect(beforeResize.isInvalidated, isTrue);
    });

    test('buffer resize invalidates issued direct access only', () {
      final renderer = Renderer.create(20, 5, testing: true);
      addTearDown(renderer.dispose);
      final buffer = renderer.nextBuffer;
      final beforeResize = buffer.getDirectAccess();

      buffer.resize(10, 2);

      expect(() => beforeResize.width, throwsA(_invalidatedState));
      expect(buffer.isInvalidated, isFalse);
      final afterResize = buffer.getDirectAccess();
      expect((afterResize.width, afterResize.height), (10, 2));
      afterResize.setChar(9, 1, 'x');
      expect(afterResize.getChar(9, 1), 'x');
    });

    test('direct access checks buffer validity on every operation', () {
      final renderer = Renderer.create(20, 5, testing: true);
      addTearDown(renderer.dispose);
      final access = renderer.nextBuffer.getDirectAccess();

      renderer.render(force: true);

      for (final operation in <void Function()>[
        () => access.width,
        () => access.height,
        () => access.length,
        () => access.getEncodedCellAt(0),
        () => access.setEncodedCellAt(0, 0),
        () => access.getChar(0, 0),
        () => access.setChar(0, 0, 'x'),
        () => access.getForeground(0, 0),
        () => access.setForeground(0, 0, Color.white),
        () => access.getBackground(0, 0),
        () => access.setBackground(0, 0, Color.black),
        () => access.getAttributes(0, 0),
        () => access.setAttributes(0, 0, Attr.bold),
      ]) {
        expect(operation, throwsA(_invalidatedState));
      }
    });

    test('failed render invalidates a possibly mutated native buffer', () {
      final bindings = OpenTuiBindings.fromNativeSymbols(
        _FailingRenderNativeSymbols(),
      );
      final renderer = createRendererForTesting(
        bindings,
        RendererHandle.fromNative(1),
      );
      addTearDown(renderer.dispose);

      final failedFrame = renderer.nextBuffer;
      expect(
        () => renderer.render(force: true, autoFlush: false),
        throwsA(isA<FFIException>()),
      );
      expect(failedFrame.isInvalidated, isTrue);
      expect(renderer.nextBuffer.isInvalidated, isFalse);
    });
  });

  group('Buffer fixed-width boundaries', () {
    late Renderer renderer;
    late Buffer buffer;
    Buffer clip(int x, int y, int w, int h) =>
        buffer.clipped(clipX: x, clipY: y, clipWidth: w, clipHeight: h);

    setUp(() {
      renderer = Renderer.create(20, 5, testing: true);
      buffer = renderer.nextBuffer;
    });

    tearDown(() => renderer.dispose());

    test('cell writes reject out-of-domain attributes instead of masking', () {
      void put(int a) => buffer.setCell(0, 0, 'A', _fg, _bg, a);
      void blend(int a) =>
          buffer.setCellWithAlphaBlending(0, 0, 'A', _fg, _bg, a);
      _expectBounds('attributes', _u32Outside, put);
      _expectBounds('attributes', _u32Outside, blend);
      blend(0xFFFFFFFF);
      expect(buffer.getDirectAccess().getAttributes(0, 0), 0xFFFFFFFF);
    });

    test('direct access setAttributes rejects out-of-domain values', () {
      final access = buffer.getDirectAccess();
      _expectBounds('attr', _u32Outside, (v) => access.setAttributes(0, 0, v));
      access.setAttributes(0, 0, 0xFFFFFFFF);
      expect(access.getAttributes(0, 0), 0xFFFFFFFF);
      // setChar needs no domain check: Dart runes are bounded by 0x10FFFF,
      // inside the u32 domain of the chars view.
      access.setChar(0, 0, '\u{1F600}');
      expect(access.getChar(0, 0), '\u{1F600}');
      access.setEncodedCellAt(0, 0xFFFFFFFF);
      expect(access.getEncodedCellAt(0), 0xFFFFFFFF);
      _expectBounds('value', _u32Outside, (v) => access.setEncodedCellAt(0, v));
    });

    test('drawText validates origins and attributes before native clips', () {
      void draw(int x, int y, int a) =>
          buffer.drawText('x', x, y, _fg, attributes: a);
      _expectBounds('x', _u32Outside, (v) => draw(v, 0, 0));
      _expectBounds('y', _u32Outside, (v) => draw(0, v, 0));
      _expectBounds('attributes', _u32Outside, (v) => draw(0, 0, v));
      // In-domain coordinates beyond the buffer clip natively.
      expect(() => draw(0xFFFFFFFF, 0xFFFFFFFF, 0xFF), returnsNormally);
    });

    test('fillRect validates four unsigned values before native clamps', () {
      void fill(int x, int y, int w, int h) => buffer.fillRect(x, y, w, h, _bg);
      _expectBounds('x', _u32Outside, (v) => fill(v, 0, 1, 1));
      _expectBounds('y', _u32Outside, (v) => fill(0, v, 1, 1));
      _expectBounds('width', _u32Outside, (v) => fill(0, 0, v, 1));
      _expectBounds('height', _u32Outside, (v) => fill(0, 0, 1, v));
      expect(() => fill(0xFFFFFFFF, 0xFFFFFFFF, 1, 1), returnsNormally);
    });

    test('drawBox validates signed origins before native span math', () {
      // Extents keep truncated origins inside native i32 span math during RED.
      void box(int x, int y, int w, int h) =>
          buffer.drawBox(x, y, w, h, _box, _fg, _bg);
      expect(() => box(-0x80000001, 0, 0, 0), throwsA(_rangeNamed('x')));
      expect(() => box(0x80000000, 0, 1, 1), throwsA(_rangeNamed('x')));
      expect(() => box(0, -0x80000001, 0, 0), throwsA(_rangeNamed('y')));
      expect(() => box(0, 0x80000000, 1, 1), throwsA(_rangeNamed('y')));
      expect(() => box(-0x80000000, 0x7FFFFFFF, 1, 0), returnsNormally);
    });

    test('resize validates the unsigned domain before the positive rule', () {
      _expectBounds('newWidth', _u32Outside, (v) => buffer.resize(v, 5));
      _expectBounds('newHeight', _u32Outside, (v) => buffer.resize(5, v));
      expect(() => buffer.resize(-5, 5), throwsA(_rangeNamed('newWidth')));
      expect(() => buffer.resize(0, 5), throwsArgumentError);
      expect(() => buffer.resize(5, 0), throwsArgumentError);
    });

    test('lifecycle failures precede fixed-width domain failures', () {
      renderer.render(force: true);
      expect(buffer.isInvalidated, isTrue);
      for (final call in <void Function()>[
        () => buffer.drawText('x', -1, 0, _fg),
        () => buffer.fillRect(-1, 0, 1, 1, _bg),
        () => buffer.drawBox(-0x80000001, 0, 0, 0, _box, _fg, _bg),
        () => buffer.setCellWithAlphaBlending(0, 0, 'A', _fg, _bg, 0x100000000),
        () => buffer.resize(-5, 5),
      ]) {
        expect(call, throwsA(_invalidatedState));
      }
    });

    test('clipped views validate attributes before the clip drop', () {
      final view = clip(2, 1, 4, 2);
      void put(int a) => view.setCell(0, 0, 'A', _fg, _bg, a);
      void blend(int x, int y, int a) =>
          view.setCellWithAlphaBlending(x, y, 'A', _fg, _bg, a);
      void draw(int x, int y, int a) =>
          view.drawText('x', x, y, _fg, attributes: a);
      // (0, 0) sits outside the clip; the drop happens after validation.
      _expectBounds('attributes', _u32Outside, put);
      _expectBounds('attributes', _u32Outside, (v) => blend(0, 0, v));
      _expectBounds('attributes', _u32Outside, (v) => draw(0, 0, v));
      // In-clip writes reject identically.
      _expectBounds('attributes', _u32Outside, (v) => blend(2, 1, v));
      // Signed logical coordinates outside the clip still drop silently.
      expect(() => view.setCell(-3, -3, 'A', _fg, _bg, 0xFF), returnsNormally);
      expect(() => draw(-5, -5, 0xFF), returnsNormally);
      expect(() => view.fillRect(-4, -4, 2, 2, _bg), returnsNormally);
      blend(2, 1, 0xFF);
      expect(buffer.getDirectAccess().getAttributes(2, 1), 0xFF);
    });

    test('clipped drawBox drops a box that misses the clip entirely', () {
      clip(0, 0, 20, 2).drawBox(1, 3, 8, 2, _box, _fg, _bg);
      final access = buffer.getDirectAccess();
      for (var y = 0; y < 5; y++) {
        expect(access.getChar(1, y), ' ', reason: 'row $y');
      }
      // A box overlapping the clip still reaches native drawBox.
      clip(0, 0, 20, 2).drawBox(1, 0, 8, 2, _box, _fg, _bg);
      expect(buffer.getDirectAccess().getChar(1, 0), isNot(' '));
    });

    test('invalidated clipped views fail closed even outside the clip', () {
      final view = clip(0, 0, 2, 2);
      renderer.render(force: true);
      for (final call in <void Function()>[
        () => view.setCell(50, 50, 'A', _fg, _bg, 0),
        () => view.setCellWithAlphaBlending(50, 50, 'A', _fg, _bg, 0),
        () => view.drawText('x', 50, 50, _fg),
        () => view.fillRect(50, 50, 1, 1, _bg),
        () => view.drawBox(50, 50, 2, 2, _box, _fg, _bg),
      ]) {
        expect(call, throwsA(_invalidatedState));
      }
    });

    test('clipped text preserves full 32-bit attributes without masking', () {
      clip(
        0,
        0,
        10,
        2,
      ).drawText('AB', 0, 0, _fg, bg: _bg, attributes: 0xFFFFFFFF);
      final direct = buffer.getDirectAccess();
      expect(direct.getChar(0, 0), 'A');
      expect(direct.getAttributes(0, 0), 0xFFFFFFFF);
      expect(direct.getAttributes(1, 0), 0xFFFFFFFF);
    });
  });

  group('Clipped view drawText terminal-cell clipping', () {
    late Renderer renderer;
    late Buffer buffer;
    Buffer clip(int x, int y, int w, int h) =>
        buffer.clipped(clipX: x, clipY: y, clipWidth: w, clipHeight: h);
    int cell(int x, int y) =>
        buffer.getDirectAccess().getEncodedCellAt(y * 20 + x);

    setUp(() {
      renderer = Renderer.create(20, 5, testing: true);
      buffer = renderer.nextBuffer..clear(_bg);
    });

    tearDown(() => renderer.dispose());

    test('clip starting mid-string keeps CJK clusters on true columns', () {
      // '中' spans cells 0-1, '文' cells 2-3, 'A' cell 4, 'B' cell 5. A clip
      // starting at cell 2 drops '中' whole and keeps everything from '文'.
      clip(2, 0, 10, 5).drawText('中文AB', 0, 0, _fg);
      expect(cell(0, 0), _blankCell);
      expect(cell(1, 0), _blankCell);
      expect(cell(2, 0), _wideStartCell);
      expect(cell(3, 0), _wideContinuationCell);
      expect(_graphemeId(cell(3, 0)), _graphemeId(cell(2, 0)));
      expect(cell(4, 0), 0x41); // 'A'
      expect(cell(5, 0), 0x42); // 'B'
      expect(cell(6, 0), _blankCell);
    });

    test('wide cluster straddling the left clip edge is dropped whole', () {
      // '中' covers cells 0-1 and straddles clipX = 1; the view never paints
      // half a cluster, so both halves stay blank and '文' begins at cell 2.
      clip(1, 0, 10, 5).drawText('中文AB', 0, 0, _fg);
      expect(cell(0, 0), _blankCell);
      expect(cell(1, 0), _blankCell);
      expect(cell(2, 0), _wideStartCell);
      expect(cell(3, 0), _wideContinuationCell);
      expect(cell(4, 0), 0x41);
      expect(cell(5, 0), 0x42);
    });

    test('wide cluster straddling the right clip edge is dropped whole', () {
      // Clip width 3 fits '中' (cells 0-1) but only half of '文' (cells 2-3),
      // so '文' and everything after it stay unpainted.
      clip(0, 0, 3, 5).drawText('中文AB', 0, 0, _fg);
      expect(cell(0, 0), _wideStartCell);
      expect(cell(1, 0), _wideContinuationCell);
      expect(cell(2, 0), _blankCell);
      expect(cell(3, 0), _blankCell);
      expect(cell(4, 0), _blankCell);
    });

    test('astral-plane emoji clips by cells without splitting surrogates', () {
      // U+1F600 is two UTF-16 code units but two terminal cells; straddling
      // clipX = 1 drops the whole cluster and never emits a lone surrogate.
      clip(1, 0, 10, 5).drawText('\u{1F600}AB', 0, 0, _fg);
      expect(cell(0, 0), _blankCell);
      expect(cell(1, 0), _blankCell);
      expect(cell(2, 0), 0x41);
      expect(cell(3, 0), 0x42);
      // Fully inside the clip the emoji keeps its packed two-cell layout.
      clip(1, 0, 10, 5).drawText('\u{1F600}AB', 2, 1, _fg);
      expect(cell(2, 1), _wideStartCell);
      expect(cell(3, 1), _wideContinuationCell);
      expect(cell(4, 1), 0x41);
      expect(cell(5, 1), 0x42);
    });

    test('ASCII clipping preserves the existing column behavior', () {
      final view = clip(2, 0, 2, 5)..drawText('ABCDE', 0, 0, _fg);
      expect(cell(0, 0), _blankCell);
      expect(cell(1, 0), _blankCell);
      expect(cell(2, 0), 0x43); // 'C'
      expect(cell(3, 0), 0x44); // 'D'
      expect(cell(4, 0), _blankCell);
      // Entirely left of the clip and at/after the right clip edge: both
      // dropped whole.
      view
        ..drawText('AB', 0, 1, _fg)
        ..drawText('AB', 4, 2, _fg);
      for (var x = 0; x < 8; x++) {
        expect(cell(x, 1), _blankCell);
        expect(cell(x, 2), _blankCell);
      }
    });
  });

  group('Buffer fixed-width guarded rejections', () {
    // Written during RED but first executed once production validation
    // existed: unguarded FFI would truncate these into native out-of-domain
    // arithmetic.
    late Renderer renderer;
    late Buffer buffer;

    setUp(() {
      renderer = Renderer.create(20, 5, testing: true);
      buffer = renderer.nextBuffer;
    });

    tearDown(() => renderer.dispose());

    test('drawBox rejects out-of-domain unsigned extents before FFI', () {
      void box(int w, int h) => buffer.drawBox(0, 0, w, h, _box, _fg, _bg);
      _expectBounds('width', _u32Outside, (v) => box(v, 1));
      _expectBounds('height', _u32Outside, (v) => box(1, v));
    });

    test('drawFrameBuffer validates lifecycles, sources, and dests', () {
      final sourceRenderer = Renderer.create(4, 2, testing: true);
      addTearDown(sourceRenderer.dispose);
      final source = sourceRenderer.nextBuffer;
      void draw(int sx, int sy, int sw, int sh, int dx, int dy) =>
          buffer.drawFrameBuffer(source, sx, sy, sw, sh, dx, dy);
      _expectBounds('srcX', _u32Outside, (v) => draw(v, 0, 1, 1, 0, 0));
      _expectBounds('srcY', _u32Outside, (v) => draw(0, v, 1, 1, 0, 0));
      _expectBounds('srcWidth', _u32Outside, (v) => draw(0, 0, v, 1, 0, 0));
      _expectBounds('srcHeight', _u32Outside, (v) => draw(0, 0, 1, v, 0, 0));
      _expectBounds('destX', _i32Outside, (v) => draw(0, 0, 1, 1, v, 0));
      _expectBounds('destY', _i32Outside, (v) => draw(0, 0, 1, 1, 0, v));
      // A u32-max source origin stays in domain and clips natively.
      expect(() => draw(0xFFFFFFFF, 0, 1, 1, -1, 0), returnsNormally);
      sourceRenderer.render(force: true);
      expect(() => draw(-1, 0, 1, 1, 0, 0), throwsA(_invalidatedState));
    });

    test('guarded raw Buffer wrappers reject before native invocation', () {
      final raw = OpenTuiBindings();
      final sourceRenderer = Renderer.create(4, 2, testing: true);
      addTearDown(sourceRenderer.dispose);
      final handle = buffer.handle;
      final source = sourceRenderer.nextBuffer.handle;
      void drawText(int x, int y, int a) =>
          raw.bufferDrawText(handle, 'x', x, y, _fg, null, a);
      void fill(int x, int y, int w, int h) =>
          raw.bufferFillRect(handle, x, y, w, h, _bg);
      void box(int x, int y, int w, int h, BoxOptions o) =>
          raw.bufferDrawBox(handle, x, y, w, h, o, _fg, _bg);
      void cell(int x, int y, int code, int a) =>
          raw.bufferSetCellWithAlphaBlending(handle, x, y, code, _fg, _bg, a);
      void copy(int dx, int dy, int sx, int sy, int sw, int sh) =>
          raw.drawFrameBuffer(handle, dx, dy, source, sx, sy, sw, sh);
      void grow(int w, int h) => raw.bufferResize(handle, w, h);

      _expectBounds('x', _u32Outside, (v) => drawText(v, 0, 0));
      _expectBounds('y', _u32Outside, (v) => drawText(0, v, 0));
      _expectBounds('attributes', _u32Outside, (v) => drawText(0, 0, v));
      _expectBounds('x', _u32Outside, (v) => fill(v, 0, 1, 1));
      _expectBounds('y', _u32Outside, (v) => fill(0, v, 1, 1));
      _expectBounds('width', _u32Outside, (v) => fill(0, 0, v, 1));
      _expectBounds('height', _u32Outside, (v) => fill(0, 0, 1, v));
      _expectBounds('x', _i32Outside, (v) => box(v, 0, 1, 1, _box));
      _expectBounds('y', _i32Outside, (v) => box(0, v, 1, 1, _box));
      _expectBounds('width', _u32Outside, (v) => box(0, 0, v, 1, _box));
      _expectBounds('height', _u32Outside, (v) => box(0, 0, 1, v, _box));
      _expectBounds('borderChars', _u32Outside, (v) {
        final chars = List<int>.filled(11, 0x2500)..[0] = v;
        box(0, 0, 1, 1, BoxOptions(borderChars: chars));
      });
      _expectBounds('x', _u32Outside, (v) => cell(v, 0, 65, 0));
      _expectBounds('y', _u32Outside, (v) => cell(0, v, 65, 0));
      _expectBounds('character', _u32Outside, (v) => cell(0, 0, v, 0));
      _expectBounds('attributes', _u32Outside, (v) => cell(0, 0, 65, v));
      _expectBounds('destX', _i32Outside, (v) => copy(v, 0, 0, 0, 1, 1));
      _expectBounds('destY', _i32Outside, (v) => copy(0, v, 0, 0, 1, 1));
      _expectBounds('sourceX', _u32Outside, (v) => copy(0, 0, v, 0, 1, 1));
      _expectBounds('sourceY', _u32Outside, (v) => copy(0, 0, 0, v, 1, 1));
      _expectBounds('sourceWidth', _u32Outside, (v) => copy(0, 0, 0, 0, v, 1));
      _expectBounds('sourceHeight', _u32Outside, (v) => copy(0, 0, 0, 0, 1, v));
      _expectBounds('width', _u32Outside, (v) => grow(v, 5));
      _expectBounds('height', _u32Outside, (v) => grow(5, v));

      // Accepts at exact bounds where the pinned native math stays in domain.
      expect(
        () => drawText(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF),
        returnsNormally,
      );
      expect(
        () => fill(0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 1),
        returnsNormally,
      );
      expect(() => cell(0, 0, 65, 0xFFFFFFFF), returnsNormally);
      expect(() => copy(-0x80000000, 0, 0xFFFFFFFF, 1, 1, 1), returnsNormally);
    });
  });
}

final class _FailingRenderNativeSymbols implements OpenTuiNativeSymbols {
  @override
  int getNextBuffer(int renderer) => 2;

  @override
  int render(int renderer, bool force) => 2;

  @override
  void destroyRenderer(int renderer) {}

  // `Renderer.nextBuffer` clears the native draw stacks on the buffer it lends
  // out, so a fake backend has to model both calls.
  @override
  void bufferClearScissorRects(int buffer) {}

  @override
  void bufferClearOpacity(int buffer) {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError(invocation.memberName.toString());
}

Matcher _rangeNamed(String name) =>
    isA<RangeError>().having((error) => error.name, 'name', name);

/// Cleared cells hold a plain space.
const _blankCell = 0x20;

/// The native text engine packs a wide grapheme cluster as a start cell
/// (high bits `10`, right extent 1 for a 2-cell cluster) followed by a
/// continuation cell (high bits `11`) sharing the same pool id.
final Matcher _wideStartCell = predicate<int>(
  (code) => (code & 0xC0000000) == 0x80000000 && ((code >> 28) & 0x3) == 1,
  'a packed 2-cell grapheme start cell',
);

final Matcher _wideContinuationCell = predicate<int>(
  (code) => (code & 0xC0000000) == 0xC0000000,
  'a packed grapheme continuation cell',
);

int _graphemeId(int code) => code & 0x03FFFFFF;

final Matcher _invalidatedState = isA<StateError>().having(
  (error) => error.message,
  'message',
  contains('Buffer has been invalidated'),
);

void _expectBounds(String name, List<int> values, void Function(int) invoke) {
  for (final value in values) {
    expect(() => invoke(value), throwsA(_rangeNamed(name)));
  }
}
