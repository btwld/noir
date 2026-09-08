import 'package:noir/noir.dart';
import 'package:signals_core/signals_core.dart';

import 'hooks/framework.dart';
import 'hooks/signals.dart';

/// Builds a subtree from the current value of an observed signal.
typedef SignalValueWidgetBuilder<T> =
    Widget Function(BuildContext context, T value);

/// Rebuilds only its own subtree when one borrowed signal changes.
///
/// Use this to keep a value change from rebuilding a whole screen: the widget
/// above stays put and only the subtree this builder returns runs again.
///
/// ```dart
/// SignalValueBuilder<int>(
///   signal: model.visibleCount,
///   builder: (context, value) => Text('$value files'),
/// )
/// ```
///
/// The builder borrows [signal] and never disposes it; its owner does. It is a
/// [SignalWidget], so it follows the same observation and lifecycle rules as
/// [useSignalValue]: the subscription survives rebuilds that pass the same
/// source, a different source replaces it, and leaving the tree cancels it. A
/// source created with `autoDispose: true` keeps its upstream behavior when
/// this builder is its last observer.
final class SignalValueBuilder<T> extends SignalWidget {
  /// Observes [signal] and rebuilds [builder] after its value changes.
  const SignalValueBuilder({
    required this.signal,
    required this.builder,
    super.key,
  });

  /// The borrowed source this builder observes.
  final ReadonlySignal<T> signal;

  /// Describes the subtree from the source's current value.
  final SignalValueWidgetBuilder<T> builder;

  @override
  Widget build(BuildContext context) =>
      builder(context, useSignalValue<T>(signal));
}
