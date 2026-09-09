import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

class _CancelFailure implements Exception {
  const _CancelFailure();
}

void main() {
  test('SignalBuilder observes hooks but not plain borrowed signal reads', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final borrowed = signal(1);
    addTearDown(borrowed.dispose);
    late Signal<int> owned;
    var builds = 0;
    var seen = 0;

    host.mount(
      SignalBuilder(
        builder: (context) {
          builds++;
          owned = useSignal(0);
          seen = borrowed.value;
          return Text('${owned.value}:$seen');
        },
      ),
    );
    expect(builds, 1);
    expect(seen, 1);

    borrowed.value = 2;
    host.pumpBuild();
    expect(builds, 1, reason: 'a plain read must not subscribe the host');
    expect(seen, 1);

    owned.value++;
    host.pumpBuild();
    expect(builds, 2, reason: 'an observed hook still schedules its host');
    expect(seen, 2, reason: 'the next build reads the current borrowed value');
  });

  group('a subscription that outlives its cancellation', () {
    test('stops rebuilding after the source is replaced', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final first = signal(1);
      final second = signal(2);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      // Cancelling this source is a no-op, so the old callback stays
      // registered with upstream after the hook replaces it.
      final leaky = _UncancellableSignal<int>(first);
      ReadonlySignal<int> current = leaky;
      var builds = 0;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          builds++;
          useSignalValue(current);
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(builds, 1);

      current = second;
      host.update(buildRoot());
      expect(builds, 2);

      first.value = 100;
      host.pumpBuild();

      expect(
        builds,
        2,
        reason: 'the replaced callback must be inert, cancelled or not',
      );
    });

    test('stops rebuilding after a cancellation that throws', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(1);
      addTearDown(source.dispose);
      final hostile = _ThrowingCancelSignal<int>(source);
      var builds = 0;
      var show = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) => Column(
          children: <Widget>[
            if (show)
              SignalValueBuilder<int>(
                signal: hostile,
                builder: (context, value) {
                  builds++;
                  return Text('$value');
                },
              ),
          ],
        ),
      );

      host.mount(buildRoot());
      expect(builds, 1);

      show = false;
      // Removing the child deactivates the observer, whose cancellation
      // throws without unsubscribing.
      expect(() => host.update(buildRoot()), throwsA(isA<_CancelFailure>()));
      expect(hostile.cancelAttempts, 1);

      source.value = 100;
      host.pumpBuild();

      expect(
        builds,
        1,
        reason: 'a throwing cancellation must still leave the callback inert',
      );
    });
  });
}

/// Delegates to [_delegate] but never really unsubscribes.
class _UncancellableSignal<T> implements ReadonlySignal<T> {
  _UncancellableSignal(this._delegate);

  final ReadonlySignal<T> _delegate;

  @override
  T get value => _delegate.value;

  @override
  void Function() subscribe(void Function(T value) fn) {
    _delegate.subscribe(fn);
    return () {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Delegates to [_delegate] and throws instead of unsubscribing.
class _ThrowingCancelSignal<T> implements ReadonlySignal<T> {
  _ThrowingCancelSignal(this._delegate);

  final ReadonlySignal<T> _delegate;

  /// How many times a caller tried to cancel a subscription.
  int cancelAttempts = 0;

  @override
  T get value => _delegate.value;

  @override
  void Function() subscribe(void Function(T value) fn) {
    _delegate.subscribe(fn);
    return () {
      cancelAttempts++;
      throw const _CancelFailure();
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
