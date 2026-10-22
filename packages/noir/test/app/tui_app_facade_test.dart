import 'dart:convert';
import 'dart:ffi';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show createTuiAppForTesting;
import 'package:noir/src/core/renderer.dart' show createRendererForTesting;
import 'package:noir/src/ffi/bindings.dart';
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:noir/src/ffi/types.dart';
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

  test(
    'copyToClipboard requests the system clipboard through the renderer',
    () {
      final native = _ClipboardNativeSymbols();
      final renderer = createRendererForTesting(
        OpenTuiBindings.fromNativeSymbols(native),
        RendererHandle.fromNative(9),
      );
      addTearDown(renderer.dispose);
      final app = createTuiAppForTesting(
        TuiBinding(headless: true, renderer: renderer),
      );
      addTearDown(app.dispose);

      expect(app.copyToClipboard('世界'), isTrue);
      expect(native.copied, (renderer: 9, target: 0, text: '世界'));

      native
        ..copied = null
        ..accepts = false;
      expect(app.copyToClipboard('declined'), isFalse);
      expect(native.copied?.text, 'declined');
    },
  );

  test('copyToClipboard reports false without a renderer or text', () {
    final headless = createTuiAppForTesting(TuiBinding(headless: true));
    addTearDown(headless.dispose);
    expect(headless.copyToClipboard('text'), isFalse);

    final native = _ClipboardNativeSymbols();
    final renderer = createRendererForTesting(
      OpenTuiBindings.fromNativeSymbols(native),
      RendererHandle.fromNative(10),
    );
    addTearDown(renderer.dispose);
    final app = createTuiAppForTesting(
      TuiBinding(headless: true, renderer: renderer),
    );
    addTearDown(app.dispose);
    expect(app.copyToClipboard(''), isFalse);
    expect(native.copied, isNull);
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
      () => app.copyToClipboard('text'),
    ]) {
      expect(operation, throwsStateError);
    }
  });
}

final class _ClipboardNativeSymbols implements OpenTuiNativeSymbols {
  ({int renderer, int target, String text})? copied;
  bool accepts = true;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final arguments = invocation.positionalArguments;
    switch (invocation.memberName) {
      case #copyToClipboardOSC52:
        final pointer = arguments[2]! as Pointer<Uint8>;
        final length = arguments[3]! as int;
        copied = (
          renderer: arguments[0]! as int,
          target: arguments[1]! as int,
          text: utf8.decode(pointer.asTypedList(length)),
        );
        return accepts;
      case #destroyRenderer:
        return null;
      default:
        throw UnsupportedError(invocation.memberName.toString());
    }
  }
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
