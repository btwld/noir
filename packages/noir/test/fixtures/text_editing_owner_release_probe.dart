import 'dart:async';

import 'package:noir/noir.dart';

import '../helpers/test_element_host.dart';

void main() {
  _connectionRejectsBeforeMutation();
  _focusedOwnerRejectsReentrantInvalidation();
}

void _connectionRejectsBeforeMutation() {
  final controller = TextEditingController(text: 'abc');
  final connection = TextInputConnection(controller: controller);
  Object? error;
  try {
    connection.insertText('x');
  } catch (caught) {
    error = caught;
  }
  if (error is! StateError ||
      controller.text != 'abc' ||
      controller.selection.isValid) {
    throw StateError(
      'connection-invalid did not reject atomically: '
      'error=$error value=${controller.value}',
    );
  }
  controller.dispose();
  print('PASS:connection-invalid');
}

void _focusedOwnerRejectsReentrantInvalidation() {
  final controller = TextEditingController(text: 'abc');
  var invalidated = false;
  controller.addListener(() {
    if (!invalidated && controller.selection.isValid) {
      invalidated = true;
      controller.value = const TextEditingValue(
        text: 'abc',
        selection: TextSelection.collapsed(offset: 99),
      );
    }
  });
  final focusNode = FocusNode();
  final host = TestElementHost()
    ..mount(TextInput(controller: controller, focusNode: focusNode));

  Object? reported;
  runZonedGuarded(focusNode.requestFocus, (error, _) => reported = error);
  if (reported is! StateError || controller.selection.extentOffset != 99) {
    throw StateError(
      'owner-reentrant did not fail before focused rebuild: '
      'reported=$reported selection=${controller.selection}',
    );
  }

  host.dispose();
  controller.dispose();
  focusNode.dispose();
  print('PASS:owner-reentrant');
}
