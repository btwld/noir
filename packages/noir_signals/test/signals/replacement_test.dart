import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

class _BuildFailure implements Exception {
  const _BuildFailure();
}

void main() {
  group('replacing a parent-owned signal', () {
    test('a child observer reads the old source until it moves', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      final rendered = <int>[];
      Signal<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key * 10, keys: <Object?>[key]);
          first ??= count;
          return SignalValueBuilder<int>(
            signal: count,
            builder: (context, value) {
              rendered.add(value);
              return Text('$value');
            },
          );
        },
      );

      host.mount(buildRoot());
      expect(rendered, <int>[0]);
      expect(first!.disposed, isFalse);

      key = 1;
      host.update(buildRoot());

      // The child already moved to the replacement, and the retired signal
      // survived that build.
      expect(rendered, <int>[0, 10]);
      expect(first!.disposed, isFalse);

      host.pumpBuild();
      expect(first!.disposed, isTrue);
    });

    test('a replaced computed can still evaluate before deferred dispose', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      final source = signal(1);
      addTearDown(source.dispose);
      Computed<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final derived = useComputed(
            () => source.value * 10,
            keys: <Object?>[key],
          );
          first ??= derived;
          return SignalValueBuilder<int>(
            signal: derived,
            builder: (context, value) => Text('$value'),
          );
        },
      );

      host.mount(buildRoot());
      expect(first!.value, 10);

      key = 1;
      host.update(buildRoot());
      expect(first!.disposed, isFalse);

      // The retired slot is unmounted, but deferDispose has not run. A
      // dependency write must recompute through the stored function, not
      // HookState.hook.
      source.value = 2;
      expect(first!.value, 20);

      host.pumpBuild();
      expect(first!.disposed, isTrue);
    });

    test('a child effect cleanup can still read the retired source', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      final log = <String>[];

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key * 10, keys: <Object?>[key]);
          return _CleanupReadsSource(source: count, log: log);
        },
      );

      host.mount(buildRoot());
      expect(log, <String>['attach:0 live']);

      key = 1;
      host.update(buildRoot());
      host.pumpBuild();

      expect(log, <String>[
        'attach:0 live',
        'attach:10 live',
        // The cleanup read a source that was still alive when it ran.
        'detach:0 live',
      ]);
    });

    test('survives repeated keyed replacements', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      final rendered = <int>[];
      final created = <Signal<int>>[];

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key, keys: <Object?>[key]);
          if (created.isEmpty || !identical(created.last, count)) {
            created.add(count);
          }
          return SignalValueBuilder<int>(
            signal: count,
            builder: (context, value) {
              rendered.add(value);
              return Text('$value');
            },
          );
        },
      );

      host.mount(buildRoot());
      for (key = 1; key <= 4; key++) {
        host.update(buildRoot());
        host.pumpBuild();
      }

      expect(rendered, <int>[0, 1, 2, 3, 4]);
      expect(created, hasLength(5));
      expect(
        created.take(4).map((signal) => signal.disposed),
        everyElement(isTrue),
      );
      expect(created.last.disposed, isFalse);
    });

    test('removing the child releases the retired source anyway', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      var showChild = true;
      Signal<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key, keys: <Object?>[key]);
          first ??= count;
          return Column(
            children: <Widget>[
              if (showChild)
                SignalValueBuilder<int>(
                  signal: count,
                  builder: (context, value) => Text('$value'),
                ),
            ],
          );
        },
      );

      host.mount(buildRoot());
      key = 1;
      showChild = false;
      host.update(buildRoot());
      host.pumpBuild();

      expect(first!.disposed, isTrue);
    });

    test('a failed parent build keeps the retired source alive', () {
      final host = TestElementHost();
      addTearDown(host.dispose);
      var key = 0;
      var failBuild = false;
      Signal<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key, keys: <Object?>[key]);
          first ??= count;
          if (failBuild) {
            throw const _BuildFailure();
          }
          return SignalValueBuilder<int>(
            signal: count,
            builder: (context, value) => Text('$value'),
          );
        },
      );

      host.mount(buildRoot());

      key = 1;
      failBuild = true;
      expect(() => host.update(buildRoot()), throwsA(isA<_BuildFailure>()));
      host.pumpBuild();

      expect(
        first!.disposed,
        isFalse,
        reason: 'the old children still reference it',
      );

      // Recovering releases it on the next successful reconciliation.
      failBuild = false;
      key = 2;
      host.update(buildRoot());
      host.pumpBuild();

      expect(first!.disposed, isTrue);
    });

    test('shutting down without another frame still releases it', () {
      final host = TestElementHost();
      var key = 0;
      Signal<int>? first;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          final count = useSignal(key, keys: <Object?>[key]);
          first ??= count;
          return SignalValueBuilder<int>(
            signal: count,
            builder: (context, value) => Text('$value'),
          );
        },
      );

      host.mount(buildRoot());
      key = 1;
      host.update(buildRoot());
      expect(first!.disposed, isFalse);

      // No pumpBuild: teardown is the only remaining chance to release it.
      host.dispose();
      expect(first!.disposed, isTrue);
    });
  });
}

/// Observes [source] and reads it again from its own cleanup.
///
/// The log records whether the source was still alive at each point, so a
/// retired source released too early is visible as `disposed`.
class _CleanupReadsSource extends SignalWidget {
  const _CleanupReadsSource({required this.source, required this.log});

  final Signal<int> source;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    useEffect(() {
      log.add('attach:${_describe(source)}');
      return () => log.add('detach:${_describe(source)}');
    }, <Object?>[source]);
    return Text('${source.value}');
  }

  static String _describe(Signal<int> source) =>
      '${source.value} ${source.disposed ? 'disposed' : 'live'}';
}
