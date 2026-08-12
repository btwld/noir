// ignore_for_file: use_setters_to_change_properties
import 'package:meta/meta.dart';

import 'build_context.dart';
import 'element.dart';
import 'widget.dart';

/// Identity token that reconciliation compares to preserve widget state
/// across rebuilds.
sealed class Key {
  const Key();
}

/// A [Key] compared only among siblings under the same parent.
sealed class LocalKey extends Key {
  const LocalKey();
}

/// A [LocalKey] that matches another [ValueKey] of the same type holding an
/// equal [value].
@immutable
class ValueKey<T> extends LocalKey {
  /// Uses [value] equality and this key's runtime type to match widgets.
  const ValueKey(this.value);

  /// Value compared with `==` to preserve widget identity across rebuilds.
  final T value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ValueKey<T> &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => 'ValueKey($value)';
}

/// A [LocalKey] equal only to its own instance, never to another key.
@immutable
class UniqueKey extends LocalKey {
  /// Allocates a key equal only to this instance.
  UniqueKey();

  @override
  bool operator ==(Object other) => identical(this, other);

  @override
  int get hashCode => identityHashCode(this);

  @override
  String toString() => 'UniqueKey(${hashCode.toRadixString(16)})';
}

/// A [LocalKey] that matches only when [value] is the identical object.
@immutable
class ObjectKey<T> extends LocalKey {
  /// Uses [value] identity and this key's runtime type to match widgets.
  const ObjectKey(this.value);

  /// Object whose identity preserves widget identity across rebuilds.
  final T value;

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is ObjectKey<T> &&
      identical(other.value, value);

  @override
  int get hashCode => Object.hash(runtimeType, identityHashCode(value));

  @override
  String toString() => 'ObjectKey($value)';
}

/// An owner-wide unique lookup handle for an [Element].
///
/// A widget carrying a [GlobalKey] names at most one live [Element]/[State]
/// instance at a time, including across different [BuildOwner]s. Ordinary
/// keyed reconciliation under the same parent preserves its Element, State,
/// and RenderObject identity, including sibling reorders.
///
/// Moving the keyed widget to a different parent is unsupported. Both
/// traversal orders throw a descriptive [StateError] before the incoming
/// child edge is replaced or a second Element is mounted. Use a fresh key and
/// accept new State when equivalent UI must be placed under another parent.
///
/// [GlobalKey] itself is a read-only handle for application code
/// ([currentContext]/[currentState]/[currentWidget]). Binding it to an
/// element is framework wiring owned by [BuildOwner] and [Element], via the
/// `@internal` [register]/[unregister] methods — application code must never
/// call them.
class GlobalKey<T extends State<StatefulWidget>> extends Key {
  /// Allocates an owner-wide lookup handle with at most one live binding.
  GlobalKey();

  Element? _currentElement;

  /// The [BuildContext] of the element currently bound to this key, or null
  /// if none is mounted.
  BuildContext? get currentContext => _currentElement?.buildContext;

  /// The widget currently bound to this key, or null if none is mounted.
  Widget? get currentWidget => _currentElement?.widget;

  /// The [State] of the element currently bound to this key, or null if
  /// none is mounted or the bound element's state is not a [T].
  T? get currentState {
    final element = _currentElement;
    if (element is StatefulElement) {
      final state = element.state;
      if (state is T) {
        return state;
      }
    }
    return null;
  }

  /// Binds this key to [element]. Called only by [BuildOwner]; not public
  /// app API.
  @internal
  void register(Element element) {
    final existing = _currentElement;
    if (existing != null && !identical(existing, element)) {
      throw StateError(
        'GlobalKey $this is already bound to '
        '${existing.debugDescribeWidget()}. Cross-parent GlobalKey placement '
        'is unsupported, duplicate placement is not allowed, and one key '
        'cannot bind elements owned by different BuildOwners.',
      );
    }
    _currentElement = element;
  }

  /// Clears this key's binding if it currently points at [element]. Called
  /// only by [BuildOwner]; not public app API.
  @internal
  void unregister(Element element) {
    if (identical(_currentElement, element)) {
      _currentElement = null;
    }
  }

  @override
  String toString() => 'GlobalKey(${hashCode.toRadixString(16)})';
}
