import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('keyed owners rewire later listeners before old disposal', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = 0;
    late _StrictNotifier notifier;
    _StrictNotifier? firstNotifier;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        notifier = useDisposable<_StrictNotifier>(
          _StrictNotifier.new,
          <Object?>[key],
        );
        useListenable<_StrictNotifier>(notifier);
        firstNotifier ??= notifier;
        return const Container();
      },
    );

    host.mount(buildRoot());
    key = 1;
    host.update(buildRoot());

    expect(notifier, isNot(same(firstNotifier)));
    expect(firstNotifier!.disposed, isTrue);
  });

  test('useValueNotifier owns state without rebuilding until observed', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = 0;
    var initialValue = 1;
    var builds = 0;
    late ValueNotifier<int> notifier;
    ValueNotifier<int>? firstNotifier;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        builds++;
        notifier = useValueNotifier<int>(initialValue, <Object?>[key]);
        firstNotifier ??= notifier;
        return const Container();
      },
    );

    host.mount(buildRoot());
    notifier.value = 2;
    host.pumpBuild();

    expect(builds, 1);
    expect(notifier.value, 2);

    initialValue = 7;
    host.update(buildRoot());
    expect(notifier, same(firstNotifier));
    expect(notifier.value, 2);

    key = 1;
    host.update(buildRoot());
    expect(notifier, isNot(same(firstNotifier)));
    expect(notifier.value, 7);
    expect(() => firstNotifier!.addListener(() {}), throwsA(isA<StateError>()));
  });

  test(
    'useOnListenableChange keeps one subscription and the latest callback',
    () {
      final host = TestElementHost();
      final listenable = _CountingListenable();
      addTearDown(() {
        host.dispose();
        listenable.dispose();
      });
      var version = 1;
      var observedVersion = 0;

      Widget buildRoot() => HookBuilder(
        builder: (context) {
          final currentVersion = version;
          useOnListenableChange(listenable, () {
            observedVersion = currentVersion;
          });
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(listenable.addCount, 1);
      expect(listenable.removeCount, 0);

      version = 2;
      host.update(buildRoot());
      expect(listenable.addCount, 1);
      expect(listenable.removeCount, 0);

      listenable.fire();
      expect(observedVersion, 2);

      host.dispose();
      expect(listenable.addCount, 1);
      expect(listenable.removeCount, 1);
    },
  );

  test('useTickerProvider is stable and does not consume a hook slot', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var readProvider = true;
    late TickerProvider provider;
    late ValueNotifier<int> tail;
    TickerProvider? firstProvider;
    ValueNotifier<int>? firstTail;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        useState<int>(0);
        if (readProvider) {
          provider = useTickerProvider();
          firstProvider ??= provider;
        }
        tail = useState<int>(1);
        firstTail ??= tail;
        return const Container();
      },
    );

    host.mount(buildRoot());
    readProvider = false;
    host.update(buildRoot());
    expect(tail, same(firstTail));

    readProvider = true;
    host.update(buildRoot());
    expect(provider, same(firstProvider));
    expect(tail, same(firstTail));
  });

  test('useEffect keeps cleanup-before-rerun key semantics', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = double.nan;
    var effectCount = 0;
    var cleanupCount = 0;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        useEffect(() {
          effectCount++;
          return () {
            cleanupCount++;
          };
        }, <Object?>[key]);
        return const Container();
      },
    );

    host.mount(buildRoot());
    key = double.nan;
    host.update(buildRoot());
    expect(effectCount, 1);
    expect(cleanupCount, 0);

    key = 0.0;
    host.update(buildRoot());
    expect(effectCount, 2);
    expect(cleanupCount, 1);

    key = -0.0;
    host.update(buildRoot());
    expect(effectCount, 3);
    expect(cleanupCount, 2);

    host.dispose();
    expect(cleanupCount, 3);
  });
}

final class _StrictNotifier extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    if (hasListeners) {
      throw StateError('Listeners must detach before owner disposal.');
    }
    disposed = true;
    super.dispose();
  }
}

final class _CountingListenable extends ChangeNotifier {
  int addCount = 0;
  int removeCount = 0;

  @override
  void addListener(VoidCallback listener) {
    addCount++;
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    removeCount++;
    super.removeListener(listener);
  }

  void fire() => notifyListeners();
}
