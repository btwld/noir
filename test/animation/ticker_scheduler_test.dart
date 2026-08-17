import 'package:noir/src/animation/ticker.dart';
import 'package:test/test.dart';

void main() {
  test('restarting during a tick requests exactly one next frame', () {
    final scheduler = TickerScheduler();
    var frameRequests = 0;
    scheduler.setFrameCallback(() => frameRequests++);

    late final Ticker ticker;
    ticker = scheduler.createTicker((_) {
      ticker
        ..stop()
        ..start();
    });
    addTearDown(ticker.dispose);

    ticker.start();
    expect(frameRequests, 1);

    frameRequests = 0;
    scheduler.handleFrame(Duration.zero);

    expect(ticker.isTicking, isTrue);
    expect(frameRequests, 1);
  });
}
