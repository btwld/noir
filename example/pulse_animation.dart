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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addListener(_onTick);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _controller.forward();
      }
    });

    _controller.forward(from: 0);
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
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
    final width = 8 + (value * 12).round();
    final height = 2 + (value * 4).round();
    final color = Color.rgb(0.2 + value * 0.6, 0.3, 0.6 + value * 0.3);
    final theme = Theme.of(context);

    return Container(
      color: theme.surface,
      alignment: Alignment.center,
      padding: EdgeInsets.all(2),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 1,
        children: [
          Text(
            'AnimationController demo',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.bold),
          ),
          Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: theme.border),
            ),
          ),
          Text(
            'controller.value: ${value.toStringAsFixed(2)}',
            style: TextStyle(color: theme.info),
          ),
          Text('(Ctrl+C to exit)', style: TextStyle(color: theme.textMuted)),
        ],
      ),
    );
  }
}
