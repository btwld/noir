// Run with: dart run example/components_demo.dart
//
// Tab and Shift+Tab move between the interactive controls; Space or Enter
// activates the focused one, and a left click does the same. Press s to stop
// or restart the spinner, and q to quit.
//
// Shows every Phase B component in one screen: Checkbox, Switch, Button,
// Divider, ProgressBar, Spinner, and Badge.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const ComponentsDemoApp(), enableMouse: true);

class ComponentsDemoApp extends StatefulWidget {
  const ComponentsDemoApp({super.key});

  @override
  State<ComponentsDemoApp> createState() => _ComponentsDemoAppState();
}

class _ComponentsDemoAppState extends State<ComponentsDemoApp> {
  bool _wrap = true;
  bool _verbose = false;
  bool _spinning = true;
  int _steps = 3;

  static const _totalSteps = 10;

  double get _progress => _steps / _totalSteps;

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    switch (event.character) {
      case 'q':
        TuiApp.exit(context);
        return KeyEventResult.handled;
      case 's':
        setState(() => _spinning = !_spinning);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  BadgeVariant get _statusVariant => switch (_steps) {
    0 => BadgeVariant.neutral,
    _totalSteps => BadgeVariant.success,
    _ => BadgeVariant.info,
  };

  String get _statusLabel => switch (_steps) {
    0 => 'IDLE',
    _totalSteps => 'DONE',
    _ => 'RUNNING',
  };

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _onAppKey,
    child: DemoScaffold(
      title: 'Components demo',
      hint: 'Tab to move · Space/Enter to activate · s spinner · q quit',
      titleTrailing: [
        Badge(label: _statusLabel, variant: _statusVariant),
        // A spinner animates for as long as it is mounted, so stopping
        // it means taking it out of the tree.
        if (_spinning) const Spinner() else const Text('·'),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 1,
        children: [
          DemoPanel(
            title: 'Controls',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Row(
                  spacing: 2,
                  children: [
                    Checkbox(
                      key: const ValueKey<String>('wrap'),
                      autofocus: true,
                      value: _wrap,
                      label: 'soft wrap',
                      onChanged: (next) => setState(() => _wrap = next),
                    ),
                    Switch(
                      key: const ValueKey<String>('verbose'),
                      value: _verbose,
                      label: 'verbose',
                      onChanged: (next) => setState(() => _verbose = next),
                    ),
                    const Checkbox(value: true, label: 'locked'),
                  ],
                ),
                Row(
                  spacing: 1,
                  children: [
                    Button(
                      key: const ValueKey<String>('step'),
                      label: 'Step',
                      onPressed: _steps == _totalSteps
                          ? null
                          : () => setState(() => _steps++),
                    ),
                    Button(
                      key: const ValueKey<String>('reset'),
                      label: 'Reset',
                      onPressed: _steps == 0
                          ? null
                          : () => setState(() => _steps = 0),
                    ),
                  ],
                ),
                Row(
                  spacing: 1,
                  children: [
                    ProgressBar(value: _progress, width: 24),
                    Text(
                      '$_steps/$_totalSteps',
                      style: TextStyle(color: Theme.of(context).textMuted),
                    ),
                  ],
                ),
                const Divider(),
              ],
            ),
          ),
          DemoPanel(
            title: 'Badges',
            child: Row(
              spacing: 1,
              children: [
                const Badge(label: 'NEUTRAL'),
                const Badge(label: 'OK', variant: BadgeVariant.success),
                const Badge(label: 'WARN', variant: BadgeVariant.warning),
                const Badge(label: 'FAIL', variant: BadgeVariant.danger),
                const Badge(label: 'INFO', variant: BadgeVariant.info),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
