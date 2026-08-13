// ignore_for_file: cascade_invocations
// Run with: dart run example/textarea_demo.dart
//
// Type to insert text. Enter inserts a newline. Ctrl+Enter submits.
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

  app = runTuiApp(_TextAreaDemoApp(onQuit: quit));
}

class _TextAreaDemoApp extends StatefulWidget {
  const _TextAreaDemoApp({required this.onQuit});

  final void Function() onQuit;

  @override
  State<_TextAreaDemoApp> createState() => _TextAreaDemoAppState();
}

class _TextAreaDemoAppState extends State<_TextAreaDemoApp> {
  String _value = '';
  String _lastSubmitted = '';

  KeyEventResult _quitOnEsc(FocusNode node, KeyEvent event) {
    if (event.isPress && event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _quitOnEsc,
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
            'Type. Enter=newline. Ctrl+Enter=submit. Esc=quit.',
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
              onSubmit: () => setState(() => _lastSubmitted = _value),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Length: ${_value.length}',
            style: const TextStyle(color: Color(0.7, 0.9, 1)),
          ),
          if (_lastSubmitted.isNotEmpty) ...[
            const SizedBox(height: 1),
            const Text(
              'Last submitted (Ctrl+Enter):',
              style: TextStyle(color: Color(0.4, 1, 0.4)),
            ),
            Text(_lastSubmitted),
          ],
        ],
      ),
    ),
  );
}
