import '../animation/animation.dart';
import '../animation/animation_controller.dart';
import '../animation/ticker.dart';
import '../core/color.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import 'text.dart';
import 'text_style.dart';
import 'theme.dart';

/// Ready-made frame sequences for [Spinner].
class SpinnerFrames {
  const SpinnerFrames._();

  /// Braille dot pattern, the densest single-cell animation available. Needs a
  /// font with Braille Patterns (U+2800) coverage; most modern terminal fonts
  /// have it.
  static const List<String> dots = [
    '⠋',
    '⠙',
    '⠹',
    '⠸',
    '⠼',
    '⠴',
    '⠦',
    '⠧',
    '⠇',
    '⠏',
  ];

  /// Pure ASCII fallback for terminals or fonts without Braille coverage.
  static const List<String> line = ['|', '/', '-', r'\'];
}

/// A one-cell animated glyph that reports ongoing work.
///
/// The spinner drives an [AnimationController] over the frame index range and
/// restarts it from the beginning on completion, because the controller has no
/// repeat mode. It advances one frame every [interval].
///
/// A spinner animates for as long as it is mounted. Remove it from the tree
/// when the work finishes rather than trying to stop it in place.
///
/// ```dart
/// if (_loading) const Spinner()
/// ```
class Spinner extends StatefulWidget {
  /// Configures a spinner cycling [frames] once every [interval] per frame.
  const Spinner({
    super.key,
    this.color,
    this.frames = SpinnerFrames.dots,
    this.interval = const Duration(milliseconds: 80),
  });

  /// Color of the glyph. Falls back to [ThemeData.accent], then to
  /// [Color.white].
  final Color? color;

  /// Glyphs cycled in order, each rendered for [interval].
  final List<String> frames;

  /// Time each frame stays on screen.
  final Duration interval;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner>
    with SingleTickerProviderStateMixin<Spinner> {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Checked here rather than in a constructor assert: `List.isEmpty` is not
    // const-evaluable, and `const Spinner()` has to stay legal.
    if (widget.frames.isEmpty) {
      throw ArgumentError.value(
        widget.frames,
        'frames',
        'must contain at least one glyph',
      );
    }
    _controller = _createController();
  }

  AnimationController _createController() {
    final controller = AnimationController(
      vsync: this,
      duration: widget.interval * widget.frames.length,
      upperBound: widget.frames.length.toDouble(),
    )..addListener(_handleTick);
    controller.addStatusListener(_handleStatus);
    controller.forward(from: 0);
    return controller;
  }

  void _handleTick() {
    if (mounted) setState(() {});
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(Spinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval ||
        oldWidget.frames.length != widget.frames.length) {
      _disposeController();
      _controller = _createController();
    }
  }

  void _disposeController() {
    _controller
      ..removeListener(_handleTick)
      ..removeStatusListener(_handleStatus)
      ..dispose();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = _controller.value.floor().clamp(0, widget.frames.length - 1);
    return Text(
      widget.frames[index],
      style: TextStyle(
        color: widget.color ?? Theme.maybeOf(context)?.accent ?? Color.white,
      ),
    );
  }
}
