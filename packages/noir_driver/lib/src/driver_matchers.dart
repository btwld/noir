/// Matchers over a captured drive-mode frame.
///
/// These exist for their failure output. `expect(frame.contains('x'), isTrue)`
/// reports `Expected: true / Actual: <false>`, which says nothing about what
/// the app actually painted, so drive tests ended up hand-appending
/// `reason: frame.lines.join('\n')` to every assertion. Each matcher here
/// prints the captured frame instead, the way [NoirDriver.waitForText] already
/// does when it times out.
///
/// ```dart
/// expect(await driver.capture(), DriverFrameMatchers.containsText('Count: 1'));
/// ```
///
/// This depends on `package:matcher` rather than `package:test` so it stays
/// usable from any driver, not only from a test.
library;

import 'package:matcher/matcher.dart';

import 'noir_driver.dart';

/// Matchers for a [DriverFrame] captured from a driven app.
abstract final class DriverFrameMatchers {
  /// Matches when any painted row contains [text].
  ///
  /// This reads painted cells, like [NoirDriver.waitForText], not the
  /// `Text` / `RichText` source that [DriverLocator.byText] matches.
  static Matcher containsText(String text) => _ContainsText(text);

  /// Matches when the cell at ([x], [y]) resolves to [expected].
  ///
  /// Needs a [NoirDriver.captureCells] frame; a text capture carries no cells.
  static Matcher hasCharAt(int x, int y, String expected) =>
      _HasCellValue(x, y, expected, _CellField.char);

  /// Matches the foreground color of the cell at ([x], [y]).
  static Matcher hasColorAt(int x, int y, DriverColor expected) =>
      _HasCellValue(x, y, expected.toAnsiHex(), _CellField.foreground);

  /// Matches the background color of the cell at ([x], [y]).
  static Matcher hasBackgroundAt(int x, int y, DriverColor expected) =>
      _HasCellValue(x, y, expected.toAnsiHex(), _CellField.background);

  /// Matches a visible cursor at ([x], [y]); a null coordinate is not checked.
  static Matcher cursorAt(int? x, int? y) => _CursorAt(x, y);
}

/// Renders the frame the way a driven terminal showed it.
///
/// Rows are numbered because a cell matcher's coordinates are otherwise
/// tedious to count out by hand in a failure report.
String _describeFrame(DriverFrame frame) {
  final width = '${frame.lines.length - 1}'.length;
  return <String>[
    'captured ${frame.width}x${frame.height} frame:',
    for (var y = 0; y < frame.lines.length; y++)
      '  ${'$y'.padLeft(width)} | ${frame.lines[y]}',
  ].join('\n');
}

class _ContainsText extends Matcher {
  _ContainsText(this.text);

  final String text;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) =>
      item is DriverFrame && item.contains(text);

  @override
  Description describe(Description description) =>
      description.add('a frame painting "$text"');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatch,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! DriverFrame) {
      return mismatch.add('is not a DriverFrame');
    }
    return mismatch.add('no row contains it.\n${_describeFrame(item)}');
  }
}

enum _CellField {
  char('character'),
  foreground('foreground'),
  background('background');

  const _CellField(this.label);

  final String label;

  String read(DriverCell cell) => switch (this) {
    _CellField.char => cell.char,
    _CellField.foreground => cell.foreground.toAnsiHex(),
    _CellField.background => cell.background.toAnsiHex(),
  };
}

/// Why a cell lookup could not be compared, or null when it could.
enum _CellFailure {
  /// The frame came from `capture`, so it carries no per-cell detail.
  noCells,

  /// The coordinate is not inside the captured frame.
  outOfRange,
}

class _HasCellValue extends Matcher {
  _HasCellValue(this.x, this.y, this.expected, this.field);

  final int x;
  final int y;
  final String expected;
  final _CellField field;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! DriverFrame) return false;
    if (item.rows.isEmpty) {
      matchState['failure'] = _CellFailure.noCells;
      return false;
    }
    if (y < 0 || y >= item.rows.length || x < 0 || x >= item.rows[y].length) {
      matchState['failure'] = _CellFailure.outOfRange;
      return false;
    }
    matchState['actual'] = field.read(item.rows[y][x]);
    return matchState['actual'] == expected;
  }

  @override
  Description describe(Description description) =>
      description.add('${field.label} "$expected" at ($x, $y)');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatch,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! DriverFrame) {
      return mismatch.add('is not a DriverFrame');
    }
    final detail = switch (matchState['failure']) {
      _CellFailure.noCells =>
        'the frame carries no cells. Capture it with '
            'NoirDriver.captureCells to assert on characters and colors.',
      _CellFailure.outOfRange =>
        '($x, $y) is outside the captured ${item.width}x${item.height} frame.',
      _ => 'the ${field.label} is "${matchState['actual']}".',
    };
    return mismatch.add('$detail\n${_describeFrame(item)}');
  }
}

class _CursorAt extends Matcher {
  _CursorAt(this.x, this.y);

  final int? x;
  final int? y;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    if (item is! DriverFrame || !item.cursor.visible) return false;
    return (x == null || item.cursor.x == x) &&
        (y == null || item.cursor.y == y);
  }

  @override
  Description describe(Description description) =>
      description.add('a visible cursor at (${x ?? 'any'}, ${y ?? 'any'})');

  @override
  Description describeMismatch(
    Object? item,
    Description mismatch,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    if (item is! DriverFrame) {
      return mismatch.add('is not a DriverFrame');
    }
    final cursor = item.cursor;
    final detail = cursor.visible
        ? 'the cursor is at (${cursor.x}, ${cursor.y}).'
        : 'the cursor is hidden.';
    return mismatch.add('$detail\n${_describeFrame(item)}');
  }
}
