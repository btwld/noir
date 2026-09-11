import 'package:noir/noir.dart';

/// The pub.dev-inspired palette shared by the search and package views.
final pubTheme = ThemeData.dark.copyWith(
  surface: const Color(0.025, 0.045, 0.055),
  surfaceVariant: const Color(0.04, 0.075, 0.085),
  textMuted: const Color(0.42, 0.51, 0.56),
  border: const Color(0.16, 0.28, 0.30),
  accent: const Color(0.39, 0.85, 0.78),
  accentForeground: const Color(0.02, 0.10, 0.09),
  selectedBackground: const Color(0.08, 0.23, 0.22),
  selectedForeground: const Color(0.39, 0.85, 0.78),
  cursor: const Color(0.95, 0.72, 0.32),
  scrollbarThumb: const Color(0.39, 0.85, 0.78),
  scrollbarTrack: const Color(0.16, 0.28, 0.30),
  warning: const Color(0.95, 0.72, 0.32),
);

/// Content emphasis where the color itself is the subject (install command,
/// metric values, version) rather than component chrome.
const pubEmphasis = Color(0.95, 0.72, 0.32);
