import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('InputDispatcher is the single input dispatch owner', () {
    final source = File('lib/src/core/input.dart').readAsStringSync();
    final managerBody = _classBody(source, 'InputManager');
    final dispatcherBody = _classBody(source, 'InputDispatcher');

    expect(source, contains('final class InputDispatcher'));
    expect(source, contains('extension InputManagerKernelAccess'));
    expect(dispatcherBody, contains('_keyByPriority'));
    expect(dispatcherBody, contains('_mouseByPriority'));
    expect(dispatcherBody, contains('_pasteByPriority'));
    expect(dispatcherBody, contains('_afterEvent'));

    expect(managerBody, isNot(contains('SplayTreeMap')));
    expect(managerBody, isNot(contains('_keyByPriority')));
    expect(managerBody, isNot(contains('_mouseByPriority')));
    expect(managerBody, isNot(contains('_pasteByPriority')));
    expect(managerBody, isNot(contains('_afterEvent')));
    expect(managerBody, isNot(contains('processKeyEvent')));
    expect(managerBody, isNot(contains('processMouseEvent')));
    expect(managerBody, isNot(contains('processPasteEvent')));
  });

  test('TuiBinding schedules frames through InputDispatcher', () {
    final bindingSource = File(
      'lib/src/app/tui_binding.dart',
    ).readAsStringSync();
    final appSource = File('lib/src/app/app.dart').readAsStringSync();

    expect(
      bindingSource,
      contains('_inputDispatcher.setEventDispatch(_scheduler.scheduleFrame)'),
    );
    expect(bindingSource, isNot(contains('_inputManager.setEventDispatch')));
    expect(appSource, isNot(contains('_inputManager.setEventDispatch')));
  });

  test('stdin and terminal session use InputDispatcher, not InputManager', () {
    final stdinSource = File(
      'lib/src/core/stdin_input_driver.dart',
    ).readAsStringSync();
    final sessionSource = File(
      'lib/src/app/terminal_session.dart',
    ).readAsStringSync();

    expect(stdinSource, contains('StdinInputDriver(this._inputDispatcher)'));
    expect(stdinSource, contains('void dispatchTo(InputDispatcher'));
    expect(stdinSource, isNot(contains('void dispatchTo(InputManager')));
    expect(
      sessionSource,
      contains('TerminalInputDriver Function(InputDispatcher inputDispatcher)'),
    );
    expect(sessionSource, isNot(contains('StdinInputDriver(inputManager)')));
  });

  test('framework managers subscribe through dispatcher path', () {
    final focusSource = File(
      'lib/src/framework/focus_manager.dart',
    ).readAsStringSync();
    final pointerSource = File(
      'lib/src/framework/pointer_router.dart',
    ).readAsStringSync();

    expect(focusSource, contains('inputManager.dispatcher.onKey'));
    expect(pointerSource, contains('inputManager.dispatcher.onMouse'));
    expect(focusSource, isNot(contains('inputManager.onKey(')));
    expect(pointerSource, isNot(contains('inputManager.onMouse(')));
  });

  test('InputDispatcher and capability internals are not exported', () {
    final publicSurfaces = [
      File('lib/noir.dart'),
      File('lib/noir_low_level.dart'),
      File('lib/noir_ffi.dart'),
      File('test/architecture/baselines/noir_low_level_symbols.txt'),
    ];

    for (final file in publicSurfaces) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('InputDispatcher')), reason: file.path);
      expect(source, isNot(contains('input_dispatcher')), reason: file.path);
      expect(
        source,
        isNot(contains('TerminalCapabilityEvent')),
        reason: file.path,
      );
      expect(source, isNot(contains('CapabilityResponse')), reason: file.path);
    }
  });

  test('InputDispatcher does not own semantic input routing', () {
    final source = File('lib/src/core/input.dart').readAsStringSync();
    final dispatcherBody = _classBody(source, 'InputDispatcher');

    for (final symbol in [
      'Shortcuts',
      'Actions',
      'Intent',
      'FocusTraversalPolicy',
      'TextInputConnection',
    ]) {
      expect(
        RegExp('\\b$symbol\\b').hasMatch(dispatcherBody),
        isFalse,
        reason: symbol,
      );
    }
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
