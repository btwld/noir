// Run with: dart run example/components_demo.dart
//
// Tab and Shift+Tab move between the interactive controls; Space or Enter
// activates the focused one, and a left click does the same. Press t to swap
// the complete palette, s to stop or restart the spinner, and q to quit.
//
// Keeps one compact category visible at a time: the public Panel foundation
// states or the Checkbox, Switch, Button, Divider, ProgressBar, Spinner, and
// Badge controls.

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() => runTuiApp(const ComponentsDemoApp(), enableMouse: true);

enum _ComponentCategory { controls, foundation }

const _categories = <SelectOption<_ComponentCategory>>[
  SelectOption(name: 'Controls', value: _ComponentCategory.controls),
  SelectOption(name: 'Foundation', value: _ComponentCategory.foundation),
];

const _emberPalette = ThemeData(
  surface: Color(0.12, 0.06, 0.08),
  surfaceVariant: Color(0.18, 0.09, 0.11),
  text: Color(0.98, 0.9, 0.84),
  textMuted: Color(0.72, 0.58, 0.55),
  border: Color(0.42, 0.22, 0.24),
  accent: Color(1, 0.55, 0.35),
  accentForeground: Color(0.14, 0.05, 0.02),
  selectedBackground: Color(0.52, 0.2, 0.16),
  selectedForeground: Color(1, 0.94, 0.88),
);

class ComponentsDemoApp extends StatefulWidget {
  const ComponentsDemoApp({super.key});

  @override
  State<ComponentsDemoApp> createState() => _ComponentsDemoAppState();
}

class _ComponentsDemoAppState extends State<ComponentsDemoApp> {
  bool _wrap = true;
  bool _verbose = false;
  bool _spinning = true;
  bool _emberActive = false;
  int _steps = 3;
  _ComponentCategory _category = _ComponentCategory.controls;

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
      case 't':
        setState(() => _emberActive = !_emberActive);
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
  Widget build(BuildContext context) => Theme(
    data: _emberActive ? _emberPalette : ThemeData.dark,
    child: Focus(
      canRequestFocus: false,
      onKeyEvent: _onAppKey,
      child: _ComponentSheet(
        category: _category,
        paletteLabel: _emberActive ? 'EMBER' : 'DARK',
        statusLabel: _statusLabel,
        statusVariant: _statusVariant,
        spinning: _spinning,
        wrap: _wrap,
        verbose: _verbose,
        steps: _steps,
        totalSteps: _totalSteps,
        progress: _progress,
        onCategoryChanged: (next) => setState(() => _category = next),
        onWrapChanged: (next) => setState(() => _wrap = next),
        onVerboseChanged: (next) => setState(() => _verbose = next),
        onStep: _steps == _totalSteps ? null : () => setState(() => _steps++),
        onReset: _steps == 0 ? null : () => setState(() => _steps = 0),
      ),
    ),
  );
}

class _ComponentSheet extends StatelessWidget {
  const _ComponentSheet({
    required this.category,
    required this.paletteLabel,
    required this.statusLabel,
    required this.statusVariant,
    required this.spinning,
    required this.wrap,
    required this.verbose,
    required this.steps,
    required this.totalSteps,
    required this.progress,
    required this.onCategoryChanged,
    required this.onWrapChanged,
    required this.onVerboseChanged,
    required this.onStep,
    required this.onReset,
  });

  final _ComponentCategory category;
  final String paletteLabel;
  final String statusLabel;
  final BadgeVariant statusVariant;
  final bool spinning;
  final bool wrap;
  final bool verbose;
  final int steps;
  final int totalSteps;
  final double progress;
  final ValueChanged<_ComponentCategory> onCategoryChanged;
  final ValueChanged<bool> onWrapChanged;
  final ValueChanged<bool> onVerboseChanged;
  final VoidCallback? onStep;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) => DemoScaffold(
    title: 'Components demo',
    hint: 'Tab move · Space/Enter activate · t palette · s spinner · q quit',
    titleTrailing: [
      Badge(label: paletteLabel),
      Badge(label: statusLabel, variant: statusVariant),
      // A spinner animates for as long as it is mounted, so stopping it means
      // taking it out of the tree.
      if (spinning) const Spinner() else const Text(Icons.dot),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabSelect<_ComponentCategory>(
          key: const ValueKey<String>('component-category'),
          options: _categories,
          selectedIndex: category.index,
          tabWidth: null,
          showScrollArrows: false,
          showDescription: false,
          showUnderline: false,
          onChanged: (_, option) {
            final value = option.value;
            if (value != null) onCategoryChanged(value);
          },
        ),
        const SizedBox(height: 1),
        switch (category) {
          _ComponentCategory.controls => _buildControls(context),
          _ComponentCategory.foundation => _buildFoundation(context),
        },
      ],
    ),
  );

  Widget _buildControls(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 1,
    children: [
      Panel(
        title: 'Controls',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              spacing: 2,
              children: [
                Checkbox(
                  key: const ValueKey<String>('wrap'),
                  autofocus: true,
                  value: wrap,
                  label: 'soft wrap',
                  onChanged: onWrapChanged,
                ),
                Switch(
                  key: const ValueKey<String>('verbose'),
                  value: verbose,
                  label: 'verbose',
                  onChanged: onVerboseChanged,
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
                  onPressed: onStep,
                ),
                Button(
                  key: const ValueKey<String>('reset'),
                  label: 'Reset',
                  onPressed: onReset,
                ),
              ],
            ),
            Row(
              spacing: 1,
              children: [
                ProgressBar(value: progress, width: 24),
                Text(
                  '$steps/$totalSteps',
                  style: TextStyle(color: Theme.of(context).textMuted),
                ),
              ],
            ),
            const Divider(),
          ],
        ),
      ),
      Panel(
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
  );

  Widget _buildFoundation(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: 1,
    children: [
      Text(
        'Panel states',
        style: TextStyle(
          color: Theme.of(context).textMuted,
          fontWeight: FontWeight.bold,
        ),
      ),
      Row(
        spacing: 1,
        children: const [
          Expanded(
            child: Panel(title: 'Default', child: Text('Theme border')),
          ),
          Expanded(
            child: Panel(
              title: 'Focused',
              focused: true,
              child: Text('Accent border + marker'),
            ),
          ),
        ],
      ),
      const Panel(focused: true, child: Text('Untitled focus remains visible')),
    ],
  );
}
