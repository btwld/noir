import 'dart:async';

import 'package:noir_driver/noir_driver.dart';
import 'package:noir_driver/src/driver_polling.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

/// Client-side waits spend one budget across every response and every pause.
///
/// A deadline checked only between completed requests does not bound a
/// request that never completes, which is exactly when a driven app has
/// stalled. Each case runs under [_watchdog] so a regression fails instead of
/// hanging the suite; the watchdog is never the deadline under test.
void main() {
  const budget = Duration(milliseconds: 40);

  group('pollFrameAdvance', () {
    test('reports no frame when the response never completes', () async {
      final advanced = await _watchdog(
        pollFrameAdvance(
          frames: () => Completer<int>().future,
          before: 0,
          cap: budget,
        ),
      );

      expect(advanced, isFalse);
    });

    test('a frame count that arrives after the cap is not a success', () async {
      final response = Completer<int>();
      var requests = 0;
      final advanced = await _watchdog(
        pollFrameAdvance(
          frames: () {
            requests++;
            return response.future;
          },
          before: 0,
          cap: budget,
        ),
      );
      response.complete(1);
      await Future<void>.delayed(budget);

      expect(advanced, isFalse);
      expect(requests, 1, reason: 'an expired wait issues no further request');
    });

    test('never pauses longer than the budget it has left', () async {
      final pauses = <Duration>[];
      final advanced = await _watchdog(
        pollFrameAdvance(
          frames: () async => 0,
          before: 0,
          cap: const Duration(milliseconds: 4),
          delay: (duration) {
            pauses.add(duration);
            return Future<void>.delayed(duration);
          },
        ),
      );

      expect(advanced, isFalse);
      expect(pauses, isNotEmpty);
      expect(pauses, everyElement(lessThan(const Duration(milliseconds: 10))));
    });

    test('a zero cap still probes once and accepts a ready response', () async {
      var requests = 0;
      final advanced = await _watchdog(
        pollFrameAdvance(
          frames: () async {
            requests++;
            return 1;
          },
          before: 0,
          cap: Duration.zero,
        ),
      );

      expect(advanced, isTrue);
      expect(requests, 1);
    });

    test('a service error stays a service error', () async {
      final error = RPCError('info', RPCErrorKind.kServiceDisappeared.code);
      await expectLater(
        _watchdog(
          pollFrameAdvance(
            frames: () async => throw error,
            before: 0,
            cap: budget,
          ),
        ),
        throwsA(same(error)),
      );
    });
  });

  group('waitForDriverLocator', () {
    final locator = DriverLocator.byKey('save');

    test('times out when the tree response never completes', () async {
      await expectLater(
        _watchdog(
          waitForDriverLocator(
            locator,
            fetchTree: () => Completer<DriverTree>().future,
            timeout: budget,
          ),
        ),
        throwsA(_timedOut('no tree snapshot')),
      );
    });

    test('a match that arrives after the timeout is not returned', () async {
      final response = Completer<DriverTree>();
      var requests = 0;
      final wait = _watchdog(
        waitForDriverLocator(
          locator,
          fetchTree: () {
            requests++;
            return response.future;
          },
          timeout: budget,
        ),
      );
      await expectLater(wait, throwsA(_timedOut('no tree snapshot')));
      response.complete(DriverTree.fromJson(_treeJson(withSave: true)));
      await Future<void>.delayed(budget);

      expect(requests, 1, reason: 'an expired wait issues no further request');
    });

    test('a poll interval longer than the budget does not extend it', () async {
      var requests = 0;
      await expectLater(
        _watchdog(
          waitForDriverLocator(
            locator,
            fetchTree: () async {
              requests++;
              return DriverTree.fromJson(_treeJson(withSave: false));
            },
            timeout: budget,
            pollInterval: const Duration(minutes: 1),
          ),
        ),
        throwsA(_timedOut('0 matches')),
      );
      expect(requests, 1, reason: 'no probe starts once the budget is spent');
    });

    test('a service error stays a service error', () async {
      final error = RPCError('tree', RPCErrorKind.kServiceDisappeared.code);
      await expectLater(
        _watchdog(
          waitForDriverLocator(
            locator,
            fetchTree: () async => throw error,
            timeout: budget,
          ),
        ),
        throwsA(same(error)),
      );
    });
  });

  group('waitForDriverText', () {
    test('says no frame was captured when the first capture stalls', () async {
      await expectLater(
        _watchdog(
          waitForDriverText(
            'READY',
            capture: () => Completer<DriverFrame>().future,
            timeout: budget,
          ),
        ),
        throwsA(_timedOut('no frame was captured')),
      );
    });

    test(
      'reports the last captured frame when a later capture stalls',
      () async {
        var requests = 0;
        await expectLater(
          _watchdog(
            waitForDriverText(
              'READY',
              capture: () {
                requests++;
                return requests == 1
                    ? Future<DriverFrame>.value(_frame('LOADING'))
                    : Completer<DriverFrame>().future;
              },
              timeout: budget,
              pollInterval: Duration.zero,
            ),
          ),
          throwsA(_timedOut('Last frame:\nLOADING')),
        );
        expect(requests, 2);
      },
    );

    test('returns the frame that arrives inside the budget', () async {
      var requests = 0;
      final frame = await _watchdog(
        waitForDriverText(
          'READY',
          capture: () async => _frame(++requests < 3 ? 'LOADING' : 'READY'),
          pollInterval: Duration.zero,
        ),
      );

      expect(frame.lines, ['READY']);
      expect(requests, 3);
    });

    test('a frame that arrives after the timeout is not returned', () async {
      final response = Completer<DriverFrame>();
      var requests = 0;
      await expectLater(
        _watchdog(
          waitForDriverText(
            'READY',
            capture: () {
              requests++;
              return response.future;
            },
            timeout: budget,
          ),
        ),
        throwsA(_timedOut('no frame was captured')),
      );
      response.complete(_frame('READY'));
      await Future<void>.delayed(budget);

      expect(requests, 1, reason: 'an expired wait issues no further request');
    });

    test('a service error stays a service error', () async {
      final error = RPCError('capture', RPCErrorKind.kServiceDisappeared.code);
      await expectLater(
        _watchdog(
          waitForDriverText(
            'READY',
            capture: () async => throw error,
            timeout: budget,
          ),
        ),
        throwsA(same(error)),
      );
    });
  });

  group('PollDeadline', () {
    test('clamps what is left at zero and reports expiry', () {
      var elapsed = Duration.zero;
      final deadline = PollDeadline(
        const Duration(milliseconds: 30),
        elapsed: () => elapsed,
      );

      expect(deadline.remaining, const Duration(milliseconds: 30));
      expect(deadline.isExpired, isFalse);
      elapsed = const Duration(milliseconds: 29);
      expect(deadline.remaining, const Duration(milliseconds: 1));
      elapsed = const Duration(milliseconds: 45);
      expect(deadline.remaining, Duration.zero);
      expect(deadline.isExpired, isTrue);
    });

    test('pauses for the interval or for what is left, whichever is less', () {
      var elapsed = Duration.zero;
      final pauses = <Duration>[];
      Future<void> record(Duration duration) async => pauses.add(duration);
      final deadline = PollDeadline(
        const Duration(milliseconds: 30),
        elapsed: () => elapsed,
      );

      deadline.pause(const Duration(milliseconds: 10), delay: record);
      elapsed = const Duration(milliseconds: 26);
      deadline.pause(const Duration(milliseconds: 10), delay: record);

      expect(pauses, const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 4),
      ]);
    });
  });

  group('waitForAbsentDriverLocator', () {
    final locator = DriverLocator.byKey('save');

    test('times out when the tree response never completes', () async {
      await expectLater(
        _watchdog(
          waitForAbsentDriverLocator(
            locator,
            fetchTree: () => Completer<DriverTree>().future,
            timeout: budget,
          ),
        ),
        throwsA(_timedOut('no tree snapshot')),
      );
    });

    test('a poll interval longer than the budget does not extend it', () async {
      await expectLater(
        _watchdog(
          waitForAbsentDriverLocator(
            locator,
            fetchTree: () async =>
                DriverTree.fromJson(_treeJson(withSave: true)),
            timeout: budget,
            pollInterval: const Duration(minutes: 1),
          ),
        ),
        throwsA(_timedOut('1 matches remain')),
      );
    });
  });
}

