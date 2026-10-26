@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:async';

import 'package:noir_driver/noir_driver.dart';
import 'package:noir_driver/src/driver_polling.dart';
import 'package:test/test.dart';

void main() {
  test(
    'launch readiness uses its startup budget, not the later RPC ceiling',
    () async {
      final driver = await NoirDriver.launch(
        'test/fixtures/driver_stalled_service_probe.dart',
        arguments: ['--delayed-ready'],
        onAppOutput: (_) {},
        requestTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(() async => expect(await driver.quit(), 0));

      expect((await driver.info()).frames, 1);
    },
  );

  test(
    'input request timeout is separate from its frame-settle window',
    () async {
      final driver = await NoirDriver.launch(
        'test/fixtures/driver_stalled_service_probe.dart',
        onAppOutput: (_) {},
        requestTimeout: const Duration(milliseconds: 40),
      );
      addTearDown(() async => expect(await driver.quit(), 0));

      await expectLater(
        driver
            .sendKey('enter', settle: Duration.zero)
            .timeout(
              const Duration(milliseconds: 500),
              onTimeout: () =>
                  throw StateError('input exceeded its request deadline'),
            ),
        throwsA(isA<TimeoutException>()),
      );
      expect((await driver.info()).frames, 1);
    },
  );

  test('late resource acquisition is released after caller timeout', () async {
    final acquisition = Completer<Object>();
    final released = Completer<Object>();
    final resource = Object();
    final result = acquireBeforeDeadline(
      acquisition.future,
      deadline: PollDeadline(Duration.zero),
      release: (value) async => released.complete(value),
      operation: 'test acquisition',
    );

    await expectLater(result, throwsA(isA<TimeoutException>()));
    expect(released.isCompleted, isFalse);
    acquisition.complete(resource);
    expect(await released.future, same(resource));
  });

  test('accepted resource remains owned by its caller', () async {
    final resource = Object();
    var releases = 0;
    final result = await acquireBeforeDeadline(
      Future.value(resource),
      deadline: PollDeadline(const Duration(seconds: 1)),
      release: (_) async => releases++,
      operation: 'test acquisition',
    );

    expect(result, same(resource));
    expect(releases, 0);
  });

  test('acquisition propagates the original failure', () async {
    final failure = StateError('connection failed');
    var releases = 0;
    await expectLater(
      acquireBeforeDeadline<Object>(
        Future.error(failure),
        deadline: PollDeadline(const Duration(seconds: 1)),
        release: (_) async => releases++,
        operation: 'test acquisition',
      ),
      throwsA(same(failure)),
    );
    expect(releases, 0);
  });

  test('waitStable bounds a pending service reply on the client', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_stalled_service_probe.dart',
      onAppOutput: (_) {},
    );
    addTearDown(() async => expect(await driver.quit(), 0));

    final stable = await driver
        .waitStable(timeout: const Duration(milliseconds: 40))
        .timeout(
          const Duration(milliseconds: 500),
          onTimeout: () => throw StateError('waitStable exceeded its deadline'),
        );

    expect(stable, isFalse);
    expect((await driver.info()).frames, 1);
  });
}
