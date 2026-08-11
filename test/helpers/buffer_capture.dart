// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import 'test_element_host.dart';

/// Captures terminal rendering output for testing.
///
/// This utility class allows you to render widgets to a virtual terminal
/// buffer and then inspect the actual character-by-character output,
/// including colors, attributes, and positioning.
///
/// Mount / layout / paint plumbing is delegated to [TestElementHost]; this
/// class adds the buffer-clear + cursor-snapshot + cell-extraction wrapper.
class BufferCapture {
  /// Creates a BufferCapture with the specified terminal dimensions.
  ///
  /// The default layout remains max-bounded and loose for focused widget
  /// captures. Pass [layoutConstraints] when the scene must model a specific
  /// root contract, such as a full terminal's tight dimensions.
  BufferCapture({this.width = 80, this.height = 24, this.layoutConstraints}) {
    _renderer = Renderer.create(width, height, testing: true);
    _buffer = _renderer.nextBuffer;
  }
  late Renderer _renderer;
  late Buffer _buffer;
  final int width;
  final int height;

  /// Optional root constraints forwarded to the shared layout host.
  final BoxConstraints? layoutConstraints;

  /// Renders a widget to the buffer and returns the captured output.
  ///
  /// This method matches TuiBinding's render pipeline:
  /// 1. Creates and mounts the widget element tree
  /// 2. Finds the root RenderObject
  /// 3. Flushes layout within the buffer constraints
  /// 4. Flushes paint from the root (children painted recursively by parents)
  /// 5. Returns a structured representation of the buffer content
  ///
  /// The returned [CapturedBuffer] also includes a [CapturedCursor] reflecting
  /// the post-paint state of the [BuildOwner.cursorController] (focus-driven
  /// widgets such as `TextInput` and `TextArea` set this during paint).
  CapturedBuffer capture(Widget widget) {
    // Clear the buffer
    _buffer.clear(Color.black);

    final host = TestElementHost(renderer: _renderer)
      ..mount(widget)
      ..pumpFrame(buffer: _buffer, constraints: layoutConstraints);

    // Capture and return the buffer content. Include the cursor snapshot
    // (taken before clearRenderer hides the cursor) for focus-aware tests.
    final cursor = CapturedCursor.fromController(host.owner.cursorController);
    final captured = CapturedBuffer.fromBuffer(_buffer, cursor: cursor);

    host.dispose();

    return captured;
  }

  /// Disposes of the renderer and buffer.
  void dispose() {
    _renderer.dispose();
  }
}

/// Represents the captured state of a terminal buffer.
///
/// This class provides various ways to inspect and verify the rendered
/// output, including character-by-character access, text extraction,
/// and color verification.
class CapturedBuffer {
  CapturedBuffer(this.cells, this.width, this.height, {CapturedCursor? cursor})
    : cursor = cursor ?? const CapturedCursor.hidden();

  /// Creates a CapturedBuffer from a Buffer instance.
  factory CapturedBuffer.fromBuffer(Buffer buffer, {CapturedCursor? cursor}) {
    final cells = <List<CapturedCell>>[];

    // Extract real cell data from buffer using DirectBufferAccess
    final direct = buffer.getDirectAccess();

    for (var y = 0; y < buffer.height; y++) {
      final row = <CapturedCell>[];
      for (var x = 0; x < buffer.width; x++) {
        // Read actual buffer content. The framework's native side packs
        // non-ASCII glyphs into a grapheme table; those cells contain a
        // 32-bit packed marker (high bit set) instead of a raw codepoint.
        // BufferCapture has no access to the grapheme table, so for packed
        // cells we substitute a single ASCII placeholder ('*') that
        // preserves cell alignment for text-position assertions without
        // exploding `String.fromCharCode`.
        final index = y * buffer.width + x;
        final code = direct.chars[index];
        final String char;
        if ((code & 0xC0000000) != 0) {
          char = '*';
        } else if (code == 0) {
          char = ' ';
        } else {
          char = String.fromCharCode(code);
        }
        final fg = direct.getForeground(x, y);
        final bg = direct.getBackground(x, y);
        final attr = direct.getAttributes(x, y);

        row.add(CapturedCell(char, fg, bg, attr));
      }
      cells.add(row);
    }

    return CapturedBuffer(cells, buffer.width, buffer.height, cursor: cursor);
  }
  final List<List<CapturedCell>> cells;
  final int width;
  final int height;

