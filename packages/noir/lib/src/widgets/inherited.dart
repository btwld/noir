part of 'package:noir/src/framework/widget.dart';

/// Base class for widgets that efficiently propagate information down the tree.
abstract class InheritedWidget extends ProxyWidget {
  /// Initializes inherited configuration for dependents below [child].
  const InheritedWidget({required super.child, super.key});

  @override
  @internal
  InheritedElement createElement() => InheritedElement(this);

  /// Whether the framework should notify widgets that inherit from this widget.
  bool updateShouldNotify(covariant InheritedWidget oldWidget);
}
