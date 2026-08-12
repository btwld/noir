// ignore_for_file: cascade_invocations
import 'dart:io';

import 'package:noir/src/core/input.dart';
import 'package:test/test.dart';

KeyEvent _character(String character, {int modifiers = 0}) => KeyEvent(
  logicalKey: LogicalKeyboardKey.forCharacter(character),
  keyCode: character.codeUnitAt(0),
  character: modifiers == 0 ? character : null,
  modifiers: modifiers,
);

void main() {
  group('InputManager subscriptions', () {
    test(
      'multiple key subscribers all see a key event in priority order (high → low)',
      () {
        final inputManager = InputManager();
        final order = <String>[];

        inputManager.onKey(
          (event) => order.add('app'),
          priority: InputPriority.app,
        );
        inputManager.onKey(
          (event) => order.add('focus'),
          priority: InputPriority.focus,
        );
        inputManager.onKey((event) => order.add('widget'));

        inputManager.dispatchKey(_character('a'));

        expect(order, equals(['app', 'focus', 'widget']));
      },
    );

    test(
      'high-priority subscriber that consumes prevents lower-priority delivery',
      () {
        final inputManager = InputManager();
        final order = <String>[];

        inputManager.onKey((event) {
          order.add('app');
          event.consume();
        }, priority: InputPriority.app);
        inputManager.onKey(
          (event) => order.add('focus'),
          priority: InputPriority.focus,
        );
        inputManager.onKey((event) => order.add('widget'));

        final event = _character('a');
        inputManager.dispatchKey(event);

        expect(order, equals(['app']));
        expect(event.isConsumed, isTrue);
      },
    );

    test(
      'subscribers at the same priority are called in registration order',
      () {
        final inputManager = InputManager();
        final order = <String>[];

        inputManager.onKey((event) => order.add('first'));
        inputManager.onKey((event) => order.add('second'));
        inputManager.onKey((event) => order.add('third'));

        inputManager.dispatchKey(_character('a'));

        expect(order, equals(['first', 'second', 'third']));
      },
    );

    test('cancelling an InputSubscription removes the handler', () {
      final inputManager = InputManager();
      final order = <String>[];

      final sub = inputManager.onKey((event) => order.add('kept'));
      final tempSub = inputManager.onKey((event) => order.add('cancelled'));

      tempSub.cancel();
      inputManager.dispatchKey(_character('a'));

      expect(order, equals(['kept']));

      // Cancelling again is a no-op.
      tempSub.cancel();
      inputManager.dispatchKey(_character('b'));
      expect(order, equals(['kept', 'kept']));

      sub.cancel();
      inputManager.dispatchKey(_character('c'));
      expect(order, equals(['kept', 'kept']));
    });

    test('dispatchPaste delivers a single PasteEvent', () {
      final inputManager = InputManager();
      final pastes = <String>[];

      inputManager.onPaste((event) => pastes.add(event.text));

      inputManager.dispatchPaste(PasteEvent('hello world'));

      expect(pastes, equals(['hello world']));
    });

    test(
      'app-priority shortcut consumes Ctrl-Q; focus listener still sees ordinary keys',
      () {
        final inputManager = InputManager();
        final focusKeys = <String>[];
        final appKeys = <String>[];

        // App-priority shortcut: consume Ctrl-Q.
        inputManager.onKey((event) {
          if (event.logicalKey == LogicalKeyboardKey.keyQ &&
              event.isControlPressed) {
            appKeys.add('ctrl-q');
            event.consume();
          }
        }, priority: InputPriority.app);

        // Focus listener: log every key it actually sees.
        inputManager.onKey((event) {
          focusKeys.add(event.character ?? event.logicalKey.keyLabel);
        }, priority: InputPriority.focus);

        // Ctrl-Q is swallowed by the app shortcut.
        final ctrlQ = _character('q', modifiers: KeyModifiers.ctrl);
        inputManager.dispatchKey(ctrlQ);

        // Plain 'a' reaches both — app handler ignores it, focus logs it.
        final a = _character('a');
        inputManager.dispatchKey(a);

        expect(appKeys, equals(['ctrl-q']));
        expect(focusKeys, equals(['a']));
        expect(ctrlQ.isConsumed, isTrue);
        expect(a.isConsumed, isFalse);
      },
    );
  });

  group('InputDispatcher ownership', () {
    test(
      'InputDispatcher preserves key priority, registration order, and consume',
      () {
        final dispatcher = InputDispatcher();
        final order = <String>[];

        dispatcher.onKey(
          (event) => order.add('app'),
          priority: InputPriority.app,
        );
        dispatcher.onKey((event) {
          order.add('focus');
          event.consume();
        }, priority: InputPriority.focus);
        dispatcher.onKey(
          (event) => order.add('second focus'),
          priority: InputPriority.focus,
        );
        dispatcher.onKey((event) => order.add('widget'));

        final event = _character('a');
        dispatcher.dispatchKeyEvent(event);

        expect(order, ['app', 'focus']);
        expect(event.isConsumed, isTrue);
      },
    );

    test('InputManager public API delegates through its dispatcher', () {
      final inputManager = InputManager();
      final seen = <String>[];

      inputManager.dispatcher.onKey(
        (event) => seen.add(
          'dispatcher:${event.character ?? event.logicalKey.keyLabel}',
        ),
        priority: InputPriority.app,
      );
      inputManager.onKey(
        (event) =>
            seen.add('manager:${event.character ?? event.logicalKey.keyLabel}'),
      );

      inputManager.dispatchKey(_character('x'));

      expect(seen, ['dispatcher:x', 'manager:x']);
    });

    test('after-event callback fires once after key, mouse, and paste', () {
      final dispatcher = InputDispatcher();
      var frames = 0;
      dispatcher.setEventDispatch(() => frames++);

      dispatcher.onKey((event) => event.consume());
      dispatcher.onMouse((event) => event.consume());
      dispatcher.onPaste((event) => event.consume());

      dispatcher.dispatchKeyEvent(_character('a'));
      dispatcher.dispatchMouseEvent(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      dispatcher.dispatchPasteEvent(PasteEvent('paste'));

      expect(frames, 3);
    });

    test('capability dispatch requests frames only when handled', () {
      final dispatcher = InputDispatcher();
      var frames = 0;
      final seen = <TerminalCapabilityEvent>[];
      dispatcher.setEventDispatch(() => frames++);

      dispatcher.dispatchCapabilityResponse(
        TerminalCapabilityEvent(
          kind: TerminalCapabilityKind.primaryDeviceAttributes,
          payload: '?62;4',
          raw: '\x1b[?62;4c',
        ),
      );

      expect(frames, 0);
      expect(seen, isEmpty);

      dispatcher.onCapabilityResponse(seen.add);
      dispatcher.dispatchCapabilityResponse(
        TerminalCapabilityEvent(
          kind: TerminalCapabilityKind.primaryDeviceAttributes,
          payload: '?62;4',
          raw: '\x1b[?62;4c',
        ),
      );

      expect(frames, 1);
      expect(seen.single.payload, '?62;4');
    });

    test('capability dispatch preserves priority order and consume', () {
      final dispatcher = InputDispatcher();
      final order = <String>[];

      dispatcher.onCapabilityResponse(
        (event) => order.add('app'),
        priority: InputPriority.app,
      );
      dispatcher.onCapabilityResponse((event) {
        order.add('focus');
        event.consume();
      }, priority: InputPriority.focus);
      dispatcher.onCapabilityResponse(
        (event) => order.add('second focus'),
        priority: InputPriority.focus,
      );
      dispatcher.onCapabilityResponse((event) => order.add('widget'));

      final event = TerminalCapabilityEvent(
        kind: TerminalCapabilityKind.primaryDeviceAttributes,
        payload: '?62;4',
        raw: '\x1b[?62;4c',
      );
      dispatcher.dispatchCapabilityResponse(event);

      expect(order, ['app', 'focus']);
      expect(event.isConsumed, isTrue);
    });

    test('InputManager owns no subscription bus', () {
      final source = File('lib/src/core/input.dart').readAsStringSync();
      final body = _classBody(source, 'InputManager');

      expect(body, isNot(contains('_keyByPriority')));
      expect(body, isNot(contains('_mouseByPriority')));
      expect(body, isNot(contains('_pasteByPriority')));
      expect(body, isNot(contains('_afterEvent')));
      expect(body, isNot(contains('SplayTreeMap')));
      expect(body, isNot(contains('processKeyEvent')));
      expect(body, isNot(contains('processMouseEvent')));
      expect(body, isNot(contains('processPasteEvent')));
    });
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
