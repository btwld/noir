import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('wheel API has one direction/magnitude payload without scalar shim', () {
    final inputSource = File('lib/src/core/input.dart').readAsStringSync();
    final mouseScroll = _classBody(inputSource, 'MouseScroll');

    expect(mouseScroll, contains('final MouseScrollDirection direction;'));
    expect(mouseScroll, contains('final int magnitude;'));
    expect(inputSource, isNot(contains('scrollDelta')));
    expect(inputSource, isNot(contains('MouseScrollAxis')));
    expect(inputSource, isNot(contains('get axis')));
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
