// ignore_for_file: prefer_constructors_over_static_methods, use_named_constants

import 'package:meta/meta.dart';

/// Immutable RGBA color stored as normalized (0–1) channel values.
///
/// This is the single color type in the framework. All drawing, theming, and
/// FFI marshalling go through `Color`.
@immutable
class Color {
  /// Stores normalized RGBA channels, with [a] defaulting to fully opaque.
  const Color(this.r, this.g, this.b, [this.a = 1.0])
    : assert(r >= 0 && r <= 1, 'red channel out of range (0–1): $r'),
      assert(g >= 0 && g <= 1, 'green channel out of range (0–1): $g'),
      assert(b >= 0 && b <= 1, 'blue channel out of range (0–1): $b'),
      assert(a >= 0 && a <= 1, 'alpha channel out of range (0–1): $a');

  /// Creates an opaque color from normalized [r], [g], [b] channels.
  const Color.rgb(double r, double g, double b) : this(r, g, b, 1);

  /// Parses `#rrggbb` or `#rrggbbaa` (with or without leading `#`).
  factory Color.fromHex(String hex) {
    final cleaned = hex.replaceFirst(RegExp('^#'), '');
    if (!(cleaned.length == 6 || cleaned.length == 8)) {
      throw FormatException('Expected 6 or 8 hex digits, received "$hex"');
    }

    final value = int.parse(cleaned, radix: 16);
    if (cleaned.length == 6) {
      final r = ((value >> 16) & 0xFF) / 255.0;
      final g = ((value >> 8) & 0xFF) / 255.0;
      final b = (value & 0xFF) / 255.0;
      return Color(r, g, b);
    }

    final r = ((value >> 24) & 0xFF) / 255.0;
    final g = ((value >> 16) & 0xFF) / 255.0;
    final b = ((value >> 8) & 0xFF) / 255.0;
    final a = (value & 0xFF) / 255.0;
    return Color(r, g, b, a);
  }

  /// Red channel in the normalized range `0–1`.
  final double r;

  /// Green channel in the normalized range `0–1`.
  final double g;

  /// Blue channel in the normalized range `0–1`.
  final double b;

  /// Alpha channel in the normalized range `0–1`.
  ///
  /// Zero is transparent and one is opaque.
  final double a;

  /// Returns a copy of this color with the alpha channel replaced by [opacity].
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Color.withOpacity`.
  Color withOpacity(double opacity) => Color(r, g, b, opacity);

  /// Linearly interpolates between [a] and [b] by [t], clamped to `0–1`.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Color.lerp`.
  static Color lerp(Color a, Color b, double t) {
    final clampedT = t.clamp(0.0, 1.0);
    if (clampedT == 0.0) return a;
    if (clampedT == 1.0) return b;
    return Color(
      _lerpDouble(a.r, b.r, clampedT),
      _lerpDouble(a.g, b.g, clampedT),
      _lerpDouble(a.b, b.b, clampedT),
      _lerpDouble(a.a, b.a, clampedT),
    );
  }

  /// Returns `#rrggbb` for opaque colors and `#rrggbbaa` when [a] < 1.
  /// Channel values are clamped to `0–1` before conversion.
  String toHex({bool includeAlpha = true}) {
    String h(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    final core = '#${h(r)}${h(g)}${h(b)}';
    return includeAlpha ? '$core${h(a)}' : core;
  }

  // --- Palette constants ----------------------------------------------------
  // Channel values mirror the previous ColorPalette so existing layouts and
  // goldens keep their colors.

  // Grayscale
  /// Opaque white (r=1, g=1, b=1).
  static const Color white = Color(1, 1, 1);

  /// Opaque light gray (r=0.8, g=0.8, b=0.8).
  static const Color lightGray = Color(0.8, 0.8, 0.8);

  /// Opaque mid gray (r=0.5, g=0.5, b=0.5).
  static const Color gray = Color(0.5, 0.5, 0.5);

  /// Opaque dark gray (r=0.3, g=0.3, b=0.3).
  static const Color darkGray = Color(0.3, 0.3, 0.3);

  /// Opaque black (r=0, g=0, b=0).
  static const Color black = Color(0, 0, 0);

  // Primary colors
  /// Opaque red (r=1, g=0, b=0).
  static const Color red = Color(1, 0, 0);

  /// Opaque green (r=0, g=1, b=0).
  static const Color green = Color(0, 1, 0);

  /// Opaque blue (r=0, g=0, b=1).
  static const Color blue = Color(0, 0, 1);

  /// Opaque yellow (r=1, g=1, b=0).
  static const Color yellow = Color(1, 1, 0);

  /// Opaque magenta (r=1, g=0, b=1).
  static const Color magenta = Color(1, 0, 1);

  /// Opaque cyan (r=0, g=1, b=1).
  static const Color cyan = Color(0, 1, 1);

  // Semantic colors
  /// Semantic success green used for positive status indicators.
  static const Color success = Color(0.2, 0.8, 0.2);

  /// Semantic warning amber used for cautionary status indicators.
  static const Color warning = Color(1, 0.6, 0);

  /// Semantic error red used for negative status indicators.
  static const Color error = Color(0.9, 0.2, 0.2);

  /// Semantic info blue used for informational status indicators.
  static const Color info = Color(0.2, 0.6, 1);

  // Transparent versions
  /// White at 50% opacity.
  static const Color whiteTransparent = Color(1, 1, 1, 0.5);

  /// Black at 50% opacity.
  static const Color blackTransparent = Color(0, 0, 0, 0.5);

  /// Gray at 50% opacity.
  static const Color grayTransparent = Color(0.5, 0.5, 0.5, 0.5);

  /// Fully transparent black; useful as a default background sentinel.
  static const Color transparent = Color(0, 0, 0, 0);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Color &&
        other.r == r &&
        other.g == g &&
        other.b == b &&
        other.a == a;
  }

  @override
  int get hashCode => Object.hash(r, g, b, a);

  @override
  String toString() =>
      'Color(r: ${r.toStringAsFixed(3)}, g: ${g.toStringAsFixed(3)}, b: ${b.toStringAsFixed(3)}, a: ${a.toStringAsFixed(3)})';

  static double _lerpDouble(double a, double b, double t) => a + (b - a) * t;
}
