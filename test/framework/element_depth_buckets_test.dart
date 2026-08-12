import 'package:noir/noir.dart';
import 'package:noir/src/framework/element.dart' show Element;
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  group('maintained element depth buckets', () {
    test('mount assigns root depth 0 and child depth parent+1', () {
      final host = TestElementHost()
        ..mount(const Column(children: [Text('a'), Text('b')]));
      final root = host.root!;
      expect(root.depth, 0);
      final depths = <int>[];
      void walk(Element e) {
        depths.add(e.depth);
        e.visitChildren(walk);
      }

      walk(root);
      expect(depths.first, 0);
      expect(depths.where((d) => d > 0), isNotEmpty);
      for (final d in depths) {
        expect(d, greaterThanOrEqualTo(0));
      }
      host.dispose();
    });

    test('parent rebuilds before child when both dirty', () {
      final order = <String>[];
      final parentKey = GlobalKey();
      final childKey = GlobalKey();
      final host = TestElementHost()
        ..mount(
          _OrderProbe(
            key: parentKey,
            label: 'parent',
            order: order,
            child: _OrderProbe(key: childKey, label: 'child', order: order),
          ),
        );
      // Rebuild both dirty: schedule child then parent.
      final parentElement = _findByLabel(host.root!, 'parent');
      final childElement = _findByLabel(host.root!, 'child');
      childElement.owner.scheduleBuild(childElement);
      parentElement.owner.scheduleBuild(parentElement);
      order.clear();
      host.owner.buildScope();
      expect(order, ['parent', 'child']);
      host.dispose();
    });

    test('dirty chain of 10/100/1000 keeps consistent maintained depths', () {
      // Parent-read budget for schedule+buildScope is proved instrumented in
      // build_owner_depth_bucket_test.dart (GREEN 0 vs predecessor 55/5050/500500).
      for (final n in [10, 100, 1000]) {
        final host = TestElementHost()..mount(_depthChain(n));
        final all = <Element>[];
        void allNodes(Element e) {
          all.add(e);
          e.visitChildren(allNodes);
        }

        allNodes(host.root!);
        for (final e in all.reversed) {
          e.owner.scheduleBuild(e);
        }
        host.owner.buildScope();
        expect(all.length, greaterThanOrEqualTo(n));
        for (final e in all) {
          if (e.parent == null) {
            expect(e.depth, 0);
          } else {
            expect(e.depth, e.parent!.depth + 1);
          }
        }
        host.dispose();
      }
    });

    test('rejected GlobalKey move leaves both subtrees depth-consistent', () {
      final key = GlobalKey();
      final host = TestElementHost()
        ..mount(
          Column(
            children: [
              SizedBox(
                key: const ValueKey('slot-a'),
                child: Text('moved', key: key),
              ),
              const SizedBox(key: ValueKey('slot-b')),
            ],
          ),
        );
      final before = _findText(host.root!, 'moved');
      final destinationSlot = host.root!.children[1];
      final destinationChildCount = destinationSlot.children.length;

      expect(
        () => host.root!.update(
          Column(
            children: [
              const SizedBox(key: ValueKey('slot-a')),
              SizedBox(
                key: const ValueKey('slot-b'),
                child: Text('moved', key: key),
              ),
            ],
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Cross-parent GlobalKey placement is unsupported'),
          ),
        ),
      );

      expect(before.parent, isNull);
      expect(before.depth, 0);
      expect(before.active, isFalse);
      expect(destinationSlot.children, hasLength(destinationChildCount));
      _expectConsistentDepths(destinationSlot);

      host.owner.finalizeTree();
      expect(before.mounted, isFalse);
      expect(key.currentContext, isNull);
      host.dispose();
    });
  });
}

Widget _depthChain(int depth) {
  Widget current = const Text('leaf');
  for (var i = 0; i < depth; i++) {
    current = SizedBox(child: current);
  }
  return current;
}

Element _findByLabel(Element root, String label) {
  Element? found;
  void walk(Element e) {
    final w = e.widget;
    if (w is _OrderProbe && w.label == label) {
      found = e;
      return;
    }
    e.visitChildren(walk);
  }

  walk(root);
  return found!;
}

Element _findText(Element root, String data) {
  Element? found;
  void walk(Element e) {
    final w = e.widget;
    if (w is Text && w.data == data) {
      found = e;
      return;
    }
    e.visitChildren(walk);
  }

  walk(root);
  return found!;
}

void _expectConsistentDepths(Element root) {
  if (root.parent == null) {
    expect(root.depth, 0);
  } else {
    expect(root.depth, root.parent!.depth + 1);
  }
  root.visitChildren(_expectConsistentDepths);
}

class _OrderProbe extends StatefulWidget {
  const _OrderProbe({
    required this.label,
    required this.order,
    this.child,
    super.key,
  });

  final String label;
  final List<String> order;
  final Widget? child;

  @override
  State<_OrderProbe> createState() => _OrderProbeState();
}

class _OrderProbeState extends State<_OrderProbe> {
  @override
  Widget build(BuildContext context) {
    widget.order.add(widget.label);
    return widget.child ?? const SizedBox();
  }
}
