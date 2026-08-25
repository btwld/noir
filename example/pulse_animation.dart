// ignore_for_file: avoid_redundant_argument_values, cascade_invocations
import 'package:noir/noir.dart';

void main() => runTuiApp(const PulseAnimationDemo());

class PulseAnimationDemo extends StatefulWidget {
  const PulseAnimationDemo({super.key});

  @override
  State<PulseAnimationDemo> createState() => _PulseAnimationDemoState();
}

class _PulseAnimationDemoState extends State<PulseAnimationDemo>
    with SingleTickerProviderStateMixin<PulseAnimationDemo> {
  late final AnimationController _controller;
  var _forward = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..addListener(_onTick);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _forward = false;
        _controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _forward = true;
        _controller.forward();
      }
    });

    _controller.forward(from: 0);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!event.isPress || event.character != ' ') {
      return KeyEventResult.ignored;
    }
    setState(() {
      if (_controller.isAnimating) {
        _controller.stop();
      } else {
        if (_forward) {
          _controller.forward();
        } else {
          _controller.reverse();
        }
      }
    });
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final theme = Theme.of(context);
    final progressColor = Color.lerp(theme.info, theme.accent, value);

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        color: theme.surface,
        alignment: Alignment.center,
        padding: EdgeInsets.all(2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 1,
          children: [
            Text(
              'Terminal-native motion',
              style: TextStyle(color: theme.text, fontWeight: FontWeight.bold),
            ),
            ProgressBar(
              value: value,
              width: 32,
              color: progressColor,
              trackColor: theme.border,
            ),
            Text(
              'controller.value: ${value.toStringAsFixed(2)} · '
              '${_controller.isAnimating ? 'running' : 'paused'}',
              style: TextStyle(color: theme.info),
            ),
            Text(
              '1/8-cell progress · Space pause/resume · Ctrl+C exit',
              style: TextStyle(color: theme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
