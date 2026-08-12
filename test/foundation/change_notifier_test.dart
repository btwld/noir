// ignore_for_file: cascade_invocations, unnecessary_lambdas

import 'dart:async';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('ChangeNotifier', () {
    test('adds, removes, and reports listeners', () {
      final notifier = ChangeNotifier();
      var calls = 0;
      void listener() => calls++;

      expect(notifier.hasListeners, isFalse);
      notifier.addListener(listener);
      expect(notifier.hasListeners, isTrue);

      notifier.notifyListeners();
      expect(calls, 1);

      notifier.removeListener(listener);
      expect(notifier.hasListeners, isFalse);
      notifier.notifyListeners();
      expect(calls, 1);
    });

    test(
      'supports duplicate listeners and removes one registration at a time',
      () {
        final notifier = ChangeNotifier();
        var calls = 0;
        void listener() => calls++;

        notifier
          ..addListener(listener)
          ..addListener(listener);
        notifier.notifyListeners();
        expect(calls, 2);

        notifier.removeListener(listener);
        notifier.notifyListeners();
        expect(calls, 3);
      },
    );

    test('uses a stable listener snapshot during notification', () {
      final notifier = ChangeNotifier();
      final events = <String>[];

      void second() => events.add('second');
      void first() {
        events.add('first');
        notifier
          ..removeListener(second)
          ..addListener(() => events.add('third'));
      }

      notifier
        ..addListener(first)
        ..addListener(second);

      notifier.notifyListeners();
      expect(events, ['first']);

      notifier.notifyListeners();
      expect(events, ['first', 'first', 'third']);
    });

    test('reports every listener failure and continues the snapshot', () {
      final notifier = ChangeNotifier();
      final log = <String>[];
      final reports = <(Object, StackTrace, Zone)>[];
      final firstError = Exception('first listener failed');
      final secondError = StateError('second listener failed');
      final firstStack = StackTrace.fromString('first listener stack');
      final secondStack = StackTrace.fromString('second listener stack');
      final boundaryKey = Object();
      final boundaryValue = Object();
      late Zone notificationZone;

      notifier
        ..addListener(() => log.add('ordinary-1'))
        ..addListener(() {
          log.add('throw-1');
          Error.throwWithStackTrace(firstError, firstStack);
        })
        ..addListener(() => log.add('ordinary-2'))
        ..addListener(() {
          log.add('throw-2');
          Error.throwWithStackTrace(secondError, secondStack);
        })
        ..addListener(() => log.add('final'));

      notificationZone = Zone.current.fork(
        zoneValues: {boundaryKey: boundaryValue},
        specification: ZoneSpecification(
          handleUncaughtError: (_, _, zone, error, stackTrace) {
            reports.add((error, stackTrace, zone));
            log.add(identical(error, firstError) ? 'report-1' : 'report-2');
          },
        ),
      );
      notificationZone.runGuarded(notifier.notifyListeners);

      expect(log, [
        'ordinary-1',
        'throw-1',
        'report-1',
        'ordinary-2',
        'throw-2',
        'report-2',
        'final',
      ]);
      expect(reports, hasLength(2));
      expect(identical(reports[0].$1, firstError), isTrue);
      expect(reports[0].$2.toString(), firstStack.toString());
      expect(reports[0].$3, same(notificationZone));
      expect(reports[0].$3[boundaryKey], same(boundaryValue));
      expect(identical(reports[1].$1, secondError), isTrue);
      expect(reports[1].$2.toString(), secondStack.toString());
      expect(reports[1].$3, same(notificationZone));
      expect(reports[1].$3[boundaryKey], same(boundaryValue));
    });

    test('preserves listener mutations when the mutator throws', () {
      final notifier = ChangeNotifier();
      final log = <String>[];
      final reports = <Object>[];
      final listenerError = StateError('mutating listener failed');
      var isFirstPass = true;

      void pending() => log.add('pending');
      void added() => log.add('added');
      void survivor() => log.add('survivor');
      void mutator() {
        log.add('mutator');
        if (isFirstPass) {
          isFirstPass = false;
          notifier
            ..removeListener(pending)
            ..addListener(added);
          throw listenerError;
        }
      }

      notifier
        ..addListener(mutator)
        ..addListener(pending)
        ..addListener(pending)
        ..addListener(survivor);

      runZonedGuarded(
        () {
          notifier.notifyListeners();
          log.add('second-pass');
          notifier.notifyListeners();
        },
        (error, _) {
          reports.add(error);
          log.add('report');
        },
      );

      expect(log, [
        'mutator',
        'report',
        'pending',
        'pending',
        'survivor',
        'second-pass',
        'mutator',
        'pending',
        'survivor',
        'added',
      ]);
      expect(reports, hasLength(1));
      expect(identical(reports.single, listenerError), isTrue);
    });

    test('isolates listener failures in nested notifications', () {
      final notifier = ChangeNotifier();
      final log = <String>[];
      final reports = <(Object, StackTrace)>[];
      final innerError = StateError('inner listener failed');
      final outerError = StateError('outer listener failed');
      final innerStack = StackTrace.fromString('inner listener stack');
      final outerStack = StackTrace.fromString('outer listener stack');
      var inNestedNotification = false;

      notifier
        ..addListener(() {
          if (inNestedNotification) {
            log.add('inner-entry');
            return;
          }
          log.add('outer-enter');
          inNestedNotification = true;
          notifier.notifyListeners();
          inNestedNotification = false;
          log.add('outer-resume');
        })
        ..addListener(() {
          if (inNestedNotification) {
            log.add('inner-throw');
            Error.throwWithStackTrace(innerError, innerStack);
          }
          log.add('outer-throw');
          Error.throwWithStackTrace(outerError, outerStack);
        })
        ..addListener(
          () => log.add(
            inNestedNotification ? 'inner-survivor' : 'outer-survivor',
          ),
        );

      runZonedGuarded(notifier.notifyListeners, (error, stackTrace) {
        reports.add((error, stackTrace));
        log.add(identical(error, innerError) ? 'report-inner' : 'report-outer');
      });

      expect(log, [
        'outer-enter',
        'inner-entry',
        'inner-throw',
        'report-inner',
        'inner-survivor',
        'outer-resume',
        'outer-throw',
        'report-outer',
        'outer-survivor',
      ]);
      expect(reports, hasLength(2));
      expect(identical(reports[0].$1, innerError), isTrue);
      expect(reports[0].$2.toString(), innerStack.toString());
      expect(identical(reports[1].$1, outerError), isTrue);
      expect(reports[1].$2.toString(), outerStack.toString());
    });

    test('dispose is idempotent and rejects new listeners', () {
      final notifier = ChangeNotifier()..addListener(() {});

      notifier
        ..dispose()
        ..dispose();

      expect(notifier.hasListeners, isFalse);
      expect(() => notifier.addListener(() {}), throwsStateError);
      expect(() => notifier.notifyListeners(), returnsNormally);
    });
  });

  group('Listenable.merge', () {
    test('notifies when any child listenable changes', () {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      final merged = Listenable.merge([first, null, second]);
      var calls = 0;

      merged.addListener(() => calls++);
      first.notifyListeners();
      second.notifyListeners();

      expect(calls, 2);
    });

    test('removeListener stops forwarding from all child listenables', () {
      final first = ChangeNotifier();
      final second = ChangeNotifier();
      final merged = Listenable.merge([first, second]);
      var calls = 0;
      void listener() => calls++;

      merged.addListener(listener);
      first.notifyListeners();
      expect(calls, 1);

      merged.removeListener(listener);
      first.notifyListeners();
      second.notifyListeners();
      expect(calls, 1);
    });
  });
}
