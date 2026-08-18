// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

class DemoThemeData extends InheritedWidget {
  const DemoThemeData({
    required this.primaryColor,
    required this.textColor,
    required super.child,
    super.key,
  });

  final Color primaryColor;
  final Color textColor;

  static DemoThemeData of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<DemoThemeData>();
    assert(result != null, 'No DemoThemeData found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(DemoThemeData oldWidget) =>
      oldWidget.primaryColor != primaryColor ||
      oldWidget.textColor != textColor;
}

class ThemedText extends StatelessWidget {
  const ThemedText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = DemoThemeData.of(context);
    return Text(text, style: TextStyle(color: theme.textColor));
  }
}

class _ThemeDependencyStatus extends StatefulWidget {
  const _ThemeDependencyStatus();

  @override
  State<_ThemeDependencyStatus> createState() => _ThemeDependencyStatusState();
}

class _ThemeDependencyStatusState extends State<_ThemeDependencyStatus> {
  late Color _derivedTextColor;
  var _dependencyUpdates = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _derivedTextColor = DemoThemeData.of(context).textColor;
    _dependencyUpdates++;
  }

  @override
  Widget build(BuildContext context) {
    // Noir snapshots dependencies per build, so reassert the registration
    // without deriving presentation state during ordinary reconciliation.
    DemoThemeData.of(context);
    return Text(
      'Dependency updates: $_dependencyUpdates',
      style: TextStyle(color: _derivedTextColor),
    );
  }
}

final class _ThemeSnapshot {
  const _ThemeSnapshot({
    required this.name,
    required this.primaryColor,
    required this.textColor,
  });

  final String name;
  final Color primaryColor;
  final Color textColor;
}

class ThemedApp extends StatefulWidget {
  const ThemedApp({super.key});

  @override
  State<ThemedApp> createState() => _ThemedAppState();
}

class _ThemedAppState extends State<ThemedApp> {
  static const _ocean = _ThemeSnapshot(
    name: 'ocean',
    primaryColor: Color(0.2, 0.4, 0.8),
    textColor: Color.white,
  );
  static const _forest = _ThemeSnapshot(
    name: 'forest',
    primaryColor: Color(0.1, 0.5, 0.25),
    textColor: Color.yellow,
  );

  var _isForest = false;

  KeyEventResult _toggleTheme(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 't') {
      setState(() => _isForest = !_isForest);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = _isForest ? _forest : _ocean;
    return DemoThemeData(
      primaryColor: theme.primaryColor,
      textColor: theme.textColor,
      child: Focus(
        autofocus: true,
        onKeyEvent: _toggleTheme,
        child: _ThemeSurface(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ThemedText('Theme: ${theme.name} (press t to toggle)'),
              const ThemedText('Welcome to Noir'),
              const ThemedText('This text uses inherited theme colors'),
              const _ThemeDependencyStatus(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeSurface extends StatelessWidget {
  const _ThemeSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = DemoThemeData.of(context);
    return Container(color: theme.primaryColor, child: child);
  }
}

void main() {
  runTuiApp(const ThemedApp());
}
