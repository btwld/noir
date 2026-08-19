// Run with: dart run example/theme_demo.dart
//
// Press t to swap palettes, q to quit. Demonstrates Theme/ThemeData: one
// InheritedWidget publishes a flat token set, and every widget below it
// resolves its colors from the nearest enclosing Theme.

import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(ThemeDemoApp(onQuit: quit));
}

/// Two presets that differ in every token a demo row reads, so a single
/// keypress visibly re-colors the whole subtree.
const _midnight = ThemeData.dark;
final _sunset = ThemeData.dark.copyWith(
  surface: const Color(0.12, 0.06, 0.08),
  surfaceVariant: const Color(0.18, 0.09, 0.11),
  text: const Color(0.98, 0.9, 0.84),
  textMuted: const Color(0.72, 0.58, 0.55),
  border: const Color(0.42, 0.22, 0.24),
  accent: const Color(1, 0.55, 0.35),
  accentForeground: const Color(0.14, 0.05, 0.02),
);

class ThemeDemoApp extends StatefulWidget {
  const ThemeDemoApp({required this.onQuit, super.key});

  /// Invoked when the user presses `q`.
  final void Function() onQuit;

  @override
  State<ThemeDemoApp> createState() => _ThemeDemoAppState();
}

class _ThemeDemoAppState extends State<ThemeDemoApp> {
  bool _sunsetActive = false;

  KeyEventResult _onAppKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    if (event.character == 't') {
      setState(() => _sunsetActive = !_sunsetActive);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  // This demo has no other focusable widget, so the key handler must be able
  // to hold primary focus itself — a `canRequestFocus: false` quit wrapper
  // would never receive a bubbled event here.
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _onAppKey,
    child: Theme(
      data: _sunsetActive ? _sunset : _midnight,
      child: _ThemedPanel(paletteName: _sunsetActive ? 'sunset' : 'midnight'),
    ),
  );
}

/// Reads every token it paints from [Theme.of], so it never names a color.
/// The frame itself is the shared [DemoScaffold], which resolves the same
/// tokens — swapping the palette re-skins chrome and content together.
class _ThemedPanel extends StatelessWidget {
  const _ThemedPanel({required this.paletteName});

  final String paletteName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DemoScaffold(
      title: 'Theme demo — $paletteName',
      hint: 'Press t to swap palettes, q to quit.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.surfaceVariant,
              border: Border.all(color: theme.border),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'surfaceVariant panel',
                  style: TextStyle(color: theme.text),
                ),
                Container(
                  color: theme.accent,
                  child: Text(
                    ' accent on accentForeground ',
                    style: TextStyle(color: theme.accentForeground),
                  ),
                ),
                Container(
                  color: theme.selectedBackground,
                  child: Text(
                    ' selected row ',
                    style: TextStyle(color: theme.selectedForeground),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 1),
          Row(
            spacing: 2,
            children: [
              Text('success', style: TextStyle(color: theme.success)),
              Text('warning', style: TextStyle(color: theme.warning)),
              Text('danger', style: TextStyle(color: theme.danger)),
              Text('info', style: TextStyle(color: theme.info)),
            ],
          ),
        ],
      ),
    );
  }
}
