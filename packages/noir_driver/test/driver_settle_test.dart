@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

import 'fixtures/driver_slow_repaint_probe.dart' show repaintDelay;

/// Input settling is reported, not silently raced.
///
/// `sendKey` and friends wait for the app to paint before returning, capped so
/// a key an app ignores does not cost the caller a full timeout. When the cap
/// expires first, the next `capture()` can still be the pre-input frame — so
/// the caller has to be able to tell the two apart.
void main() {
  test('a repaint slower than the settle window reports false', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_slow_repaint_probe.dart',
      width: 20,
      height: 3,
    );
    addTearDown(driver.quit);
    expect(await driver.waitStable(), isTrue);
    expect(await driver.capture(), DriverFrameMatchers.containsText('COUNT 0'));

    // The fixture repaints on a timer well past the default cap.
    expect(await driver.sendKey('up'), isFalse);

    // False means "no frame yet", not "the input was lost".
    await driver.waitForText('COUNT 1');
  });

  test('a settle window longer than the repaint reports true', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_slow_repaint_probe.dart',
      width: 20,
      height: 3,
    );
    addTearDown(driver.quit);
    expect(await driver.waitStable(), isTrue);

    expect(
      await driver.sendKey('up', settle: repaintDelay * 3),
      isTrue,
      reason: 'the frame lands inside a settle window that outlasts it',
    );
    expect(await driver.capture(), DriverFrameMatchers.containsText('COUNT 1'));
  });

  test('an ignored key returns at the cap instead of hanging', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_slow_repaint_probe.dart',
      width: 20,
      height: 3,
    );
    addTearDown(driver.quit);
    expect(await driver.waitStable(), isTrue);

    // The fixture handles only arrow-up, so this paints nothing at all. The
    // call must still come back once the window closes rather than waiting on
    // a frame that will never arrive.
    final started = DateTime.now();
    expect(await driver.sendKey('down', settle: repaintDelay), isFalse);
    final elapsed = DateTime.now().difference(started);
    expect(elapsed, greaterThanOrEqualTo(repaintDelay));
    expect(elapsed, lessThan(repaintDelay * 4));
  });

  test('typeText and click report settling the same way', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_slow_repaint_probe.dart',
      width: 20,
      height: 3,
    );
    addTearDown(driver.quit);
    expect(await driver.waitStable(), isTrue);

    // Neither reaches the fixture's arrow-up handler, so neither repaints.
    expect(await driver.typeText('x'), isFalse);
    expect(await driver.click(0, 0), isFalse);
  });
}
