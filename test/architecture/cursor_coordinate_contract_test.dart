import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'Renderer cursor API converts zero-based cells to native coordinates',
    () {
      final cursorSource = File('lib/src/core/cursor.dart').readAsStringSync();

      expect(cursorSource, contains('zero-based terminal cells'));
      expect(cursorSource, contains('one-based'));
      expect(
        cursorSource,
        contains('bindings.setCursorPosition(handle, x + 1, y + 1, visible);'),
      );
    },
  );
}
