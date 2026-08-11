// Regression tests: a deferred autofocus microtask
// must not target a disposed/replaced/detached FocusNode.
//
// These mount/unmount Focus widgets directly via BuildOwner + Element,
// mirroring test/framework/state_lifecycle_test.dart, so the unmount can be
// forced to happen synchronously before the autofocus microtask
// (scheduled during didChangeDependencies at mount time) has a chance to
// run.
// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('Focus autofocus microtask lifecycle', () {
    test('owned node: unmounting before the autofocus microtask runs does not '
        'throw and does not request focus', () async {
      final owner = BuildOwner();
      final widget = Focus(autofocus: true, child: Container());
      final element = widget.createElement();

      element.mount(null, owner);
      element.unmount();

      // Flush the queued autofocus microtask.
      await Future<void>.delayed(Duration.zero);

      expect(owner.focusManager.primaryFocus, isNull);
    });

    test('supplied node: unmounting before the autofocus microtask runs does '
        'not throw and does not request focus', () async {
      final owner = BuildOwner();
      final node = FocusNode();
      final widget = Focus(
        focusNode: node,
        autofocus: true,
        child: Container(),
      );
      final element = widget.createElement();

      element.mount(null, owner);
      element.unmount();

      await Future<void>.delayed(Duration.zero);

      expect(node.hasFocus, isFalse);
      expect(owner.focusManager.primaryFocus, isNull);

      node.dispose();
    });

    test('positive control: a Focus widget that stays mounted still gains '
        'focus after the autofocus microtask runs', () async {
      final owner = BuildOwner();
      final node = FocusNode();
      final widget = Focus(
        focusNode: node,
        autofocus: true,
        child: Container(),
      );
      final element = widget.createElement();

      element.mount(null, owner);

      await Future<void>.delayed(Duration.zero);

      expect(node.hasFocus, isTrue);
      expect(owner.focusManager.primaryFocus, same(node));

      element.unmount();
      node.dispose();
    });
  });
}
