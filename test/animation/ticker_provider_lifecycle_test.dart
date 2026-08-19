import 'dart:mirrors';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart' show Element;
import 'package:test/test.dart';

void main() {
  group('TickerProviderStateMixin', () {
    test('immediately releases each disposed controller ticker', () async {
      final host = _mountMultiTickerHost();
      addTearDown(host.unmount);

      for (var index = 0; index < 3; index++) {
        final controller = host.state.createController();
        final run = controller.forward();

        expect(host.state.mounted, isTrue);
        expect(controller.isAnimating, isTrue);
        expect(_trackedTickers(host.state), hasLength(1));

        controller.dispose();
        await run;

        expect(controller.isAnimating, isFalse);
        expect(controller.forward, throwsStateError);
        expect(_trackedTickers(host.state), isEmpty);
        expect(host.state.mounted, isTrue);
      }
    });

    test('only a current live ticker participates in teardown', () {
      final host = _mountMultiTickerHost();
      AnimationController? current;
      addTearDown(() {
        current?.dispose();
        if (host.state.mounted) {
          host.unmount();
        }
      });

      for (var index = 0; index < 3; index++) {
        host.state.createController()
          ..forward()
          ..dispose();
      }

      current = host.state.createController()..forward();
      expect(_trackedTickers(host.state), hasLength(1));
      expect(
        host.state.dispose,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'TickerProviderStateMixin.dispose called with an active ticker',
            ),
          ),
        ),
      );

      current.dispose();
      expect(_trackedTickers(host.state), isEmpty);
      host.unmount();
      expect(host.state.mounted, isFalse);
    });

    test('teardown drains every ticker and chains before it reports', () {
      final host = _mountMultiTickerHost();
      final active = host.state.createRawTicker()..start();
      final idle = host.state.createRawTicker();

      expect(host.state.dispose, throwsStateError);

      expect(
        active.isDisposed,
        isTrue,
        reason: 'the misused ticker is still released',
      );
      expect(idle.isDisposed, isTrue, reason: 'its siblings are not skipped');
      expect(_trackedTickers(host.state), isEmpty);
      expect(
        host.state.superDisposeCalls,
        1,
        reason: 'the full super.dispose() chain runs before the report',
      );

      host.unmount();
    });

    test('drains multiple inactive live tickers during teardown', () {
      final host = _mountMultiTickerHost();
      final first = host.state.createRawTicker();
      final second = host.state.createRawTicker();

      expect(_trackedTickers(host.state), hasLength(2));

      host.unmount();

      expect(first.isDisposed, isTrue);
      expect(second.isDisposed, isTrue);
      expect(_trackedTickers(host.state), isEmpty);
    });

    test('keeps stopped tickers until exactly-once terminal disposal', () {
      final host = _mountMultiTickerHost();
      addTearDown(host.unmount);
      final ticker = host.state.createRawTicker();

      expect(_trackedTickers(host.state), hasLength(1));

      ticker
        ..start()
        ..stop();
      expect(ticker.isTicking, isFalse);
      expect(_trackedTickers(host.state), hasLength(1));

      ticker.dispose();
      expect(ticker.isDisposed, isTrue);
      expect(_trackedTickers(host.state), isEmpty);

      ticker.dispose();
      expect(ticker.isDisposed, isTrue);
      expect(_trackedTickers(host.state), isEmpty);
    });
  });

  group('SingleTickerProviderStateMixin', () {
    test('remains single-use after disposal', () {
      final host = _mountSingleTickerHost();
      addTearDown(host.unmount);
      host.state.createRawTicker().dispose();

      expect(host.state.createRawTicker, throwsStateError);
    });

    test('teardown releases an active ticker before it reports', () {
      final host = _mountSingleTickerHost();
      final ticker = host.state.createRawTicker()..start();

      expect(
        host.state.dispose,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(
              'SingleTickerProviderStateMixin.dispose called with an active '
              'ticker',
            ),
          ),
        ),
      );

      expect(ticker.isDisposed, isTrue);
      expect(host.state.superDisposeCalls, 1);

      host.unmount();
    });
  });
}

Set<Ticker> _trackedTickers(_MultiTickerHostState state) {
  final tickerLibrary = currentMirrorSystem().libraries.values.singleWhere(
    (library) => library.declarations.containsKey(
      MirrorSystem.getSymbol('TickerProviderStateMixin', library),
    ),
  );
  final field = MirrorSystem.getSymbol('_tickers', tickerLibrary);
  return (reflect(state).getField(field).reflectee as Set<Object?>)
      .cast<Ticker>();
}

_MountedHost<_MultiTickerHostState> _mountMultiTickerHost() {
  final owner = BuildOwner()..setFrameCallback(() {});
  final key = GlobalKey<_MultiTickerHostState>();
  final element = _MultiTickerHost(key: key).createElement()
    ..mount(null, owner);
  return _MountedHost<_MultiTickerHostState>(
    element: element,
    state: key.currentState!,
  );
}

_MountedHost<_SingleTickerHostState> _mountSingleTickerHost() {
  final owner = BuildOwner()..setFrameCallback(() {});
  final key = GlobalKey<_SingleTickerHostState>();
  final element = _SingleTickerHost(key: key).createElement()
    ..mount(null, owner);
  return _MountedHost<_SingleTickerHostState>(
    element: element,
    state: key.currentState!,
  );
}

class _MountedHost<T extends State<StatefulWidget>> {
  const _MountedHost({required this.element, required this.state});

  final Element element;
  final T state;

  void unmount() => element.unmount();
}

class _MultiTickerHost extends StatefulWidget {
  const _MultiTickerHost({super.key});

  @override
  State<_MultiTickerHost> createState() => _MultiTickerHostState();
}

/// Observes the `super.dispose()` chain below the ticker mixin under test.
mixin _SuperDisposeProbe<T extends StatefulWidget> on State<T> {
  int superDisposeCalls = 0;

  @override
  void dispose() {
    superDisposeCalls++;
    super.dispose();
  }
}

class _MultiTickerHostState extends State<_MultiTickerHost>
    with
        _SuperDisposeProbe<_MultiTickerHost>,
        TickerProviderStateMixin<_MultiTickerHost> {
  AnimationController createController() =>
      AnimationController(vsync: this, duration: const Duration(seconds: 1));

  Ticker createRawTicker() => createTicker((_) {});

  @override
  Widget build(BuildContext context) => const SizedBox();
}

class _SingleTickerHost extends StatefulWidget {
  const _SingleTickerHost({super.key});

  @override
  State<_SingleTickerHost> createState() => _SingleTickerHostState();
}

class _SingleTickerHostState extends State<_SingleTickerHost>
    with
        _SuperDisposeProbe<_SingleTickerHost>,
        SingleTickerProviderStateMixin<_SingleTickerHost> {
  Ticker createRawTicker() => createTicker((_) {});

  @override
  Widget build(BuildContext context) => const SizedBox();
}
