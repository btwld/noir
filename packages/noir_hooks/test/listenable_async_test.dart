import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir_hooks/noir_hooks.dart';
import 'package:test/test.dart';

import '../../../test/helpers/test_element_host.dart';

void main() {
  test('useValueListenable rebuilds and rewires on identity change', () {
    final host = TestElementHost();
    final first = ValueNotifier<int>(1);
    final second = ValueNotifier<int>(10);
    addTearDown(() {
      host.dispose();
      first.dispose();
      second.dispose();
    });
    var current = first;
    var builds = 0;
    late int value;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        builds++;
        value = useValueListenable<int>(current);
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(value, 1);

    first.value = 2;
    host.pumpBuild();
    expect(builds, 2);
    expect(value, 2);

    current = second;
    host.update(buildRoot());
    expect(value, 10);

    first.value = 3;
    host.pumpBuild();
    expect(builds, 3);

    second.value = 11;
    host.pumpBuild();
    expect(builds, 4);
    expect(value, 11);
  });

  test('useListenableSelector suppresses unrelated notifications', () {
    final host = TestElementHost();
    final model = _SelectorModel();
    addTearDown(() {
      host.dispose();
      model.dispose();
    });
    var builds = 0;
    late int selected;

    host.mount(
      HookBuilder(
        builder: (context) {
          builds++;
          selected = useListenableSelector<_SelectorModel, int>(
            model,
            (value) => value.primary,
          );
          return const Container();
        },
      ),
    );

    model.notifySecondaryChanged();
    host.pumpBuild();
    expect(builds, 1);
    expect(selected, 0);

    model.setPrimary(2);
    host.pumpBuild();
    expect(builds, 2);
    expect(selected, 2);
  });

  test('useChangeNotifier owns and disposes its notifier', () {
    final host = TestElementHost();
    late _DisposableNotifier notifier;

    host.mount(
      HookBuilder(
        builder: (context) {
          notifier = useChangeNotifier<_DisposableNotifier>(
            _DisposableNotifier.new,
          );
          return const Container();
        },
      ),
    );

    expect(notifier.disposed, isFalse);
    host.dispose();
    expect(notifier.disposed, isTrue);
  });

  test('useFuture publishes waiting then completed data', () async {
    final host = TestElementHost();
    final completer = Completer<int>();
    addTearDown(host.dispose);
    late AsyncSnapshot<int> snapshot;

    host.mount(
      HookBuilder(
        builder: (context) {
          snapshot = useFuture<int>(completer.future);
          return const Container();
        },
      ),
    );

    expect(snapshot.connectionState, ConnectionState.waiting);
    expect(snapshot.hasData, isFalse);

    completer.complete(42);
    await Future<void>.delayed(Duration.zero);
    host.pumpBuild();

    expect(snapshot.connectionState, ConnectionState.done);
    expect(snapshot.requireData, 42);
  });

  test('useFuture ignores completion from a replaced future', () async {
    final host = TestElementHost();
    final first = Completer<int>();
    final second = Completer<int>();
    addTearDown(host.dispose);
    var current = first.future;
    late AsyncSnapshot<int> snapshot;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        snapshot = useFuture<int>(current);
        return const Container();
      },
    );

    host.mount(buildRoot());
    current = second.future;
    host.update(buildRoot());

    first.complete(1);
    await Future<void>.delayed(Duration.zero);
    host.pumpBuild();
    expect(snapshot.connectionState, ConnectionState.waiting);
    expect(snapshot.data, isNull);

    second.complete(2);
    await Future<void>.delayed(Duration.zero);
    host.pumpBuild();
    expect(snapshot.requireData, 2);
  });

  test('useStream reports data and completion', () async {
    final host = TestElementHost();
    final controller = StreamController<int>(sync: true);
    addTearDown(host.dispose);
    late AsyncSnapshot<int> snapshot;

    host.mount(
      HookBuilder(
        builder: (context) {
          snapshot = useStream<int>(controller.stream);
          return const Container();
        },
      ),
    );

    expect(snapshot.connectionState, ConnectionState.waiting);

    controller.add(7);
    host.pumpBuild();
    expect(snapshot.connectionState, ConnectionState.active);
    expect(snapshot.requireData, 7);

    await controller.close();
    host.pumpBuild();
    expect(snapshot.connectionState, ConnectionState.done);
  });

  test('useStream cancels its subscription on disposal', () async {
    final host = TestElementHost();
    var cancelCount = 0;
    final controller = StreamController<int>(
      sync: true,
      onCancel: () {
        cancelCount++;
      },
    );

    host.mount(
      HookBuilder(
        builder: (context) {
          useStream<int>(controller.stream);
          return const Container();
        },
      ),
    );

    host.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(cancelCount, 1);
    await controller.close();
  });

  test('AsyncSnapshot requireData rethrows the stored error', () {
    final error = StateError('failed');
    final snapshot = AsyncSnapshot<int>.withError(
      ConnectionState.done,
      error,
      StackTrace.current,
    );

    expect(() => snapshot.requireData, throwsA(same(error)));
  });
}

final class _SelectorModel extends ChangeNotifier {
  int primary = 0;
  void setPrimary(int value) {
    primary = value;
    notifyListeners();
  }

  void notifySecondaryChanged() => notifyListeners();
}

final class _DisposableNotifier extends ChangeNotifier {
  bool disposed = false;

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}
