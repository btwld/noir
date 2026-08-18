import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import 'text.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'theme.dart';

/// Left-anchored block elements from one eighth (U+258F) through seven eighths
/// (U+2589). They let the bar advance in eighth-cell steps instead of jumping a
/// whole cell at a time.
const List<String> _partials = ['▏', '▎', '▍', '▌', '▋', '▊', '▉'];
const String _full = '█'; // U+2588
const String _track = '░'; // U+2591

/// A one-row bar showing a fraction of completed work.
///
/// The bar is [width] cells wide and resolves to eighth-cell precision, so a
/// 20-cell bar distinguishes 160 positions rather than 20. It renders as text,
/// which means it inherits the text pipeline's clipping and needs no render
/// object of its own.
///
/// ```dart
/// ProgressBar(value: downloaded / total, width: 30)
/// ```
class ProgressBar extends StatelessWidget {
  /// Configures a bar [width] cells wide showing [value], clamped to `0..1`.
  const ProgressBar({
    required this.value,
    super.key,
    this.width = 20,
    this.color,
    this.trackColor,
  }) : assert(width >= 0);

  /// Completed fraction, clamped to `0..1` before rendering.
  final double value;

  /// Cells occupied by the whole bar, filled and unfilled together.
  final int width;

  /// Color of the filled part. Falls back to [ThemeData.accent].
  final Color? color;

  /// Color of the unfilled track. Falls back to [ThemeData.scrollbarTrack].
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fillColor = color ?? theme.accent;
    final trackFill = trackColor ?? theme.scrollbarTrack;

    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final eighths = (clamped * width * 8).round();
    final fullCells = eighths ~/ 8;
    final remainder = eighths % 8;
    final filled = _full * fullCells;
    final partial = remainder == 0 ? '' : _partials[remainder - 1];
    final trackCells = width - fullCells - partial.length;

    return Text.rich(
      TextSpan(
        children: [
          if (filled.isNotEmpty || partial.isNotEmpty)
            TextSpan(
              text: '$filled$partial',
              style: TextStyle(color: fillColor),
            ),
          if (trackCells > 0)
            TextSpan(
              text: _track * trackCells,
              style: TextStyle(color: trackFill),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}
