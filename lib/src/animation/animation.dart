import '../foundation/change_notifier.dart';
import '../foundation/listenable.dart';

/// Signature of callbacks notified when an animation's status changes.
typedef AnimationStatusListener = void Function(AnimationStatus status);

/// Direction or terminal state reported by [Animation.status].
enum AnimationStatus {
  /// Animation is stopped at its beginning or lower bound.
  dismissed,

  /// Value is oriented toward completion; this may remain after a mid-range stop.
  forward,

  /// Value is oriented toward dismissal; this may remain after a mid-range stop.
  reverse,

  /// Animation is stopped at its end or upper bound.
  completed,
}

/// A value that changes over time, notifying value and status listeners.
abstract class Animation<T> extends ChangeNotifier
    implements ValueListenable<T> {
  /// Initializes a listenable animation whose subclass supplies value and status.
  Animation();

  /// Current animation value.
  @override
  T get value;

  /// Current direction or terminal state of this animation.
  AnimationStatus get status;

  /// Registers [listener] for later status transitions.
  void addStatusListener(AnimationStatusListener listener);

  /// Removes a matching status-listener registration.
  void removeStatusListener(AnimationStatusListener listener);
}
