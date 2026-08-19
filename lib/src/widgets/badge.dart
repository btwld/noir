import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'container.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';

/// Meanings a [Badge] can carry, each mapping to one [ThemeData] status token.
enum BadgeVariant {
  /// No status — a plain tag such as a category or a count.
  neutral,

  /// A completed or passing state.
  success,

  /// A state that needs attention.
  warning,

  /// A failed or destructive state.
  danger,

  /// Neutral information worth calling out.
  info,
}

/// A short, bold, filled tag that labels the state of something near it.
///
/// A badge is passive: it never takes focus and has no callback. It exists so
/// status colors come from one place instead of being spelled out at each call
/// site.
///
/// ```dart
/// Badge(label: 'STAGED', variant: BadgeVariant.success)
/// ```
class Badge extends StatelessWidget {
  /// Configures a badge showing [label] colored by [variant].
  const Badge({
    required this.label,
    super.key,
    this.variant = BadgeVariant.neutral,
    this.color,
    this.textColor,
  });

  /// Text rendered inside the badge.
  final String label;

  /// Meaning the badge carries, which chooses its default fill.
  final BadgeVariant variant;

  /// Fill painted behind the label, overriding the [variant] color.
  final Color? color;

  /// Color of the label. Falls back to [ThemeData.accentForeground], which
  /// stays legible on every variant fill.
  final Color? textColor;

  Color _variantColor(ThemeData theme) => switch (variant) {
    BadgeVariant.neutral => theme.textMuted,
    BadgeVariant.success => theme.success,
    BadgeVariant.warning => theme.warning,
    BadgeVariant.danger => theme.danger,
    BadgeVariant.info => theme.info,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: color ?? _variantColor(theme),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: textColor ?? theme.accentForeground,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
