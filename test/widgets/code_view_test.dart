import 'dart:async';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  test('CodeView paints line gutters and synchronous highlight ranges', () {
    final capture = BufferCapture(width: 12, height: 2);
    try {
      final frame = capture.capture(
        const CodeView(code: 'let x\nnext', highlighter: _KeywordHighlighter()),
      );

      expect(frame.getChar(0, 0), ' ');
      expect(frame.getChar(1, 0), '1');
      expect(frame.getChar(3, 0), 'l');
      expect(frame, BufferMatchers.hasColorAt(3, 0, Color.red));
      expect(frame.getChar(1, 1), '2');
    } finally {
      capture.dispose();
    }
  });

  test('Ctrl+A selects and Ctrl+C reports the explicit copy result', () async {
    SelectedText? selected;
    SelectedText? copied;
    bool? copySucceeded;
    final driver = KeyDriver(
      CodeView(
        code: 'A😀B',
        autofocus: true,
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) {
          copied = value;
          copySucceeded = success;
        },
      ),
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);
    expect(selected?.text, 'A😀B');
    expect(
      selected?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 4),
    );

    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, selected);
    expect(copySucceeded, isFalse);
  });

  test(
    'pointer drag selects whole graphemes across cell-width mapping',
    () async {
      SelectedText? selected;
      final driver = KeyDriver(
        CodeView(
          code: 'A😀B',
          showLineNumbers: false,
          onSelectionChanged: (value) => selected = value,
        ),
        width: 4,
        height: 1,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          x: 1,
          y: 0,
          button: MouseButton.left,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.move,
          x: 3,
          y: 0,
          button: MouseButton.left,
        ),
      );
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.up,
          x: 3,
          y: 0,
          button: MouseButton.left,
        ),
      );

      expect(selected?.text, '😀');
      expect(selected?.selection.start, 1);
      expect(selected?.selection.end, 3);
    },
  );

  test('Ctrl+C bubbles only when the selection is empty', () async {
    var bubbledCopies = 0;
    final driver = KeyDriver(
      Focus(
        onKeyEvent: (node, event) {
          if (event.isControlPressed && event.character == 'c') {
            bubbledCopies++;
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const CodeView(
          code: 'copy me',
          autofocus: true,
          showLineNumbers: false,
        ),
      ),
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(bubbledCopies, 1);
    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(bubbledCopies, 1);
  });

  test('Shift+arrow moves by grapheme and Escape clears selection', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      CodeView(
        code: 'A😀B',
        showLineNumbers: false,
        onSelectionChanged: (value) => selected = value,
      ),
      width: 4,
      height: 1,
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 0,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 0, button: MouseButton.left),
    );
    await driver.sendLogicalKey(
      LogicalKeyboardKey.arrowRight,
      modifiers: KeyModifiers.shift,
    );

    expect(selected?.text, '😀');
    expect(selected?.selection.start, 1);
    expect(selected?.selection.end, 3);

    await driver.sendLogicalKey(LogicalKeyboardKey.escape);
    expect(selected, isNull);
  });

  test('wrapped line gutter labels each source line only once', () {
    final capture = BufferCapture(width: 5, height: 4);
    try {
      final frame = capture.capture(
        const CodeView(code: 'abcdef\nx', wrap: true),
      );

      expect(frame.toLines()[0].substring(0, 3), ' 1 ');
      expect(frame.toLines()[1].substring(0, 3), '   ');
      expect(frame.toLines()[2].substring(0, 3), '   ');
      expect(frame.toLines()[3].substring(0, 3), ' 2 ');
    } finally {
      capture.dispose();
    }
  });

  test('pointer mapping clamps scroll after source content shrinks', () async {
    SelectedText? selected;
    final key = GlobalKey<_ShrinkingCodeHarnessState>();
    final driver = KeyDriver(
      _ShrinkingCodeHarness(
        key: key,
        onSelectionChanged: (value) => selected = value,
      ),
      width: 20,
      height: 3,
    );
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.end);

    key.currentState!.shrink();
    driver.app.debugFlushFrame();
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 0,
        y: 0,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.move,
        x: 1,
        y: 0,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 0, button: MouseButton.left),
    );

    expect(selected?.text, 'f');
  });

  test('content shrink reconciles stored scroll before regrowth', () async {
    final visibleLines = <int>[];
    final key = GlobalKey<_ShrinkingCodeHarnessState>();
    final driver = KeyDriver(
      _ShrinkingCodeHarness(
        key: key,
        onSelectionChanged: (_) {},
        onVisibleLineChanged: visibleLines.add,
      ),
      width: 20,
      height: 3,
    );
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.end);
    expect(visibleLines.last, 197);

    key.currentState!.shrink();
    driver.app.debugFlushFrame();
    expect(visibleLines.last, 0);

    key.currentState!.grow();
    driver.app.debugFlushFrame();
    await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
    expect(visibleLines.last, 1);
  });

  test('stale asynchronous highlight results are discarded', () async {
    final highlighter = _DeferredHighlighter();
    final errors = <Object>[];
    final key = GlobalKey<_CodeHarnessState>();
    final driver = KeyDriver(
      _CodeHarness(key: key, highlighter: highlighter, errors: errors),
    );
    addTearDown(driver.dispose);
    key.currentState!.replaceCode('x');
    await Future<void>.delayed(Duration.zero);

    highlighter.pending['x']!.complete(const <StyledTextRange>[]);
    await Future<void>.delayed(Duration.zero);
    highlighter.pending['longer']!.complete(const <StyledTextRange>[
      StyledTextRange(start: 5, end: 6, style: TextStyle(color: Color.red)),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
  });

  test(
    'source replacement clears resolved ranges while highlighting',
    () async {
      final highlighter = _TransitionHighlighter();
      final errors = <Object>[];
      final key = GlobalKey<_CodeHarnessState>();
      final driver = KeyDriver(
        _CodeHarness(key: key, highlighter: highlighter, errors: errors),
      );
      addTearDown(driver.dispose);
      await driver.ready();

      key.currentState!.replaceCode('x');
      driver.app.debugFlushFrame();
      await Future<void>.delayed(Duration.zero);

      highlighter.pending.complete(const <StyledTextRange>[]);
      await Future<void>.delayed(Duration.zero);
      expect(errors, isEmpty);
    },
  );

  test('invalid ranges surface an error and render plain text', () {
    final errors = <Object>[];
    final capture = BufferCapture(width: 8, height: 1);
    try {
      final frame = capture.capture(
        CodeView(
          code: 'plain',
          showLineNumbers: false,
          highlighter: const _InvalidHighlighter(),
          onHighlightError: (error, stackTrace) => errors.add(error),
        ),
      );
      expect(frame.toLines().single, startsWith('plain'));
      expect(errors.single, isA<FormatException>());
    } finally {
      capture.dispose();
    }
  });
}

final class _KeywordHighlighter implements CodeHighlighter {
  const _KeywordHighlighter();

  @override
  List<StyledTextRange> highlight(String source, {String? language}) => const [
    StyledTextRange(start: 0, end: 3, style: TextStyle(color: Color.red)),
  ];
}

final class _InvalidHighlighter implements CodeHighlighter {
  const _InvalidHighlighter();

  @override
  List<StyledTextRange> highlight(String source, {String? language}) => const [
    StyledTextRange(start: 1, end: 99, style: TextStyle(color: Color.red)),
  ];
}

final class _DeferredHighlighter implements CodeHighlighter {
  final pending = <String, Completer<List<StyledTextRange>>>{};

  @override
  Future<List<StyledTextRange>> highlight(String source, {String? language}) =>
      (pending[source] = Completer<List<StyledTextRange>>()).future;
}

final class _TransitionHighlighter implements CodeHighlighter {
  final pending = Completer<List<StyledTextRange>>();

  @override
  FutureOr<List<StyledTextRange>> highlight(
    String source, {
    String? language,
  }) => source == 'longer'
      ? const <StyledTextRange>[
          StyledTextRange(start: 5, end: 6, style: TextStyle(color: Color.red)),
        ]
      : pending.future;
}

final class _CodeHarness extends StatefulWidget {
  const _CodeHarness({
    required this.highlighter,
    required this.errors,
    super.key,
  });

  final CodeHighlighter highlighter;
  final List<Object> errors;

  @override
  State<_CodeHarness> createState() => _CodeHarnessState();
}

final class _CodeHarnessState extends State<_CodeHarness> {
  String code = 'longer';

  void replaceCode(String value) => setState(() => code = value);

  @override
  Widget build(BuildContext context) => CodeView(
    code: code,
    highlighter: widget.highlighter,
    onHighlightError: (error, stackTrace) => widget.errors.add(error),
  );
}

final class _ShrinkingCodeHarness extends StatefulWidget {
  const _ShrinkingCodeHarness({
    required this.onSelectionChanged,
    this.onVisibleLineChanged,
    super.key,
  });

  final void Function(SelectedText? value) onSelectionChanged;
  final void Function(int line)? onVisibleLineChanged;

  @override
  State<_ShrinkingCodeHarness> createState() => _ShrinkingCodeHarnessState();
}

final class _ShrinkingCodeHarnessState extends State<_ShrinkingCodeHarness> {
  String code = List<String>.generate(200, (index) => 'line $index').join('\n');

  void shrink() => setState(() => code = 'first\nsecond\nthird');

  void grow() => setState(
    () => code = List<String>.generate(
      200,
      (index) => 'regrown $index',
    ).join('\n'),
  );

  @override
  Widget build(BuildContext context) => CodeView(
    code: code,
    autofocus: true,
    showLineNumbers: false,
    onSelectionChanged: widget.onSelectionChanged,
    onVisibleLineChanged: widget.onVisibleLineChanged,
  );
}
