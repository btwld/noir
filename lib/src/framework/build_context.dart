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
