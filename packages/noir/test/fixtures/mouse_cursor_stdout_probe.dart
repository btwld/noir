// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:noir/src/app/terminal_session.dart';
import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/mouse_cursor.dart';
import 'package:noir/src/core/renderer.dart';

// A pipe-backed, blocking Dart stdout with terminal capabilities supplied by
// a fake. This exercises the real platform writer without a PTY or raw stdin.
class _TerminalStdout implements Stdout {
  _TerminalStdout(this.delegate);
  final Stdout delegate;
  @override
  bool get hasTerminal => true;
  @override
  int get terminalColumns => 8;
  @override
  int get terminalLines => 2;
  @override
  void write(Object? object) => delegate.write(object);
  @override
  Future<void> flush() => delegate.flush();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Input implements TerminalInputDriver {
  @override
  bool start() => true;
  @override
  void stop() {}
}

void main() {
  // Borrows process stdout; this adapter does not own or close that sink.
  // ignore: close_sinks
  final output = _TerminalStdout(stdout);
  IOOverrides.runZoned(() {
    final renderer = Renderer.create(8, 2, testing: true);
    final session = TerminalSession(
      width: 8,
      height: 2,
      headless: false,
      renderer: renderer,
      inputDispatcher: InputDispatcher(),
      scheduleFrame: () {},
      inputDriverFactory: (_) => _Input(),
    );
    try {
      session.enableMouse();
      session.updateMouseCursor(MouseCursor.pointer);
      session.disableMouse();
      session.enableMouse();
      session.updateMouseCursor(MouseCursor.text);
    } finally {
      session.close();
      renderer.dispose();
    }
  }, stdout: () => output);
  stdout.write('PASS:mouse-pointer-startup-and-cleanup');
}
