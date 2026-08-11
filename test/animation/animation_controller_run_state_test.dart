// ignore_for_file: cascade_invocations
import 'package:noir/src/animation/animation.dart';
import 'package:noir/src/animation/animation_controller.dart';
import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

/// Covers proportional partial-distance duration and the run-completion
/// contract after `stop()`.
class TestTickerProvider implements TickerProvider {
  TestTickerProvider(this.scheduler);
  final TickerScheduler scheduler;
  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      scheduler.createTicker(onTick, debugLabel: debugLabel);
}

void main() {
  group('AnimationController run-state contract', () {
    late TickerScheduler scheduler;
    late TestTickerProvider vsync;

    setUp(() {
      scheduler = TickerScheduler();
      vsync = TestTickerProvider(scheduler);
    });

    group('partial-distance runs scale duration', () {
      test('forward(from: 0.5) over [0, 1] with duration:100ms completes by '
          '~50ms, while forward(from: 0.0) is only half-way at the same '
          'timestamp', () async {
        final half = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );
        final full = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );

        final halfFuture = half.forward(from: 0.5);
        final fullFuture = full.forward(from: 0);

        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));

        // Partial run (traveling half the range) is already done: it only
        // needed half the full duration.
        expect(half.status, AnimationStatus.completed);
        expect(half.value, closeTo(1.0, 1e-6));

        // Full-range run at the same wall-clock point is only half-way,
        // and its own timing is unaffected by the partial-distance run.
        expect(full.status, AnimationStatus.forward);
        expect(full.value, closeTo(0.5, 1e-6));

        scheduler.handleFrame(const Duration(milliseconds: 100));
        await fullFuture;
        expect(full.status, AnimationStatus.completed);
        expect(full.value, closeTo(1.0, 1e-6));

        await halfFuture;
        half.dispose();
        full.dispose();
      });

      test('reverse(from: 0.5) over [0, 1] with duration:100ms completes by '
          '~50ms', () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
          value: 1,
        );

        final future = controller.reverse(from: 0.5);
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));

        expect(controller.status, AnimationStatus.dismissed);
        expect(controller.value, closeTo(0.0, 1e-6));

        await future;
        controller.dispose();
      });

      test('reverse(from: 0.5) respects an explicit reverseDuration, not the '
          'forward duration', () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
          reverseDuration: const Duration(milliseconds: 200),
          value: 1,
        );

        final future = controller.reverse(from: 0.5);

        // Half the range over reverseDuration:200ms should take ~100ms,
        // not ~50ms (which would be half of the forward duration).
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));
        expect(controller.status, AnimationStatus.reverse);
        expect(controller.value, closeTo(0.25, 1e-6));

        scheduler.handleFrame(const Duration(milliseconds: 100));
        expect(controller.status, AnimationStatus.dismissed);
        expect(controller.value, closeTo(0.0, 1e-6));

        await future;
        controller.dispose();
      });

      test(
        'full-range forward()/reverse() timing is unchanged (fraction == 1.0)',
        () async {
          final controller = AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 100),
          );

          final forwardFuture = controller.forward(from: 0);
          scheduler.handleFrame(Duration.zero);
          scheduler.handleFrame(const Duration(milliseconds: 50));
          expect(controller.value, closeTo(0.5, 1e-6));
          expect(controller.status, AnimationStatus.forward);
          scheduler.handleFrame(const Duration(milliseconds: 100));
          await forwardFuture;
          expect(controller.status, AnimationStatus.completed);

          final reverseFuture = controller.reverse();
          scheduler.handleFrame(Duration.zero);
          scheduler.handleFrame(const Duration(milliseconds: 50));
          expect(controller.value, closeTo(0.5, 1e-6));
          expect(controller.status, AnimationStatus.reverse);
          scheduler.handleFrame(const Duration(milliseconds: 100));
          await reverseFuture;
          expect(controller.status, AnimationStatus.dismissed);

          controller.dispose();
        },
      );
    });

    group('zero-distance short-circuit retained', () {
      test(
        'forward() already at upperBound completes with no ticking',
        () async {
          final controller = AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 100),
            value: 1,
          );

          final future = controller.forward();
          await future;
          expect(controller.status, AnimationStatus.completed);
          expect(controller.isAnimating, isFalse);
          controller.dispose();
        },
      );

      test(
        'reverse() already at lowerBound completes with no ticking',
        () async {
          final controller = AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 100),
          );

          final future = controller.reverse();
          await future;
          expect(controller.status, AnimationStatus.dismissed);
          expect(controller.isAnimating, isFalse);
          controller.dispose();
        },
      );
    });

    group('stop() has no canceled parameter; Future means "run ended"', () {
      test('forward() future completes on natural finish', () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );

        var completed = false;
        final future = controller.forward(from: 0).then((_) {
          completed = true;
        });
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 100));
        await future;
        expect(completed, isTrue);
        expect(controller.status, AnimationStatus.completed);
        controller.dispose();
      });

      test('interrupting forward() with reverse() completes the first future '
          '(run-ended, not cancellation-aware)', () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );

        var forwardCompleted = false;
        final forwardFuture = controller.forward(from: 0).then((_) {
          forwardCompleted = true;
        });
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));
        expect(forwardCompleted, isFalse);

        final reverseFuture = controller.reverse();
        // The first future must already be complete: reverse() calls
        // stop() internally before starting its own run. By the time an
        // asynchronous continuation observes that completion, status is
        // the current replacement run's status, not the old run's outcome.
        await forwardFuture;
        expect(forwardCompleted, isTrue);
        expect(controller.status, AnimationStatus.reverse);
        expect(controller.isAnimating, isTrue);

        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 100));
        await reverseFuture;
        expect(controller.status, AnimationStatus.dismissed);
        controller.dispose();
      });

      test(
        'stop() completes the pending future without reaching the target',
        () async {
          final controller = AnimationController(
            vsync: vsync,
            duration: const Duration(milliseconds: 100),
          );

          final future = controller.forward(from: 0);
          scheduler.handleFrame(Duration.zero);
          scheduler.handleFrame(const Duration(milliseconds: 50));
          expect(controller.value, closeTo(0.5, 1e-6));
          final valueAtStop = controller.value;

          // stop() takes no arguments -- the `canceled` parameter is gone.
          controller.stop();
          await future;
          expect(controller.value, valueAtStop);
          expect(controller.status, AnimationStatus.forward);
          expect(controller.isAnimating, isFalse);
          controller.dispose();
        },
      );

      test('dispose() completes a still-pending future', () async {
        final controller = AnimationController(
          vsync: vsync,
          duration: const Duration(milliseconds: 100),
        );

        final future = controller.forward(from: 0);
        scheduler.handleFrame(Duration.zero);
        scheduler.handleFrame(const Duration(milliseconds: 50));

        controller.dispose();
        await future;
      });
    });
  });
}
