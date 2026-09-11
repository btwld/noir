import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;
import 'package:noir/src/app/terminal_session.dart';
import 'package:noir/src/app/tui_binding.dart' show createTuiBindingForTesting;
import 'package:test/test.dart';

void main() {
  test('rendererless mouse options fail before mounting the widget', () {
    var initialized = 0;
    TuiApp? captured;
    addTearDown(() => captured?.dispose());

    expect(
      () => runTuiApp(
        _StartupProbe(
          onInit: () => initialized++,
          onBuild: (state) => captured = TuiApp.of(state.context),
          onDispose: () {},
        ),
        headless: true,
        enableMouse: true,
      ),
      throwsStateError,
    );
    expect(initialized, 0);
  });

  test('mode activation failure releases an already mounted binding', () {
    final binding = TuiBinding(headless: true);
    late _StartupProbeState state;
    TuiApp? captured;
    var disposals = 0;
    addTearDown(() => captured?.dispose());

    expect(
      () => mountTuiAppForTesting(
        binding,
        _StartupProbe(
          onInit: () {},
          onBuild: (mounted) {
            state = mounted;
            captured = TuiApp.of(state.context);
          },
          onDispose: () => disposals++,
        ),
        exitCodeSink: (_) {},
        enableMouse: true,
      ),
      throwsStateError,
    );

    expect(state.mounted, isFalse);
    expect(disposals, 1);
    expect(binding.debugHasScheduledFrame, isFalse);
    expect(captured!.dispose, returnsNormally);
    expect(disposals, 1);
  });

  for (final failDuringDisposal in [false, true]) {
    test('activation failure releases ownership when disposal '
        '${failDuringDisposal ? 'throws' : 'succeeds'}', () {
      final renderer = Renderer.create(8, 2, testing: true);
      final driver = _InputDriver();
      final input = InputManager();
      final binding = createTuiBindingForTesting(
        width: 8,
        height: 2,
        inputManager: input,
        rendererFactory: (_, _) => renderer,
        terminalPlatform: _TerminalPlatform(),
        inputDriverFactory: (_) => driver,
      );
      late _StartupProbeState state;
      TuiApp? captured;
      var disposals = 0;
      var keyCalls = 0;
      final primaryError = StateError('activation failed');
      final primaryStack = StackTrace.fromString('activation stack');
      Object? caughtError;
      StackTrace? caughtStack;
      addTearDown(() {
        try {
          captured?.dispose();
        } on Object {
          // The red regression must also release its intentionally leaked app.
        }
        binding.dispose();
        renderer.dispose();
      });

      try {
        mountTuiAppForTesting(
          binding,
          _StartupProbe(
            onInit: () {},
            onBuild: (mounted) => state = mounted,
            onDispose: () {
              disposals++;
              if (failDuringDisposal) throw StateError('cleanup failed');
            },
          ),
          exitCodeSink: (_) {},
          onMounted: (app) {
            captured = app;
            app.onKey((_) => keyCalls++);
            Error.throwWithStackTrace(primaryError, primaryStack);
          },
        );
      } on Object catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      }

      expect(caughtError, same(primaryError));
      expect(caughtStack.toString(), primaryStack.toString());
      expect(state.mounted, isFalse);
      expect(disposals, 1);
      expect(driver.stops, 1);
      expect(binding.debugHasScheduledFrame, isFalse);
      expect(() => renderer.nextBuffer, throwsStateError);
      expect(() => binding.runApp(const SizedBox()), throwsStateError);
      input.dispatchKey(
        KeyEvent(logicalKey: LogicalKeyboardKey.keyA, keyCode: 97),
      );
      expect(keyCalls, 0);
      expect(captured!.dispose, returnsNormally);
      expect(disposals, 1);
      expect(driver.stops, 1);
    });
  }
}

class _StartupProbe extends StatefulWidget {
  const _StartupProbe({
    required this.onInit,
    required this.onBuild,
    required this.onDispose,
  });

  final void Function() onInit;
  final void Function(_StartupProbeState state) onBuild;
  final void Function() onDispose;

  @override
  State<_StartupProbe> createState() => _StartupProbeState();
}

class _StartupProbeState extends State<_StartupProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) {
    widget.onBuild(this);
    return const SizedBox();
  }

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}

class _InputDriver implements TerminalInputDriver {
  int stops = 0;

  @override
  bool start() => true;

  @override
  void stop() => stops++;
}

class _TerminalPlatform implements TerminalPlatform {
  @override
  String? get terminalProgram => null;

  @override
  bool get stdoutHasTerminal => false;

  @override
  bool get isWindows => false;

  @override
  int get terminalColumns => 8;

  @override
  int get terminalLines => 2;

  @override
  void stdoutWrite(String data) {}

  @override
  Stream<void> watchSignal(TerminalSignal signal) => const Stream.empty();
}