  /// Cursor state observed at the moment the buffer was captured. May be
  /// non-visible (`cursor.visible == false`) for non-focused widgets.
  final CapturedCursor cursor;

  /// Gets the cell at the specified position.
  CapturedCell getCell(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw ArgumentError('Position ($x, $y) is out of bounds');
    }
    return cells[y][x];
  }

  /// Gets the character at the specified position.
  String getChar(int x, int y) => getCell(x, y).char;

  /// Gets the foreground color at the specified position.
  Color getForegroundColor(int x, int y) => getCell(x, y).foreground;

  /// Gets the background color at the specified position.
  Color getBackgroundColor(int x, int y) => getCell(x, y).background;

  /// Converts the buffer to a plain text string.
  String toText() {
    final buffer = StringBuffer();
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        buffer.write(cells[y][x].char);
      }
      if (y < height - 1) buffer.writeln();
    }
    return buffer.toString();
  }

  /// Converts the buffer to a list of lines.
  List<String> toLines() {
    final lines = <String>[];
    for (var y = 0; y < height; y++) {
      final line = StringBuffer();
      for (var x = 0; x < width; x++) {
        line.write(cells[y][x].char);
      }
      lines.add(line.toString().trimRight());
    }
    return lines;
  }

  /// Finds all occurrences of a string in the buffer.
  List<BufferPosition> findText(String text) {
    final positions = <BufferPosition>[];
    final lines = toLines();

    for (var y = 0; y < lines.length; y++) {
      var index = 0;
      while (true) {
        index = lines[y].indexOf(text, index);
        if (index == -1) break;
        positions.add(BufferPosition(index, y));
        index++;
      }
    }

    return positions;
  }

  /// Checks if the buffer contains the specified text.
  bool containsText(String text) => findText(text).isNotEmpty;

  /// Gets a rectangular region of the buffer as text.
  String getRegion(int x, int y, int width, int height) {
    final buffer = StringBuffer();
    for (var row = y; row < y + height && row < this.height; row++) {
      for (var col = x; col < x + width && col < this.width; col++) {
        buffer.write(getChar(col, row));
      }
      if (row < y + height - 1) buffer.writeln();
    }
    return buffer.toString();
  }
}

/// Represents a single character cell in the captured buffer.
class CapturedCell {
  const CapturedCell(
    this.char,
    this.foreground,
    this.background,
    this.attributes,
  );
  final String char;
  final Color foreground;
  final Color background;
  final int attributes;

  /// Checks if this cell has the specified text attributes.
  bool hasAttribute(int attr) => (attributes & attr) != 0;

  /// Checks if this cell is bold.
  bool get isBold => hasAttribute(Attr.bold);

  @override
  String toString() =>
      'CapturedCell(char: "$char", fg: $foreground, bg: $background, attrs: $attributes)';
}

/// Represents a position in the buffer.
class BufferPosition {
  const BufferPosition(this.x, this.y);
  final int x;
  final int y;

  @override
  String toString() => 'BufferPosition($x, $y)';

  @override
  bool operator ==(Object other) =>
      other is BufferPosition && other.x == x && other.y == y;

  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

/// Cursor state captured alongside the buffer. Cursor positioning is driven
/// by ANSI escapes through `CursorController` and never lands in the buffer
/// itself; this snapshot is the only way for golden tests to assert on it.
class CapturedCursor {
  const CapturedCursor({
    required this.visible,
    required this.x,
    required this.y,
    required this.style,
    required this.color,
    required this.blinking,
  });

