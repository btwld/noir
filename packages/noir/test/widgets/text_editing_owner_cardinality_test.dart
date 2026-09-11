import 'package:noir/noir.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/widgets/focus_node_owner_mixin.dart';
import 'package:noir/src/widgets/text_editing_owner_mixin.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('nested repair and parent update have one hook/build owner', () {
    final controller = TextEditingController(text: 'abc');
    final focusNode = FocusNode();
    var raw = 0;
    controller.addListener(() => raw++);
    final host = TestElementHost()
      ..mount(_OwnerProbe(controller: controller, focusNode: focusNode));
    final state = (host.root! as StatefulElement).state as _OwnerProbeState;

    expect((state.builds, state.hooks), (1, 0));

    void reset() {
      raw = 0;
      state
        ..builds = 0
        ..hooks = 0;
    }

    reset();
    focusNode.requestFocus();
    host.owner.buildScope();
    expect(controller.selection, const TextSelection.collapsed(offset: 3));
    expect(
      (raw, state.hooks, state.builds),
      (1, 1, 1),
      reason: 'invalid focus gain repairs, hooks, and rebuilds exactly once',
    );

    reset();
    controller.text = 'longer';
    host.owner.buildScope();
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
    expect(
      (raw, state.hooks, state.builds),
      (2, 1, 1),
      reason:
          'the initiating text notification plus nested selection repair '
          'have one semantic hook/rebuild owner',
    );

    reset();
    host.root!.update(
      _OwnerProbe(
        controller: controller,
        focusNode: focusNode,
        parentText: 'parent update',
      ),
    );
    expect(
      (raw, state.hooks, state.builds),
      (2, 1, 1),
      reason: 'same-controller parent text update directly rebuilds once',
    );
    host.owner.buildScope();
    expect(
      (raw, state.hooks, state.builds),
      (2, 1, 1),
      reason: 'the direct parent rebuild consumes the dirty reservation',
    );

    host.dispose();
    controller.dispose();
    focusNode.dispose();
  });
}

class _OwnerProbe extends StatefulWidget {
  const _OwnerProbe({
    required this.controller,
    required this.focusNode,
    this.parentText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? parentText;

  @override
  State<_OwnerProbe> createState() => _OwnerProbeState();
}

class _OwnerProbeState extends State<_OwnerProbe>
    with
        FocusNodeOwnerStateMixin<_OwnerProbe>,
        TextEditingOwnerStateMixin<_OwnerProbe> {
  int builds = 0;
  int hooks = 0;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  TextEditingController? get widgetController => widget.controller;

  @override
  String? get widgetValue => null;

  @override
  void initState() {
    super.initState();
    attachController(widget.controller, ownsController: false);
  }

  @override
  void didUpdateWidget(_OwnerProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    assert(identical(widget.controller, oldWidget.controller));
    if (widget.parentText != oldWidget.parentText &&
        widget.parentText != null &&
        widget.parentText != controller.text) {
      controller.text = widget.parentText!;
    }
    reconcileControllerUpdate(controllerChanged: false);
  }

  @override
  TextInputConnection get connection =>
      TextInputConnection(controller: controller);

  @override
  void onControllerChanged() {
    hooks++;
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    requireUsableSelectionForBuild();
    return Focus(
      focusNode: focusNode,
      onFocusChange: handleFocusChange,
      child: const SizedBox(width: 1, height: 1),
    );
  }
}
