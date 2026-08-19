import 'package:noir/noir.dart';

import 'framework.dart';
import 'listenable.dart';

/// Creates and owns a Noir [AnimationController].
///
/// [duration] and [reverseDuration] update the retained controller. Changing
/// [vsync] or an explicit key recreates it because Noir's controller has no
/// resync operation. [initialValue], [lowerBound], [upperBound], and
/// [debugLabel] are used only when a controller is created.
AnimationController useAnimationController({
  Duration duration = const Duration(milliseconds: 300),
  Duration? reverseDuration,
  double lowerBound = 0.0,
  double upperBound = 1.0,
  double? initialValue,
  String? debugLabel,
  TickerProvider? vsync,
  List<Object?> keys = const <Object?>[],
}) => use(
  _AnimationControllerHook(
    duration: duration,
    reverseDuration: reverseDuration,
    lowerBound: lowerBound,
    upperBound: upperBound,
    initialValue: initialValue,
    debugLabel: debugLabel,
    vsync: vsync,
    keys: <Object?>[vsync, ...keys],
  ),
);

/// Subscribes to [animation] and returns its current value.
T useAnimation<T>(Animation<T> animation) => useValueListenable<T>(animation);

/// Subscribes to [animation]'s status and returns its current status.
AnimationStatus useAnimationStatus<T>(Animation<T> animation) =>
    use(_AnimationStatusHook<T>(animation));

final class _AnimationControllerHook extends Hook<AnimationController> {
  const _AnimationControllerHook({
    required this.duration,
    required this.reverseDuration,
    required this.lowerBound,
    required this.upperBound,
    required this.initialValue,
    required this.debugLabel,
    required this.vsync,
    required super.keys,
  });

  final Duration duration;
  final Duration? reverseDuration;
  final double lowerBound;
  final double upperBound;
  final double? initialValue;
  final String? debugLabel;
  final TickerProvider? vsync;

  @override
  _AnimationControllerHookState createState() =>
      _AnimationControllerHookState();
}

final class _AnimationControllerHookState
    extends HookState<AnimationController, _AnimationControllerHook> {
  late final AnimationController _controller;

  @override
  void initHook() {
    _controller = AnimationController(
      vsync: hook.vsync ?? tickerProvider,
      duration: hook.duration,
      reverseDuration: hook.reverseDuration,
      lowerBound: hook.lowerBound,
      upperBound: hook.upperBound,
      value: hook.initialValue ?? hook.lowerBound,
      debugLabel: hook.debugLabel,
    );
  }

  @override
  void didUpdateHook(_AnimationControllerHook _) {
    if (_controller.duration != hook.duration) {
      _controller.duration = hook.duration;
    }
    if (_controller.reverseDuration != hook.reverseDuration) {
      _controller.reverseDuration = hook.reverseDuration;
    }
  }

  @override
  AnimationController build(BuildContext context) => _controller;

  @override
  void dispose() {
    try {
      _controller.dispose();
    } finally {
      super.dispose();
    }
  }
}

final class _AnimationStatusHook<T> extends Hook<AnimationStatus> {
  const _AnimationStatusHook(this.animation);

  final Animation<T> animation;

  @override
  _AnimationStatusHookState<T> createState() => _AnimationStatusHookState<T>();
}

final class _AnimationStatusHookState<T>
    extends HookState<AnimationStatus, _AnimationStatusHook<T>> {
  @override
  void initHook() => hook.animation.addStatusListener(_handleStatusChange);

  @override
  void didUpdateHook(_AnimationStatusHook<T> oldHook) {
    if (identical(oldHook.animation, hook.animation)) {
      return;
    }
    oldHook.animation.removeStatusListener(_handleStatusChange);
    hook.animation.addStatusListener(_handleStatusChange);
  }

  @override
  AnimationStatus build(BuildContext context) => hook.animation.status;

  @override
  void dispose() {
    try {
      hook.animation.removeStatusListener(_handleStatusChange);
    } finally {
      super.dispose();
    }
  }

  void _handleStatusChange(AnimationStatus _) => markMayNeedRebuild();
}
