// ignore_for_file: public_member_api_docs

import '../../core/color.dart';
import '../../widgets/icons.dart';
import 'review_controller.dart';

/// Visual design language for Patch Manager: palette tokens and status glyphs.
///
/// Every value here is a `static const`. Widgets pull from this class instead
/// of hard-coding `Color(...)` literals or one-off glyph strings, so layout
/// + style changes stay in one place.
class PatchTheme {
  PatchTheme._();

  // Surface colors.
  static const Color bgBase = Color(0.035, 0.038, 0.044);
  static const Color bgPanel = Color(0.06, 0.064, 0.075);
  static const Color bgPanelAlt = Color(0.075, 0.08, 0.092);
  static const Color bgSelected = Color(0.10, 0.18, 0.24);

  // Borders.
  static const Color border = Color(0.18, 0.22, 0.28);
  static const Color borderHi = Color(0.32, 0.78, 1);

  // Accents (primary action chip, selected accent bar).
  static const Color accent = Color(0.40, 0.85, 1);
  static const Color accentInk = Color(0.02, 0.10, 0.16);

  // Text.
  static const Color text = Color(0.74, 0.80, 0.86);
  static const Color textHi = Color(0.82, 0.94, 1);
  static const Color muted = Color(0.54, 0.59, 0.65);
  static const Color subtitle = Color(0.58, 0.64, 0.7);

  // Status colors (used for status dots, chip accents, etc.).
  static const Color green = Color(0.50, 0.92, 0.62);
  static const Color red = Color(0.96, 0.48, 0.46);
  static const Color cyan = Color(0.55, 0.82, 1);
  static const Color amber = Color(0.90, 0.74, 0.42);
  static const Color grayDot = Color(0.45, 0.50, 0.56);

  // Diff line palette — softer text on a slightly richer background wash,
  // plus brighter, more saturated stripe accents at the gutter edge.
  static const Color diffAddFg = Color(0.62, 0.92, 0.70);
  static const Color diffDelFg = Color(0.98, 0.62, 0.60);
  static const Color diffAddStripe = Color(0.30, 0.86, 0.45);
  static const Color diffDelStripe = Color(1, 0.40, 0.42);
  static const Color diffAddBg = Color(0.05, 0.17, 0.09);
  static const Color diffDelBg = Color(0.20, 0.07, 0.08);
  static const Color diffNoNewlineBg = Color(0.14, 0.11, 0.04);

  /// Single-cell glyph that visually represents the given status.
  ///
  /// Distinct shapes so the status reads even in monochrome, and all four are
  /// drawn from the narrow [Icons] group: they share a column, so a glyph that
  /// widened alone would misalign every row below it. `○` and `◆` are
  /// ambiguous-width and would have.
  static String statusGlyph(PatchReviewStatus status) => switch (status) {
    PatchReviewStatus.unreviewed => Icons.circleDotted,
    PatchReviewStatus.staged => Icons.lozenge,
    PatchReviewStatus.skipped => Icons.close,
    PatchReviewStatus.failed => Icons.bang,
  };

  /// Color paired with each status glyph.
  static Color statusColor(PatchReviewStatus status) => switch (status) {
    PatchReviewStatus.unreviewed => grayDot,
    PatchReviewStatus.staged => cyan,
    PatchReviewStatus.skipped => amber,
    PatchReviewStatus.failed => red,
  };

  /// Selected-row accent bar glyph (one-eighth left block, U+258E).
  static const String accentBar = '▎';

  /// Selection caret, drawn against a blank cell on unselected rows. Both are
  /// narrow, so the selected row does not shift against its neighbours — `▶`
  /// carries the Unicode `Emoji` property and may receive a two-cell emoji
  /// presentation in some environments.
  static const String caret = Icons.pointerRight;
}
