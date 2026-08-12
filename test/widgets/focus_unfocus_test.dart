// Regression tests: `FocusNode.unfocus()` on the
// primary focus must never immediately reselect the node itself and must
// never jump to an arbitrary sibling. It follows Flutter's default
// `UnfocusDisposition.scope`: focus moves to the nearest enclosing scope
// that can hold it, or clears to `null` when only the synthetic root scope
// remains.
// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:test/test.dart';

void main() {
  group('FocusManager.unfocus scope disposition', () {
    test('unfocusing the first child clears focus to null with no explicit '
        'scope', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');

      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(
              focusNode: a,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
            Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
            Focus(focusNode: c, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      expect(fm.primaryFocus, same(a));

      a.unfocus();

      expect(fm.primaryFocus, isNot(same(a)));
      expect(fm.primaryFocus, isNull);
      expect(a.hasFocus, isFalse);

      app.dispose();
    });

    test(
      'unfocusing the first child moves focus to the enclosing FocusScope',
      () async {
        final scope = FocusScopeNode(debugLabel: 'scope');
        final a = FocusNode(debugLabel: 'a');
        final b = FocusNode(debugLabel: 'b');
        final c = FocusNode(debugLabel: 'c');

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
                Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
                Focus(focusNode: c, child: const SizedBox(width: 1, height: 1)),
              ],
            ),
          ),
          headless: true,
        );

        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final fm = app.buildOwner.focusManager;
        expect(fm.primaryFocus, same(a));

        a.unfocus();

        expect(fm.primaryFocus, isNot(same(a)));
        expect(fm.primaryFocus, same(scope));
        expect(scope.hasFocus, isTrue);

        app.dispose();
      },
    );

    test('unfocusing a middle child does not jump to the first sibling '
        '(root scope clears to null)', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');

      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(focusNode: a, child: const SizedBox(width: 1, height: 1)),
            Focus(
              focusNode: b,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
            Focus(focusNode: c, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      expect(fm.primaryFocus, same(b));

      b.unfocus();

      expect(fm.primaryFocus, isNot(same(a)));
      expect(fm.primaryFocus, isNot(same(b)));
      expect(fm.primaryFocus, isNull);
      expect(a.hasFocus, isFalse);
      expect(b.hasFocus, isFalse);

      app.dispose();
    });

    test('unfocusing a middle child moves focus to the enclosing FocusScope, '
        'not the first sibling', () async {
      final scope = FocusScopeNode(debugLabel: 'scope');
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final c = FocusNode(debugLabel: 'c');

      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          child: Column(
            children: [
              Focus(focusNode: a, child: const SizedBox(width: 1, height: 1)),
              Focus(
                focusNode: b,
                autofocus: true,
                child: const SizedBox(width: 1, height: 1),
              ),
              Focus(focusNode: c, child: const SizedBox(width: 1, height: 1)),
            ],
          ),
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      expect(fm.primaryFocus, same(b));

      b.unfocus();

      expect(fm.primaryFocus, isNot(same(a)));
      expect(fm.primaryFocus, isNot(same(b)));
      expect(fm.primaryFocus, same(scope));

      app.dispose();
    });

    test('unfocusing the only focusable node in a scope is not immediately '
        'reselected', () async {
      final scope = FocusScopeNode(debugLabel: 'scope');
      final a = FocusNode(debugLabel: 'a');

      final app = runTuiAppForTesting(
        FocusScope(
          node: scope,
          child: Focus(
            focusNode: a,
            autofocus: true,
            child: const SizedBox(width: 1, height: 1),
          ),
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      expect(fm.primaryFocus, same(a));

      a.unfocus();

      expect(fm.primaryFocus, isNot(same(a)));
      expect(fm.primaryFocus, same(scope));
      expect(a.hasFocus, isFalse);

      app.dispose();
    });

    test('after unfocus hands focus to the scope, Tab traversal still reaches '
        'the first focusable child', () async {
      final scope = FocusScopeNode(debugLabel: 'scope');
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');

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
              Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
            ],
          ),
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final fm = app.buildOwner.focusManager;
      a.unfocus();
      expect(fm.primaryFocus, same(scope));

      app.inputManager.dispatchKey(
        KeyEvent(logicalKey: LogicalKeyboardKey.tab, keyCode: 9),
      );
      await Future<void>.delayed(Duration.zero);

      expect(a.hasFocus, isTrue);

      app.dispose();
    });

    test('unfocus notifies hasFocus exactly once (true to false), with no '
        'reselection churn', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');

      final app = runTuiAppForTesting(
        Column(
          children: [
            Focus(
              focusNode: a,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
            Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        headless: true,
      );

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(a.hasFocus, isTrue);

      final observed = <bool>[];
      a.addListener(() {
        observed.add(a.hasFocus);
      });

      a.unfocus();

      expect(observed, [false]);

      app.dispose();
    });
  });
}
