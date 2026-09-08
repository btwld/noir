import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

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

  test('useEffect keeps keyed rerun and cleanup counts', () {
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

  test('deferDispose holds a replaced hook resource until children move', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final log = <String>[];
    var key = 0;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final resource = use(
          _DeferredResourceHook(<Object?>[key], log, 'resource-$key'),
        );
        return _ResourceReader(resource: resource, log: log);
      },
    );

    host.mount(buildRoot());
    expect(log, <String>['read:resource-0']);

    key = 1;
    host.update(buildRoot());

    // The replacement build already read the new resource; the retired one is
    // still alive because the pass has not finalized.
    expect(log, <String>['read:resource-0', 'read:resource-1']);

    host.pumpBuild();
    expect(log, <String>[
      'read:resource-0',
      'read:resource-1',
      'release:resource-0',
    ]);
  });

  test('deferDispose runs synchronously while the host tears down', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final log = <String>[];

    host.mount(
      HookBuilder(
        builder: (context) {
          final resource = use(
            _DeferredResourceHook(const <Object?>[], log, 'solo'),
          );
          return _ResourceReader(resource: resource, log: log);
        },
      ),
    );
    expect(log, <String>['read:solo']);
    host.dispose();

    expect(log, <String>['read:solo', 'release:solo']);
  });

  test('keyed effects detach later listeners before old cleanup', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = 0;
    _StrictNotifier? firstNotifier;
    late _StrictNotifier notifier;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final notifierRef = useRef<_StrictNotifier?>(null);
        useEffect(() {
          final created = _StrictNotifier();
          notifierRef.value = created;
          firstNotifier ??= created;
          return created.dispose;
        }, <Object?>[key]);
        notifier = notifierRef.value!;
        useListenable<_StrictNotifier>(notifier);
        return const Container();
      },
    );

    host.mount(buildRoot());
    key = 1;

    expect(() => host.update(buildRoot()), returnsNormally);
    expect(notifier, isNot(same(firstNotifier)));
    expect(firstNotifier!.disposed, isTrue);
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

/// Hook that hands its retired resource to [HookState.deferDispose].
class _DeferredResourceHook extends Hook<_TrackedResource> {
  const _DeferredResourceHook(List<Object?> keys, this.log, this.name)
    : super(keys: keys);

  final List<String> log;
  final String name;

  @override
  HookState<_TrackedResource, _DeferredResourceHook> createState() =>
      _DeferredResourceHookState();
}

class _DeferredResourceHookState
    extends HookState<_TrackedResource, _DeferredResourceHook> {
  late final _TrackedResource _resource;

  @override
  void initHook() {
    // Named by the caller, so the expectations do not depend on how many
    // other tests in this file ran first.
    _resource = _TrackedResource(hook.name, hook.log);
  }

  @override
  _TrackedResource build(BuildContext context) => _resource;

  @override
  void dispose() {
    deferDispose(_resource.release);
    super.dispose();
  }
}

/// Reads the borrowed resource on every build, so an early release shows up.
class _ResourceReader extends StatelessWidget {
  const _ResourceReader({required this.resource, required this.log});

  final _TrackedResource resource;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('read:${resource.read()}');
    return const Container();
  }
}

class _TrackedResource {
  _TrackedResource(this.name, this._log);

  final String name;
  final List<String> _log;
  bool _released = false;

  String read() {
    if (_released) {
      throw StateError('Resource $name was read after release.');
    }
    return name;
  }

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _log.add('release:$name');
  }
}
