import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('a focus-loss callback can reattach the node during detach', () {
    final node = FocusNode();
    final key = GlobalKey();
    final app = createTuiTestApp(
      Focus(
        key: key,
        focusNode: node,
        child: const SizedBox(width: 1, height: 1),
      ),
    );
    addTearDown(() {
      app.dispose();
      node.dispose();
    });
    final manager = app.binding.buildOwner.focusManager;
    final context = key.currentContext!;
    node.requestFocus();
    var reattached = false;
    node.addListener(() {
      if (!node.hasFocus && !reattached) {
        reattached = true;
        node.attach(context);
      }
    });

    node.detach();

    expect(reattached, isTrue);
    expect(manager.nodeForElement(context.element), same(node));
    expect(node.isAttachedTo(manager), isTrue);
    expect(node.isAttached, isTrue);
    node.requestFocus();
    expect(manager.primaryFocus, same(node));
    expect(node.hasPrimaryFocus, isTrue);
  });

  for (final nested in [false, true]) {
    test('parsed Tab follows a warm keyed reorder (nested: $nested)', () {
      final nodes = [FocusNode(), FocusNode(), FocusNode()];
      final key = GlobalKey<_ReorderState>();
      final app = createTuiTestApp(
        _Reorder(key: key, nodes: nodes, nested: nested),
      );
      addTearDown(() {
        app.dispose();
        for (final node in nodes) {
          node.dispose();
        }
      });
      final manager = app.binding.buildOwner.focusManager;
      expect(manager.traversalOrder(), nodes);
      nodes.first.requestFocus();

      key.currentState!.reorder();
      app.pumpFrame();

      app.mockInput.pressTab();
      expect(manager.primaryFocus, same(nodes[2]));
      app.mockInput.pressShiftTab();
      expect(manager.primaryFocus, same(nodes[0]));
      app.mockInput.pressShiftTab();
      expect(manager.primaryFocus, same(nodes[1]));
      expect(manager.traversalOrder(), [nodes[0], nodes[2], nodes[1]]);
    });
  }

  test('a focus-gain callback can redirect to the previous primary node', () {
    final a = FocusNode();
    final b = FocusNode();
    final scope = FocusScopeNode();
    final app = _app([a, b], scope: scope);
    addTearDown(() {
      app.dispose();
      a.dispose();
      b.dispose();
      scope.dispose();
    });
    a.requestFocus();
    b.addListener(() {
      if (b.hasFocus) a.requestFocus();
    });

    b.requestFocus();

    expect(app.binding.buildOwner.focusManager.primaryFocus, same(a));
    expect(a.hasFocus, isTrue);
    expect(a.hasPrimaryFocus, isTrue);
    expect(b.hasFocus, isFalse);
    expect(scope.focusedChild, same(a));
  });

  test('a request from the unfocus callback stays authoritative', () {
    final a = FocusNode();
    final b = FocusNode();
    final app = _app([a, b]);
    addTearDown(() {
      app.dispose();
      a.dispose();
      b.dispose();
    });
    a.requestFocus();
    a.addListener(() {
      if (!a.hasFocus) b.requestFocus();
    });

    a.unfocus();

    expect(app.binding.buildOwner.focusManager.primaryFocus, same(b));
    expect(a.hasFocus, isFalse);
    expect(b.hasFocus, isTrue);
  });

  test('scope callbacks see coherent flags and can redirect synchronously', () {
    final a = FocusNode();
    final b = FocusNode();
    final scope = FocusScopeNode();
    final app = _app([a, b], scope: scope);
    addTearDown(() {
      app.dispose();
      a.dispose();
      b.dispose();
      scope.dispose();
    });
    final observations = <FocusNode?>[];
    scope.addListener(() {
      final primary = app.binding.buildOwner.focusManager.primaryFocus;
      observations.add(scope.focusedChild);
      expect(primary == null || primary.hasFocus, isTrue);
      expect(scope.focusedChild, same(primary));
      if (identical(primary, a)) b.requestFocus();
    });

    a.requestFocus();

    expect(observations, [a]);
    expect(app.binding.buildOwner.focusManager.primaryFocus, same(b));
    expect(scope.focusedChild, same(b));
    expect(a.hasFocus, isFalse);
    expect(b.hasFocus, isTrue);
  });

  test(
    'a gain callback can dispose its new focus without stale publication',
    () {
      final a = FocusNode();
      final b = FocusNode();
      final scope = FocusScopeNode();
      final app = _app([a, b], scope: scope);
      addTearDown(() {
        app.dispose();
        a.dispose();
        b.dispose();
        scope.dispose();
      });
      a.requestFocus();
      b.addListener(() {
        if (b.hasFocus) b.dispose();
      });

      expect(b.requestFocus, returnsNormally);

      expect(app.binding.buildOwner.focusManager.primaryFocus, isNull);
      expect(a.hasFocus, isFalse);
      expect(b.hasFocus, isFalse);
      expect(b.isAttached, isFalse);
      expect(scope.focusedChild, isNot(same(b)));
    },
  );

  test('a scope callback can dispose its focused child and choose another', () {
    final a = FocusNode();
    final b = FocusNode();
    final scope = FocusScopeNode();
    final app = _app([a, b], scope: scope);
    addTearDown(() {
      app.dispose();
      a.dispose();
      b.dispose();
      scope.dispose();
    });
    scope.addListener(() {
      if (!a.hasPrimaryFocus) return;
      a.dispose();
      b.requestFocus();
    });

    expect(a.requestFocus, returnsNormally);

    expect(app.binding.buildOwner.focusManager.primaryFocus, same(b));
    expect(a.hasFocus, isFalse);
    expect(a.isAttached, isFalse);
    expect(b.hasFocus, isTrue);
    expect(scope.focusedChild, same(b));
  });

  test(
    'an explicit empty-focus decision during disabling cancels recovery',
    () async {
      final a = FocusNode();
      final b = FocusNode();
      final app = _app([a, b]);
      addTearDown(() {
        app.dispose();
        a.dispose();
        b.dispose();
      });
      a.requestFocus();
      a.addListener(() {
        if (a.hasFocus) return;
        b.requestFocus();
        b.unfocus();
      });

      a.canRequestFocus = false;
      await Future<void>.value();

      expect(app.binding.buildOwner.focusManager.primaryFocus, isNull);
      expect(b.hasFocus, isFalse);
    },
  );
}

TuiTestApp _app(List<FocusNode> nodes, {FocusScopeNode? scope}) {
  final child = Column(
    children: [
      for (final node in nodes)
        Focus(focusNode: node, child: const SizedBox(width: 1, height: 1)),
    ],
  );
  return createTuiTestApp(
    scope == null ? child : FocusScope(node: scope, child: child),
  );
}

class _Reorder extends StatefulWidget {
  const _Reorder({required this.nodes, required this.nested, super.key});

  final List<FocusNode> nodes;
  final bool nested;

  @override
  State<_Reorder> createState() => _ReorderState();
}

class _ReorderState extends State<_Reorder> {
  var _order = [0, 1, 2];

  void reorder() => setState(() => _order = [0, 2, 1]);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final index in _order)
        if (widget.nested)
          _NestedFocus(key: ValueKey(index), node: widget.nodes[index])
        else
          Focus(
            key: ValueKey(index),
            focusNode: widget.nodes[index],
            child: const SizedBox(width: 1, height: 1),
          ),
    ],
  );
}

class _NestedFocus extends StatelessWidget {
  const _NestedFocus({required this.node, super.key});

  final FocusNode node;

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: node, child: const SizedBox(width: 1, height: 1));
}
