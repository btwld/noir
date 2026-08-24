// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:test/test.dart';

void main() {
  test('one FocusNode cannot be attached to two live sibling widgets', () {
    final node = FocusNode();
    final owner = BuildOwner();
    addTearDown(node.dispose);
    addTearDown(owner.dispose);
    final first = Focus(
      focusNode: node,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    final second = Focus(
      focusNode: node,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    first.mount(null, owner);

    expect(() => second.mount(null, owner), throwsA(isA<StateError>()));
    second.unmount();
    expect(node.isAttached, isTrue);
    node.requestFocus();
    expect(owner.focusManager.primaryFocus, same(node));

    first.unmount();
    expect(node.isAttached, isFalse);
  });

  test('one FocusNode cannot migrate between live focus managers', () {
    final node = FocusNode();
    final firstOwner = BuildOwner();
    final secondOwner = BuildOwner();
    addTearDown(node.dispose);
    addTearDown(firstOwner.dispose);
    addTearDown(secondOwner.dispose);
    final first = Focus(
      focusNode: node,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    final second = Focus(
      focusNode: node,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    first.mount(null, firstOwner);

    expect(() => second.mount(null, secondOwner), throwsA(isA<StateError>()));
    second.unmount();
    node.requestFocus();
    expect(firstOwner.focusManager.primaryFocus, same(node));
    expect(secondOwner.focusManager.primaryFocus, isNull);

    first.unmount();
    expect(node.isAttached, isFalse);
  });

  test('a rejected live-node replacement preserves both attachments', () {
    final currentNode = FocusNode();
    final occupiedNode = FocusNode();
    final currentOwner = BuildOwner();
    final occupiedOwner = BuildOwner();
    final currentElement = Focus(
      focusNode: currentNode,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    final occupiedElement = Focus(
      focusNode: occupiedNode,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    addTearDown(currentElement.unmount);
    addTearDown(occupiedElement.unmount);
    addTearDown(currentOwner.dispose);
    addTearDown(occupiedOwner.dispose);
    addTearDown(currentNode.dispose);
    addTearDown(occupiedNode.dispose);
    currentElement.mount(null, currentOwner);
    occupiedElement.mount(null, occupiedOwner);

    expect(
      () => currentElement.update(
        Focus(
          focusNode: occupiedNode,
          child: const SizedBox(width: 1, height: 1),
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(currentNode.isAttached, isTrue);
    expect(occupiedNode.isAttached, isTrue);
    currentNode.requestFocus();
    occupiedNode.requestFocus();
    expect(currentOwner.focusManager.primaryFocus, same(currentNode));
    expect(occupiedOwner.focusManager.primaryFocus, same(occupiedNode));
  });

  test('a rejected disposed-node replacement preserves the attachment', () {
    final currentNode = FocusNode();
    final disposedNode = FocusNode()..dispose();
    final owner = BuildOwner();
    final element = Focus(
      focusNode: currentNode,
      child: const SizedBox(width: 1, height: 1),
    ).createElement();
    addTearDown(element.unmount);
    addTearDown(owner.dispose);
    addTearDown(currentNode.dispose);
    element.mount(null, owner);

    expect(
      () => element.update(
        Focus(
          focusNode: disposedNode,
          child: const SizedBox(width: 1, height: 1),
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(currentNode.isAttached, isTrue);
    currentNode.requestFocus();
    expect(owner.focusManager.primaryFocus, same(currentNode));
  });

  test('FocusNode handles key events once focused', () async {
    final focusNode = FocusNode();
    final handled = <String>[];
    final app = runTuiAppForTesting(
      Focus(
        focusNode: focusNode,
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            handled.add('enter');
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const SizedBox(width: 5, height: 1),
      ),
      headless: true,
    );

    focusNode.requestFocus();
    await Future<void>.delayed(Duration.zero);
    expect(focusNode.hasFocus, isTrue);

    app.inputManager.dispatchKey(
      KeyEvent(logicalKey: LogicalKeyboardKey.enter, keyCode: 13),
    );
    await Future<void>.delayed(Duration.zero);

    expect(handled, equals(['enter']));
    app.dispose();
  });

  test('Focus receives key events via focus node', () async {
    final focusNode = FocusNode();
    final captured = <String>[];
    final app = runTuiAppForTesting(
      Focus(
        focusNode: focusNode,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event.character == 'a' && event.isPress) {
            captured.add('a');
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: const Container(),
      ),
      headless: true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(focusNode.hasFocus, isTrue);

    app.inputManager.dispatchKey(
      KeyEvent(
        logicalKey: LogicalKeyboardKey.keyA,
        keyCode: 97,
        character: 'a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(captured, equals(['a']));
    app.dispose();
  });

  test('FocusNode listeners observe focus state via the node', () async {
    final focusNode = FocusNode();
    final otherFocusNode = FocusNode();
    final observed = <bool>[];

    focusNode.addListener(() {
      observed.add(focusNode.hasFocus);
    });

    final app = runTuiAppForTesting(
      Column(
        children: [
          Focus(
            focusNode: focusNode,
            child: const SizedBox(width: 1, height: 1),
          ),
          Focus(
            focusNode: otherFocusNode,
            child: const SizedBox(width: 1, height: 1),
          ),
        ],
      ),
      headless: true,
    );

    focusNode.requestFocus();
    await Future<void>.delayed(Duration.zero);
    otherFocusNode.requestFocus();
    await Future<void>.delayed(Duration.zero);

    expect(observed, [true, false]);
    app.dispose();
    focusNode.dispose();
    otherFocusNode.dispose();
  });

  test('TextInput value updates via focus-driven key events', () async {
    final focusNode = FocusNode();
    final changes = <String>[];
    final app = runTuiAppForTesting(
      TextInput(focusNode: focusNode, autofocus: true, onChanged: changes.add),
      headless: true,
    );

    await Future<void>.delayed(Duration.zero);
    expect(focusNode.hasFocus, isTrue);

    void sendCharacter(String character) {
      app.inputManager.dispatchKey(
        KeyEvent(
          logicalKey: LogicalKeyboardKey.forCharacter(character),
          keyCode: character.codeUnitAt(0),
          character: character,
        ),
      );
    }

    sendCharacter('h');
    await Future<void>.delayed(Duration.zero);
    sendCharacter('i');
    await Future<void>.delayed(Duration.zero);
    app.inputManager.dispatchKey(
      KeyEvent(logicalKey: LogicalKeyboardKey.backspace, keyCode: 8),
    );
    await Future<void>.delayed(Duration.zero);

    expect(changes, equals(['h', 'hi', 'h']));
    app.dispose();
  });
}
