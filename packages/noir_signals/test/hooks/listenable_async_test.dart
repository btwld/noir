import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

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

    Widget buildRoot() => SignalBuilder(
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
      SignalBuilder(
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
      SignalBuilder(
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
      SignalBuilder(
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

  test(
    'useFuture handles initial data, null sources, and reset policy',
    () async {
      final host = TestElementHost();
      final first = Completer<int>();
      final second = Completer<int>();
      final third = Completer<int>();
      addTearDown(host.dispose);
      Future<int>? current;
      var preserveState = true;
      late AsyncSnapshot<int> snapshot;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          snapshot = useFuture<int>(
            current,
            initialData: 7,
            preserveState: preserveState,
          );
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 7);

      current = first.future;
      host.update(buildRoot());
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 7);

      first.complete(11);
      await Future<void>.delayed(Duration.zero);
      host.pumpBuild();
      expect(snapshot.connectionState, ConnectionState.done);
      expect(snapshot.requireData, 11);

      current = second.future;
      host.update(buildRoot());
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 11);

      preserveState = false;
      current = third.future;
      host.update(buildRoot());
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 7);

      current = null;
      host.update(buildRoot());
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 7);

      second.complete(22);
      third.complete(33);
      await Future<void>.delayed(Duration.zero);
      host.pumpBuild();
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 7);
    },
  );

  test('useFuture ignores completion from a replaced future', () async {
    final host = TestElementHost();
    final first = Completer<int>();
    final second = Completer<int>();
    addTearDown(host.dispose);
    var current = first.future;
    late AsyncSnapshot<int> snapshot;

    Widget buildRoot() => SignalBuilder(
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

  test('useFuture reports errors with their stack traces', () async {
    final host = TestElementHost();
    final completer = Completer<int>();
    addTearDown(host.dispose);
    final error = StateError('future failed');
    final stackTrace = StackTrace.fromString('future stack');
    late AsyncSnapshot<int> snapshot;

    host.mount(
      SignalBuilder(
        builder: (context) {
          snapshot = useFuture<int>(completer.future);
          return const Container();
        },
      ),
    );

    completer.completeError(error, stackTrace);
    await Future<void>.delayed(Duration.zero);
    host.pumpBuild();

    expect(snapshot.connectionState, ConnectionState.done);
    expect(snapshot.error, same(error));
    expect(snapshot.stackTrace, same(stackTrace));
  });

  test('useStream reports data and completion', () async {
    final host = TestElementHost();
    final controller = StreamController<int>(sync: true);
    addTearDown(host.dispose);
    late AsyncSnapshot<int> snapshot;

    host.mount(
      SignalBuilder(
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

  test(
    'useStream handles initial data, null sources, replacement, and reset',
    () async {
      final host = TestElementHost();
      final cancelCounts = <int>[0, 0, 0];
      final first = StreamController<int>(
        sync: true,
        onCancel: () => cancelCounts[0]++,
      );
      final second = StreamController<int>(
        sync: true,
        onCancel: () => cancelCounts[1]++,
      );
      final third = StreamController<int>(
        sync: true,
        onCancel: () => cancelCounts[2]++,
      );
      addTearDown(() async {
        host.dispose();
        await first.close();
        await second.close();
        await third.close();
      });
      Stream<int>? current;
      var preserveState = true;
      late AsyncSnapshot<int> snapshot;

      Widget buildRoot() => SignalBuilder(
        builder: (context) {
          snapshot = useStream<int>(
            current,
            initialData: 4,
            preserveState: preserveState,
          );
          return const Container();
        },
      );

      host.mount(buildRoot());
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 4);

      current = first.stream;
      host.update(buildRoot());
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 4);

      first.add(9);
      host.pumpBuild();
      expect(snapshot.connectionState, ConnectionState.active);
      expect(snapshot.requireData, 9);

      current = second.stream;
      host.update(buildRoot());
      expect(cancelCounts, <int>[1, 0, 0]);
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 9);

      first.add(99);
      host.pumpBuild();
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 9);

      preserveState = false;
      current = third.stream;
      host.update(buildRoot());
      expect(cancelCounts, <int>[1, 1, 0]);
      expect(snapshot.connectionState, ConnectionState.waiting);
      expect(snapshot.requireData, 4);

      current = null;
      host.update(buildRoot());
      expect(cancelCounts, <int>[1, 1, 1]);
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 4);

      second.add(22);
      third.add(33);
      host.pumpBuild();
      expect(snapshot.connectionState, ConnectionState.none);
      expect(snapshot.requireData, 4);
    },
  );

  test('useStream reports errors with their stack traces', () async {
    final host = TestElementHost();
    final controller = StreamController<int>(sync: true);
    addTearDown(() async {
      host.dispose();
      await controller.close();
    });
    final error = StateError('stream failed');
    final stackTrace = StackTrace.fromString('stream stack');
    late AsyncSnapshot<int> snapshot;

    host.mount(
      SignalBuilder(
        builder: (context) {
          snapshot = useStream<int>(controller.stream);
          return const Container();
        },
      ),
    );

    controller.addError(error, stackTrace);
    host.pumpBuild();

    expect(snapshot.connectionState, ConnectionState.active);
    expect(snapshot.error, same(error));
    expect(snapshot.stackTrace, same(stackTrace));
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
      SignalBuilder(
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
