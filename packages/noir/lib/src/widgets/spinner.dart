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

  /// Color of the glyph. Falls back to [ThemeData.accent].
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
  // One controller for this state's whole life. It runs over a fixed 0..1
  // range and the frame index is derived from it, so neither a new `interval`
  // nor a different frame count can ever require a second controller — and
  // therefore a second ticker, which `SingleTickerProviderStateMixin` forbids.
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _requireFrames();
    _controller = AnimationController(vsync: this, duration: _runDuration)
      ..addListener(_handleTick)
      ..addStatusListener(_handleStatus);
    _controller.forward(from: 0);
  }

  /// One full pass through every frame.
  Duration get _runDuration => widget.interval * widget.frames.length;

  /// Checked here rather than in a constructor assert: `List.isEmpty` is not
  /// const-evaluable, and `const Spinner()` has to stay legal.
  void _requireFrames() {
    if (widget.frames.isEmpty) {
      throw ArgumentError.value(
        widget.frames,
        'frames',
        'must contain at least one glyph',
      );
    }
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
    _requireFrames();
    _controller.duration = _runDuration;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleTick)
      ..removeStatusListener(_handleStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = (_controller.value * widget.frames.length).floor().clamp(
      0,
      widget.frames.length - 1,
    );
    return Text(
      widget.frames[index],
      style: TextStyle(color: widget.color ?? Theme.of(context).accent),
    );
  }
}
