import 'package:noir/noir.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/widgets/focus_node_owner_mixin.dart';
import 'package:test/test.dart';

import '../helpers/listenable_liveness.dart';
import '../helpers/test_element_host.dart';

void main() {
  group('syncFocusNode is transactional', () {
    test(
      'the replacement hook observes the old node before it is disposed',
      () {
        final supplied = FocusNode();
        final host = TestElementHost()..mount(const _SwapProbe());
        final state = _stateOf(host);
        final owned = state.focusNode;

        host.root!.update(_SwapProbe(focusNode: supplied));

        expect(state.hookCalls, 1);
        expect(state.observedLiveOldNodes, [owned]);
        expect(
          isLive(owned),
          isFalse,
          reason: 'the owned node is released last',
        );
        expect(identical(state.focusNode, supplied), isTrue);

        host.dispose();
        expect(
          isLive(supplied),
          isTrue,
          reason: 'a widget-supplied node stays caller-owned',
        );
        supplied.dispose();
      },
    );

    test('a failing replacement hook keeps the owned old node current', () {
      final supplied = FocusNode();
      final host = TestElementHost()..mount(const _SwapProbe());
      final state = _stateOf(host);
      final owned = state.focusNode;

      expect(
        () =>
            host.root!.update(_SwapProbe(focusNode: supplied, hookFails: true)),
        throwsStateError,
      );

      expect(identical(state.focusNode, owned), isTrue);
      expect(isLive(owned), isTrue);
      expect(isLive(supplied), isTrue);

      host.dispose();
      expect(
        isLive(owned),
        isFalse,
        reason: 'the retained node is still owned, so dispose() releases it',
      );
      supplied.dispose();
    });

    test('a failing replacement hook releases the candidate it minted', () {
      final supplied = FocusNode();
      final host = TestElementHost()..mount(_SwapProbe(focusNode: supplied));
      final state = _stateOf(host);

      expect(
        () => host.root!.update(const _SwapProbe(hookFails: true)),
        throwsStateError,
      );

      expect(state.createdNodes, hasLength(1));
      expect(
        isLive(state.createdNodes.single),
        isFalse,
        reason: 'the rolled-back candidate is disposed, not leaked',
      );
      expect(identical(state.focusNode, supplied), isTrue);
      expect(isLive(supplied), isTrue);

      host.dispose();
      expect(
        isLive(supplied),
        isTrue,
        reason: 'ownership rolled back with the node',
      );
      supplied.dispose();
    });

    test('a failing default-node creation keeps the supplied node current', () {
      final supplied = FocusNode();
      final host = TestElementHost()..mount(_SwapProbe(focusNode: supplied));
      final state = _stateOf(host);

      expect(
        () => host.root!.update(const _SwapProbe(createFails: true)),
        throwsStateError,
      );

      expect(identical(state.focusNode, supplied), isTrue);
      expect(isLive(supplied), isTrue);
      expect(state.hookCalls, 0);

      host.dispose();
      expect(isLive(supplied), isTrue);
      supplied.dispose();
    });
  });
}

_SwapProbeState _stateOf(TestElementHost host) =>
    (host.root! as StatefulElement).state as _SwapProbeState;

class _SwapProbe extends StatefulWidget {
  const _SwapProbe({
    this.focusNode,
    this.createFails = false,
    this.hookFails = false,
  });

  final FocusNode? focusNode;
  final bool createFails;
  final bool hookFails;

  @override
  State<_SwapProbe> createState() => _SwapProbeState();
}

class _SwapProbeState extends State<_SwapProbe>
    with FocusNodeOwnerStateMixin<_SwapProbe> {
  final List<FocusNode> createdNodes = <FocusNode>[];
  final List<FocusNode> observedLiveOldNodes = <FocusNode>[];
  int hookCalls = 0;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  FocusNode createDefaultFocusNode() {
    if (widget.createFails) {
      throw StateError('createDefaultFocusNode failed');
    }
    final node = FocusNode();
    createdNodes.add(node);
    return node;
  }

  @override
  void onFocusNodeReplaced(FocusNode oldNode) {
    hookCalls++;
    if (isLive(oldNode)) {
      observedLiveOldNodes.add(oldNode);
    }
    if (widget.hookFails) {
      throw StateError('onFocusNodeReplaced failed');
    }
  }

  @override
  void didUpdateWidget(_SwapProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
