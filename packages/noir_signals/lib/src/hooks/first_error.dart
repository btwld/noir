import 'package:meta/meta.dart';

/// Runs a sequence of cleanup actions to completion while retaining only the
/// first failure, then rethrows it with its original stack trace.
///
/// Hook teardown paths share this first-error-wins shape: every action is
/// attempted, later failures are swallowed, and the earliest error escapes
/// after the whole sequence has run. Internal to this package — not exported
/// from its library.
@internal
final class FirstErrorRecorder {
  Object? _error;
  StackTrace? _stackTrace;

  /// Runs [action], recording its error only when no earlier error exists.
  void attempt(void Function() action) {
    try {
      action();
    } on Object catch (error, stackTrace) {
      _error ??= error;
      _stackTrace ??= stackTrace;
    }
  }

  /// Rethrows the first recorded error with its stack trace, if any.
  void rethrowFirst() {
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stackTrace!);
    }
  }
}
