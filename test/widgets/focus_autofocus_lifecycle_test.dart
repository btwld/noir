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

import '../helpers/test_element_host.dart';

void main() {
  group('Focus autofocus updates', () {
    for (final supplied in [false, true]) {
      test(
        'enabling autofocus on a retained '
        '${supplied ? 'supplied' : 'owned'} node requests focus once',
        () async {
          final host = TestElementHost();
          final suppliedNode = supplied ? FocusNode() : null;
          addTearDown(() {
            host.dispose();
            suppliedNode?.dispose();
          });
          host.mount(Focus(focusNode: suppliedNode, child: Container()));
          final element = host.root;
          final node = host.owner.focusManager.nodeForElement(element!)!;
          await Future<void>.delayed(Duration.zero);
          expect(node.hasFocus, isFalse);

          host.update(
            Focus(focusNode: suppliedNode, autofocus: true, child: Container()),
          );
          expect(host.root, same(element));
          await Future<void>.delayed(Duration.zero);
          expect(host.owner.focusManager.primaryFocus, same(node));

          node.unfocus();
          host.update(
            Focus(focusNode: suppliedNode, autofocus: true, child: Container()),
          );
          await Future<void>.delayed(Duration.zero);
          expect(node.hasFocus, isFalse);
        },
      );
    }

    test(
      'enabling autofocus while replacing the node requests the new node',
      () async {
        final host = TestElementHost();
        final oldNode = FocusNode();
        final newNode = FocusNode();
        addTearDown(() {
          host.dispose();
          oldNode.dispose();
          newNode.dispose();
        });
        host.mount(Focus(focusNode: oldNode, child: Container()));
        oldNode.requestFocus();
        await Future<void>.delayed(Duration.zero);
        expect(oldNode.hasPrimaryFocus, isTrue);

        // Avoid focus recovery masking the replacement's autofocus behavior.
        oldNode.unfocus();
        host.update(
          Focus(focusNode: newNode, autofocus: true, child: Container()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(oldNode.isAttached, isFalse);
        expect(host.owner.focusManager.primaryFocus, same(newNode));
      },
    );

    test('disabling an updated autofocus request cancels dispatch', () async {
      final host = TestElementHost();
      final node = FocusNode();
      addTearDown(() {
        host.dispose();
        node.dispose();
      });
      host.mount(Focus(focusNode: node, child: Container()));
      host.update(Focus(focusNode: node, autofocus: true, child: Container()));
      host.update(Focus(focusNode: node, child: Container()));
      await Future<void>.delayed(Duration.zero);
      expect(host.owner.focusManager.primaryFocus, isNull);
    });

    test('replacing a node cancels its pending updated request', () async {
      final host = TestElementHost();
      final oldNode = FocusNode();
      final newNode = FocusNode();
      addTearDown(() {
        host.dispose();
        oldNode.dispose();
        newNode.dispose();
      });
      host.mount(Focus(focusNode: oldNode, child: Container()));
      host.update(
        Focus(focusNode: oldNode, autofocus: true, child: Container()),
      );
      host.update(Focus(focusNode: newNode, child: Container()));
      await Future<void>.delayed(Duration.zero);
      expect(oldNode.isAttached, isFalse);
      expect(newNode.hasFocus, isFalse);
      expect(host.owner.focusManager.primaryFocus, isNull);
    });

    test('detaching a node cancels its pending updated request', () async {
      final host = TestElementHost();
      final node = FocusNode();
      addTearDown(() {
        host.dispose();
        node.dispose();
      });
      host.mount(Focus(focusNode: node, child: Container()));
      host.update(Focus(focusNode: node, autofocus: true, child: Container()));
      node.detach();
      await Future<void>.delayed(Duration.zero);
      expect(host.owner.focusManager.primaryFocus, isNull);
    });

    test('unmounting cancels a pending updated autofocus request', () async {
      final host = TestElementHost();
      final node = FocusNode();
      addTearDown(() {
        host.dispose();
        node.dispose();
      });
      host.mount(Focus(focusNode: node, child: Container()));
      final manager = host.owner.focusManager;
      host.update(Focus(focusNode: node, autofocus: true, child: Container()));
      host.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(node.isAttached, isFalse);
      expect(manager.primaryFocus, isNull);
    });
  });

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
