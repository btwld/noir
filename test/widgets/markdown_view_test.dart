import 'package:markdown/markdown.dart' as md;
import 'package:noir/noir.dart';
import 'package:noir/src/app/driver.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

const _markdown = '''
# Heading

Paragraph with *emphasis*, **strong**, ~~strike~~, and [link](https://example.test).

- [x] done
- [ ] pending

> quoted

---

```dart
void main() {}
```

| Name | State |
| --- | --- |
| Noir | ready |

![remote alt](https://images.example.test/a.png)
''';

void main() {
  test('MarkdownView covers GFM blocks through Noir components', () {
    final host = DriverHost.create(width: 70, height: 24);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: _markdown))
      ..debugFlushFrame();

    final lines = (host.capture()['lines']! as List<Object?>).cast<String>();
    final text = lines.join('\n');
    expect(text, contains('Heading'));
    expect(text, contains('emphasis'));
    expect(text, contains('[x] done'));
    expect(text, contains('│ quoted'));
    expect(text, contains('void main() {}'));
    expect(text, contains('Noir'));
    expect(text, contains('remote alt'));

    final types = _driverTreeTypes(host.tree(maxDepth: 18));
    expect(types, contains('CodeView'));
    expect(types, contains('TextTable'));
  });

  test('Markdown images render linked alt text without creating Image', () {
    final host = DriverHost.create(width: 40, height: 3);
    addTearDown(host.dispose);
    host.binding
      ..runApp(
        const MarkdownView(
          markdown: '![alt](https://images.example.test/image.png)',
        ),
      )
      ..debugFlushFrame();

    final cells = host.capture(format: DriverCaptureFormat.cells);
    final row =
        (cells['rows']! as List<Object?>).first! as Map<String, Object?>;
    final links = (row['links']! as List<Object?>).cast<String?>();
    expect(
      links.take(3),
      everyElement('https://images.example.test/image.png'),
    );
    final types = _driverTreeTypes(host.tree(maxDepth: 12));
    expect(types, isNot(contains('Image')));
  });

  test('CRLF input renders identically to LF input', () {
    const lf = '# Heading\n\nBody\n\n- a\n- b';
    final lfHost = DriverHost.create(width: 30, height: 7);
    final crlfHost = DriverHost.create(width: 30, height: 7);
    addTearDown(lfHost.dispose);
    addTearDown(crlfHost.dispose);
    lfHost.binding
      ..runApp(const MarkdownView(markdown: lf))
      ..debugFlushFrame();
    crlfHost.binding
      ..runApp(MarkdownView(markdown: lf.replaceAll('\n', '\r\n')))
      ..debugFlushFrame();

    expect(crlfHost.capture()['lines'], lfHost.capture()['lines']);
  });

  test('nested lists render one indented marker per item', () {
    final capture = BufferCapture(width: 40, height: 4);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      const MarkdownView(markdown: '- Item 1\n  - Nested A\n  - Nested B'),
    );

    expect(frame.toLines().take(3), <String>[
      '• Item 1',
      '  • Nested A',
      '  • Nested B',
    ]);
  });

  test('nested list metadata stays local to the owning list', () {
    final capture = BufferCapture(width: 40, height: 4);
    addTearDown(capture.dispose);

    final tasks = capture.capture(
      const MarkdownView(markdown: '- parent\n  - [x] child'),
    );
    expect(tasks.toLines().take(2), <String>['• parent', '  [x] child']);

    final ordered = capture.capture(
      const MarkdownView(markdown: '- parent\n  3. third\n  4. fourth'),
    );
    expect(ordered.toLines().take(3), <String>[
      '• parent',
      '  3. third',
      '  4. fourth',
    ]);
  });

  test('nested inline styles preserve outer terminal attributes', () {
    final capture = BufferCapture(width: 30, height: 3);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      const MarkdownView(
        markdown: '**bold _ital_ tail**\n\n~~strike **both**~~',
      ),
    );
    final italicPosition = frame.findText('ital').single;
    final italic = frame.getCell(italicPosition.x, italicPosition.y);
    final boldStrikePosition = frame.findText('both').single;
    final boldStrike = frame.getCell(
      boldStrikePosition.x,
      boldStrikePosition.y,
    );

    expect(italic.hasAttribute(Attr.bold), isTrue);
    expect(italic.hasAttribute(Attr.italic), isTrue);
    expect(boldStrike.hasAttribute(Attr.bold), isTrue);
    expect(boldStrike.hasAttribute(Attr.strike), isTrue);
  });

  test('block renderer receives AST nodes and may delegate or replace', () {
    final tags = <String>[];
    final host = DriverHost.create(width: 30, height: 5);
    addTearDown(host.dispose);
    host.binding
      ..runApp(
        MarkdownView(
          markdown: '# title\n\n---',
          blockRenderer: (context, node, buildDefault) {
            if (node is md.Element) tags.add(node.tag);
            return node is md.Element && node.tag == 'hr'
                ? const Text('custom rule')
                : buildDefault();
          },
        ),
      )
      ..debugFlushFrame();

    expect(tags, <String>['h1', 'hr']);
    expect(
      (host.capture()['lines']! as List<Object?>).cast<String>().join('\n'),
      contains('custom rule'),
    );
  });

  test('all replacement blocks retain semantic selection and copy', () async {
    SelectedText? selected;
    SelectedText? copied;
    bool? copySucceeded;
    final driver = KeyDriver(
      MarkdownView(
        markdown: '# title\n\nbody',
        blockRenderer: (context, node, buildDefault) =>
            const Text('replacement'),
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) {
          copied = value;
          copySucceeded = success;
        },
      ),
      width: 20,
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

    expect(selected?.text, 'title\n\nbody');
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, selected);
    expect(copySucceeded, isFalse);
  });

  test('updated Markdown source is reparsed into replacement blocks', () {
    final key = GlobalKey<_MarkdownHarnessState>();
    final host = DriverHost.create(width: 30, height: 5);
    addTearDown(host.dispose);
    host.binding
      ..runApp(_MarkdownHarness(key: key))
      ..debugFlushFrame();
    expect(_capturedText(host), contains('before'));

    key.currentState!.replace('## after');
    host.binding.debugFlushFrame();

    expect(_capturedText(host), contains('after'));
    expect(_capturedText(host), isNot(contains('before')));
  });

  test(
    'focused text block lets boundary scrolling reach the document',
    () async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final driver = KeyDriver(
        MarkdownView(
          markdown: List<String>.generate(
            8,
            (index) => 'paragraph $index',
          ).join('\n\n'),
          controller: controller,
        ),
        width: 24,
        height: 3,
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
          type: MouseEventType.up,
          x: 1,
          y: 0,
          button: MouseButton.left,
        ),
      );
      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);

      expect(controller.offset, 1);
    },
  );

  test('selection and copy span the complete rendered document', () async {
    SelectedText? selected;
    SelectedText? copied;
    bool? copySucceeded;
    final driver = KeyDriver(
      MarkdownView(
        markdown: 'first\n\nsecond',
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) {
          copied = value;
          copySucceeded = success;
        },
      ),
      width: 20,
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

    expect(selected?.text, 'first\n\nsecond');
    expect(
      selected?.selection,
      const TextSelection(baseOffset: 0, extentOffset: 13),
    );

    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, selected);
    expect(copySucceeded, isFalse);
  });

  test('whole-document selection includes table cells row-major', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      MarkdownView(
        markdown: 'intro\n\n| H1 | H2 |\n| --- | --- |\n| A | B |',
        onSelectionChanged: (value) => selected = value,
      ),
      width: 30,
      height: 8,
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

    expect(selected?.text, 'intro\n\nH1\tH2\nA\tB');
  });

  test('pointer drag may cross selectable Markdown blocks', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      MarkdownView(
        markdown: 'first\n\nsecond',
        onSelectionChanged: (value) => selected = value,
      ),
      width: 20,
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
        type: MouseEventType.move,
        x: 3,
        y: 2,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 3, y: 2, button: MouseButton.left),
    );

    expect(selected?.text, 'irst\n\nsec');
  });

  test('vertical Shift+arrow crosses Markdown block boundaries', () async {
    SelectedText? selected;
    final driver = KeyDriver(
      MarkdownView(
        markdown: 'first\n\nsecond',
        onSelectionChanged: (value) => selected = value,
      ),
      width: 20,
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

    expect(selected?.text, 'irst\n');
  });

  test('table-only Markdown owns pointer selection and copy actions', () async {
    SelectedText? selected;
    SelectedText? copied;
    bool? copySucceeded;
    final driver = KeyDriver(
      MarkdownView(
        markdown: '| H1 | H2 |\n| --- | --- |\n| A | B |',
        onSelectionChanged: (value) => selected = value,
        onCopy: (value, {required success}) {
          copied = value;
          copySucceeded = success;
        },
      ),
      width: 20,
      height: 6,
    );
    addTearDown(driver.dispose);
    await driver.ready();

    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 1,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.move,
        x: 2,
        y: 1,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 2, y: 1, button: MouseButton.left),
    );
    expect(selected?.text, 'H');

    await driver.sendCharacter('a', modifiers: KeyModifiers.ctrl);
    expect(selected?.text, 'H1\tH2\nA\tB');
    await driver.sendCharacter('c', modifiers: KeyModifiers.ctrl);
    expect(copied, selected);
    expect(copySucceeded, isFalse);

    await driver.sendLogicalKey(LogicalKeyboardKey.escape);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 1,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 1, button: MouseButton.left),
    );
    await driver.sendLogicalKey(
      LogicalKeyboardKey.arrowDown,
      modifiers: KeyModifiers.shift,
    );
    expect(selected?.text, 'H1\tH2\n');

    await driver.sendLogicalKey(LogicalKeyboardKey.escape);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        x: 1,
        y: 3,
        button: MouseButton.left,
      ),
    );
    await driver.sendMouse(
      MouseEvent(type: MouseEventType.up, x: 1, y: 3, button: MouseButton.left),
    );
    await driver.sendLogicalKey(
      LogicalKeyboardKey.arrowUp,
      modifiers: KeyModifiers.shift,
    );
    expect(selected?.text, 'H1\tH2\n');
  });
}

List<String> _driverTreeTypes(Map<String, Object?> tree) {
  final types = <String>[];
  void visit(Map<String, Object?> node) {
    types.add(node['type']! as String);
    for (final child in node['children']! as List<Object?>) {
      visit(child! as Map<String, Object?>);
    }
  }

  final root = tree['root'];
  if (root != null) visit(root as Map<String, Object?>);
  return types;
}

String _capturedText(DriverHost host) =>
    (host.capture()['lines']! as List<Object?>).cast<String>().join('\n');

final class _MarkdownHarness extends StatefulWidget {
  const _MarkdownHarness({super.key});

  @override
  State<_MarkdownHarness> createState() => _MarkdownHarnessState();
}

final class _MarkdownHarnessState extends State<_MarkdownHarness> {
  String markdown = '# before';

  void replace(String value) => setState(() => markdown = value);

  @override
  Widget build(BuildContext context) => MarkdownView(markdown: markdown);
}
