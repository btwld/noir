// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:test/test.dart';

void main() {
  group('Tab-key focus traversal and onKeyEvent routing', () {
    test('Tab walks attached focus nodes in widget-tree order', () async {
      final scope = FocusScopeNode(debugLabel: 'app');
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');
      final d = FocusNode(debugLabel: 'd');

      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          child: Column(
            children: [
              Focus(
                focusNode: a,
                autofocus: true,
                child: const SizedBox(width: 1, height: 1),
              ),
              TextInput(focusNode: b),
              Select<String>(
                focusNode: c,
                options: const [SelectOption(name: 'one', value: 'one')],
              ),
              Focus(focusNode: d, child: const SizedBox(width: 1, height: 1)),
            ],
          ),
        ),
        headless: true,
      );

      // Yield twice: autofocus runs as a microtask, and we want the first
      // setState reaction to flush as well.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      // The FocusScope is excluded because it can't itself request focus;
      // mixed `Focus`/`TextInput`/`Select` widgets appear in declared order.
      expect(fm.traversalOrder(), [a, b, c, d]);
      expect(a.hasFocus, isTrue);

      Future<void> tab({bool shift = false}) async {
        app.inputManager.dispatchKey(
          KeyEvent(
            logicalKey: LogicalKeyboardKey.tab,
            keyCode: 9,
            modifiers: shift ? KeyModifiers.shift : 0,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      }

      await tab();
      expect(b.hasFocus, isTrue);

      await tab();
      expect(c.hasFocus, isTrue);

      await tab();
      expect(d.hasFocus, isTrue);

      // Wrap-around forward.
      await tab();
      expect(a.hasFocus, isTrue);

      // Shift+Tab walks backwards and wraps to the last node.
      await tab(shift: true);
      expect(d.hasFocus, isTrue);

      await tab(shift: true);
      expect(c.hasFocus, isTrue);

      app.dispose();
    });

    test('Scope onKeyEvent remains a semantic low-level hook', () async {
      final scope = FocusScopeNode(debugLabel: 'app');
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final intercepted = <String>[];

      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          onKeyEvent: (node, event) {
            if (event.logicalKey == LogicalKeyboardKey.escape &&
                event.isPress) {
              intercepted.add('escape');
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            children: [
              Focus(
                focusNode: a,
                autofocus: true,
                child: const SizedBox(width: 1, height: 1),
              ),
              Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
            ],
          ),
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      app.inputManager.dispatchKey(
        KeyEvent(logicalKey: LogicalKeyboardKey.escape, keyCode: 27),
      );
      await Future<void>.delayed(Duration.zero);

      expect(intercepted, ['escape']);
      expect(a.hasFocus, isTrue);
      expect(b.hasFocus, isFalse);

      app.dispose();
    });

    test('focused node can consume Tab before default traversal', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final intercepted = <String>[];

      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(
              focusNode: a,
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event.logicalKey == LogicalKeyboardKey.tab) {
                  intercepted.add('tab');
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: const SizedBox(width: 1, height: 1),
            ),
            Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      app.inputManager.dispatchKey(
        KeyEvent(logicalKey: LogicalKeyboardKey.tab, keyCode: 9),
      );
      await Future<void>.delayed(Duration.zero);

      expect(intercepted, ['tab']);
      expect(a.hasFocus, isTrue);
      expect(b.hasFocus, isFalse);

      app.dispose();
    });

    test('skipRemainingHandlers stops focus chain without consuming', () async {
      final scope = FocusScopeNode(debugLabel: 'app');
      final child = FocusNode(debugLabel: 'child');
      final calls = <String>[];

      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          onKeyEvent: (node, event) {
            calls.add('scope');
            return KeyEventResult.handled;
          },
          child: Focus(
            focusNode: child,
            autofocus: true,
            onKeyEvent: (node, event) {
              calls.add('child');
              return KeyEventResult.skipRemainingHandlers;
            },
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
        headless: true,
      );
      final fallback = app.inputManager.onKey((event) => calls.add('fallback'));

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      app.inputManager.dispatchKey(
        KeyEvent(logicalKey: LogicalKeyboardKey.escape, keyCode: 27),
      );
      await Future<void>.delayed(Duration.zero);

      expect(calls, ['child', 'fallback']);

      fallback.cancel();
      app.dispose();
    });

    test('traversalOrder is recomputed when nodes attach and detach', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');

      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(focusNode: a, child: const SizedBox(width: 1, height: 1)),
            Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      expect(fm.traversalOrder(), [a, b]);

      // Disposing `a` detaches its node from the manager; the cache
      // invalidates and the next read no longer contains it.
      a.dispose();
      expect(fm.traversalOrder(), [b]);

      app.dispose();
    });

    test('detaching the focused child notifies its immediate scope', () async {
      final scope = FocusScopeNode(debugLabel: 'scope');
      final child = FocusNode(debugLabel: 'child');
      final key = GlobalKey<_RemovableFocusState>();
      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          child: _RemovableFocus(key: key, node: child),
        ),
        headless: true,
      );
      addTearDown(app.dispose);
      addTearDown(scope.dispose);
      addTearDown(child.dispose);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(child.hasFocus, isTrue);

      var notifications = 0;
      scope.addListener(() => notifications++);
      key.currentState!.hide();
      app.debugFlushFrame();

      expect(app.buildOwner.focusManager.primaryFocus, isNull);
      expect(notifications, 1);
    });
  });
}

class _RemovableFocus extends StatefulWidget {
  const _RemovableFocus({required this.node, super.key});

  final FocusNode node;

  @override
  State<_RemovableFocus> createState() => _RemovableFocusState();
}

class _RemovableFocusState extends State<_RemovableFocus> {
  var _visible = true;

  void hide() => setState(() => _visible = false);

  @override
  Widget build(BuildContext context) => _visible
      ? Focus(
          focusNode: widget.node,
          autofocus: true,
          child: const SizedBox(width: 1, height: 1),
        )
      : const SizedBox.shrink();
}
