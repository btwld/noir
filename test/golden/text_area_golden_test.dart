import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/golden_testing.dart';
import '../helpers/test_element_host.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('TextArea Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 20, height: 6);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('placeholder shows when empty and unfocused', () async {
      const widget = TextArea(
        height: 3,
        width: 18,
        placeholder: 'Type here...',
      );
      await tester.expectGolden(
        widget,
        'text_area_placeholder',
        updateGoldens: _updateGoldens,
      );
    });

    test('multi-line value renders each line', () async {
      const widget = TextArea(
        height: 4,
        width: 18,
        value: 'line one\nline two\nline three',
      );
      await tester.expectGolden(
        widget,
        'text_area_multiline',
        updateGoldens: _updateGoldens,
      );
    });

    test('long line is clipped to width (no wrap in v1)', () async {
      const widget = TextArea(
        height: 3,
        width: 10,
        value: 'aaaaaaaaaabbbbbbbbbb',
      );
      await tester.expectGolden(
        widget,
        'text_area_long_line_clipped',
        updateGoldens: _updateGoldens,
      );
    });

    test('focused owned multiline cursor at last-line end', () async {
      final captured = _captureFocused(
        (focusNode) => TextArea(
          value: 'line one\nline two',
          height: 4,
          width: 18,
          focusNode: focusNode,
        ),
      );
      await tester.expectCapturedGolden(
        captured,
        'text_area_focused_owned_end',
        updateGoldens: _updateGoldens,
      );
      // "line two" is 8 chars on row 1 → cursor at (8, 1).
      expect(captured, BufferMatchers.cursorAt(8, 1));
    });

    test('focused external multiline cursor at last-line end', () async {
      final controller = TextEditingController(text: 'line one\nline two');
      final captured = _captureFocused(
        (focusNode) => TextArea(
          controller: controller,
          height: 4,
          width: 18,
          focusNode: focusNode,
        ),
      );
      await tester.expectCapturedGolden(
        captured,
        'text_area_focused_external_end',
        updateGoldens: _updateGoldens,
      );
      expect(captured, BufferMatchers.cursorAt(8, 1));
      expect(controller.selection, const TextSelection.collapsed(offset: 17));
      controller.dispose();
    });

    test('focused programmatic replacement scrolls to document end', () async {
      final controller = TextEditingController(text: 'a\nb');
      final session = _FocusedAreaSession(
        (focusNode) => TextArea(
          controller: controller,
          height: 3,
          width: 12,
          focusNode: focusNode,
        ),
      );
      controller.text = 'row0\nrow1\nrow2\nrow3';
      final captured = session.paint();
      await tester.expectCapturedGolden(
        captured,
        'text_area_focused_programmatic_end',
        updateGoldens: _updateGoldens,
      );
      expect(captured.cursor.visible, isTrue);
      // Viewport height 3 → last visible row is y=2 after scroll-to-end.
      expect(captured.cursor.y, 2);
      expect(
        controller.selection,
        TextSelection.collapsed(offset: controller.text.length),
      );
      session.dispose();
      controller.dispose();
    });

    test('unfocused cleared selection hides cursor', () async {
      final controller = TextEditingController(text: 'line one\nline two');
      final capture = BufferCapture(width: 20, height: 6);
      final captured = capture.capture(
        TextArea(controller: controller, height: 4, width: 18),
      );
      await tester.expectCapturedGolden(
        captured,
        'text_area_unfocused_hidden_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(captured.cursor.visible, isFalse);
      expect(controller.selection.isValid, isFalse);
      capture.dispose();
      controller.dispose();
    });

    test('blur hides cursor then refocus repairs and shows it', () async {
      final controller = TextEditingController(text: 'ab\ncd');
      final session = _FocusedAreaSession(
        (focusNode) => TextArea(
          controller: controller,
          height: 4,
          width: 18,
          focusNode: focusNode,
        ),
      );

      session.focusNode.unfocus();
      controller.text = 'x\ny\nz';
      final blurred = session.paint();
      await tester.expectCapturedGolden(
        blurred,
        'text_area_blur_hidden_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(blurred.cursor.visible, isFalse);

      session.focusNode.requestFocus();
      final refocused = session.paint();
      await tester.expectCapturedGolden(
        refocused,
        'text_area_refocus_repaired_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(refocused.cursor.visible, isTrue);
      expect(controller.selection, const TextSelection.collapsed(offset: 5));

      session.dispose();
      controller.dispose();
    });
  });
}

CapturedBuffer _captureFocused(Widget Function(FocusNode focusNode) builder) {
  final session = _FocusedAreaSession(builder);
  final captured = session.paint();
  session.dispose();
  return captured;
}

class _FocusedAreaSession {
  _FocusedAreaSession(Widget Function(FocusNode focusNode) builder)
    : focusNode = FocusNode(),
      _renderer = Renderer.create(20, 6, testing: true) {
    _buffer = _renderer.nextBuffer;
    _host = TestElementHost(renderer: _renderer)..mount(builder(focusNode));
    focusNode.requestFocus();
    paint();
  }

  final FocusNode focusNode;
  final Renderer _renderer;
  late final Buffer _buffer;
  late final TestElementHost _host;

  CapturedBuffer paint() {
    _buffer.clear(Color.black);
    _host.pumpFrame(buffer: _buffer);
    final cc = _host.owner.cursorController;
    return CapturedBuffer.fromBuffer(
      _buffer,
      cursor: CapturedCursor(
        visible: cc.isVisible,
        x: cc.x,
        y: cc.y,
        style: cc.style,
        color: cc.color,
        blinking: cc.blinking,
      ),
    );
  }

  void dispose() {
    _host.dispose();
    _renderer.dispose();
    focusNode.dispose();
  }
}
