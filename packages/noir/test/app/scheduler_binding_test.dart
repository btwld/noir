import 'package:noir/src/animation/ticker.dart';
import 'package:noir/src/scheduler/scheduler_binding.dart';
import 'package:test/test.dart';

void main() {
  test('coalesces multiple frame requests before the timer fires', () {
    final timers = _FakeSchedulerTimers();
    final scheduler = SchedulerBinding(
      clock: timers.now,
      timerFactory: timers.createTimer,
    );
    final frames = <Duration>[];
    scheduler.setFrameCallback(frames.add);

    scheduler.scheduleFrame();
    scheduler.scheduleFrame();
    scheduler.scheduleFrame();

    expect(timers.createdDelays, [Duration.zero]);
    expect(scheduler.hasScheduledFrame, isTrue);

    timers.fireNext();

    expect(frames, [Duration.zero]);
    expect(scheduler.hasScheduledFrame, isFalse);
    expect(timers.createdDelays, hasLength(1));
  });

  test('idles after a non-animation frame', () {
    final timers = _FakeSchedulerTimers();
    final scheduler = SchedulerBinding(
      clock: timers.now,
      timerFactory: timers.createTimer,
    );
    var frameCount = 0;
    scheduler.setFrameCallback((_) {
      frameCount++;
    });

    scheduler.scheduleFrame();
    timers.fireNext();
    timers.elapse(const Duration(milliseconds: 100));

    expect(frameCount, 1);
    expect(scheduler.hasScheduledFrame, isFalse);
    expect(timers.pendingCount, 0);
    expect(timers.createdDelays, [Duration.zero]);
  });

  test('delivers elapsed timestamps from the first frame', () {
    final timers = _FakeSchedulerTimers();
    final scheduler = SchedulerBinding(
      clock: timers.now,
      timerFactory: timers.createTimer,
    );
    final frames = <Duration>[];
    scheduler.setFrameCallback(frames.add);

    scheduler.scheduleFrame();
    timers.fireNext();
    timers.elapse(const Duration(milliseconds: 25));
    scheduler.scheduleFrame();
    timers.fireNext();

    expect(frames, [Duration.zero, const Duration(milliseconds: 25)]);
    expect(timers.createdDelays, [Duration.zero, Duration.zero]);
  });

  test('dispose cancels pending frame and blocks future scheduling', () {
    final timers = _FakeSchedulerTimers();
    final scheduler = SchedulerBinding(
      clock: timers.now,
      timerFactory: timers.createTimer,
    );
    var frameCount = 0;
    scheduler.setFrameCallback((_) {
      frameCount++;
    });

    scheduler.scheduleFrame();
    scheduler.dispose();
    timers.fireNext();
    scheduler.scheduleFrame();

    expect(frameCount, 0);
    expect(scheduler.hasScheduledFrame, isFalse);
    expect(timers.pendingCount, 0);
    expect(timers.createdDelays, [Duration.zero]);
  });

  test('active ticker reschedules at target frame interval', () {
    final timers = _FakeSchedulerTimers();
    final scheduler = SchedulerBinding(
      clock: timers.now,
      timerFactory: timers.createTimer,
    );
    final tickerScheduler = TickerScheduler();
    tickerScheduler.setFrameCallback(scheduler.scheduleFrame);
    final ticker = tickerScheduler.createTicker((_) {});
    scheduler.setFrameCallback(tickerScheduler.handleFrame);

    ticker.start();
    expect(timers.createdDelays, [Duration.zero]);

    timers.fireNext();
    expect(timers.createdDelays, [
      Duration.zero,
      const Duration(microseconds: 1000000 ~/ 60),
    ]);
    expect(scheduler.hasScheduledFrame, isTrue);

    timers.elapse(const Duration(microseconds: 1000000 ~/ 60));
    timers.fireNext();
    expect(timers.createdDelays, [
      Duration.zero,
      const Duration(microseconds: 1000000 ~/ 60),
      const Duration(microseconds: 1000000 ~/ 60),
    ]);

    ticker.dispose();
    timers.elapse(const Duration(microseconds: 1000000 ~/ 60));
    timers.fireNext();
    expect(scheduler.hasScheduledFrame, isFalse);
    expect(timers.createdDelays, hasLength(3));
  });
}

class _FakeSchedulerTimers {
  DateTime _now = DateTime(2026);
  final List<Duration> createdDelays = [];
  final List<_FakeSchedulerTimer> _timers = [];

  DateTime now() => _now;

  int get pendingCount => _timers.where((timer) => !timer.isCanceled).length;

  SchedulerTimer createTimer(Duration delay, void Function() callback) {
    createdDelays.add(delay);
    final timer = _FakeSchedulerTimer(callback);
    _timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    _now = _now.add(duration);
  }

  void fireNext() {
    final timer = _timers.firstWhere((timer) => !timer.hasFired);
    timer.fire();
  }
}

class _FakeSchedulerTimer implements SchedulerTimer {
  _FakeSchedulerTimer(this._callback);

  final void Function() _callback;
  bool isCanceled = false;
  bool hasFired = false;

  @override
  void cancel() {
    isCanceled = true;
  }

  void fire() {
    hasFired = true;
    if (isCanceled) {
      return;
    }
    isCanceled = true;
    _callback();
  }
}
