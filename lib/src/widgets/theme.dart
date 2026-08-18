import 'package:meta/meta.dart';

import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';

/// The color tokens Noir's built-in widgets resolve against.
///
/// The token set is deliberately flat: one class of named colors, no
/// per-component sub-themes. Every built-in widget resolves a color as
/// `explicitParameter ?? Theme.maybeOf(context)?.token ?? widgetDefault`, so an
/// explicit constructor argument always wins and an app with no [Theme]
/// ancestor renders exactly as it did before theming existed.
///
/// [dark] reproduces the color literals the built-in widgets hard-coded before
/// they were themed, so adopting it changes only the tokens an app overrides.
@immutable
class ThemeData {
  /// Stores one color per token, defaulting to the [dark] palette values.
  const ThemeData({
    this.surface = const Color(0.035, 0.038, 0.044),
    this.surfaceVariant = const Color(0.06, 0.064, 0.075),
    this.text = Color.white,
    this.textMuted = const Color(0.6, 0.6, 0.6),
    this.border = const Color(0.18, 0.22, 0.28),
    this.accent = const Color(0.4, 0.85, 1),
    this.accentForeground = const Color(0.02, 0.1, 0.16),
    this.selectedBackground = const Color(0.2, 0.4, 0.8),
    this.selectedForeground = Color.white,
    this.cursor = Color.white,
    this.scrollbarThumb = const Color(0.7, 0.7, 0.7),
    this.scrollbarTrack = const Color(0.2, 0.2, 0.2),
    this.success = Color.success,
    this.warning = Color.warning,
    this.danger = Color.error,
    this.info = Color.info,
  });

  /// Palette whose tokens equal the literals the built-in widgets used before
  /// they resolved colors through a [Theme].
  static const ThemeData dark = ThemeData();

  /// Fill painted behind a themed widget's own box.
  final Color surface;

  /// Fill that separates a nested region — a panel, gutter, or header row —
  /// from the surrounding [surface].
  final Color surfaceVariant;

  /// Foreground of ordinary body text.
  final Color text;

  /// Foreground of secondary text such as descriptions, hints, and the labels
  /// of disabled controls.
  final Color textMuted;

  /// Foreground of box borders and rules.
  final Color border;

  /// Fill or foreground that marks the primary action and other emphasized
  /// chrome.
  final Color accent;

  /// Foreground legible against an [accent] fill.
  final Color accentForeground;

  /// Fill painted behind the highlighted row of a list or table.
  final Color selectedBackground;

  /// Foreground of text on a [selectedBackground] row.
  final Color selectedForeground;

  /// Foreground of the text-editing caret.
  final Color cursor;

  /// Fill of the movable part of a scrollbar.
  final Color scrollbarThumb;

  /// Fill of the scrollbar gutter behind the [scrollbarThumb].
  final Color scrollbarTrack;

  /// Foreground or fill that reports a completed or passing state.
  final Color success;

  /// Foreground or fill that reports a state needing attention.
  final Color warning;

  /// Foreground or fill that reports a failed or destructive state.
  final Color danger;

  /// Foreground or fill that reports neutral information.
  final Color info;

  /// Returns a copy of this palette with every supplied token replaced.
  ThemeData copyWith({
    Color? surface,
    Color? surfaceVariant,
    Color? text,
    Color? textMuted,
    Color? border,
    Color? accent,
    Color? accentForeground,
    Color? selectedBackground,
    Color? selectedForeground,
    Color? cursor,
    Color? scrollbarThumb,
    Color? scrollbarTrack,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
  }) => ThemeData(
    surface: surface ?? this.surface,
    surfaceVariant: surfaceVariant ?? this.surfaceVariant,
    text: text ?? this.text,
    textMuted: textMuted ?? this.textMuted,
    border: border ?? this.border,
    accent: accent ?? this.accent,
    accentForeground: accentForeground ?? this.accentForeground,
    selectedBackground: selectedBackground ?? this.selectedBackground,
    selectedForeground: selectedForeground ?? this.selectedForeground,
    cursor: cursor ?? this.cursor,
    scrollbarThumb: scrollbarThumb ?? this.scrollbarThumb,
    scrollbarTrack: scrollbarTrack ?? this.scrollbarTrack,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    info: info ?? this.info,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeData &&
        other.surface == surface &&
        other.surfaceVariant == surfaceVariant &&
        other.text == text &&
        other.textMuted == textMuted &&
        other.border == border &&
        other.accent == accent &&
        other.accentForeground == accentForeground &&
        other.selectedBackground == selectedBackground &&
        other.selectedForeground == selectedForeground &&
        other.cursor == cursor &&
        other.scrollbarThumb == scrollbarThumb &&
        other.scrollbarTrack == scrollbarTrack &&
        other.success == success &&
        other.warning == warning &&
        other.danger == danger &&
        other.info == info;
  }

  @override
  int get hashCode => Object.hash(
    surface,
    surfaceVariant,
    text,
    textMuted,
    border,
    accent,
    accentForeground,
    selectedBackground,
    selectedForeground,
    cursor,
    scrollbarThumb,
    scrollbarTrack,
    success,
    warning,
    danger,
    info,
  );
}

/// Publishes a [ThemeData] palette to every widget below it.
///
/// Built-in widgets read the palette through [maybeOf], so wrapping part of a
/// tree re-colors only that subtree. Nesting is supported: the nearest
/// enclosing `Theme` wins.
///
/// ```dart
/// Theme(
///   data: ThemeData.dark.copyWith(accent: Color.magenta),
///   child: const Button(label: 'Run'),
/// )
/// ```
class Theme extends InheritedWidget {
  /// Publishes [data] to the dependents inside [child].
  const Theme({required this.data, required super.child, super.key});

  /// Palette that dependents below this widget resolve against.
  final ThemeData data;

  /// Returns the nearest enclosing palette, or [ThemeData.dark] when the
  /// context has no [Theme] ancestor.
  ///
  /// Use this when a widget always needs a concrete color. Use [maybeOf] when
  /// "no theme" and "themed" must render differently — the built-in widgets
  /// use [maybeOf] so an unthemed app keeps its original appearance.
  static ThemeData of(BuildContext context) =>
      maybeOf(context) ?? ThemeData.dark;

  /// Returns the nearest enclosing palette, or null when the context has no
  /// [Theme] ancestor.
  static ThemeData? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Theme>()?.data;

  @override
  bool updateShouldNotify(covariant Theme oldWidget) => oldWidget.data != data;
}
