import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';

void main() {
  test(
    'readOnly blocks edits while preserving caret, controller, and submit',
    () async {
      final controller = TextEditingController(text: 'abcd')
        ..selection = const TextSelection.collapsed(offset: 2);
      final focusNode = FocusNode();
      final changes = <String>[];
      var submits = 0;
      final key = GlobalKey<_ReadOnlyHarnessState>();
      final driver = KeyDriver(
        _ReadOnlyHarness(
          key: key,
          controller: controller,
          focusNode: focusNode,
          onChanged: changes.add,
          onSubmit: () => submits += 1,
        ),
      );
      addTearDown(driver.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(controller.dispose);
      await driver.ready();

      await driver.sendCharacter('X');
      await driver.sendPaste('paste');
      await driver.sendLogicalKey(LogicalKeyboardKey.backspace);
      await driver.sendLogicalKey(LogicalKeyboardKey.delete);

      expect(controller.text, 'abcd');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));
      expect(changes, isEmpty);

      await driver.sendLogicalKey(LogicalKeyboardKey.arrowLeft);
      expect(controller.selection, const TextSelection.collapsed(offset: 1));
      await driver.sendLogicalKey(LogicalKeyboardKey.enter);
      expect(submits, 1, reason: 'readOnly does not redefine submission');

      controller.text = 'host';
      await Future<void>.delayed(Duration.zero);
      expect(controller.text, 'host');
      expect(controller.selection, const TextSelection.collapsed(offset: 4));

      key.currentState!.setReadOnly(false);
      driver.app.debugFlushFrame();
      expect(controller.selection, const TextSelection.collapsed(offset: 4));
      await driver.sendCharacter('!');
      expect(controller.text, 'host!');
      expect(changes, ['host!']);

      key.currentState!.setReadOnly(true);
      driver.app.debugFlushFrame();
      await driver.sendLogicalKey(LogicalKeyboardKey.backspace);
      expect(controller.text, 'host!');
      expect(controller.selection, const TextSelection.collapsed(offset: 5));
    },
  );
}

final class _ReadOnlyHarness extends StatefulWidget {
  const _ReadOnlyHarness({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmit,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  State<_ReadOnlyHarness> createState() => _ReadOnlyHarnessState();
}

final class _ReadOnlyHarnessState extends State<_ReadOnlyHarness> {
  var _readOnly = true;

  // Positional bool keeps the test control terse.
  // ignore: avoid_positional_boolean_parameters
  void setReadOnly(bool value) => setState(() => _readOnly = value);

  @override
  Widget build(BuildContext context) => TextInput(
    controller: widget.controller,
    focusNode: widget.focusNode,
    autofocus: true,
    readOnly: _readOnly,
    onChanged: widget.onChanged,
    onSubmit: widget.onSubmit,
  );
}
