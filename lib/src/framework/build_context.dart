import 'package:meta/meta.dart';

import '../rendering/object.dart';
import 'element.dart';
import 'owner.dart';
import 'widget.dart';

/// A widget's location in the element tree, exposing inherited and ancestor
/// lookups.
abstract class BuildContext {
  /// Framework [Element] represented by this context; internal wiring only.
  @internal
  Element get element;

  /// [BuildOwner] responsible for the backing [element].
  @internal
  BuildOwner get owner => element.owner;

  /// Whether this context's element is still in the tree.
  ///
  /// Check this after any `await` before using the context again: the widget
  /// may have been removed while the future was in flight, and every lookup
  /// on this class then reads a torn-down element.
  ///
  /// This mirrors the framework's `mounted`, not its `active`: an element
  /// removed by reconciliation stays mounted — and reports `true` here —
  /// until the build pass finalizes and permanently unmounts it. That window
  /// is exactly where a retained-`State` reinsertion would be observed, so
  /// mounted is the liveness question a caller across an async gap is asking.
  ///
  /// It is also not `State.mounted`. The element leaves the tree before
  /// `State.dispose()` runs, so this reads `false` for the whole of that call
  /// while `State.mounted` deliberately stays `true`.
  bool get mounted => element.mounted;

  /// Register a dependency on the nearest [InheritedWidget] of type [T].
  T? dependOnInheritedWidgetOfExactType<T extends InheritedWidget>({
    Object? aspect,
  }) {
    final inherited = element.dependOnInheritedElementOfExactType<T>(
      aspect: aspect,
    );
    return inherited?.widget as T?;
  }

  /// Look up the nearest [InheritedElement] of type [T] without establishing a
  /// dependency.
  @internal
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      element.getElementForInheritedWidgetOfExactType<T>();

  /// Find the nearest ancestor widget of type [T].
  T? findAncestorWidgetOfExactType<T extends Widget>() =>
      element.findAncestorWidgetOfExactType<T>();

  /// Find the nearest ancestor [State] of type [T].
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() =>
      element.findAncestorStateOfType<T>();

  /// Returns the render object associated with this context, if any.
  @internal
  RenderObject? findRenderObject() => element.findRenderObject();

  /// Find the nearest ancestor [RenderObject] of type [T].
  @internal
  T? findAncestorRenderObjectOfType<T extends RenderObject>() =>
      element.findAncestorRenderObjectOfType<T>();

  /// Visit each ancestor element starting from the parent of this context.
  @internal
  void visitAncestorElements(bool Function(Element element) visitor) {
    element.visitAncestorElements(visitor);
  }

  /// Visit direct child elements of this context.
  @internal
  void visitChildElements(ElementVisitor visitor) {
    element.visitChildren(visitor);
  }
}
