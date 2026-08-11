import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TuiApp no longer owns terminal session internals', () {
    final source = File('lib/src/app/app.dart').readAsStringSync();
    final body = _classBody(source, 'TuiApp');

    expect(source, isNot(contains('Renderer.create')));
    expect(source, isNot(contains('StdinInputDriver')));
    expect(source, isNot(contains('ProcessSignal')));
    expect(source, isNot(contains('_installSignalHandlers')));
    expect(source, isNot(contains('_installResizeHandler')));
    expect(source, isNot(contains('_restoreTerminalSession')));
    expect(source, isNot(contains(r'\x1b[?1049l\x1b[?25h\x1b[0m')));
    expect(source, isNot(contains(r'\x1b[?1000l\x1b[?1006l')));
    expect(source, isNot(contains(r'\x1b[<u')));
    expect(body, isNot(contains('TerminalSession')));
  });

  test('TerminalSession remains internal and owns terminal lifecycle', () {
    final source = File('lib/src/app/terminal_session.dart').readAsStringSync();
    final bindingSource = File(
      'lib/src/app/tui_binding.dart',
    ).readAsStringSync();
    final publicBarrel = File('lib/noir.dart').readAsStringSync();
    final lowLevelBarrel = File('lib/noir_low_level.dart').readAsStringSync();

    expect(publicBarrel, isNot(contains('terminal_session.dart')));
    expect(lowLevelBarrel, isNot(contains('terminal_session.dart')));
    expect(source, contains('class TerminalSession'));
    expect(source, contains('Renderer.create'));
    expect(source, contains('StdinInputDriver'));
    expect(source, contains('TerminalSignal.resize'));
    expect(source, contains(r'\x1b[?1049l\x1b[?25h\x1b[0m'));
    expect(bindingSource, contains('TerminalSession('));
  });

  test('stdin modes have one driver owner and app code stays above FFI', () {
    final sessionSource = File(
      'lib/src/app/terminal_session.dart',
    ).readAsStringSync();
    final stdinSource = File(
      'lib/src/core/stdin_input_driver.dart',
    ).readAsStringSync();
    final rendererSource = File(
      'lib/src/core/renderer.dart',
    ).readAsStringSync();

    for (final forbidden in <String>[
      'stdinHasTerminal',
      'stdinLineMode',
      'stdinEchoMode',
      'io.stdin',
      'OpenTuiBindings',
      '.bindings',
      '.handle',
    ]) {
      expect(sessionSource, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(stdinSource, contains('lineMode'));
    expect(stdinSource, contains('echoMode'));
    expect(rendererSource, contains('processRendererCapabilityResponse'));
    expect(
      rendererSource,
      contains(
        'renderer._bindings.processCapabilityResponse(renderer._ptr, response)',
      ),
    );
  });
}

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex < 0) {
    throw StateError('Class $className not found');
  }
  final start = source.indexOf('{', classIndex);
  if (start < 0) {
    throw StateError('Class $className has no body');
  }
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 0x7b) depth++;
    if (code == 0x7d) {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('Class $className body is unterminated');
}
