import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/golden_testing.dart';
import '../helpers/test_element_host.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// TextInput goldens capture buffer content plus style and cursor sidecars.
/// The cursor is positioned through [CursorController], so its visibility and
/// coordinates are asserted by the cursor sidecar rather than character cells.
void main() {
  group('TextInput Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 30, height: 4);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('empty input shows placeholder text', () async {
      const widget = TextInput(placeholder: 'Type here...');
      await tester.expectGolden(
        widget,
        'text_input_placeholder_only',
        updateGoldens: _updateGoldens,
      );
    });

    test('input with value renders the value', () async {
      const widget = TextInput(value: 'hello');
      await tester.expectGolden(
        widget,
        'text_input_with_value',
        updateGoldens: _updateGoldens,
      );
    });

    test('input with background color fills cells', () async {
      const widget = TextInput(
        value: 'colored',
        backgroundColor: Color(0, 0.2, 0.4),
      );
      await tester.expectGolden(
        widget,
        'text_input_with_bg',
        updateGoldens: _updateGoldens,
      );
    });

    test('obscured input shows asterisks for entered chars', () async {
      // The widget renders the literal value field as-is in the buffer; the
      // `obscureText` flag converts inserted keys to '*' on input. To exercise
      // the visual representation, we pass an already-masked value here.
      const widget = TextInput(value: '*****', obscureText: true);
      await tester.expectGolden(
        widget,
        'text_input_obscured',
        updateGoldens: _updateGoldens,
      );
    });

    test('value with bg writes styles + cursor sidecars (default)', () async {
      // Style + cursor sidecars are written by default for every visual
      // golden; this case documents that the sidecar mechanism is active.
      const widget = TextInput(
        value: 'styled',
        color: Color.yellow,
        backgroundColor: Color(0, 0, 0.5),
      );
      await tester.expectGolden(
        widget,
        'text_input_styled_with_sidecars',
        updateGoldens: _updateGoldens,
      );
    });

    test('focused owned input cursor at document end', () async {
      final captured = _captureFocused(
        (focusNode) => TextInput(value: 'hello', focusNode: focusNode),
      );
      await tester.expectCapturedGolden(
        captured,
        'text_input_focused_owned_end',
        updateGoldens: _updateGoldens,
      );
      expect(captured, BufferMatchers.cursorAt(5, 0));
    });

    test('focused external input cursor at document end', () async {
      final controller = TextEditingController(text: 'hello');
      final captured = _captureFocused(
        (focusNode) => TextInput(controller: controller, focusNode: focusNode),
      );
      await tester.expectCapturedGolden(
        captured,
        'text_input_focused_external_end',
        updateGoldens: _updateGoldens,
      );
      expect(captured, BufferMatchers.cursorAt(5, 0));
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
      controller.dispose();
    });

    test('focused programmatic replacement moves cursor to new end', () async {
      final controller = TextEditingController(text: 'old');
      final session = _FocusedSession(
        (focusNode) => TextInput(controller: controller, focusNode: focusNode),
      );
      controller.text = 'replacement';
      final captured = session.paint();
      await tester.expectCapturedGolden(
        captured,
        'text_input_focused_programmatic_end',
        updateGoldens: _updateGoldens,
      );
      expect(captured, BufferMatchers.cursorAt(11, 0));
      expect(controller.selection, const TextSelection.collapsed(offset: 11));
      session.dispose();
      controller.dispose();
    });

    test('unfocused cleared selection hides cursor', () async {
      final controller = TextEditingController(text: 'hello');
      final capture = BufferCapture(width: 30, height: 4);
      final captured = capture.capture(TextInput(controller: controller));
      await tester.expectCapturedGolden(
        captured,
        'text_input_unfocused_hidden_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(captured.cursor.visible, isFalse);
      expect(controller.selection.isValid, isFalse);
      capture.dispose();
      controller.dispose();
    });

    test('blur hides cursor then refocus repairs and shows it', () async {
      final controller = TextEditingController(text: 'ab');
      final session = _FocusedSession(
        (focusNode) => TextInput(controller: controller, focusNode: focusNode),
      );

      session.focusNode.unfocus();
      controller.text = 'blurred';
      final blurred = session.paint();
      await tester.expectCapturedGolden(
        blurred,
        'text_input_blur_hidden_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(blurred.cursor.visible, isFalse);

      session.focusNode.requestFocus();
      final refocused = session.paint();
      await tester.expectCapturedGolden(
        refocused,
        'text_input_refocus_repaired_cursor',
        updateGoldens: _updateGoldens,
      );
      expect(refocused, BufferMatchers.cursorAt(7, 0));
      expect(controller.selection, const TextSelection.collapsed(offset: 7));

      session.dispose();
      controller.dispose();
    });
  });
}

CapturedBuffer _captureFocused(Widget Function(FocusNode focusNode) builder) {
  final session = _FocusedSession(builder);
  final captured = session.paint();
  session.dispose();
  return captured;
}

/// Hosts a focused editor long enough to paint buffer + cursor sidecars.
class _FocusedSession {
  _FocusedSession(Widget Function(FocusNode focusNode) builder)
    : focusNode = FocusNode(),
      _renderer = Renderer.create(30, 4, testing: true) {
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
