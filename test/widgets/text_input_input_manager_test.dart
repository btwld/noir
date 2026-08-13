import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/widget_tester.dart';

void main() {
  test(
    'TextInput routes key events through shared InputManager when focused',
    () {
      final tester = WidgetTester();
      final changes = <String>[];
      final focusNode = FocusNode();

      tester.pumpWidget(
        TextInput(focusNode: focusNode, onChanged: changes.add),
      );

      focusNode.requestFocus();
      tester.inputManager.dispatchKey(
        KeyEvent(
          logicalKey: LogicalKeyboardKey.keyA,
          keyCode: 97,
          character: 'a',
        ),
      );

      expect(changes, ['a']);

      focusNode.dispose();
      tester.dispose();
    },
  );

  test('TextInput stops receiving events after unmount', () {
    final tester = WidgetTester();
    final changes = <String>[];
    final focusNode = FocusNode();

    tester.pumpWidget(TextInput(focusNode: focusNode, onChanged: changes.add));
    final manager = tester.inputManager;
    final rootElement = tester.element!;

    focusNode.requestFocus();
    manager.dispatchKey(
      KeyEvent(
        logicalKey: LogicalKeyboardKey.keyA,
        keyCode: 97,
        character: 'a',
      ),
    );
    expect(changes, ['a']);

    rootElement.unmount();
    focusNode.dispose();

    manager.dispatchKey(
      KeyEvent(
        logicalKey: LogicalKeyboardKey.keyB,
        keyCode: 98,
        character: 'b',
      ),
    );
    expect(changes, ['a']);

    tester.dispose();
  });
}
