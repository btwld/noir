@TestOn('vm')
library;

import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

/// A text-only frame, the shape `NoirDriver.capture` returns.
DriverFrame _textFrame() => DriverFrame.fromJson(<String, dynamic>{
  'width': 12,
  'height': 3,
  'lines': <String>['Noir Counter', '  Count: 0', ''],
  'cursor': <String, Object?>{
    'visible': true,
    'x': 2,
    'y': 1,
    'style': 'block',
    'color': '#ffffff',
    'blinking': false,
  },
});

/// A cells frame, the shape `NoirDriver.captureCells` returns.
DriverFrame _cellsFrame() => DriverFrame.fromJson(<String, dynamic>{
  'width': 2,
  'height': 1,
  'lines': <String>['ab'],
  'rows': <Map<String, Object?>>[
    <String, Object?>{
      'chars': <String>['a', 'b'],
      'fg': <String>['#ff0000', '#00ff00'],
      'bg': <String>['#000000', '#000000'],
      'attrs': <int>[0, 1],
    },
  ],
  'cursor': <String, Object?>{
    'visible': false,
    'x': 0,
    'y': 0,
    'style': 'block',
    'color': '#ffffff',
    'blinking': false,
  },
});

/// The failure text `expect` would print for [matcher] against [frame].
String _mismatch(DriverFrame frame, Matcher matcher) {
  final state = <Object?, Object?>{};
  expect(matcher.matches(frame, state), isFalse);
  return matcher
      .describeMismatch(frame, StringDescription(), state, false)
      .toString();
}

void main() {
  group('containsText', () {
    test('matches a substring of any painted row', () {
      expect(_textFrame(), DriverFrameMatchers.containsText('Count: 0'));
    });

    test('prints the captured frame when it does not match', () {
      final mismatch = _mismatch(
        _textFrame(),
        DriverFrameMatchers.containsText('Count: 9'),
      );

      // The whole point of the matcher: a failure shows the frame, so a
      // reader does not need a hand-written `reason:` to see what painted.
      expect(mismatch, contains('Noir Counter'));
      expect(mismatch, contains('Count: 0'));
    });
  });

  group('hasCharAt', () {
    test('reads a cell from a cells capture', () {
      expect(_cellsFrame(), DriverFrameMatchers.hasCharAt(1, 0, 'b'));
    });

    test('reports the actual character and the frame', () {
      final mismatch = _mismatch(
        _cellsFrame(),
        DriverFrameMatchers.hasCharAt(0, 0, 'z'),
      );

      expect(mismatch, contains('"a"'));
      expect(mismatch, contains('ab'));
    });

    test('explains that a text capture carries no cells', () {
      final mismatch = _mismatch(
        _textFrame(),
        DriverFrameMatchers.hasCharAt(0, 0, 'N'),
      );

      expect(mismatch, contains('captureCells'));
    });

    test('rejects a position outside the frame', () {
      final mismatch = _mismatch(
        _cellsFrame(),
        DriverFrameMatchers.hasCharAt(9, 0, 'a'),
      );

      expect(mismatch, contains('outside'));
    });
  });

  group('color matchers', () {
    test('match a cell foreground and background', () {
      expect(
        _cellsFrame(),
        DriverFrameMatchers.hasColorAt(0, 0, DriverColor.parse('#ff0000')),
      );
      expect(
        _cellsFrame(),
        DriverFrameMatchers.hasBackgroundAt(1, 0, DriverColor.parse('#000000')),
      );
    });

    test('report the actual color as hex', () {
      final mismatch = _mismatch(
        _cellsFrame(),
        DriverFrameMatchers.hasColorAt(0, 0, DriverColor.parse('#0000ff')),
      );

      expect(mismatch, contains('#ff0000'));
    });
  });

  group('cursorAt', () {
    test('matches a visible cursor and skips a null coordinate', () {
      expect(_textFrame(), DriverFrameMatchers.cursorAt(2, 1));
      expect(_textFrame(), DriverFrameMatchers.cursorAt(null, 1));
      expect(_textFrame(), DriverFrameMatchers.cursorAt(2, null));
    });

    test('reports a hidden cursor as hidden', () {
      final mismatch = _mismatch(
        _cellsFrame(),
        DriverFrameMatchers.cursorAt(0, 0),
      );

      expect(mismatch, contains('hidden'));
    });

    test('reports the actual position', () {
      final mismatch = _mismatch(
        _textFrame(),
        DriverFrameMatchers.cursorAt(5, 5),
      );

      expect(mismatch, contains('(2, 1)'));
    });
  });
}
