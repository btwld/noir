import 'dart:io';

import 'package:test/test.dart';

/// Locks the migrated boundary between named terminal chrome and ordinary text.
///
/// Migrated application chrome and status markers use [Icons] so their width
/// policy and intent are visible at the call site. Prose, user and document
/// content, box drawing, progress and sparkline pixels, spinner frames, and
/// raster-font implementation glyphs remain literal. In particular, this test
/// does not ban emoji from normal text: Noir measures that content through its
/// grapheme-width model.
void main() {
  test('migrated chrome and status glyphs use Icons members', () {
    const expectedReferences = <String, List<String>>{
      'lib/src/widgets/checkbox.dart': ['Icons.squareOutline', 'Icons.square'],
      'lib/src/widgets/switch.dart': ['Icons.circleOutline', 'Icons.circle'],
      'lib/src/widgets/data_table.dart': [
        'Icons.triangleUp',
        'Icons.triangleDown',
      ],
      'lib/src/widgets/list_view.dart': [
        'Icons.triangleUp',
        'Icons.triangleDown',
      ],
      'lib/src/widgets/select.dart': ['Icons.triangleUp', 'Icons.triangleDown'],
      'lib/src/widgets/tab_select.dart': [
        'Icons.chevronLeft',
        'Icons.chevronRight',
        'Icons.ellipsis',
      ],
      'lib/src/tools/patch_manager/patch_theme.dart': [
        'Icons.circleDotted',
        'Icons.lozenge',
        'Icons.close',
        'Icons.bang',
        'Icons.pointerRight',
      ],
      'example/counter.dart': ['Icons.plus'],
      'example/components_demo.dart': ['Icons.dot'],
      'example/like_reactor.dart': [
        'Icons.sparkle',
        'Icons.sparkleOutline',
        'Icons.starSmall',
        'Icons.bulletSmall',
      ],
      'example/listview_demo.dart': ['Icons.pointerRight'],
      'example/pub_search/app.dart': ['Icons.caretDown'],
      'example/pub_search/package_detail.dart': [
        'Icons.arrowUpRight',
        'Icons.bulletSmall',
        'Icons.arrowBranchDown',
      ],
      'README.md': ['Text(Icons.plus)'],
    };
    const forbiddenLiterals = <String, List<String>>{
      'lib/src/widgets/checkbox.dart': ["_unchecked = '□'", "_checked = '■'"],
      'lib/src/widgets/switch.dart': ["_off = '○'", "_on = '●'"],
      'lib/src/widgets/data_table.dart': [
        "_ascending = '▲'",
        "_descending = '▼'",
      ],
      'lib/src/widgets/list_view.dart': ["return '▲'", "return '▼'"],
      'lib/src/widgets/select.dart': ["? '▲'", "? '▼'"],
      'lib/src/widgets/tab_select.dart': ["'‹'", "'›'", "'…'"],
      'lib/src/tools/patch_manager/patch_theme.dart': [
        "=> '○'",
        "=> '◆'",
        "=> '✗'",
        "=> '!'",
        "caret = '▶'",
      ],
      'example/counter.dart': ["Text('+')"],
      'example/components_demo.dart': ["Text('·')"],
      'example/like_reactor.dart': [
        "return '♥'",
        "return '♡'",
        "return '✦'",
        "return '·'",
      ],
      'example/listview_demo.dart': ["selected ? '▶'"],
      'example/pub_search/app.dart': ["} ▾'"],
      'example/pub_search/package_detail.dart': [
        "'View changelog ↗'",
        "'● '",
        "'  ↳ ",
      ],
      'README.md': ["Text('+')"],
    };
    final violations = <String>[];

    for (final entry in expectedReferences.entries) {
      final source = File(entry.key).readAsStringSync();
      for (final reference in entry.value) {
        if (!source.contains(reference)) {
          violations.add('${entry.key}: missing $reference');
        }
      }
      for (final literal in forbiddenLiterals[entry.key] ?? const <String>[]) {
        if (source.contains(literal)) {
          violations.add('${entry.key}: literal $literal');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Migrated application chrome and status markers must keep using '
          'their named Icons member. Prose, document content, and rendering '
          'primitives remain literal.\n${violations.join('\n')}',
    );
  });
}
