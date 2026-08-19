import 'package:noir/noir.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/widgets/focus_node_owner_mixin.dart';
import 'package:noir/src/widgets/text_editing_owner_mixin.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  group('syncController is transactional', () {
    test('an unusable replacement leaves the owned controller attached', () {
      final disposed = TextEditingController(text: 'replacement')..dispose();
      final host = TestElementHost()..mount(const _EditorProbe(value: 'seed'));
      final state = _stateOf(host);
      final owned = state.controller;

      expect(
        () => host.root!.update(_EditorProbe(controller: disposed)),
        throwsStateError,
      );

      expect(identical(state.controller, owned), isTrue);
      expect(_isLive(owned), isTrue);
      expect(owned.text, 'seed');

      final builds = state.builds;
      owned.text = 'edited';
      host.owner.buildScope();
      expect(
        state.builds,
        builds + 1,
        reason: 'the retained controller is still the attached one',
      );

      host.dispose();
      expect(
        _isLive(owned),
        isFalse,
        reason: 'ownership was retained with the controller',
      );
    });

    test('a completed swap releases the previously owned controller', () {
      final supplied = TextEditingController(text: 'supplied');
      final host = TestElementHost()..mount(const _EditorProbe(value: 'seed'));
      final state = _stateOf(host);
      final owned = state.controller;

      host.root!.update(_EditorProbe(controller: supplied));

      expect(identical(state.controller, supplied), isTrue);
      expect(_isLive(owned), isFalse);

      final builds = state.builds;
      supplied.text = 'observed';
      host.owner.buildScope();
      expect(
        state.builds,
        builds + 1,
        reason: 'the adopted controller drives rebuilds',
      );

      host.dispose();
      expect(
        _isLive(supplied),
        isTrue,
        reason: 'a widget-supplied controller stays caller-owned',
      );
      supplied.dispose();
    });
  });
}

_EditorProbeState _stateOf(TestElementHost host) =>
    (host.root! as StatefulElement).state as _EditorProbeState;

void _probeListener() {}

/// Liveness probe: [ChangeNotifier.addListener] throws once `dispose()` ran.
bool _isLive(TextEditingController controller) {
  try {
    controller
      ..addListener(_probeListener)
      ..removeListener(_probeListener);
    return true;
    // ignore: avoid_catching_errors
  } on StateError {
    return false;
  }
}

class _EditorProbe extends StatefulWidget {
  const _EditorProbe({this.controller, this.value});

  final TextEditingController? controller;
  final String? value;

  @override
  State<_EditorProbe> createState() => _EditorProbeState();
}

class _EditorProbeState extends State<_EditorProbe>
    with
        FocusNodeOwnerStateMixin<_EditorProbe>,
        TextEditingOwnerStateMixin<_EditorProbe> {
  int builds = 0;

  @override
  FocusNode? get widgetFocusNode => null;

  @override
  TextEditingController? get widgetController => widget.controller;

  @override
  String? get widgetValue => widget.value;

  @override
  TextInputConnection get connection =>
      TextInputConnection(controller: controller);

  @override
  void initState() {
    super.initState();
    initController();
  }

  @override
  void didUpdateWidget(_EditorProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncController(oldWidget.controller, oldWidget.value);
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return const SizedBox(width: 1, height: 1);
  }
}
