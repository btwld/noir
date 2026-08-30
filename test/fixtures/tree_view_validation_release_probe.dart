import 'package:noir/noir.dart';

import '../helpers/test_element_host.dart';

void main() {
  _expectArgument('negative-height', () => _mount(height: -1));
  _expectArgument('negative-indentation', () => _mount(indentation: -1));
}

void _mount({int height = 8, int indentation = 2}) {
  final controller = TreeViewController<String>(roots: const []);
  try {
    TestElementHost().mount(
      TreeView<String>(
        controller: controller,
        itemBuilder: (context, node, selected) => Text(node.value),
        height: height,
        indentation: indentation,
      ),
    );
  } finally {
    controller.dispose();
  }
}

void _expectArgument(String label, void Function() body) {
  Object? error;
  try {
    body();
  } catch (caught) {
    error = caught;
  }
  if (error is! ArgumentError) {
    throw StateError('$label did not throw ArgumentError: $error');
  }
  print('PASS:$label');
}
