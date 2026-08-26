import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

/// Checks the [Icons] width-group rule where it actually matters: the rendered
/// glyphs of a control whose value flips.
///
/// `icon_width_class_test.dart` proves each declared group is uniform, but it
/// does not read what a widget actually puts on screen. A future edit could
/// pair two glyphs from different groups and still pass it. This test captures
/// the real frames and compares the glyphs the user sees.
void main() {
  group('state pairs stay inside one Icons width group', () {
    test('Checkbox paints the same width class for both values', () {
      expect(
        _toggleGlyphs(
          ({required value}) => Checkbox(value: value, onChanged: (_) {}),
        ),
        _sameWidthGroup,
      );
    });

    test('Switch paints the same width class for both values', () {
      expect(
        _toggleGlyphs(
          ({required value}) => Switch(value: value, onChanged: (_) {}),
        ),
        _sameWidthGroup,
      );
    });
  });
}

/// Renders [build] with false and then true, returning the glyph each frame
/// paints in the control cell.
Set<String> _toggleGlyphs(Widget Function({required bool value}) build) {
  final glyphs = <String>{};
  for (final value in [false, true]) {
    final capture = BufferCapture(width: 12, height: 1);
    try {
      glyphs.add(capture.capture(build(value: value)).getChar(0, 0));
    } finally {
      capture.dispose();
    }
  }
  expect(glyphs, hasLength(2), reason: 'the two values must differ visually');
  return glyphs;
}

/// Passes when every glyph in the set belongs to the same [Icons] group.
final _sameWidthGroup = predicate<Set<String>>((glyphs) {
  final groups = glyphs.map(_group).toSet();
  return groups.length == 1;
}, 'all drawn from one Icons width group');

/// Which declared [Icons] group a rendered glyph came from.
String _group(String glyph) {
  if (_narrow.contains(glyph)) return 'narrow';
  if (_ambiguous.contains(glyph)) return 'ambiguous';
  throw StateError(
    'The widget painted "$glyph", which is not an Icons member. Rendered '
    'glyphs must come from Icons so their width class is known.',
  );
}

const _narrow = <String>{
  Icons.check,
  Icons.close,
  Icons.closeHeavy,
  Icons.closeThin,
  Icons.caretUp,
  Icons.caretDown,
  Icons.caretLeft,
  Icons.caretRight,
  Icons.caretUpOutline,
  Icons.caretDownOutline,
  Icons.pointerRight,
  Icons.pointerLeft,
  Icons.squareRounded,
  Icons.rectangle,
  Icons.rectangleOutline,
  Icons.bar,
  Icons.barOutline,
  Icons.lozenge,
  Icons.lozengeOutline,
  Icons.fisheye,
  Icons.circleDotted,
  Icons.circleSmall,
  Icons.bulletSmall,
  Icons.bulletOutline,
  Icons.sparkle,
  Icons.sparkleOutline,
  Icons.starHollow,
  Icons.starSmall,
};

const _ambiguous = <String>{
  Icons.square,
  Icons.squareOutline,
  Icons.circle,
  Icons.circleOutline,
  Icons.diamond,
  Icons.diamondOutline,
  Icons.triangleUp,
  Icons.triangleDown,
  Icons.triangleUpOutline,
  Icons.triangleDownOutline,
  Icons.bullseye,
  Icons.circleLarge,
  Icons.star,
  Icons.starOutline,
};
