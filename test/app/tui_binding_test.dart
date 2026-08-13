import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  test(
    'runTuiApp mounts widget, schedules first frame, and returns facade',
    () {
      final key = GlobalKey<_BuildProbeState>();
      final app = runTuiApp(_BuildProbe(key: key), headless: true);

      try {
        expect(app, isA<TuiApp>());
        expect(app.isHeadless, isTrue);
        expect(key.currentState!.buildCount, 1);
      } finally {
        app.dispose();
      }
    },
  );

  test('binding input dispatch schedules frames and rebuilds state', () async {
    final key = GlobalKey<_CounterAppState>();
    final binding = TuiBinding(headless: true)..runApp(_CounterApp(key: key));

    try {
      final state = key.currentState!;
      expect(state.buildCount, 1);

      await Future<void>.delayed(Duration.zero);

      binding.inputManager.dispatchKey(
        KeyEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          keyCode: 97,
          character: 'a',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(state.receivedKeys, ['a']);
      expect(state.buildCount, 2);
    } finally {
      binding.dispose();
    }
  });

  test('facade dispose unregisters and unmounts root once', () {
    final disposals = <String>[];
    final app = runTuiApp(
      _DisposeProbe(onDispose: () => disposals.add('dispose')),
      headless: true,
    );

    for (var i = 0; i < 2; i++) {
      app.dispose();
    }

    expect(disposals, ['dispose']);
  });

  test('binding rejects a second root mount', () {
    final firstDisposals = <String>[];
    final binding = TuiBinding(headless: true)
      ..runApp(_DisposeProbe(onDispose: () => firstDisposals.add('first')));

    try {
      expect(
        () => binding.runApp(const Text('second')),
        throwsA(isA<StateError>()),
      );
      expect(firstDisposals, isEmpty);
    } finally {
      binding.dispose();
    }

    expect(firstDisposals, ['first']);
  });

  test('binding rejects mounting after dispose', () {
    final binding = TuiBinding(headless: true)
      ..runApp(const Text('first'))
      ..dispose();

    expect(
      () => binding.runApp(const Text('second')),
      throwsA(isA<StateError>()),
    );
  });

  test(
    'headless injected renderer remains caller-owned through binding dispose',
    () async {
      final renderer = Renderer.create(8, 2, testing: true);
      final binding = TuiBinding(
        width: 8,
        height: 2,
        headless: true,
        renderer: renderer,
      )..runApp(const Text('ok'));

      try {
        await Future<void>.delayed(Duration.zero);

        binding.dispose();

        expect(() => renderer.nextBuffer.clear(Color.black), returnsNormally);
      } finally {
        renderer.dispose();
      }
    },
  );

  test('resize schedules only after a different positive size is applied', () {
    final binding = TuiBinding(width: 5, height: 2, headless: true);
    addTearDown(binding.dispose);

    expect(binding.debugHasScheduledFrame, isFalse);

    binding.handleResize(0, 4);
    expect(binding.debugHasScheduledFrame, isFalse);

    binding.handleResize(5, 2);
    expect(binding.debugHasScheduledFrame, isFalse);

    binding.handleResize(9, 4);
    expect(binding.debugHasScheduledFrame, isTrue);
  });

  test('failed resize preserves state and does not schedule', () {
    final renderer = Renderer.create(5, 2, testing: true);
    final binding = TuiBinding(
      width: 5,
      height: 2,
      headless: true,
      renderer: renderer,
    );
    renderer.dispose();

    addTearDown(binding.dispose);

    expect(binding.debugHasScheduledFrame, isFalse);
    expect(() => binding.handleResize(9, 4), throwsStateError);
    expect(binding.debugHasScheduledFrame, isFalse);

    expect(() => binding.handleResize(5, 2), returnsNormally);
    expect(binding.debugHasScheduledFrame, isFalse);
  });
}

class _CounterApp extends StatefulWidget {
  const _CounterApp({super.key});

  @override
  State<StatefulWidget> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  int buildCount = 0;
  final List<String> receivedKeys = [];
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }
    receivedKeys.add(event.character ?? event.logicalKey.keyLabel);
    setState(() {});
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: const Container(),
    );
  }
}

class _BuildProbe extends StatefulWidget {
  const _BuildProbe({super.key});

  @override
  State<_BuildProbe> createState() => _BuildProbeState();
}

class _BuildProbeState extends State<_BuildProbe> {
  int buildCount = 0;

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return const Container();
  }
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
  Widget build(BuildContext context) => const Container();
}
