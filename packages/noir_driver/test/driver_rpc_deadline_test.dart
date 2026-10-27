@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:async';
import 'dart:io';

import 'package:noir_driver/noir_driver.dart';
import 'package:noir_driver/src/driver_polling.dart';
import 'package:test/test.dart';

void main() {
  test('acknowledged quit timeout kills before workspace cleanup', () async {
    final events = <String>[];
    final systemTemp = Directory.systemTemp;
    final acknowledged = Completer<void>();
    final deleted = Completer<void>();
    final driver = await IOOverrides.runZoned(
      () => NoirDriver.launch(
        'test/fixtures/driver_stalled_service_probe.dart',
        arguments: ['--ignore-quit'],
        onAppOutput: (line) {
          if (line == 'quit acknowledged') acknowledged.complete();
        },
      ),
      getSystemTempDirectory: () => _TrackedDirectory(systemTemp, () {
        events.add('workspace deleted');
        if (!deleted.isCompleted) deleted.complete();
      }),
    );
    final exited = driver.waitForExit().then((code) {
      events.add('process exited');
      return code;
    });
    addTearDown(() async {
      await driver.kill();
      await exited;
    });

    const budget = Duration(milliseconds: 100);
    await expectLater(
      driver
          .quit(timeout: budget)
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () => throw StateError('quit exceeded its deadline'),
          ),
      throwsA(
        isA<TimeoutException>().having((e) => e.duration, 'budget', budget),
      ),
    );
    await acknowledged.future.timeout(const Duration(seconds: 1));
    expect(await exited.timeout(const Duration(seconds: 1)), isNot(0));
    await deleted.future.timeout(const Duration(seconds: 1));
    expect(events, ['process exited', 'workspace deleted']);
  });

  test('a rejected quit still kills the driven process', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_stalled_service_probe.dart',
      arguments: ['--fail-quit'],
      onAppOutput: (_) {},
    );
    addTearDown(driver.kill);

    expect(await driver.quit(), isNot(0));
  });

  test('waitForExit times out and kills a process that stays alive', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_stalled_service_probe.dart',
      onAppOutput: (_) {},
    );
    addTearDown(driver.kill);
    // Observe the exit independently of the short wait. A missing timeout
    // kill cannot pass by relying on this observer's longer timeout.
    final exited = driver.waitForExit(timeout: const Duration(seconds: 5));

    const budget = Duration(milliseconds: 40);
    await expectLater(
      driver
          .waitForExit(timeout: budget)
          .timeout(
            const Duration(seconds: 1),
            onTimeout: () =>
                throw StateError('exit wait exceeded its deadline'),
          ),
      throwsA(
        isA<TimeoutException>().having((e) => e.duration, 'budget', budget),
      ),
    );
    expect(await exited.timeout(const Duration(seconds: 1)), isNot(0));
  });

  test('waitForExit preserves the natural exit code', () async {
    final driver = await NoirDriver.launch(
      'test/fixtures/driver_stalled_service_probe.dart',
      onAppOutput: (_) {},
    );
    addTearDown(driver.kill);
    final exited = driver.waitForExit();

    expect(await driver.quit(), 0);
    expect(await exited, 0);
  });

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

class _TrackedDirectory implements Directory {
  _TrackedDirectory(this.directory, this.onDelete);

  final Directory directory;
  final void Function() onDelete;

  @override
  String get path => directory.path;

  @override
  Directory createTempSync([String? prefix]) =>
      _TrackedDirectory(directory.createTempSync(prefix), onDelete);

  @override
  bool existsSync() => directory.existsSync();

  @override
  void deleteSync({bool recursive = false}) {
    onDelete();
    directory.deleteSync(recursive: recursive);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
