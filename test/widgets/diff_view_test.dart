import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/src/app/driver.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

const _patch = '''
diff --git a/lib/a.dart b/lib/a.dart
--- a/lib/a.dart
+++ b/lib/a.dart
@@ -1,2 +1,2 @@ method
 keep
-old
+new
''';

void main() {
  test('UnifiedDiffParser accepts Git unified patches with coordinates', () {
    final document = const UnifiedDiffParser().parse(_patch);

    expect(document.files, hasLength(1));
    final file = document.files.single;
    expect(file.oldPath, 'lib/a.dart');
    expect(file.newPath, 'lib/a.dart');
    expect(file.hunks.single.header, 'method');
    expect(file.hunks.single.lines, hasLength(3));
    expect(file.hunks.single.lines[1].kind, DiffLineKind.deletion);
    expect(file.hunks.single.lines[1].oldLineNumber, 2);
    expect(file.hunks.single.lines[2].newLineNumber, 2);
  });

  test('UnifiedDiffParser keeps file-header-like deletion content', () {
    final document = const UnifiedDiffParser().parse('''
--- a.txt
+++ a.txt
@@ -1 +1 @@
--- old heading
++ new heading
''');

    final lines = document.files.single.hunks.single.lines;
    expect(lines, hasLength(2));
    expect(lines.first.kind, DiffLineKind.deletion);
    expect(lines.first.text, '-- old heading');
    expect(lines.last.kind, DiffLineKind.addition);
  });

  test('UnifiedDiffParser decodes Git-quoted paths', () {
    final document = const UnifiedDiffParser().parse(r'''
diff --git "a/lib/path with space-\303\244.dart" "b/lib/path with space-\303\244.dart"
--- "a/lib/path with space-\303\244.dart"
+++ "b/lib/path with space-\303\244.dart"
@@ -1 +1 @@
-old
+new
''');

    expect(document.files, hasLength(1));
    expect(document.files.single.oldPath, 'lib/path with space-ä.dart');
    expect(document.files.single.newPath, 'lib/path with space-ä.dart');
  });

  test('UnifiedDiffParser retains trimmed blank context coordinates', () {
    final document = const UnifiedDiffParser().parse(
      '--- a.txt\n'
      '+++ a.txt\n'
      '@@ -1,3 +1,3 @@\n'
      ' one\n'
      '\n'
      ' three',
    );

    final lines = document.files.single.hunks.single.lines;
    expect(lines, hasLength(3));
    expect(lines[1].kind, DiffLineKind.context);
    expect(lines[1].text, isEmpty);
    expect(lines[1].oldLineNumber, 2);
    expect(lines[1].newLineNumber, 2);
    expect(lines[2].oldLineNumber, 3);
    expect(lines[2].newLineNumber, 3);
  });

  test('UnifiedDiffParser does not fabricate context from final newline', () {
    final document = const UnifiedDiffParser().parse(
      '--- a.txt\n'
      '+++ a.txt\n'
      '@@ -1,2 +1,2 @@\n'
      ' one\n',
    );

    final lines = document.files.single.hunks.single.lines;
    expect(lines, hasLength(1));
    expect(lines.single.text, 'one');
  });

  test('DiffView paints unified gutters and change styles', () {
    final capture = BufferCapture(width: 40, height: 4);
    try {
      final frame = capture.capture(
        DiffView(document: const UnifiedDiffParser().parse(_patch)),
      );

      expect(frame.toLines()[0], contains('@@ -1,2 +1,2 @@ method'));
      expect(frame.toLines()[2], contains('-old'));
      expect(frame.toLines()[3], contains('+new'));
      expect(frame.getBackgroundColor(0, 2).toHex(), '#380f0fff');
      expect(frame.getBackgroundColor(0, 3).toHex(), '#0d331aff');
    } finally {
      capture.dispose();
    }
  });

  test('split mode aligns old and new sides in one synchronized viewport', () {
    final capture = BufferCapture(width: 60, height: 4);
    try {
      final frame = capture.capture(
        DiffView(
          document: const UnifiedDiffParser().parse(_patch),
          mode: DiffViewMode.split,
          splitColumnWidth: 20,
        ),
      );

      expect(frame.toLines()[1], contains('│'));
      expect(frame.toLines()[2], contains('-old'));
      expect(frame.toLines()[2], contains('+new'));
      expect(
        frame.getForegroundColor(4, 2).toHex(),
        ThemeData.dark.danger.toHex(),
      );
      expect(frame.getBackgroundColor(4, 2).toHex(), '#380f0fff');
      expect(
        frame.getForegroundColor(27, 2).toHex(),
        ThemeData.dark.success.toHex(),
      );
      expect(frame.getBackgroundColor(27, 2).toHex(), '#0d331aff');
    } finally {
      capture.dispose();
    }
  });

  test('row builder default preserves syntax and diff backgrounds', () {
    final capture = BufferCapture(width: 40, height: 4);
    try {
      final frame = capture.capture(
        DiffView(
          document: const UnifiedDiffParser().parse(_patch),
          highlighter: const _OldWordHighlighter(),
          rowBuilder: (context, file, hunk, line, defaultRow) => defaultRow,
        ),
      );

      final oldX = frame.toLines()[2].indexOf('old');
      expect(oldX, greaterThanOrEqualTo(0));
      expect(frame.getForegroundColor(oldX, 2), Color.magenta);
      expect(frame.getBackgroundColor(oldX, 2).toHex(), '#380f0fff');
    } finally {
      capture.dispose();
    }
  });

  test('row builder default retains whole-diff selection and copy', () async {
    SelectedText? selected;
    SelectedText? copied;
    bool? copySucceeded;
    final driver = KeyDriver(
      DiffView(
        document: const UnifiedDiffParser().parse(_patch),
        rowBuilder: (context, file, hunk, line, defaultRow) =>
            Padding(padding: EdgeInsets.zero, child: defaultRow),
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) {
          copied = value;
          copySucceeded = success;
        },
      ),
      width: 40,
      height: 4,
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
    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);

    expect(selected?.text, contains('-old'));
    expect(selected?.text, contains('+new'));
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, selected);
    expect(copySucceeded, isFalse);
  });

  test('replacement diff rows retain semantic selection and copy', () async {
    SelectedText? selected;
    SelectedText? copied;
    final driver = KeyDriver(
      DiffView(
        document: const UnifiedDiffParser().parse(_patch),
        rowBuilder: (context, file, hunk, line, defaultRow) =>
            const Text('replacement'),
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) => copied = value,
      ),
      width: 40,
      height: 4,
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
    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);

    expect(selected?.text, contains('-old'));
    expect(selected?.text, contains('+new'));
    expect(copied, selected);
  });

  test('vertical Shift+arrow crosses custom diff row boundaries', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      DiffView(
        document: const UnifiedDiffParser().parse(_patch),
        rowBuilder: (context, file, hunk, line, defaultRow) => defaultRow,
        onSelectionChanged: (value) => selected = value,
      ),
      width: 40,
      height: 4,
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
      LogicalKeyboardKey.arrowDown,
      modifiers: KeyModifiers.shift,
    );

    expect(selected?.text, endsWith('\n'));
    expect(selected?.text, contains('@ -1,2 +1,2 @@ method'));
  });

  test('selection survives row builder transitions', () async {
    SelectedText? selected;
    SelectedText? copied;
    final key = GlobalKey<_DiffRowBuilderHarnessState>();
    final driver = KeyDriver(
      _DiffRowBuilderHarness(
        key: key,
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) => copied = value,
      ),
      width: 40,
      height: 4,
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
    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);
    final completeSelection = selected;
    expect(completeSelection?.text, contains('-old'));

    key.currentState!.useCustomRows(enabled: true);
    driver.app.debugFlushFrame();
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, completeSelection);

    copied = null;
    key.currentState!.useCustomRows(enabled: false);
    driver.app.debugFlushFrame();
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, completeSelection);
  });

  test('controller jumps to a later hunk', () {
    final document = const UnifiedDiffParser().parse('''
--- a.txt
+++ a.txt
@@ -1 +1 @@ first
-a
+b
@@ -10 +10 @@ second
-c
+d
''');
    final controller = DiffViewController();
    final host = DriverHost.create(width: 40, height: 2);
    addTearDown(host.dispose);
    host.binding
      ..runApp(DiffView(document: document, controller: controller))
      ..debugFlushFrame();

    controller.jumpToHunk(1);
    host.binding.debugFlushFrame();

    expect(host.capture()['lines'], everyElement(isNot(contains('first'))));
    expect(host.capture()['lines'], contains(contains('second')));
  });

  test('controller retains pre-mount jumps in both row modes', () async {
    final document = const UnifiedDiffParser().parse('''
--- a.txt
+++ a.txt
@@ -1 +1 @@ first
-a
+b
@@ -10 +10 @@ second
-c
+d
''');
    for (final customRows in <bool>[false, true]) {
      final controller = DiffViewController()..jumpToHunk(1);
      final host = DriverHost.create(width: 40, height: 2);
      addTearDown(host.dispose);
      host.binding
        ..runApp(
          DiffView(
            document: document,
            controller: controller,
            rowBuilder: customRows
                ? (context, file, hunk, line, defaultRow) => defaultRow
                : null,
          ),
        )
        ..debugFlushFrame();

      await Future<void>.delayed(Duration.zero);
      host.binding.debugFlushFrame();

      expect(
        host.capture()['lines'],
        contains(contains('second')),
        reason: 'customRows=$customRows',
      );
    }
  });

  test('default no-wrap diff scrolls horizontally', () {
    final host = DriverHost.create(width: 12, height: 3);
    addTearDown(host.dispose);
    host.binding
      ..runApp(
        DiffView(
          document: const UnifiedDiffParser().parse('''
--- a.txt
+++ a.txt
@@ -1 +1 @@
 abcdefghijklmnopqrstuvwxyz
'''),
          showLineNumbers: false,
        ),
      )
      ..debugFlushFrame();

    host.binding.inputManager.dispatchMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 1,
        button: MouseButton.left,
      ),
    );
    host.binding.inputManager.dispatchMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 1, button: MouseButton.left),
    );
    final before = host.capture()['lines'];
    host.binding.inputManager.dispatchKey(
      KeyEvent(logicalKey: LogicalKeyboardKey.arrowRight, keyCode: 0),
    );
    host.binding.debugFlushFrame();
    final after = host.capture()['lines'];

    expect(after, isNot(before));
  });

  test(
    'default renderer selects and explicitly copies the whole diff',
    () async {
      SelectedText? selected;
      SelectedText? copied;
      bool? copySucceeded;
      final driver = KeyDriver(
        DiffView(
          document: const UnifiedDiffParser().parse(_patch),
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
      expect(selected?.text, contains('-old'));
      expect(selected?.text, contains('+new'));

      await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
      expect(copied, selected);
      expect(copySucceeded, isFalse);
    },
  );

  test('stale asynchronous diff highlights are discarded', () async {
    final highlighter = _DeferredDiffHighlighter();
    final errors = <Object>[];
    final key = GlobalKey<_DiffHarnessState>();
    final driver = KeyDriver(
      _DiffHarness(key: key, highlighter: highlighter, errors: errors),
    );
    addTearDown(driver.dispose);
    await Future<void>.delayed(Duration.zero);
    final firstSource = highlighter.pending.keys.single;

    key.currentState!.replace('''
--- b.txt
+++ b.txt
@@ -1 +1 @@
-before
+after
''');
    driver.app.debugFlushFrame();
    await Future<void>.delayed(Duration.zero);
    final secondSource = highlighter.pending.keys.singleWhere(
      (source) => source != firstSource,
    );
    highlighter.pending[secondSource]!.complete(const <StyledTextRange>[]);
    highlighter.pending[firstSource]!.complete(const <StyledTextRange>[
      StyledTextRange(start: 0, end: 999, style: TextStyle(color: Color.red)),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
  });

  test('invalid diff highlight ranges report and fall back', () {
    final errors = <Object>[];
    final capture = BufferCapture(width: 40, height: 4);
    try {
      final frame = capture.capture(
        DiffView(
          document: const UnifiedDiffParser().parse(_patch),
          highlighter: const _InvalidDiffHighlighter(),
          onHighlightError: (error, stackTrace) => errors.add(error),
        ),
      );

      expect(frame.toLines()[2], contains('-old'));
      expect(errors.single, isA<FormatException>());
    } finally {
      capture.dispose();
    }
  });

  test('hunk and line callbacks map pointer rows', () async {
    DiffHunk? activatedHunk;
    DiffLine? activatedLine;
    final driver = KeyDriver(
      DiffView(
        document: const UnifiedDiffParser().parse(_patch),
        onHunk: (file, hunk) => activatedHunk = hunk,
        onLine: (file, hunk, line) => activatedLine = line,
      ),
      width: 40,
      height: 4,
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
        type: MouseEventType.down,
        x: 1,
        y: 1,
        button: MouseButton.left,
      ),
    );

    expect(activatedHunk, isNotNull);
    expect(activatedLine?.kind, DiffLineKind.context);
  });

  test(
    'callbacks map wrapped visual lines back to their semantic row',
    () async {
      DiffHunk? activatedHunk;
      DiffLine? activatedLine;
      final driver = KeyDriver(
        DiffView(
          document: const UnifiedDiffParser().parse(_patch),
          wrap: true,
          onHunk: (file, hunk) => activatedHunk = hunk,
          onLine: (file, hunk, line) => activatedLine = line,
        ),
        width: 12,
        height: 4,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          x: 2,
          y: 1,
          button: MouseButton.left,
        ),
      );

      expect(activatedHunk, isNotNull);
      expect(activatedLine, isNull);
    },
  );
}

final class _OldWordHighlighter implements CodeHighlighter {
  const _OldWordHighlighter();

  @override
  List<StyledTextRange> highlight(String source, {String? language}) {
    final start = source.indexOf('old');
    return <StyledTextRange>[
      StyledTextRange(
        start: start,
        end: start + 3,
        style: const TextStyle(color: Color.magenta),
      ),
    ];
  }
}

final class _DeferredDiffHighlighter implements CodeHighlighter {
  final pending = <String, Completer<List<StyledTextRange>>>{};

  @override
  Future<List<StyledTextRange>> highlight(String source, {String? language}) =>
      (pending[source] = Completer<List<StyledTextRange>>()).future;
}

final class _InvalidDiffHighlighter implements CodeHighlighter {
  const _InvalidDiffHighlighter();

  @override
  List<StyledTextRange> highlight(String source, {String? language}) => const [
    StyledTextRange(start: 0, end: 999, style: TextStyle(color: Color.red)),
  ];
}

final class _DiffHarness extends StatefulWidget {
  const _DiffHarness({
    required this.highlighter,
    required this.errors,
    super.key,
  });

  final CodeHighlighter highlighter;
  final List<Object> errors;

  @override
  State<_DiffHarness> createState() => _DiffHarnessState();
}

final class _DiffHarnessState extends State<_DiffHarness> {
  String patch = _patch;

  void replace(String value) => setState(() => patch = value);

  @override
  Widget build(BuildContext context) => DiffView(
    document: const UnifiedDiffParser().parse(patch),
    highlighter: widget.highlighter,
    onHighlightError: (error, stackTrace) => widget.errors.add(error),
  );
}

final class _DiffRowBuilderHarness extends StatefulWidget {
  const _DiffRowBuilderHarness({
    required this.onSelectionChanged,
    required this.onCopy,
    super.key,
  });

  final void Function(SelectedText? selection) onSelectionChanged;
  final SelectionCopyCallback onCopy;

  @override
  State<_DiffRowBuilderHarness> createState() => _DiffRowBuilderHarnessState();
}

final class _DiffRowBuilderHarnessState extends State<_DiffRowBuilderHarness> {
  bool customRows = false;

  void useCustomRows({required bool enabled}) =>
      setState(() => customRows = enabled);

  @override
  Widget build(BuildContext context) => DiffView(
    document: const UnifiedDiffParser().parse(_patch),
    rowBuilder: customRows
        ? (context, file, hunk, line, defaultRow) => defaultRow
        : null,
    onSelectionChanged: widget.onSelectionChanged,
    onCopy: widget.onCopy,
  );
}
