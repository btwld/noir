/// Key and mouse names encoded to the escape bytes a real terminal sends.
///
/// The driven app accepts bytes only: `ext.noir.driver.sendBytes` feeds them
/// straight into the production ANSI parser. Keeping every name-to-sequence
/// decision on this side is what preserves that parser path — the app never
/// grows a second, synthetic input entry point.
///
/// The sequences mirror the repository's byte-level input helpers, which are
/// the ones the widget suite already trusts.
library;

import 'dart:convert';

/// Mouse buttons an SGR report can carry.
enum DriverMouseButton {
  /// Primary button, SGR button code 0.
  left(0),

  /// Middle button, SGR button code 1.
  middle(1),

  /// Secondary button, SGR button code 2.
  right(2);

  const DriverMouseButton(this.code);

  /// SGR button code for this button.
  final int code;
}

/// Wheel directions an SGR report can carry.
enum DriverScrollDirection {
  /// Wheel up, SGR button code 64.
  up(64),

  /// Wheel down, SGR button code 65.
  down(65),

  /// Wheel left, SGR button code 66.
  left(66),

  /// Wheel right, SGR button code 67.
  right(67);

  const DriverScrollDirection(this.code);

  /// SGR button code for this wheel direction.
  final int code;
}

/// Every key name [encodeKey] accepts, excluding the `ctrl-<a-z>` family.
List<String> get namedKeys => _namedKeys.keys.toList(growable: false);

/// Encodes a key [name] as the bytes a terminal would send for that key.
///
/// Accepts the names in [namedKeys] plus `ctrl-<a-z>`. Throws an
/// [ArgumentError] for anything else, so a typo in a script fails loudly
/// instead of silently sending nothing.
List<int> encodeKey(String name) {
  final normalized = name.trim().toLowerCase();
  final sequence = _namedKeys[normalized];
  if (sequence != null) {
    return utf8.encode(sequence);
  }
  if (normalized.startsWith('ctrl-') && normalized.length == 6) {
    final letter = normalized.codeUnitAt(5);
    if (letter >= 0x61 && letter <= 0x7a) {
      // Ctrl+letter is the letter's position in the alphabet: Ctrl+A is 0x01.
      return <int>[letter - 0x60];
    }
  }
  throw ArgumentError.value(
    name,
    'name',
    'Expected ctrl-<a-z> or one of: ${namedKeys.join(', ')}',
  );
}

/// Encodes [text] as the UTF-8 bytes a terminal sends while typing it.
List<int> encodeText(String text) => utf8.encode(text);

/// Encodes a press and release of [button] at the zero-based cell (x, y).
List<int> encodeClick(
  int x,
  int y, {
  DriverMouseButton button = DriverMouseButton.left,
}) => <int>[
  ..._encodeMouseReport(x, y, button.code, press: true),
  ..._encodeMouseReport(x, y, button.code, press: false),
];

/// Encodes one wheel notch in [direction] at the zero-based cell (x, y).
List<int> encodeScroll(int x, int y, DriverScrollDirection direction) =>
    _encodeMouseReport(x, y, direction.code, press: true);

const Map<String, String> _namedKeys = <String, String>{
  'up': '\x1b[A',
  'down': '\x1b[B',
  'right': '\x1b[C',
  'left': '\x1b[D',
  'enter': '\r',
  'tab': '\t',
  // A lone Escape is ambiguous until the next byte arrives, so the parser
  // holds it briefly before deciding. `waitStable` covers that delay.
  'esc': '\x1b',
  // Terminals send DEL for Backspace; the parser accepts BS and DEL alike.
  'backspace': '\x7f',
  'pgup': '\x1b[5~',
  'pgdn': '\x1b[6~',
};

/// SGR mouse report: `ESC [ < button ; column ; row M|m`, 1-indexed.
List<int> _encodeMouseReport(
  int x,
  int y,
  int buttonCode, {
  required bool press,
}) {
  if (x < 0 || y < 0) {
    throw ArgumentError('Mouse coordinates must be non-negative: ($x, $y)');
  }
  final finalByte = press ? 'M' : 'm';
  return utf8.encode('\x1b[<$buttonCode;${x + 1};${y + 1}$finalByte');
}
