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

  test('layout-time element building is confined to LayoutBuilder', () {
    // Building elements from inside layout is a deliberate ownership seam:
    // only LayoutBuilder may do it, and only these owners may finalize the
    // element tree. A new caller must be added here on purpose.
    const allowed = <String>{
      'lib/src/framework/owner.dart',
      'lib/src/app/tui_binding.dart',
      'lib/src/widgets/layout_builder.dart',
    };
    final offenders = <String>[];

    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (allowed.contains(path)) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        // Prose may name the method; only a call is a seam.
        if (line.startsWith('//')) {
          continue;
        }
        if (line.contains('finalizeTree(')) {
          offenders.add('$path:${i + 1}: $line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Only BuildOwner, TuiBinding, and LayoutBuilder may finalize the '
          'element tree; a layout-time build elsewhere is a new seam.',
    );
  });

  test('rendering does not depend on the element layer', () {
    // Render objects may import widget configuration types (spans, styles,
    // flex data), but never elements, the build owner, or the focus tree.
    final offenders = <String>[];

    for (final entity in Directory(
      'lib/src/rendering',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('import ') && !line.startsWith('export ')) {
          continue;
        }
        if (line.contains('../framework/') || line.contains('src/framework/')) {
          offenders.add('${entity.path}:${i + 1}: $line');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'Render objects lay out and paint; they must not reach the element '
          'layer. LayoutBuilder owns that bridge from the widgets side.',
    );
  });
}
