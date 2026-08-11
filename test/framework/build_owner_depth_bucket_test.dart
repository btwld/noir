import 'dart:collection';

import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:test/test.dart';

/// Predecessor [BuildOwner._elementDepth] parent-getter cost for a dirty chain
/// of length [n] scheduled and flushed together.
///
/// For each dirty element at depth `d` (0..n-1), the old walk read `parent`
/// once per ancestor plus the terminating null read ⇒ `d + 1` reads.
/// Summing over the chain: `Σ_{d=0}^{n-1}(d+1) = n(n+1)/2`.
int predecessorParentReadsForChain(int n) => n * (n + 1) ~/ 2;

void main() {
  group('maintained depth bucket parent-read budget', () {
    test('predecessor quadratic budget is 55 / 5_050 / 500_500', () {
      expect(predecessorParentReadsForChain(10), 55);
      expect(predecessorParentReadsForChain(100), 5050);
      expect(predecessorParentReadsForChain(1000), 500500);
    });

    test(
      'schedule+buildScope of dirty chain reads parent zero times (10/100/1000)',
      () {
        for (final n in [10, 100, 1000]) {
          final owner = BuildOwner();
          final rebuilds = <int>[];
          final nodes = <_CountingElement>[];

          // Mount chain: root depth 0 … leaf depth n-1.
          _CountingElement? parent;
          for (var d = 0; d < n; d++) {
            final element =
                _CountingWidget(d, rebuilds).createElement() as _CountingElement
                  ..mount(parent, owner);
            parent?.addChildForTest(element);
            nodes.add(element);
            parent = element;
          }

          // Reset after mount (mount may touch parent for registration/render).
          _CountingElement.parentReads = 0;
          rebuilds.clear();

          // Schedule deepest-first without resetting the counter mid-way.
          for (var i = nodes.length - 1; i >= 0; i--) {
            owner.scheduleBuild(nodes[i]);
          }
          owner.buildScope();

          expect(
            rebuilds,
            List.generate(n, (i) => i),
            reason: 'n=$n rebuild order must be shallow-first',
          );
          expect(
            _CountingElement.parentReads,
            0,
            reason:
                'n=$n schedule+buildScope must not read Element.parent '
                '(predecessor budget ${predecessorParentReadsForChain(n)})',
          );

          // Depth registry remains consistent (reads parent after measurement).
          for (final node in nodes) {
            if (node.depth == 0) {
              expect(node.debugParentWithoutCount, isNull);
            } else {
              expect(node.depth, node.debugParentWithoutCount!.depth + 1);
            }
          }

          nodes.first.unmount();
          owner.dispose();
        }
      },
    );
  });
}

class _CountingWidget extends Widget {
  _CountingWidget(this.depthLabel, this.rebuilds);

  final int depthLabel;
  final List<int> rebuilds;

  @override
  Element createElement() => _CountingElement(this);
}

class _CountingElement extends Element {
  _CountingElement(_CountingWidget super.widget);

  static int parentReads = 0;

  @override
  _CountingWidget get widget => super.widget as _CountingWidget;

  /// Readable parent that instruments the audited getter path.
  @override
  Element? get parent {
    parentReads++;
    return super.parent;
  }

  /// Test-only parent access that does not increment the measurement counter.
  ///
  /// `super.parent` calls [Element.parent] without re-entering this override.
  Element? get debugParentWithoutCount => super.parent;

  final List<Element> _children = <Element>[];
  late final List<Element> _childrenView = UnmodifiableListView<Element>(
    _children,
  );

  @override
  List<Element> get children => _childrenView;

  void addChildForTest(Element child) => _children.add(child);

  @override
  void performRebuild() {
    widget.rebuilds.add(widget.depthLabel);
  }

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}
