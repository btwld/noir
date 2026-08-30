import 'package:noir/noir.dart';

import '../helpers/test_element_host.dart';

void main() {
  _expectArgument('nonpositive-height', () {
    final controller = TextEditingController();
    try {
      TestElementHost().mount(
        _autocomplete(controller: controller, maxOptionsHeight: 0),
      );
    } finally {
      controller.dispose();
    }
  });

  _expectState('ready-empty', () {
    final controller = TextEditingController();
    try {
      TestElementHost().mount(
        _autocomplete(controller: controller, options: const []),
      );
    } finally {
      controller.dispose();
    }
  });

  _expectState('duplicate-focus-roles', () {
    final controller = TextEditingController();
    final node = FocusNode();
    try {
      TestElementHost().mount(
        _autocomplete(
          controller: controller,
          focusNode: node,
          optionsFocusNode: node,
        ),
      );
    } finally {
      node.dispose();
      controller.dispose();
    }
  });
}

Autocomplete<String> _autocomplete({
  required TextEditingController controller,
  List<String> options = const ['alpha'],
  int maxOptionsHeight = 5,
  FocusNode? focusNode,
  FocusNode? optionsFocusNode,
}) => Autocomplete<String>(
  controller: controller,
  options: options,
  status: AutocompleteStatus.ready,
  optionBuilder: (context, option, highlighted) => Text(option),
  onChanged: (value) {},
  onSelected: (option) {},
  onDismiss: () {},
  maxOptionsHeight: maxOptionsHeight,
  focusNode: focusNode,
  optionsFocusNode: optionsFocusNode,
);

void _expectArgument(String label, void Function() body) {
  _expect<ArgumentError>(label, body);
}

void _expectState(String label, void Function() body) {
  _expect<StateError>(label, body);
}

void _expect<T extends Object>(String label, void Function() body) {
  Object? error;
  try {
    body();
  } catch (caught) {
    error = caught;
  }
  if (error is! T) {
    throw StateError('$label did not throw $T: $error');
  }
  print('PASS:$label');
}
