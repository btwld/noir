import 'dart:collection';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/key.dart';
import '../framework/widget.dart';
import '../rendering/box.dart';
import '../rendering/flex.dart';
import '../rendering/object.dart';

/// How a flexible child is allowed to size itself along the main axis.
enum FlexFit {
  /// The child is forced to fill the available space allocated to it.
  tight,

  /// The child can be at most as large as the available space, but may be
  /// smaller.
  loose,
}

/// A widget that gives its [child] a share of the main-axis space in a [Flex].
class Flexible extends StatelessWidget {
  /// Gives [child] a positive flex share with loose fit by default.
  const Flexible({
    required this.child,
    this.flex = 1,
    this.fit = FlexFit.loose,
    super.key,
  }) : assert(flex > 0);

  /// The flex factor determining this child's share of main-axis space
  /// relative to its siblings.
  final int flex;

  /// How the child is allowed to size itself within its allotted space.
  final FlexFit fit;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      _FlexibleNode(flex: flex, fit: fit, child: child);
}

/// A [Flexible] that forces its [child] to fill the available main-axis space.
class Expanded extends Flexible {
  /// Gives [child] a flex share that is forced to fill its allocation.
  const Expanded({required super.child, super.flex, super.key})
    : super(fit: FlexFit.tight);
}

class _FlexibleNode extends Widget {
  const _FlexibleNode({
    required this.flex,
    required this.fit,
    required this.child,
  });
  final int flex;
  final FlexFit fit;
  final Widget child;

  @override
  Element createElement() => FlexibleElement._(this);
}

/// Element that exposes [flex]/[fit] metadata while preserving its single
/// child's identity.
class FlexibleElement extends Element {
  /// Preserves one flexible child and exposes its flex metadata to the framework.
  FlexibleElement._(_FlexibleNode super.widget);

  _FlexibleNode get _widget => widget as _FlexibleNode;
  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  /// The flex factor of the underlying [Flexible] widget.
  int get flex => _widget.flex;

  /// The fit of the underlying [Flexible] widget.
  FlexFit get fit => _widget.fit;

  @override
  void performRebuild() {
    final candidate = _widget.child;
    final currentChild = _children.isEmpty ? null : _children.single;
    final key = candidate.key;
    if (key is GlobalKey) {
      owner.validateGlobalKeyPlacement(
        key,
        candidate,
        this,
        retainedElement:
            currentChild != null &&
                Widget.canUpdate(currentChild.widget, candidate)
            ? currentChild
            : null,
      );
    }
    if (currentChild == null) {
      _children.add(Element.inflateWidget(candidate, this));
      return;
    }
    if (Widget.canUpdate(currentChild.widget, candidate)) {
      currentChild.update(candidate);
      return;
    }

    try {
      owner.deactivateChild(currentChild);
    } finally {
      if (currentChild.parent == null && !currentChild.active) {
        _children.clear();
      }
    }
    final child = Element.inflateWidget(candidate, this);
    _children.add(child);
  }

  @override
  RenderObject? findRenderObject() => _children.isEmpty
      ? null
      : Element.findDescendantRenderObject(_children.single);

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}

/// [MultiChildRenderObjectElement] specialised for [RenderFlex] parents.
///
/// Adopts each child onto the parent [RenderFlex] together with the per-child
/// flex metadata (factor + fit) resolved from [FlexibleElement] /
/// [Flexible] descendants. Keeps flex-specific concerns out of the generic
/// multi-child element.
class FlexRenderObjectElement extends MultiChildRenderObjectElement {
  /// Adopts render children with their resolved flex factor and fit.
  FlexRenderObjectElement(super.widget);

  @override
  void adoptChildRenderObject(RenderBox child, Element childElement, int slot) {
    final renderFlex = renderObject! as RenderFlex;
    final metadata = _resolveFlexMetadata(childElement);
    renderFlex.add(child, flex: metadata.flex, fit: metadata.fit);
  }

  @override
  void dropChildRenderObject(RenderObject child, Element? childElement) {
    final renderFlex = renderObject as RenderFlex?;
    if (renderFlex == null) return;
    if (child is! RenderBox || !identical(child.parent, renderFlex)) return;
    renderFlex.remove(child);
  }

  _ResolvedFlexMetadata _resolveFlexMetadata(Element element) {
    if (element is FlexibleElement) {
      return _ResolvedFlexMetadata(element.flex, element.fit);
    }
    final widget = element.widget;
    if (widget is Flexible) {
      return _ResolvedFlexMetadata(widget.flex, widget.fit);
    }
    return const _ResolvedFlexMetadata(null, null);
  }
}

class _ResolvedFlexMetadata {
  const _ResolvedFlexMetadata(this.flex, this.fit);

  final int? flex;
  final FlexFit? fit;
}
