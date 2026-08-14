import 'dart:async';

import 'package:noir/src/animation/animation.dart';
import 'package:noir/src/animation/animation_controller.dart';
import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

final class _TestTickerProvider implements TickerProvider {
  _TestTickerProvider(this.scheduler);

  final TickerScheduler scheduler;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      scheduler.createTicker(onTick, debugLabel: debugLabel);
}

void main() {
  test(
    'status listener failure is reported without starving listeners or run',
    () async {
      final scheduler = TickerScheduler();
      final controller = AnimationController(
        vsync: _TestTickerProvider(scheduler),
        duration: const Duration(milliseconds: 100),
      );
      addTearDown(controller.dispose);

      final listenerError = StateError('status listener failed');
      final listenerStack = StackTrace.fromString('status listener stack');
      final log = <String>[];
      final reports = <(Object, StackTrace, Zone)>[];
      final boundaryMarker = Object();

      controller
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          log.add('throwing');
          Error.throwWithStackTrace(listenerError, listenerStack);
        })
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) log.add('later');
        });

      late Future<void> run;
      late Zone notificationZone;
      notificationZone = Zone.current.fork(
        zoneValues: {#animationBoundary: boundaryMarker},
        specification: ZoneSpecification(
          handleUncaughtError: (_, _, zone, error, stackTrace) {
            reports.add((error, stackTrace, zone));
            log.add('reported');
          },
        ),
      );

      notificationZone.runGuarded(() {
        run = controller.forward(from: 0);
        scheduler
          ..handleFrame(Duration.zero)
          ..handleFrame(const Duration(milliseconds: 100));
      });

      await run.timeout(const Duration(milliseconds: 100));
      expect(log, ['throwing', 'reported', 'later']);
      expect(reports, hasLength(1));
      expect(identical(reports.single.$1, listenerError), isTrue);
      expect(reports.single.$2.toString(), listenerStack.toString());
      expect(reports.single.$3, same(notificationZone));
      expect(reports.single.$3[#animationBoundary], same(boundaryMarker));
      expect(controller.value, controller.upperBound);
      expect(controller.status, AnimationStatus.completed);
      expect(controller.isAnimating, isFalse);
    },
  );

  test('ticker failure is reported without starving siblings or frames', () {
    final scheduler = TickerScheduler();
    final tickerError = StateError('ticker callback failed');
    final tickerStack = StackTrace.fromString('ticker callback stack');
    final log = <String>[];
    final reports = <(Object, StackTrace, Zone)>[];
    var frameRequests = 0;

    scheduler.setFrameCallback(() => frameRequests++);
    final throwingTicker = scheduler.createTicker((_) {
      log.add('throwing');
      Error.throwWithStackTrace(tickerError, tickerStack);
    });
    final siblingTicker = scheduler.createTicker((_) => log.add('sibling'));
    addTearDown(throwingTicker.dispose);
    addTearDown(siblingTicker.dispose);

    throwingTicker.start();
    siblingTicker.start();
    frameRequests = 0;

    late Zone frameZone;
    frameZone = Zone.current.fork(
      specification: ZoneSpecification(
        handleUncaughtError: (_, _, zone, error, stackTrace) {
          reports.add((error, stackTrace, zone));
          log.add('reported');
        },
      ),
    );
    frameZone.runGuarded(() => scheduler.handleFrame(Duration.zero));

    expect(log, ['throwing', 'reported', 'sibling']);
    expect(reports, hasLength(1));
    expect(identical(reports.single.$1, tickerError), isTrue);
    expect(reports.single.$2.toString(), tickerStack.toString());
    expect(reports.single.$3, same(frameZone));
    expect(throwingTicker.isTicking, isTrue);
    expect(siblingTicker.isTicking, isTrue);
    expect(frameRequests, 1);
  });
}
