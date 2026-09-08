// Regression tests: losing the focused node involuntarily must not leave the
// app with nothing focused. `Shortcuts.handleKeyEvent` routes from the
// focused element, so an unfocused tree silently stops answering every
// binding. Disabling the focused control and removing it from the tree are
// both ordinary application actions.
//
// Intentional `unfocus()` keeps its documented scope disposition and is not
// recovered; `test/widgets/focus_unfocus_test.dart` owns that contract.
// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/src/app/tui_binding.dart'
    show TuiBinding, runTuiAppForTesting;
import 'package:test/test.dart';

void main() {
  group('focus recovery after involuntary loss', () {
    test(
      'disabling the focused control focuses the first eligible node',
      () async {
        final a = FocusNode(debugLabel: 'a');
        final b = FocusNode(debugLabel: 'b');
        final c = FocusNode(debugLabel: 'c');
        final step = ValueNotifier<int>(0);
        final app = runTuiAppForTesting(
          _Swap(
            notifier: step,
            builder: (context, value) => Column(
              children: [
                Focus(
                  focusNode: a,
                  autofocus: true,
                  canRequestFocus: value == 0,
                  child: _cell,
                ),
                Focus(focusNode: b, child: _cell),
                Focus(focusNode: c, child: _cell),
              ],
            ),
          ),
          headless: true,
        );
        final manager = app.buildOwner.focusManager;
        try {
          await _settle(app);
          expect(manager.primaryFocus, same(a));

          step.value = 1;
          await _settle(app);

          expect(manager.primaryFocus, same(b));
        } finally {
          app.dispose();
          step.dispose();
        }
      },
    );

    test('a disabled Button hands focus on rather than clearing it', () async {
      final run = FocusNode(debugLabel: 'run');
      final other = FocusNode(debugLabel: 'other');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              Focus(focusNode: other, child: _cell),
              Button(
                label: 'Run',
                focusNode: run,
                autofocus: true,
                onPressed: value == 0 ? () {} : null,
              ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(run));

        step.value = 1;
        await _settle(app);

        expect(manager.primaryFocus, same(other));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('removing the focused control focuses the surviving tree', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              if (value == 0)
                Focus(focusNode: a, autofocus: true, child: _cell)
              else
                _cell,
              Focus(focusNode: b, child: _cell),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        step.value = 1;
        await _settle(app);

        expect(manager.primaryFocus, same(b));
        expect(a.isAttached, isFalse);
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('recovery prefers the nearest surviving focusable scope', () async {
      final scope = FocusScopeNode(debugLabel: 'scope');
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              Focus(focusNode: b, child: _cell),
              FocusScope(
                node: scope,
                child: value == 0
                    ? Focus(focusNode: a, autofocus: true, child: _cell)
                    : _cell,
              ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        step.value = 1;
        await _settle(app);

        expect(manager.primaryFocus, same(scope));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test(
      'recovery keeps looking past a scope that left with the control',
      () async {
        final outer = FocusScopeNode(debugLabel: 'outer');
        final inner = FocusScopeNode(debugLabel: 'inner');
        final a = FocusNode(debugLabel: 'a');
        final b = FocusNode(debugLabel: 'b');
        final step = ValueNotifier<int>(0);
        final app = runTuiAppForTesting(
          _Swap(
            notifier: step,
            builder: (context, value) => FocusScope(
              node: outer,
              child: Column(
                children: [
                  Focus(
                    key: const ValueKey<String>('b'),
                    focusNode: b,
                    child: _cell,
                  ),
                  if (value == 0)
                    FocusScope(
                      key: const ValueKey<String>('inner'),
                      node: inner,
                      child: Focus(focusNode: a, autofocus: true, child: _cell),
                    )
                  else
                    const SizedBox(
                      key: ValueKey<String>('gap'),
                      width: 1,
                      height: 1,
                    ),
                ],
              ),
            ),
          ),
          headless: true,
        );
        final manager = app.buildOwner.focusManager;
        try {
          await _settle(app);
          expect(manager.primaryFocus, same(a));

          // The inner scope leaves with the control it held, so recovery has to
          // reach the outer scope rather than fall back to traversal order.
          step.value = 1;
          await _settle(app);

          expect(manager.primaryFocus, same(outer));
        } finally {
          app.dispose();
          step.dispose();
        }
      },
    );

    test('recovery leaves focus empty when nothing is eligible', () async {
      final a = FocusNode(debugLabel: 'a');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => value == 0
              ? Focus(focusNode: a, autofocus: true, child: _cell)
              : _cell,
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        step.value = 1;
        await _settle(app);

        expect(manager.primaryFocus, isNull);
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('an intentional unfocus is still not recovered', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(focusNode: a, autofocus: true, child: _cell),
            Focus(focusNode: b, child: _cell),
          ],
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        a.unfocus();
        await _settle(app);

        expect(manager.primaryFocus, isNull);
      } finally {
        app.dispose();
      }
    });

    test('an explicit unfocus cancels an already queued recovery', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              Focus(
                key: const ValueKey<String>('a'),
                focusNode: a,
                autofocus: true,
                canRequestFocus: value == 0,
                child: _cell,
              ),
              Focus(
                key: const ValueKey<String>('b'),
                focusNode: b,
                child: _cell,
              ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        // Disabling `a` queues recovery. The caller then makes two explicit
        // decisions before the queued microtask can run: focus `b`, then clear
        // focus. The queued recovery must not undo the second one.
        step.value = 1;
        app.debugFlushFrame();
        b.requestFocus();
        b.unfocus();
        await _settle(app);

        expect(manager.primaryFocus, isNull);
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('an unrelated unfocus leaves a queued recovery alone', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final bystander = FocusNode(debugLabel: 'bystander');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              Focus(
                key: const ValueKey<String>('a'),
                focusNode: a,
                autofocus: true,
                canRequestFocus: value == 0,
                child: _cell,
              ),
              Focus(
                key: const ValueKey<String>('b'),
                focusNode: b,
                child: _cell,
              ),
              Focus(
                key: const ValueKey<String>('bystander'),
                focusNode: bystander,
                child: _cell,
              ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        // Disabling `a` queues recovery. A node that holds no focus then
        // clears its own: that is a no-op, so it must not cancel a recovery
        // queued for somebody else's involuntary loss.
        step.value = 1;
        app.debugFlushFrame();
        bystander.unfocus();
        await _settle(app);

        expect(manager.primaryFocus, same(b));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('a request that cannot claim focus leaves recovery alone', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final disabled = FocusNode(debugLabel: 'disabled');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              Focus(
                key: const ValueKey<String>('a'),
                focusNode: a,
                autofocus: true,
                canRequestFocus: value == 0,
                child: _cell,
              ),
              Focus(
                key: const ValueKey<String>('b'),
                focusNode: b,
                child: _cell,
              ),
              Focus(
                key: const ValueKey<String>('disabled'),
                focusNode: disabled,
                canRequestFocus: false,
                child: _cell,
              ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        // `disabled` cannot take focus, so its request claims nothing. It must
        // not cancel the recovery queued by disabling `a`.
        step.value = 1;
        app.debugFlushFrame();
        disabled.requestFocus();
        await _settle(app);

        expect(manager.primaryFocus, same(b));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('an explicit request in the same batch wins over recovery', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              if (value == 0)
                Focus(focusNode: a, autofocus: true, child: _cell)
              else
                _cell,
              Focus(focusNode: b, child: _cell),
              Focus(focusNode: c, child: _cell),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        step.value = 1;
        app.debugFlushFrame();
        c.requestFocus();
        await _settle(app);

        expect(manager.primaryFocus, same(c));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('an incoming autofocus wins over recovery', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final d = FocusNode(debugLabel: 'd');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              if (value == 0)
                Focus(
                  key: const ValueKey<String>('a'),
                  focusNode: a,
                  autofocus: true,
                  child: _cell,
                )
              else
                const SizedBox(
                  key: ValueKey<String>('gap'),
                  width: 1,
                  height: 1,
                ),
              Focus(
                key: const ValueKey<String>('b'),
                focusNode: b,
                child: _cell,
              ),
              if (value == 1)
                Focus(
                  key: const ValueKey<String>('d'),
                  focusNode: d,
                  autofocus: true,
                  child: _cell,
                ),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      try {
        await _settle(app);
        expect(manager.primaryFocus, same(a));

        step.value = 1;
        await _settle(app);

        expect(manager.primaryFocus, same(d));
      } finally {
        app.dispose();
        step.dispose();
      }
    });

    test('tearing the app down right after the loss does not throw', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final step = ValueNotifier<int>(0);
      final app = runTuiAppForTesting(
        _Swap(
          notifier: step,
          builder: (context, value) => Column(
            children: [
              if (value == 0)
                Focus(focusNode: a, autofocus: true, child: _cell)
              else
                _cell,
              Focus(focusNode: b, child: _cell),
            ],
          ),
        ),
        headless: true,
      );
      final manager = app.buildOwner.focusManager;
      await _settle(app);
      expect(manager.primaryFocus, same(a));

      step.value = 1;
      app.debugFlushFrame();
      app.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(manager.primaryFocus, isNull);
      step.dispose();
    });
  });
}

/// One focusable terminal cell; every node in these trees is the same size.
const _cell = SizedBox(width: 1, height: 1);

/// Rebuilds [builder] with the current [notifier] value so a test can disable
/// or remove the focused control in one ordinary frame.
class _Swap extends StatefulWidget {
  const _Swap({required this.notifier, required this.builder});

  /// Step the test advances to trigger the rebuild.
  final ValueNotifier<int> notifier;

  /// Builds the tree for the current step.
  final Widget Function(BuildContext context, int value) builder;

  @override
  State<_Swap> createState() => _SwapState();
}

class _SwapState extends State<_Swap> {
  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_handleStep);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_handleStep);
    super.dispose();
  }

  void _handleStep() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.notifier.value);
}

/// Runs one frame, then lets the autofocus and recovery microtasks finish.
Future<void> _settle(TuiBinding app) async {
  app.debugFlushFrame();
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.debugFlushFrame();
}
