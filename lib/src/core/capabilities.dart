import 'dart:io';

import 'renderer.dart';

/// Terminal color support levels, from no color to 24-bit true color.
enum ColorSupport {
  /// No color support.
  none,

  /// Basic 16-color ANSI support.
  ansi16,

  /// 256-color palette support.
  ansi256,

  /// 24-bit RGB true-color support.
  trueColor,
}

/// Terminal feature capabilities detected at runtime.
class TerminalCapabilities {
  /// Stores an immutable snapshot of detected features and terminal dimensions.
  const TerminalCapabilities({
    required this.colorSupport,
    required this.supportsUnicode,
    required this.supportsMouse,
    required this.supportsKittyKeyboard,
    required this.supportsAlternateScreen,
    required this.supportsCursor,
    required this.supportsSixel,
    required this.supportsImages,
    required this.width,
    required this.height,
  });

  /// Level of color rendering supported by the terminal.
  final ColorSupport colorSupport;

  /// Whether the terminal environment reports UTF-8 locale support.
  final bool supportsUnicode;

  /// Whether the terminal likely supports mouse reporting.
  final bool supportsMouse;

  /// Whether the terminal likely supports the Kitty keyboard protocol.
  final bool supportsKittyKeyboard;

  /// Whether the terminal supports the alternate screen buffer.
  final bool supportsAlternateScreen;

  /// Whether the terminal supports cursor positioning and style escapes.
  final bool supportsCursor;

  /// Whether the terminal supports Sixel graphics.
  final bool supportsSixel;

  /// Whether the terminal supports inline image protocols (e.g., iTerm2, Kitty).
  final bool supportsImages;

  /// Terminal width in columns at the time of detection.
  final int width;

  /// Terminal height in rows at the time of detection.
  final int height;

  @override
  String toString() =>
      'TerminalCapabilities('
      'colorSupport: $colorSupport, '
      'unicode: $supportsUnicode, '
      'mouse: $supportsMouse, '
      'kittyKeyboard: $supportsKittyKeyboard, '
      'alternateScreen: $supportsAlternateScreen, '
      'cursor: $supportsCursor, '
      'sixel: $supportsSixel, '
      'images: $supportsImages, '
      'size: ${width}x$height)';
}

/// Capability-detection methods added to [Renderer].
extension CapabilitiesDetection on Renderer {
  /// Detects and returns the terminal capabilities for the current
  /// environment, using environment variables and known patterns.
  TerminalCapabilities detectCapabilities() {
    final term = Platform.environment['TERM'] ?? '';
    final colorterm = Platform.environment['COLORTERM'] ?? '';
    final termProgram = Platform.environment['TERM_PROGRAM'] ?? '';

    // Detect color support
    var colorSupport = ColorSupport.none;
    if (colorterm == 'truecolor' ||
        colorterm == '24bit' ||
        termProgram.contains('iTerm') ||
        termProgram.contains('vscode') ||
        term.contains('256color')) {
      colorSupport = ColorSupport.trueColor;
    } else if (term.contains('256') || term.contains('xterm')) {
      colorSupport = ColorSupport.ansi256;
    } else if (term.contains('color') || term.contains('ansi')) {
      colorSupport = ColorSupport.ansi16;
    }

    // Mouse reporting, alternate screen, and cursor escapes are near
    // universal in any real (non-"dumb") terminal.
    final capableTerm = term.isNotEmpty && term != 'dumb';

    // Detect Kitty keyboard protocol (limited terminal support)
    final supportsKittyKeyboard =
        termProgram.contains('kitty') ||
        termProgram.contains('wezterm') ||
        termProgram.contains('foot');

    // Sixel graphics support (limited)
    final supportsSixel =
        termProgram.contains('xterm') ||
        termProgram.contains('mintty') ||
        term.contains('sixel');

    // Image support (very limited, mainly iTerm2 and Kitty)
    final supportsImages =
        termProgram.contains('iTerm') ||
        termProgram.contains('kitty') ||
        termProgram.contains('wezterm');

    // Get terminal size
    final size = _getTerminalSize();

    return TerminalCapabilities(
      colorSupport: colorSupport,
      supportsUnicode: _detectUnicodeSupport(),
      supportsMouse: capableTerm,
      supportsKittyKeyboard: supportsKittyKeyboard,
      supportsAlternateScreen: capableTerm,
      supportsCursor: capableTerm,
      supportsSixel: supportsSixel,
      supportsImages: supportsImages,
      width: size.width,
      height: size.height,
    );
  }
}

/// Detect Unicode support: any environment value carrying a UTF-8 marker
/// (LANG, LC_ALL, LC_CTYPE, ...) satisfies this deliberately broad heuristic.
bool _detectUnicodeSupport() =>
    Platform.environment.values.any((value) => value.contains('UTF-8'));

/// Simple terminal size detection
TerminalSize _getTerminalSize() {
  try {
    // Try to get from stdout if available
    if (stdout.hasTerminal) {
      return TerminalSize(
        width: stdout.terminalColumns,
        height: stdout.terminalLines,
      );
    }
  } catch (e) {
    // Fallback to environment variables or defaults
  }

  // Fallback to environment variables
  final columns = int.tryParse(Platform.environment['COLUMNS'] ?? '') ?? 80;
  final lines = int.tryParse(Platform.environment['LINES'] ?? '') ?? 24;

  return TerminalSize(width: columns, height: lines);
}

/// Terminal dimensions in columns and rows.
class TerminalSize {
  /// Stores terminal [width] in columns and [height] in rows.
  const TerminalSize({required this.width, required this.height});

  /// Terminal width in columns.
  final int width;

  /// Terminal height in rows.
  final int height;

  @override
  String toString() => '${width}x$height';
}
