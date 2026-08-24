// ignore_for_file: cascade_invocations
// Run with: dart run example/textarea_demo.dart
//
// Type to insert text. Enter inserts a newline. Ctrl+D submits. Ctrl+Enter
// also submits when the terminal reports modified Enter keys.
// Backspace, arrows, Home/End, PgUp/PgDn, Ctrl+Home/End all work.
// Press Esc to quit.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const TextAreaDemoApp());

class TextAreaDemoApp extends StatefulWidget {
  const TextAreaDemoApp({super.key});

  @override
  State<TextAreaDemoApp> createState() => _TextAreaDemoAppState();
}

class _TextAreaDemoAppState extends State<TextAreaDemoApp> {
  String _value = '';
  String _lastSubmitted = '';

  int get _graphemeLength => TextIndexMap(_value).graphemeCount;

  void _submit() => setState(() => _lastSubmitted = _value);

  KeyEventResult _handleAppKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleAppKey,
      child: DemoScaffold(
        title: 'TextArea demo',
        hint: 'Type. Enter=newline. Ctrl+D=submit. Esc=quit.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DemoPanel(
              title: 'Draft',
              child: TextArea(
                key: const ValueKey<String>('editor'),
                autofocus: true,
                width: 50,
                height: 6,
                placeholder: 'Write something multi-line here…',
                onChanged: (v) => setState(() => _value = v),
                onSubmit: _submit,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Length: $_graphemeLength',
              style: TextStyle(color: theme.info),
            ),
            if (_lastSubmitted.isNotEmpty) ...[
              const SizedBox(height: 1),
              Text('Last submitted:', style: TextStyle(color: theme.success)),
              Text(_lastSubmitted),
            ],
          ],
        ),
      ),
    );
  }
}
