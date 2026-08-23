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
  test('MarkdownThemeData.copyWith replaces only provided fields', () {
    final base = MarkdownThemeData.fromTheme(ThemeData.dark);
    final updated = base.copyWith(
      heading3: const TextStyle(color: Color.red, attributes: Attr.bold),
    );

    expect(updated.heading3.color, Color.red);
    expect(updated.heading3.attributes, Attr.bold);
    expect(updated.paragraph, base.paragraph);
    expect(updated.heading1, base.heading1);
    expect(updated.heading2, base.heading2);
    expect(updated.emphasis, base.emphasis);
    expect(updated.strong, base.strong);
    expect(updated.link, base.link);
    expect(updated.quote, base.quote);
    expect(updated.inlineCode, base.inlineCode);
    expect(updated.ruleColor, base.ruleColor);
  });

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

  test('embedded MarkdownView omits its inner ScrollBox', () {
    final host = DriverHost.create(width: 30, height: 5);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: '# title\n\nbody', embedded: true))
      ..debugFlushFrame();

    final types = _driverTreeTypes(host.tree(maxDepth: 12));
    expect(types, contains('MarkdownView'));
    expect(types, contains('DocumentView'));
    expect(types, isNot(contains('ScrollBox')));
    expect(_capturedText(host), contains('title'));
    expect(_capturedText(host), contains('body'));
  });

  test(
    'embedded MarkdownView lets an ancestor ScrollBox own keyboard scrolling',
    () async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final driver = KeyDriver(
        ScrollBox(
          controller: controller,
          autofocus: true,
          child: MarkdownView(
            markdown: List<String>.generate(
              12,
              (index) => 'paragraph $index',
            ).join('\n\n'),
            embedded: true,
          ),
        ),
        width: 24,
        height: 4,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      expect(controller.offset, 0);
      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
      expect(controller.offset, 1);
    },
  );

  test(
    'clicking embedded MarkdownView still leaves ancestor ScrollBox keyboard scrolling',
    () async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final driver = KeyDriver(
        ScrollBox(
          controller: controller,
          autofocus: true,
          child: MarkdownView(
            markdown: List<String>.generate(
              12,
              (index) => 'paragraph $index',
            ).join('\n\n'),
            embedded: true,
          ),
        ),
        width: 24,
        height: 4,
      );
      addTearDown(driver.dispose);
      await driver.ready();

      expect(controller.offset, 0);
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
          type: MouseEventType.up,
          x: 1,
          y: 1,
          button: MouseButton.left,
        ),
      );
      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
      expect(controller.offset, 1);
    },
  );

  test('GitHub details wrappers unwrap into visible inner markdown', () {
    const source = '''
### [*] 10/10 points: Provide a valid `pubspec.yaml`

<details>
<summary>
1 check passed
</summary>
Detected license: `BSD-3-Clause`.
</details>

<details><summary>Transitive dependencies</summary>

| Package | Latest |
| --- | --- |
| `meta` | 1.16.0 |
</details>
''';
    final host = DriverHost.create(width: 50, height: 16);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: source))
      ..debugFlushFrame();

    final text = _capturedText(host);
    expect(text, contains('10/10 points'));
    expect(text, contains('pubspec.yaml'));
    expect(text, contains('1 check passed'));
    expect(text, contains('BSD-3-Clause'));
    expect(text, contains('Transitive dependencies'));
    expect(text, contains('meta'));
    expect(text, contains('1.16.0'));
    expect(text, isNot(contains('<details>')));
    expect(text, isNot(contains('</details>')));
    expect(text, isNot(contains('<summary>')));
    expect(text, isNot(contains('###')));

    final types = _driverTreeTypes(host.tree(maxDepth: 16));
    expect(types, contains('TextTable'));
  });

  test('fenced details tags stay literal instead of unwrapping', () {
    const source = '''
```html
<details>
<summary>hidden</summary>
secret
</details>
```
''';
    final host = DriverHost.create(width: 50, height: 12);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: source))
      ..debugFlushFrame();

    final text = _capturedText(host);
    expect(text, contains('<details>'));
    expect(text, contains('hidden'));
    expect(text, isNot(contains('**hidden**')));
  });

  test('consecutive headings stay tight and a body opens the next section', () {
    final capture = BufferCapture(width: 40, height: 8);
    addTearDown(capture.dispose);
    final frame = capture.capture(
      const MarkdownView(
        markdown: '### Alpha\n### Beta\n\nbody copy\n\n### Gamma',
        embedded: true,
      ),
    );

    final alpha = frame.findText('Alpha').single;
    final beta = frame.findText('Beta').single;
    final body = frame.findText('body copy').single;
    final gamma = frame.findText('Gamma').single;
    expect(beta.y, alpha.y + 1);
    expect(body.y, beta.y + 1);
    expect(gamma.y, body.y + 2);
  });

  test('markdown tables drop columns whose body cells are empty', () {
    const source = '''
| Package | Constraint | Notes |
| --- | --- | --- |
| meta | ^1.3.0 | |
| web | >=0.5.0 | |
''';
    final host = DriverHost.create(width: 56, height: 8);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: source, embedded: true))
      ..debugFlushFrame();

    final text = _capturedText(host);
    expect(text, contains('Package'));
    expect(text, contains('Constraint'));
    expect(text, contains('meta'));
    expect(text, contains('^1.3.0'));
    expect(text, isNot(contains('Notes')));
  });

  test('GFM tables keep literal >= and < instead of HTML entities', () {
    const source = '''
|Package|Constraint|
|:-|:-|
|[`web`](https://pub.dev/packages/web)|`>=0.5.0 <2.0.0`|
''';
    final host = DriverHost.create(width: 56, height: 8);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const MarkdownView(markdown: source))
      ..debugFlushFrame();

    final text = _capturedText(host);
    expect(text, contains('>=0.5.0 <2.0.0'));
    expect(text, contains('web'));
    expect(text, isNot(contains('&gt;')));
    expect(text, isNot(contains('&lt;')));
    expect(text, isNot(contains('&amp;')));
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
