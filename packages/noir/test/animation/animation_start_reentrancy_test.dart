import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

void main() {
  for (final reverse in [false, true]) {
    final direction = reverse
        ? AnimationStatus.reverse
        : AnimationStatus.forward;

    test('$direction start callback can stop its announced run', () async {
      final controller = _controller(value: reverse ? 1 : 0);
      addTearDown(controller.dispose);
      var called = false;
      controller.addStatusListener((status) {
        if (status != direction) return;
        called = true;
        expect(controller.isAnimating, isTrue);
        controller.stop();
      });

      final run = reverse ? controller.reverse() : controller.forward();

      expect(called, isTrue);
      expect(controller.isAnimating, isFalse);
      await run;
    });

    test('$direction start callback can dispose its announced run', () async {
      final controller = _controller(value: reverse ? 1 : 0);
      addTearDown(controller.dispose);
      controller.addStatusListener((status) {
        if (status == direction) controller.dispose();
      });

      final run = reverse ? controller.reverse() : controller.forward();

      expect(controller.isAnimating, isFalse);
      await run;
    });

    test(
      '$direction replacement keeps independent run-ended Futures',
      () async {
        final controller = _controller(value: reverse ? 1 : 0);
        addTearDown(controller.dispose);
        Future<void>? replacement;
        var replacementEnded = false;
        controller.addStatusListener((status) {
          if (status != direction || replacement != null) return;
          replacement = reverse
              ? controller.forward(from: 0)
              : controller.reverse(from: 1);
          replacement!.then((_) => replacementEnded = true);
        });

        final run = reverse ? controller.reverse() : controller.forward();
        var originalEnded = false;
        unawaited(run.then((_) => originalEnded = true));
        await Future<void>.value();

        expect(replacement, isNotNull);
        expect(run, isNot(same(replacement)));
        expect(originalEnded, isTrue);
        expect(replacementEnded, isFalse);
        expect(controller.isAnimating, isTrue);
        expect(
          controller.status,
          reverse ? AnimationStatus.forward : AnimationStatus.reverse,
        );
        controller.stop();
        await replacement;
      },
    );
  }

  test('a from-value callback can stop before start returns', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.value == 0.25) controller.stop();
    });

    final run = controller.forward(from: 0.25);

    expect(controller.isAnimating, isFalse);
    expect(controller.value, 0.25);
    await run;
  });

  test(
    'a from-value callback can supersede without stale direction or time',
    () async {
      final scheduler = TickerScheduler();
      final controller = _controller(scheduler: scheduler);
      addTearDown(controller.dispose);
      var redirected = false;
      Future<void>? replacement;
      controller.addListener(() {
        if (redirected || controller.value != 0.25) return;
        redirected = true;
        replacement = controller.reverse();
      });

      final original = controller.forward(from: 0.25);
      var originalEnded = false;
      unawaited(original.then((_) => originalEnded = true));
      await Future<void>.value();

      expect(originalEnded, isTrue);
      expect(controller.status, AnimationStatus.reverse);
      scheduler.handleFrame(Duration.zero);
      scheduler.handleFrame(const Duration(milliseconds: 25));
      await replacement;
      expect(controller.value, 0);
      expect(controller.status, AnimationStatus.dismissed);
      expect(controller.isAnimating, isFalse);
    },
  );

  test(
    'disposal from a from-value callback cannot restart the ticker',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      controller.addListener(controller.dispose);

      final run = controller.forward(from: 0.25);

      expect(controller.isAnimating, isFalse);
      await run;
    },
  );

  test(
    'instant completion callback can replace the run without being reset',
    () async {
      final controller = _controller()..duration = Duration.zero;
      addTearDown(controller.dispose);
      Future<void>? replacement;
      final values = <double>[];
      controller.addListener(() => values.add(controller.value));
      controller.addStatusListener((status) {
        if (status != AnimationStatus.completed || replacement != null) return;
        controller.duration = const Duration(milliseconds: 100);
        replacement = controller.reverse();
      });

      await controller.forward();

      expect(replacement, isNotNull);
      expect(controller.status, AnimationStatus.reverse);
      expect(controller.isAnimating, isTrue);
      expect(values, [1]);
      controller.stop();
      await replacement;
    },
  );

  test(
    'invalid from input leaves an active run and its Future intact',
    () async {
      final scheduler = TickerScheduler();
      final controller = _controller(scheduler: scheduler);
      addTearDown(controller.dispose);
      var ended = false;
      final run = controller.forward();
      unawaited(run.then((_) => ended = true));
      scheduler.handleFrame(Duration.zero);
      scheduler.handleFrame(const Duration(milliseconds: 25));

      expect(() => controller.reverse(from: double.nan), throwsArgumentError);
      await Future<void>.value();

      expect(ended, isFalse);
      expect(controller.isAnimating, isTrue);
      expect(controller.value, 0.25);
      expect(controller.status, AnimationStatus.forward);
      scheduler.handleFrame(const Duration(milliseconds: 100));
      await run;
    },
  );

  test(
    'stopping in a start-status callback still publishes the from value',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      final values = <double>[];
      controller.addListener(() => values.add(controller.value));
      controller.addStatusListener((status) {
        if (status == AnimationStatus.forward) controller.stop();
      });

      await controller.forward(from: 0.25);

      expect(values, [0.25]);
      expect(controller.isAnimating, isFalse);
    },
  );

  test('reset from a from-value callback ends only its current run', () async {
    final controller = _controller();
    addTearDown(controller.dispose);
    controller.addListener(() {
      if (controller.value == 0.25) controller.reset();
    });

    await controller.forward(from: 0.25);

    expect(controller.value, 0);
    expect(controller.status, AnimationStatus.dismissed);
    expect(controller.isAnimating, isFalse);
  });

  test(
    'ticker disposal failure still ends the run and notifier ownership',
    () async {
      final failure = StateError('provider cleanup');
      final controller = AnimationController(vsync: _ThrowingProvider(failure));
      final run = controller.forward();

      expect(controller.dispose, throwsA(same(failure)));
      await run;

      expect(controller.isAnimating, isFalse);
      expect(() => controller.addListener(() {}), throwsStateError);
      expect(() => controller.addStatusListener((_) {}), throwsStateError);
      expect(controller.dispose, returnsNormally);
    },
  );
}

AnimationController _controller({
  double value = 0,
  TickerScheduler? scheduler,
}) => AnimationController(
  vsync: _Provider(scheduler ?? TickerScheduler()),
  value: value,
  duration: const Duration(milliseconds: 100),
);

class _Provider implements TickerProvider {
  _Provider(this.scheduler);

  final TickerScheduler scheduler;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      scheduler.createTicker(onTick, debugLabel: debugLabel);
}

class _ThrowingProvider implements TickerProvider {
  _ThrowingProvider(this.failure);

  final StateError failure;

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      TickerScheduler().createTicker(onTick, onDispose: (_) => throw failure);
}
