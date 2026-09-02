// Run with: dart run example/parity_components_demo.dart
//
// Left/Right or [/] changes the active document tab. Arrow keys adjust the
// slider when it has focus. Document text supports pointer/Shift selection,
// Ctrl+A, Escape, and explicit Ctrl+C OSC52 copy. Press q to quit.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const ParityComponentsDemoApp(), enableMouse: true);

class ParityComponentsDemoApp extends StatefulWidget {
  const ParityComponentsDemoApp({super.key});

  @override
  State<ParityComponentsDemoApp> createState() =>
      _ParityComponentsDemoAppState();
}

class _ParityComponentsDemoAppState extends State<ParityComponentsDemoApp> {
  static const _tabs = <SelectOption<int>>[
    SelectOption(name: 'Code', description: 'Source with a shared gutter'),
    SelectOption(name: 'Diff', description: 'Unified or split patch view'),
    SelectOption(name: 'Markdown', description: 'GitHub-flavoured document'),
  ];

  static final _diff = const UnifiedDiffParser().parse('''
diff --git a/lib/status.dart b/lib/status.dart
--- a/lib/status.dart
+++ b/lib/status.dart
@@ -1,2 +1,2 @@
-const status = 'draft';
+const status = 'ready';
 const retries = 3;
''');

  int _tab = 0;
  double _progress = 42;

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (!event.isPress || event.character != 'q') {
      return KeyEventResult.ignored;
    }
    TuiApp.exit(context);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onAppKey,
    child: DemoScaffold(
      title: 'OpenTUI parity components',
      hint: 'Tab focus · arrows navigate · drag/select · Ctrl+C copy · q quit',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 4,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AsciiFont('NOIR', color: Color.cyan),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Wrap(
                    spacing: 1,
                    children: const [
                      Badge(label: 'STACK'),
                      Badge(label: 'WRAP', variant: BadgeVariant.info),
                      Badge(label: 'ASCII', variant: BadgeVariant.success),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Row(
            spacing: 2,
            children: [
              const Text('Viewport'),
              Expanded(
                child: Slider(
                  key: const ValueKey<String>('slider'),
                  value: _progress,
                  viewportSize: 18,
                  step: 2,
                  onChanged: (value) => setState(() => _progress = value),
                ),
              ),
              Text('${_progress.round()}%'),
            ],
          ),
          const TextTable(
            content: [
              [
                TextSpan(text: 'Surface', style: TextStyles.bold),
                TextSpan(text: 'Role', style: TextStyles.bold),
              ],
              [TextSpan(text: 'TextTable'), TextSpan(text: 'static rich grid')],
              [TextSpan(text: 'DataTable'), TextSpan(text: 'virtualized rows')],
            ],
            columnWidthMode: TextTableColumnWidthMode.content,
          ),
          TabSelect<int>(
            key: const ValueKey<String>('tabs'),
            options: _tabs,
            selectedIndex: _tab,
            tabWidth: 13,
            autofocus: true,
            onChanged: (index, option) => setState(() => _tab = index),
          ),
          _document(),
        ],
      ),
    ),
  );

  Widget _document() => switch (_tab) {
    0 => const CodeView(
      code: 'void main() => runTuiApp(const App());\n',
      language: 'dart',
      wrap: true,
    ),
    1 => DiffView(document: _diff, wrap: true),
    _ => const MarkdownView(
      markdown: '''
## Declarative terminal UI

- **Widgets** declare configuration.
- [Links](https://github.com/conceptadev/noir) stay semantic.

```dart
const Text('Hello, terminal!')
```
''',
    ),
  };
}
