import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show createTuiAppForTesting;
import 'package:test/test.dart';

void main() {
  test('runTuiApp mounts once and TuiApp dispose unmounts once', () {
    final disposals = <String>[];
    final app = runTuiApp(
      _DisposeProbe(onDispose: () => disposals.add('dispose')),
      headless: true,
    );

    expect(app, isA<TuiApp>());
    expect(app.isHeadless, isTrue);

    for (var i = 0; i < 2; i++) {
      app.dispose();
    }

    expect(disposals, ['dispose']);
  });

  test('app handlers dispatch first and cancel idempotently', () {
    final inputManager = InputManager();
    final app = createTuiAppForTesting(
      TuiBinding(headless: true, inputManager: inputManager),
    );
    final calls = <String>[];
    inputManager
      ..onKey((_) => calls.add('key:focus'), priority: InputPriority.focus)
      ..onMouse((_) => calls.add('mouse:widget'))
      ..onPaste((_) => calls.add('paste:widget'));
    final cancelKey = app.onKey((_) => calls.add('key:app'));
    final cancelMouse = app.onMouse((_) => calls.add('mouse:app'));
    final cancelPaste = app.onPaste((_) => calls.add('paste:app'));

    try {
      _dispatchAll(inputManager);
      expect(calls, <String>[
        'key:app',
        'key:focus',
        'mouse:app',
        'mouse:widget',
        'paste:app',
        'paste:widget',
      ]);

      calls.clear();
      for (final cancel in <VoidCallback>[
        cancelKey,
        cancelMouse,
        cancelPaste,
      ]) {
        cancel();
        cancel();
      }
      _dispatchAll(inputManager);
      expect(calls, <String>['key:focus', 'mouse:widget', 'paste:widget']);
    } finally {
      app.dispose();
    }
  });

  test('reassemble forwards to the binding and rebuilds the tree', () {
    final log = <String>[];
    final binding = TuiBinding(headless: true)..runApp(_BuildProbe(log));
    final app = createTuiAppForTesting(binding);
    addTearDown(app.dispose);

    expect(log, <String>['build']);

    app.reassemble();
    binding.debugFlushFrame();

    expect(log, <String>['build', 'build']);
  });

  test('dispose cancels active handlers and rejects every mutator', () {
    final inputManager = InputManager();
    final app = createTuiAppForTesting(
      TuiBinding(headless: true, inputManager: inputManager),
    );
    final calls = <String>[];
    final cancelers = <VoidCallback>[
      app.onKey((_) => calls.add('key')),
      app.onMouse((_) => calls.add('mouse')),
      app.onPaste((_) => calls.add('paste')),
    ];

    expect(app.isHeadless, isTrue);
    _dispatchAll(inputManager);
    expect(calls, <String>['key', 'mouse', 'paste']);

    app
      ..dispose()
      ..dispose();
    for (final cancel in cancelers) {
      cancel();
      cancel();
    }

    calls.clear();
    _dispatchAll(inputManager);
    expect(calls, isEmpty);
    expect(app.isHeadless, isTrue);

    for (final operation in <void Function()>[
      () => app.onKey((_) {}),
      () => app.onMouse((_) {}),
      () => app.onPaste((_) {}),
      app.enableMouse,
      app.disableMouse,
      app.enableKittyKeyboard,
      app.disableKittyKeyboard,
      app.reassemble,
    ]) {
      expect(operation, throwsStateError);
    }
  });
}

class _BuildProbe extends StatelessWidget {
  const _BuildProbe(this.log);

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('build');
    return const SizedBox();
  }
}

void _dispatchAll(InputManager inputManager) {
  inputManager
    ..dispatchKey(
      KeyEvent(
        logicalKey: LogicalKeyboardKey.keyA,
        keyCode: 'a'.codeUnitAt(0),
        character: 'a',
      ),
    )
    ..dispatchMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 1,
        y: 2,
      ),
    )
    ..dispatchPaste(PasteEvent('paste'));
}

class _DisposeProbe extends StatefulWidget {
  const _DisposeProbe({required this.onDispose});

  final void Function() onDispose;

  @override
  State<_DisposeProbe> createState() => _DisposeProbeState();
}

class _DisposeProbeState extends State<_DisposeProbe> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
