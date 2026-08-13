// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

class ThemeData extends InheritedWidget {
  const ThemeData({
    required this.primaryColor,
    required this.textColor,
    required super.child,
    super.key,
  });

  final Color primaryColor;
  final Color textColor;

  static ThemeData of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<ThemeData>();
    assert(result != null, 'No ThemeData found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeData oldWidget) =>
      oldWidget.primaryColor != primaryColor ||
      oldWidget.textColor != textColor;
}

class ThemedText extends StatelessWidget {
  const ThemedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.of(context);
    return Text(text, style: TextStyle(color: theme.textColor));
  }
}

class ThemedApp extends StatelessWidget {
  const ThemedApp({super.key});

  @override
  Widget build(BuildContext context) => ThemeData(
    primaryColor: Color(0.2, 0.4, 0.8),
    textColor: Color.white,
    child: const _ThemeSurface(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ThemedText('Welcome to OpenTUI'),
          ThemedText('This text uses inherited theme colors'),
        ],
      ),
    ),
  );
}

class _ThemeSurface extends StatelessWidget {
  const _ThemeSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData.of(context);
    return Container(color: theme.primaryColor, child: child);
  }
}

void main() {
  runTuiApp(const ThemedApp());
}
