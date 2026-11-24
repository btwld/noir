import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TuiApp no longer owns frame timing or coalescing', () {
    final source = File('lib/src/app/app.dart').readAsStringSync();
    final body = _classBody(source, 'TuiApp');

    expect(source, isNot(contains('scheduleMicrotask')));
    expect(source, isNot(contains('_frameScheduled')));
    expect(source, isNot(contains('_firstFrameTime')));
    expect(source, isNot(contains('_currentTimestamp')));
    expect(body, isNot(contains('SchedulerBinding')));
  });

  test('TuiBinding owns frame scheduling integration', () {
    final source = File('lib/src/app/tui_binding.dart').readAsStringSync();
    final body = _classBody(source, 'TuiBinding');

    expect(body, contains('SchedulerBinding'));
    expect(body, contains('_scheduler.setFrameCallback(_drawFrame)'));
    expect(body, contains('_owner.setFrameCallback(_scheduler.scheduleFrame)'));
    expect(source, isNot(contains('scheduleMicrotask')));
    expect(body, isNot(contains('scheduleMicrotask')));
  });

  test('InlineHost defers nothing of its own', () {
    final source = File('lib/src/app/inline_host.dart').readAsStringSync();
    final body = _classBody(source, 'InlineHost');

    // A new width is applied where it is read, and the host is torn down
    // where it ends. Both are safe on the spot because the host refuses to be
    // called while its tree is walked, so it has nothing to put off.
    expect(body, contains('_binding.isWalkingTree'));
    expect(body, isNot(contains('Timer')));
    expect(body, isNot(contains('scheduleMicrotask')));
  });

  test('TickerScheduler only owns ticker registry and dispatch', () {
    final source = File('lib/src/animation/ticker.dart').readAsStringSync();

    expect(source, isNot(contains('_frameScheduled')));
    expect(source, isNot(contains('Timer')));
    expect(source, isNot(contains('scheduleMicrotask')));
  });

  test('SchedulerBinding remains internal', () {
    final publicBarrel = File('lib/noir.dart').readAsStringSync();
    final lowLevelBarrel = File('lib/noir_low_level.dart').readAsStringSync();
    final ffiBarrel = File('lib/noir_ffi.dart').readAsStringSync();

    for (final source in [publicBarrel, lowLevelBarrel, ffiBarrel]) {
      expect(source, isNot(contains('scheduler_binding.dart')));
      expect(source, isNot(contains('SchedulerBinding')));
    }
  });
}

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex < 0) {
    throw StateError('Class $className not found');
  }
  final start = source.indexOf('{', classIndex);
  if (start < 0) {
    throw StateError('Class $className has no body');
  }
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 0x7b) depth++;
    if (code == 0x7d) {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('Class $className body is unterminated');
}
