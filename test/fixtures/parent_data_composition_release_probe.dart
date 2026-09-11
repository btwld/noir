import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

void main() {
  _reject(
    'zero-flex',
    Row(children: [_Component(Expanded(flex: 0, child: const Text('x')))]),
    argument: true,
  );
  _reject(
    'negative-flex',
    Row(children: [_Component(Expanded(flex: -1, child: const Text('x')))]),
    argument: true,
  );
  _reject(
    'misplaced-flex',
    const Row(
      children: [
        Padding(
          padding: EdgeInsets.zero,
          child: Expanded(child: Text('x')),
        ),
      ],
    ),
  );
  _reject(
    'duplicate-flex',
    const Row(
      children: [Expanded(child: _Component(Expanded(child: Text('x'))))],
    ),
  );
  _reject(
    'misplaced-position',
    const Stack(
      children: [
        Padding(
          padding: EdgeInsets.zero,
          child: Positioned(left: 1, child: Text('x')),
        ),
      ],
    ),
  );
  _reject(
    'duplicate-position',
    const Stack(
      children: [
        Positioned(
          left: 1,
          child: _Component(Positioned(top: 1, child: Text('x'))),
        ),
      ],
    ),
  );
  _reject(
    'negative-position-width',
    Stack(
      children: [_Component(Positioned(width: -1, child: const Text('x')))],
    ),
    argument: true,
  );
  _reject(
    'conflicting-position-size',
    Stack(
      children: [
        _Component(
          Positioned(left: 1, right: 1, width: 1, child: const Text('x')),
        ),
      ],
    ),
    argument: true,
  );
}

void _reject(String label, Widget widget, {bool argument = false}) {
  final owner = BuildOwner();
  final element = widget.createElement();
  Object? failure;
  try {
    element.mount(null, owner);
  } on Object catch (error) {
    failure = error;
  } finally {
    element.unmount();
    owner.dispose();
  }
  if (argument ? failure is! ArgumentError : failure is! StateError) {
    throw StateError('$label did not reject invalid metadata: $failure');
  }
  print('PASS:$label');
}

class _Component extends StatelessWidget {
  const _Component(this.child);
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
