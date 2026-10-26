import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;
import 'package:noir/src/core/input.dart';
import 'package:test/test.dart';

void main() {
  test('app exit cancels later app handlers in the same dispatch', () {
    final binding = TuiBinding(headless: true);
    final app = mountTuiAppForTesting(
      binding,
      const Text('app'),
      exitCodeSink: (_) {},
    );
    addTearDown(app.dispose);
    final calls = <String>[];
    app.onKey((_) {
      calls.add('exit');
      app.requestExit();
    });
    app.onKey((_) => calls.add('disposed'));

    binding.inputManager.dispatchKey(_key());

    expect(calls, ['exit']);
  });

  final lanes =
      <
        String,
        ({
          InputSubscription Function(InputDispatcher, void Function())
          subscribe,
          void Function(InputDispatcher) dispatch,
        })
      >{
        'key': (
          subscribe: (dispatcher, callback) =>
              dispatcher.onKey((_) => callback()),
          dispatch: (dispatcher) => dispatcher.dispatchKeyEvent(_key()),
        ),
        'mouse': (
          subscribe: (dispatcher, callback) =>
              dispatcher.onMouse((_) => callback()),
          dispatch: (dispatcher) => dispatcher.dispatchMouseEvent(
            MouseEvent(
              type: MouseEventType.down,
              button: MouseButton.left,
              x: 0,
              y: 0,
            ),
          ),
        ),
        'paste': (
          subscribe: (dispatcher, callback) =>
              dispatcher.onPaste((_) => callback()),
          dispatch: (dispatcher) =>
              dispatcher.dispatchPasteEvent(PasteEvent('a')),
        ),
        'capability': (
          subscribe: (dispatcher, callback) =>
              dispatcher.onCapabilityResponse((_) => callback()),
          dispatch: (dispatcher) => dispatcher.dispatchCapabilityResponse(
            TerminalCapabilityEvent(
              kind: TerminalCapabilityKind.primaryDeviceAttributes,
              payload: '?1',
              raw: '\x1b[?1c',
            ),
          ),
        ),
      };

  for (final MapEntry(key: lane, value: operations) in lanes.entries) {
    test('$lane cancellation skips a pending listener and preserves order', () {
      final dispatcher = InputDispatcher();
      final calls = <String>[];
      late InputSubscription canceled;
      operations.subscribe(dispatcher, () {
        calls.add('first');
        canceled.cancel();
      });
      canceled = operations.subscribe(dispatcher, () => calls.add('canceled'));
      operations.subscribe(dispatcher, () => calls.add('last'));

      operations.dispatch(dispatcher);

      expect(calls, ['first', 'last']);
    });
  }

  test('canceling a duplicate callback skips only its registration', () {
    final dispatcher = InputDispatcher();
    final calls = <String>[];
    void shared(KeyEvent _) => calls.add('shared');
    dispatcher.onKey(shared);
    late InputSubscription second;
    dispatcher.onKey((_) {
      calls.add('cancel');
      second.cancel();
    });
    second = dispatcher.onKey(shared);

    dispatcher.dispatchKeyEvent(_key());
    dispatcher.dispatchKeyEvent(_key());

    expect(calls, ['shared', 'cancel', 'shared', 'cancel']);
  });

  test('canceling the first duplicate keeps the second active', () {
    final dispatcher = InputDispatcher();
    var calls = 0;
    void shared(KeyEvent _) => calls++;
    final first = dispatcher.onKey(shared);
    dispatcher.onKey((_) => first.cancel(), priority: InputPriority.app);
    dispatcher.onKey(shared);

    dispatcher.dispatchKeyEvent(_key());

    expect(calls, 1);
  });
}

KeyEvent _key() =>
    KeyEvent(logicalKey: LogicalKeyboardKey.keyA, keyCode: 97, character: 'a');
