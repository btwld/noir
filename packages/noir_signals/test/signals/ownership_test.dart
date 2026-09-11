import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

class _CleanupFailure implements Exception {
  const _CleanupFailure();
}

void main() {
  group('owned versus borrowed disposal', () {
    test('an owned signal is disposed and a borrowed one is not', () {
      final host = TestElementHost();
      final borrowed = signal(0);
      addTearDown(borrowed.dispose);
      late Signal<int> owned;
      late Computed<int> derived;

      host.mount(
        SignalBuilder(
          builder: (context) {
            owned = useSignal(1);
            derived = useComputed(() => owned.value + borrowed.value);
            useSignalValue(borrowed);
            return Text('${derived.value}');
          },
        ),
      );

      expect(owned.disposed, isFalse);
      expect(derived.disposed, isFalse);

      host.dispose();

      expect(owned.disposed, isTrue);
      expect(derived.disposed, isTrue);
      expect(borrowed.disposed, isFalse);
    });

    test('a failed replacement leaves no half-owned signal behind', () {
      final host = TestElementHost();
      final log = <String>[];
      var key = 0;
      late Signal<int> created;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          useEffect(() {
            log.add('effect');
            return () => log.add('cleanup');
          }, const <Object?>[]);
          created = useSignal(
            0,
            keys: <Object?>[key],
            options: key == 0
                ? null
                : const SignalOptions<int>(autoDispose: true),
          );
          return const Container();
        },
      );

      host.mount(buildRoot());
      final first = created;
      expect(log, <String>['effect']);

      key = 1;
      expect(() => host.update(buildRoot()), throwsA(isA<ArgumentError>()));

      // The rejected slot owns nothing, and the retained one is untouched.
      expect(first.disposed, isFalse);

      host.dispose();
      expect(log, <String>['effect', 'cleanup']);
      expect(first.disposed, isTrue);
    });
  });

  group('deactivation', () {
    test('a write after teardown requests no rebuild', () {
      final host = TestElementHost();
      final borrowed = signal(0);
      addTearDown(borrowed.dispose);
      var builds = 0;

      host.mount(
        SignalBuilder(
          builder: (context) {
            builds++;
            useSignalValue(borrowed);
            return const Container();
          },
        ),
      );

      expect(builds, 1);
      host.dispose();

      borrowed.value = 1;
      expect(builds, 1);
    });

    test('removing an observing child stops its subscription', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final borrowed = signal(0);
      addTearDown(borrowed.dispose);
      var childBuilds = 0;
      var showChild = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) => Column(
          children: <Widget>[
            if (showChild)
              SignalValueBuilder<int>(
                signal: borrowed,
                builder: (context, value) {
                  childBuilds++;
                  return Text('$value');
                },
              ),
          ],
        ),
      );

      host.mount(buildRoot());
      expect(childBuilds, 1);

      showChild = false;
      host.update(buildRoot());
      host.pumpBuild();

      borrowed.value = 5;
      host.pumpBuild();
      expect(childBuilds, 1);
    });
  });

  group('useSignalEffect', () {
    test('runs on install and again when a dependency changes', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(0);
      addTearDown(source.dispose);
      final runs = <int>[];

      host.mount(
        SignalBuilder(
          builder: (context) {
            useSignalEffect(() {
              runs.add(source.value);
              return null;
            });
            return const Container();
          },
        ),
      );

      expect(runs, <int>[0]);

      source.value = 1;
      expect(runs, <int>[0, 1], reason: 'reruns keep upstream timing');
    });

    test('runs its cleanup before a rerun and once at teardown', () {
      final host = TestElementHost();
      final source = signal(0);
      addTearDown(source.dispose);
      final log = <String>[];

      host.mount(
        SignalBuilder(
          builder: (context) {
            useSignalEffect(() {
              final value = source.value;
              log.add('run:$value');
              return () => log.add('cleanup:$value');
            });
            return const Container();
          },
        ),
      );

      expect(log, <String>['run:0']);

      source.value = 1;
      expect(log, <String>['run:0', 'cleanup:0', 'run:1']);

      host.dispose();
      expect(log, <String>['run:0', 'cleanup:0', 'run:1', 'cleanup:1']);
    });

    test('ignores dependency changes after teardown', () {
      final host = TestElementHost();
      final source = signal(0);
      addTearDown(source.dispose);
      final runs = <int>[];

      host.mount(
        SignalBuilder(
          builder: (context) {
            useSignalEffect(() {
              runs.add(source.value);
              return null;
            });
            return const Container();
          },
        ),
      );
      host.dispose();

      source.value = 1;
      source.value = 2;
      expect(runs, <int>[0]);
    });

    test('uses the latest callback and re-installs when keys change', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(0);
      addTearDown(source.dispose);
      var label = 'first';
      var key = 0;
      final log = <String>[];

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final current = label;
          useSignalEffect(() {
            log.add('$current:${source.value}');
            return null;
          }, keys: <Object?>[key]);
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(log, <String>['first:0']);

      label = 'second';
      host.update(buildRoot());
      expect(log, <String>[
        'first:0',
      ], reason: 'a rebuild does not re-run the effect');

      source.value = 1;
      expect(log, <String>[
        'first:0',
        'second:1',
      ], reason: 'the latest callback runs');

      key = 1;
      host.update(buildRoot());
      expect(log, <String>['first:0', 'second:1', 'second:1']);
    });

    test('a throwing cleanup still releases the rest of the host', () {
      final host = TestElementHost();
      final log = <String>[];

      host.mount(
        SignalBuilder(
          builder: (context) {
            useSignalEffect(
              () =>
                  () => throw const _CleanupFailure(),
            );
            useEffect(
              () =>
                  () => log.add('later-cleanup'),
              const <Object?>[],
            );
            return const Container();
          },
        ),
      );

      expect(host.dispose, throwsA(isA<_CleanupFailure>()));
      expect(log, <String>['later-cleanup']);
    });

    test('rejects a hook rebuild requested while installing', () {
      final host = TestElementHost();
      addTearDown(host.dispose);

      expect(
        () => host.mount(
          SignalBuilder(
            builder: (context) {
              final count = useSignal(0);
              useSignalEffect(() {
                count.value++;
                return null;
              });
              return const Container();
            },
          ),
        ),
        throwsA(
          // The write notifies the `useSignal` subscription from inside the
          // effect, so the rejection surfaces through Signals' batch, which
          // wraps it.
          isA<SignalEffectException>().having(
            (exception) => exception.error,
            'error',
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('cannot request a rebuild'),
            ),
          ),
        ),
      );
    });

    test('propagates an install failure unchanged', () {
      final host = TestElementHost();
      addTearDown(host.dispose);

      expect(
        () => host.mount(
          SignalBuilder(
            builder: (context) {
              useSignalEffect(() => throw const _InstallFailure());
              return const Container();
            },
          ),
        ),
        // Upstream rethrows the install failure; only a later rerun is
        // wrapped in a SignalEffectException.
        throwsA(isA<_InstallFailure>()),
      );
    });

    test('guards the cleanup it runs when the host leaves the tree', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var show = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) =>
            Column(children: <Widget>[if (show) const _GuardedCleanupWidget()]),
      );

      host.mount(buildRoot());

      show = false;
      // The cleanup writes a signal this host still observes. The guard
      // rejects the rebuild that write asks for, and Signals surfaces the
      // rejection when it ends the batch.
      expect(
        () => host.update(buildRoot()),
        throwsA(
          isA<SignalEffectException>().having(
            (exception) => exception.error,
            'error',
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('cannot request a rebuild'),
            ),
          ),
        ),
      );
    });
  });

  group('deactivation detaches observation', () {
    test('an owned signal stops being watched before the pass finalizes', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var unwatched = 0;
      var show = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) => Column(
          children: <Widget>[
            if (show) _OwnedWatchProbe(onUnwatched: () => unwatched++),
          ],
        ),
      );

      host.mount(buildRoot());
      expect(unwatched, 0);

      show = false;
      host.update(buildRoot());

      // `deactivate` must cancel now, before finalizeTree disposes anything.
      expect(unwatched, 1);
    });

    test('a borrowed source stops being watched before the pass finalizes', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var watched = 0;
      var unwatched = 0;
      final source = signal(
        0,
        options: SignalOptions<int>(
          watched: () => watched++,
          unwatched: () => unwatched++,
        ),
      );
      addTearDown(source.dispose);
      var show = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) => Column(
          children: <Widget>[
            if (show)
              SignalValueBuilder<int>(
                signal: source,
                builder: (context, value) => Text('$value'),
              ),
          ],
        ),
      );

      host.mount(buildRoot());
      expect(<int>[watched, unwatched], <int>[1, 0]);

      show = false;
      host.update(buildRoot());

      expect(unwatched, 1);
    });

    test('cancelling twice is safe and leaves the source untouched', () {
      final host = TestElementHost();
      var unwatched = 0;
      final source = signal(
        0,
        options: SignalOptions<int>(unwatched: () => unwatched++),
      );
      addTearDown(source.dispose);
      var show = true;

      Widget buildRoot() => SignalBuilder(
        builder: (context) => Column(
          children: <Widget>[
            if (show)
              SignalValueBuilder<int>(
                signal: source,
                builder: (context, value) => Text('$value'),
              ),
          ],
        ),
      );

      host.mount(buildRoot());
      show = false;
      host.update(buildRoot());
      expect(unwatched, 1);

      // deactivate cancelled; finalizeTree then disposes the hook, which
      // retires the same observation, and teardown repeats it once more.
      host.pumpBuild();
      host.dispose();

      expect(unwatched, 1, reason: 'the source is unsubscribed exactly once');
      expect(source.disposed, isFalse);
      source.value = 1;
      expect(source.value, 1);
    });
  });
}

class _InstallFailure implements Exception {
  const _InstallFailure();
}

/// Writes its own observed signal from the cleanup Noir runs at teardown.
class _GuardedCleanupWidget extends SignalWidget {
  const _GuardedCleanupWidget();

  @override
  Widget build(BuildContext context) {
    final count = useSignal(0);
    useSignalEffect(
      () =>
          () => count.value++,
    );
    return Text('${count.value}');
  }
}

/// Reports when its hook-owned signal loses its last observer.
class _OwnedWatchProbe extends SignalWidget {
  const _OwnedWatchProbe({required this.onUnwatched});

  final VoidCallback onUnwatched;

  @override
  Widget build(BuildContext context) {
    final count = useSignal(
      0,
      options: SignalOptions<int>(unwatched: onUnwatched),
    );
    return Text('${count.value}');
  }
}