  const CapturedCursor.hidden()
    : visible = false,
      x = 0,
      y = 0,
      style = CursorStyle.block,
      color = Color.white,

      blinking = false;

  /// Snapshots the post-paint state of [controller] — the shared capture
  /// path for both `BufferCapture` and `TuiTestApp.captureFrame`.
  factory CapturedCursor.fromController(CursorController controller) =>
      CapturedCursor(
        visible: controller.isVisible,
        x: controller.x,
        y: controller.y,
        style: controller.style,
        color: controller.color,
        blinking: controller.blinking,
      );
  final bool visible;
  final int x;
  final int y;
  final CursorStyle style;
  final Color color;
  final bool blinking;

  /// Compact serialised form used by golden `<name>.cursor.txt` sidecars.
  String toGolden() {
    if (!visible) return 'hidden';
    return 'visible at ($x,$y) style=${style.value} '
        'color=${color.toHex(includeAlpha: false)} blinking=$blinking';
  }
}

/// Custom matchers for buffer testing.
class BufferMatchers {
  /// Matches if the buffer contains the specified text.
  static Matcher containsText(String text) => _ContainsTextMatcher(text);

  /// Matches if the buffer has the specified character at the given position.
  static Matcher hasCharAt(int x, int y, String expectedChar) =>
      _HasCharAtMatcher(x, y, expectedChar);

  /// Matches if the buffer has the specified foreground color at the given
  /// position.
  static Matcher hasColorAt(int x, int y, Color expectedColor) =>
      _HasColorAtMatcher(x, y, expectedColor);

  /// Matches if the buffer has the specified background color at the given
  /// position.
  static Matcher hasBackgroundAt(int x, int y, Color expectedColor) =>
      _HasBackgroundAtMatcher(x, y, expectedColor);

  /// Matches if the captured cursor is visible at the given position. Use
  /// `null` for either coord to skip that check.
  static Matcher cursorAt(int? x, int? y) => _CursorAtMatcher(x, y);
}

class _ContainsTextMatcher extends Matcher {
  _ContainsTextMatcher(this.expectedText);
  final String expectedText;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is CapturedBuffer) {
      return item.containsText(expectedText);
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('contains text "$expectedText"');
}

class _HasCharAtMatcher extends Matcher {
  _HasCharAtMatcher(this.x, this.y, this.expectedChar);
  final int x;
  final int y;
  final String expectedChar;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is CapturedBuffer) {
      try {
        return item.getChar(x, y) == expectedChar;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('has character "$expectedChar" at position ($x, $y)');
}

class _HasColorAtMatcher extends Matcher {
  _HasColorAtMatcher(this.x, this.y, this.expectedColor);
  final int x;
  final int y;
  final Color expectedColor;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is CapturedBuffer) {
      try {
        return item.getForegroundColor(x, y) == expectedColor;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('has color $expectedColor at position ($x, $y)');
}

class _HasBackgroundAtMatcher extends Matcher {
  _HasBackgroundAtMatcher(this.x, this.y, this.expectedColor);
  final int x;
  final int y;
  final Color expectedColor;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is CapturedBuffer) {
      try {
        return item.getBackgroundColor(x, y) == expectedColor;
      } catch (e) {
        return false;
      }
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('has background $expectedColor at position ($x, $y)');
}

class _CursorAtMatcher extends Matcher {
  _CursorAtMatcher(this.expectedX, this.expectedY);
  final int? expectedX;
  final int? expectedY;

  @override
  bool matches(Object? item, Map<dynamic, dynamic> matchState) {
    if (item is! CapturedBuffer) return false;
    if (!item.cursor.visible) return false;
    if (expectedX != null && item.cursor.x != expectedX) return false;
    if (expectedY != null && item.cursor.y != expectedY) return false;
    return true;
  }

  @override
  Description describe(Description description) {
    final pos = '(${expectedX ?? '*'}, ${expectedY ?? '*'})';
    return description.add('cursor is visible at $pos');
  }
}
