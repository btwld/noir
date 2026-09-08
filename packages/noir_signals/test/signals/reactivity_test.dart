import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

void main() {
  group('useSignal', () {
    test('rebuilds its host after the value changes', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final rendered = <int>[];
      late Signal<int> count;

      host.mount(
        SignalBuilder(
          builder: (context) {
            count = useSignal(0);
            rendered.add(count.value);
            return const Container();
          },
        ),
      );

      expect(rendered, <int>[0], reason: 'attaching must not rebuild');

      count.value = 1;
      host.pumpBuild();

      expect(rendered, <int>[0, 1]);
    });

    test('coalesces repeated writes before a frame into one build', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var builds = 0;
      late Signal<int> count;

      host.mount(
        SignalBuilder(
          builder: (context) {
            builds++;
            count = useSignal(0);
            return Text('${count.value}');
          },
        ),
      );

      expect(builds, 1);

      count.value = 1;
      count.value = 2;
      count.value = 3;
      host.pumpBuild();

      expect(builds, 2);
    });

    test('groups a batch into one build and keeps upstream semantics', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var builds = 0;
      late Signal<int> left;
      late Signal<int> right;

      host.mount(
        SignalBuilder(
          builder: (context) {
            builds++;
            left = useSignal(0);
            right = useSignal(0);
            return Text('${left.value}/${right.value}');
          },
        ),
      );

      batch(() {
        left.value = 1;
        right.value = 2;
      });
      host.pumpBuild();

      expect(builds, 2);
      expect(left.value, 1);
      expect(right.value, 2);
    });

    test('retains the signal and its initial value until keys change', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var initialValue = 0;
      var key = 0;
      late Signal<int> count;
      Signal<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          count = useSignal(initialValue, keys: <Object?>[key]);
          first ??= count;
          return Text('${count.value}');
        },
      );

      host.mount(buildRoot());
      count.value = 5;
      host.pumpBuild();

      initialValue = 9;
      host.update(buildRoot());

      expect(count, same(first));
      expect(count.value, 5, reason: 'initialValue is used only at creation');

      key = 1;
      host.update(buildRoot());
      host.pumpBuild();

      expect(count, isNot(same(first)));
      expect(count.value, 9);
    });

    test('rejects an auto-disposing owned signal', () {
      final host = TestElementHost();
      addTearDown(host.dispose);

      expect(
        () => host.mount(
          SignalBuilder(
            builder: (context) {
              useSignal(
                0,
                options: const SignalOptions<int>(autoDispose: true),
              );
              return const Container();
            },
          ),
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            allOf(contains('useSignal'), contains('useSignalValue')),
          ),
        ),
      );
    });
  });

  group('useComputed', () {
    test('rebuilds only when the computed result changes', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var builds = 0;
      // The host observes only the computed, so an unchanged result is the
      // only thing that can keep it from rebuilding.
      final count = signal(1);
      addTearDown(count.dispose);
      late Computed<bool> isOdd;

      host.mount(
        SignalBuilder(
          builder: (context) {
            builds++;
            isOdd = useComputed(
              () => count.value.isOdd,
              keys: <Object?>[count],
            );
            return Text('${isOdd.value}');
          },
        ),
      );

      expect(builds, 1);
      expect(isOdd.value, isTrue);

      // 1 -> 3 keeps the computed result, so the host must not rebuild.
      count.value = 3;
      host.pumpBuild();
      expect(builds, 1);

      count.value = 4;
      host.pumpBuild();
      expect(builds, 2);
      expect(isOdd.value, isFalse);
    });

    test('refreshes conditional dependencies on each evaluation', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final rendered = <int>[];
      final preferLeft = signal(true);
      final left = signal(1);
      final right = signal(2);
      addTearDown(preferLeft.dispose);
      addTearDown(left.dispose);
      addTearDown(right.dispose);

      host.mount(
        SignalBuilder(
          builder: (context) {
            final selected = useComputed(
              () => preferLeft.value ? left.value : right.value,
              keys: <Object?>[preferLeft, left, right],
            );
            rendered.add(selected.value);
            return const Container();
          },
        ),
      );

      expect(rendered, <int>[1]);

      // `right` is not a dependency yet.
      right.value = 20;
      host.pumpBuild();
      expect(rendered, <int>[1]);

      preferLeft.value = false;
      host.pumpBuild();
      expect(rendered, <int>[1, 20]);

      // `left` is no longer a dependency.
      left.value = 10;
      host.pumpBuild();
      expect(rendered, <int>[1, 20]);

      right.value = 30;
      host.pumpBuild();
      expect(rendered, <int>[1, 20, 30]);
    });

    test('retains the computation until keys change', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var factor = 2;
      var key = 0;
      final count = signal(3);
      addTearDown(count.dispose);
      late Computed<int> scaled;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          scaled = useComputed(
            () => count.value * factor,
            keys: <Object?>[count, key],
          );
          return Text('${scaled.value}');
        },
      );

      host.mount(buildRoot());
      expect(scaled.value, 6);

      factor = 10;
      host.update(buildRoot());
      expect(scaled.value, 6, reason: 'captured props need a key change');

      key = 1;
      host.update(buildRoot());
      host.pumpBuild();
      expect(scaled.value, 30);
    });

    test('rejects an auto-disposing owned computed', () {
      final host = TestElementHost();
      addTearDown(host.dispose);

      expect(
        () => host.mount(
          SignalBuilder(
            builder: (context) {
              useComputed(
                () => 1,
                options: const ComputedOptions<int>(autoDispose: true),
              );
              return const Container();
            },
          ),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('useSignalValue', () {
    test('observes a borrowed source without disposing it', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(0);
      addTearDown(source.dispose);
      final rendered = <int>[];

      host.mount(
        SignalBuilder(
          builder: (context) {
            rendered.add(useSignalValue(source));
            return const Container();
          },
        ),
      );

      expect(rendered, <int>[0]);

      source.value = 7;
      host.pumpBuild();
      expect(rendered, <int>[0, 7]);

      host.dispose();
      expect(source.disposed, isFalse);
      source.value = 8;
      expect(source.value, 8);
    });

    test('keeps the subscription when the source identity is unchanged', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(0);
      addTearDown(source.dispose);
      var watched = 0;
      var unwatched = 0;
      final tracked = signal(
        0,
        options: SignalOptions<int>(
          watched: () => watched++,
          unwatched: () => unwatched++,
        ),
      );
      addTearDown(tracked.dispose);

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          useSignalValue(source);
          useSignalValue(tracked);
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(watched, 1);
      expect(unwatched, 0);

      host.update(buildRoot());
      host.update(buildRoot());

      expect(watched, 1, reason: 'rebuilds must not resubscribe');
      expect(unwatched, 0);
    });

    test('replaces the source and stops observing the old one', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final first = signal(1);
      final second = signal(2);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var current = first;
      final rendered = <int>[];

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          rendered.add(useSignalValue(current));
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(rendered, <int>[1]);

      current = second;
      host.update(buildRoot());
      expect(rendered, <int>[1, 2]);

      first.value = 100;
      host.pumpBuild();
      expect(rendered, <int>[1, 2], reason: 'the old source is detached');

      second.value = 200;
      host.pumpBuild();
      expect(rendered, <int>[1, 2, 200]);
    });
  });

  group('SignalValueBuilder', () {
    test('rebuilds its subtree without rebuilding its parent', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal(0);
      addTearDown(source.dispose);
      var parentBuilds = 0;
      var childBuilds = 0;
      var siblingBuilds = 0;

      host.mount(
        SignalBuilder(
          builder: (context) {
            parentBuilds++;
            return Column(
              children: <Widget>[
                SignalValueBuilder<int>(
                  signal: source,
                  builder: (context, value) {
                    childBuilds++;
                    return Text('$value');
                  },
                ),
                SignalBuilder(
                  builder: (context) {
                    siblingBuilds++;
                    return const Text('sibling');
                  },
                ),
              ],
            );
          },
        ),
      );

      expect(<int>[parentBuilds, childBuilds, siblingBuilds], <int>[1, 1, 1]);

      source.value = 5;
      host.pumpBuild();

      expect(<int>[parentBuilds, childBuilds, siblingBuilds], <int>[1, 2, 1]);
    });

    test('borrows its source and leaves disposal to the owner', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      final source = signal('a');
      addTearDown(source.dispose);

      host.mount(
        SignalValueBuilder<String>(
          signal: source,
          builder: (context, value) => Text(value),
        ),
      );
      host.dispose();

      expect(source.disposed, isFalse);
    });
  });
}
