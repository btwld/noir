// ignore_for_file: cascade_invocations
import 'dart:async';

import 'package:noir/src/animation/animation.dart';
import 'package:noir/src/animation/animation_controller.dart';
import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

class TestTickerProvider implements TickerProvider {
  TestTickerProvider(this.scheduler);
  final TickerScheduler scheduler;
  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      scheduler.createTicker(onTick, debugLabel: debugLabel);
}

void main() {
  group('AnimationController sanity', () {
    late TickerScheduler scheduler;
    late TestTickerProvider vsync;

    setUp(() {
      scheduler = TickerScheduler();
      // Drive frames manually via scheduler.handleFrame(...)
      vsync = TestTickerProvider(scheduler);
    });

    test(
      'negative durations are rejected without disturbing an active run',
      () {
        expect(
          () => AnimationController(
            vsync: vsync,
            duration: const Duration(microseconds: -1),
          ),
          throwsArgumentError,
        );
        expect(
          () => AnimationController(
            vsync: vsync,
            reverseDuration: const Duration(microseconds: -1),
          ),
          throwsArgumentError,
        );

        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );
        addTearDown(controller.dispose);
        controller.forward();

        expect(
          () => controller.duration = const Duration(microseconds: -1),
          throwsArgumentError,
        );
        expect(
          () => controller.reverseDuration = const Duration(microseconds: -1),
          throwsArgumentError,
        );
        expect(controller.duration, const Duration(milliseconds: 100));
        expect(controller.reverseDuration, isNull);
        expect(controller.isAnimating, isTrue);
      },
    );

    test(
      'reverse(from:) sets reverse first status (no transient forward)',
      () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
          value: 0.7,
        );

        final statuses = <AnimationStatus>[];
        controller.addStatusListener(statuses.add);

        final reverse = controller.reverse(from: 0.3);
        expect(statuses.first, AnimationStatus.reverse);

        // Drive frames to finish
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));
        scheduler.handleFrame(const Duration(milliseconds: 100));

        await reverse;
        expect(controller.status, AnimationStatus.dismissed);
        expect(controller.value, closeTo(controller.lowerBound, 1e-6));
        controller.dispose();
      },
    );

    test(
      're-entrant restart on completion does not complete second future early',
      () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );

        var startedSecond = false;
        var secondCompleted = false;
        Future<void>? f2;
        controller.addStatusListener((s) {
          if (s == AnimationStatus.completed && !startedSecond) {
            startedSecond = true;
            f2 = controller.forward(from: 0)
              ..then((_) => secondCompleted = true);
          }
        });

        final f1 = controller.forward(from: 0);

        // First run
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));
        scheduler.handleFrame(const Duration(milliseconds: 100));

        await f1; // should complete exactly once here
        expect(f2, isNotNull);
        expect(controller.isAnimating, isTrue);
        expect(controller.value, controller.lowerBound);
        await Future<void>.value();
        expect(secondCompleted, isFalse);

        // Second run
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));
        scheduler.handleFrame(const Duration(milliseconds: 100));

        await f2; // should complete now
        expect(controller.status, AnimationStatus.completed);
        controller.dispose();
      },
    );

    test('zero-distance forward short-circuits', () async {
      final controller = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 100),
        value: 1,
      );

      final future = controller.forward();
      // Should be already completed without ticking
      await future;
      expect(controller.status, AnimationStatus.completed);
      expect(controller.value, 1.0);
      expect(controller.isAnimating, isFalse);
      controller.dispose();
    });

    test('manual jump to end mid-run finishes immediately', () async {
      final controller = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 100),
      );

      final future = controller.forward();
      scheduler.handleFrame(Duration.zero);
      scheduler.handleFrame(const Duration(milliseconds: 50));

      // Force to end mid-run
      controller.value = controller.upperBound;
      // No additional frame should be required
      await future;
      expect(controller.status, AnimationStatus.completed);
      expect(controller.isAnimating, isFalse);
      controller.dispose();
    });
  });
}
