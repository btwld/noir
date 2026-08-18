// ignore_for_file: cascade_invocations
// Run with: dart run example/textarea_demo.dart
//
// Type to insert text. Enter inserts a newline. Ctrl+D submits. Ctrl+Enter
// also submits when the terminal reports modified Enter keys.
// Backspace, arrows, Home/End, PgUp/PgDn, Ctrl+Home/End all work.
// Press Esc to quit.

import 'dart:io' as io;

import 'package:noir/noir.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(TextAreaDemoApp(onQuit: quit));
}

class TextAreaDemoApp extends StatefulWidget {
  const TextAreaDemoApp({required this.onQuit, super.key});

  final void Function() onQuit;

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
      widget.onQuit();
      return KeyEventResult.handled;
    }
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyD) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _handleAppKey,
    child: Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TextArea demo',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Type. Enter=newline. Ctrl+D=submit. Esc=quit.',
            style: TextStyle(color: Color(0.7, 0.7, 0.7)),
          ),
          const SizedBox(height: 1),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0.4, 0.4, 0.6)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: TextArea(
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
            style: const TextStyle(color: Color(0.7, 0.9, 1)),
          ),
          if (_lastSubmitted.isNotEmpty) ...[
            const SizedBox(height: 1),
            const Text(
              'Last submitted:',
              style: TextStyle(color: Color(0.4, 1, 0.4)),
            ),
            Text(_lastSubmitted),
          ],
        ],
      ),
    ),
  );
}
