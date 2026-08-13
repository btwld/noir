import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('production parents do not call child performBoxLayout directly', () {
    final offenders = <String>[];

    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.contains('.performBoxLayout(')) {
          continue;
        }
        // An override delegating to its own base class is not a parent
        // laying out a child; only cross-object calls are offenders.
        if (line.contains('super.performBoxLayout(')) {
          continue;
        }
        offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Parent render objects must call child.layout(...). '
          'performBoxLayout is the child override point.',
    );
  });
}