Matcher _timedOut(String detail) => isA<StateError>().having(
  (error) => error.message,
  'message',
  allOf(contains('Timed out'), contains(detail)),
);

DriverFrame _frame(String row) => DriverFrame.fromJson(<String, Object?>{
  'type': 'Success',
  'width': row.length,
  'height': 1,
  'lines': <Object?>[row],
  'cursor': <String, Object?>{
    'visible': false,
    'x': 0,
    'y': 0,
    'style': 'block',
    'color': '#ffffff',
    'blinking': false,
  },
});

/// Fails a case that outlives any deadline it could legitimately be testing.
Future<T> _watchdog<T>(Future<T> wait) => wait.timeout(
  const Duration(seconds: 2),
  onTimeout: () => throw StateError('The wait outlived its own deadline'),
);

Map<String, Object?> _treeJson({required bool withSave}) => <String, Object?>{
  'type': 'Success',
  'root': <String, Object?>{
    'type': 'Root',
    'key': null,
    'text': null,
    'focused': false,
    'hasFocusedDescendant': false,
    'hitPoint': null,
    'children': <Object?>[
      if (withSave)
        <String, Object?>{
          'type': 'Button',
          'key': 'save',
          'text': null,
          'focused': false,
          'hasFocusedDescendant': false,
          'hitPoint': <String, Object?>{'x': 1, 'y': 1},
          'children': <Object?>[],
        },
    ],
  },
};
