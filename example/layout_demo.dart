/// Flex layout showcase demonstrating [Row], [Column], [Expanded], alignment,
/// and [BoxDecoration] inside a full Noir application.
library;

// ignore_for_file: avoid_redundant_argument_values, cascade_invocations
import 'dart:io' as io;

import 'package:noir/noir.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(FlexLayoutShowcase(onQuit: quit));
  app.enableMouse();
}

class FlexLayoutShowcase extends StatelessWidget {
  const FlexLayoutShowcase({required this.onQuit, super.key});

  final VoidCallback onQuit;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _handleKey,
      child: Container(
        color: theme.surface,
        padding: EdgeInsets.all(1),
        child: Column(
          children: [
            _buildHeader(theme),
            const SizedBox(height: 1),
            Expanded(
              child: Row(
                children: [
                  _buildNavigationPane(theme),
                  const SizedBox(width: 1),
                  Expanded(child: _buildContentArea(theme)),
                ],
              ),
            ),
            const SizedBox(height: 1),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) => Container(
    height: 3,
    alignment: Alignment.center,
    padding: EdgeInsets.all(1),
    color: theme.selectedBackground,
    child: Text(
      'Noir Flex Layout Showcase',
      style: TextStyle(
        color: theme.selectedForeground,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildNavigationPane(ThemeData theme) => Container(
    width: 24,
    decoration: BoxDecoration(
      color: theme.surfaceVariant,
      border: Border.all(color: theme.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 3,
          alignment: Alignment.center,
          color: theme.selectedBackground,
          child: Text(
            'Sections',
            style: TextStyle(color: theme.selectedForeground),
          ),
        ),
        const SizedBox(height: 1),
        _buildNavItem(theme, 'Main Axis Alignments'),
        _buildNavItem(theme, 'Cross Axis Alignments'),
        _buildNavItem(theme, 'Flex Factors'),
        _buildNavItem(theme, 'Nested Layouts'),
        const Expanded(child: SizedBox.shrink()),
        Container(
          height: 2,
          alignment: Alignment.center,
          child: Text('Noir', style: TextStyle(color: theme.textMuted)),
        ),
      ],
    ),
  );

  Widget _buildContentArea(ThemeData theme) => Container(
    decoration: BoxDecoration(
      color: theme.surfaceVariant,
      border: Border.all(color: theme.border),
    ),
    child: ScrollBox(
      autofocus: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader(theme, 'MainAxisAlignment Examples'),
          _buildMainAxisExamples(),
          const SizedBox(height: 1),
          _buildSectionHeader(theme, 'CrossAxisAlignment Examples'),
          _buildCrossAxisExamples(),
          const SizedBox(height: 1),
          _buildSectionHeader(theme, 'Flexible & Expanded Distribution'),
          _buildFlexFactorExamples(),
          const SizedBox(height: 1),
          _buildSectionHeader(theme, 'Nested Layout: Dashboard Panel'),
          SizedBox(height: 14, child: _buildDashboardSample()),
        ],
      ),
    ),
  );

  Widget _buildFooter(ThemeData theme) => Container(
    height: 2,
    color: theme.surfaceVariant,
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Flex Layout Demo', style: TextStyle(color: theme.textMuted)),
        Text(
          '↑/↓ to scroll · q or Ctrl+C to exit',
          style: TextStyle(color: theme.textMuted),
        ),
      ],
    ),
  );

  Widget _buildNavItem(ThemeData theme, String label) => Container(
    height: 2,
    alignment: Alignment.centerLeft,
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Text(label, style: TextStyle(color: theme.textMuted)),
  );

  Widget _buildSectionHeader(ThemeData theme, String title) => Container(
    height: 2,
    alignment: Alignment.centerLeft,
    padding: EdgeInsets.symmetric(horizontal: 2),
    color: theme.selectedBackground,
    child: Text(
      title,
      style: TextStyle(
        color: theme.selectedForeground,
        fontWeight: FontWeight.bold,
      ),
    ),
  );

  Widget _buildMainAxisExamples() => Column(
    children: [
      _buildMainAxisExample('Start', MainAxisAlignment.start),
      _buildMainAxisExample('Center', MainAxisAlignment.center),
      _buildMainAxisExample('End', MainAxisAlignment.end),
      _buildMainAxisExample('Space Between', MainAxisAlignment.spaceBetween),
      _buildMainAxisExample('Space Around', MainAxisAlignment.spaceAround),
      _buildMainAxisExample('Space Evenly', MainAxisAlignment.spaceEvenly),
    ],
  );

  Widget _buildMainAxisExample(String label, MainAxisAlignment alignment) =>
      Container(
        height: 4,
        margin: EdgeInsets.symmetric(horizontal: 1, vertical: 1),
        padding: EdgeInsets.all(1),
        decoration: BoxDecoration(
          border: Border.all(color: Color(1, 1, 1, 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: TextStyle(color: Color(0.85, 0.9, 1))),
            Expanded(
              child: Row(
                mainAxisAlignment: alignment,
                children: const [
                  _DemoBlock(label: 'A', color: Color(0.9, 0.3, 0.3), width: 5),
                  _DemoBlock(label: 'B', color: Color(0.3, 0.9, 0.3), width: 5),
                  _DemoBlock(label: 'C', color: Color(0.3, 0.5, 0.9), width: 5),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _buildCrossAxisExamples() => Row(
    children: const [
      Expanded(
        child: _CrossAxisExample(
          label: 'Start',
          alignment: CrossAxisAlignment.start,
        ),
      ),
      SizedBox(width: 1),
      Expanded(
        child: _CrossAxisExample(
          label: 'Center',
          alignment: CrossAxisAlignment.center,
        ),
      ),
      SizedBox(width: 1),
      Expanded(
        child: _CrossAxisExample(
          label: 'Stretch',
          alignment: CrossAxisAlignment.stretch,
        ),
      ),
    ],
  );

  Widget _buildFlexFactorExamples() => Container(
    margin: EdgeInsets.all(1),
    padding: EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.3))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: const [
            Expanded(
              child: _DemoBlock(label: 'Flex 1', color: Color(0.3, 0.7, 0.9)),
            ),
            Expanded(
              flex: 2,
              child: _DemoBlock(label: 'Flex 2', color: Color(0.9, 0.6, 0.3)),
            ),
            Expanded(
              flex: 3,
              child: _DemoBlock(label: 'Flex 3', color: Color(0.6, 0.3, 0.9)),
            ),
          ],
        ),
        const SizedBox(height: 1),
        Row(
          children: const [
            SizedBox(
              width: 8,
              child: _DemoBlock(label: 'Fixed', color: Color(0.9, 0.3, 0.3)),
            ),
            SizedBox(width: 1),
            Flexible(
              child: _DemoBlock(
                label: 'Loose flex 1',
                color: Color(0.3, 0.8, 0.8),
              ),
            ),
            SizedBox(width: 1),
            Expanded(
              child: _DemoBlock(
                label: 'Tight flex 1',
                color: Color(0.8, 0.8, 0.3),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildDashboardSample() => Container(
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.2))),
    padding: EdgeInsets.all(1),
    child: Row(
      children: [
        Expanded(
          flex: 2,
          child: Column(
            children: const [
              _DemoBlock(
                label: 'Chart',
                color: Color(0.3, 0.5, 0.9),
                height: 6,
              ),
              SizedBox(height: 1),
              _DemoBlock(
                label: 'Activity Feed',
                color: Color(0.3, 0.9, 0.5),
                height: 5,
              ),
            ],
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: Column(
            children: const [
              _DemoBlock(
                label: 'Stats',
                color: Color(0.9, 0.6, 0.3),
                height: 4,
              ),
              SizedBox(height: 1),
              _DemoBlock(
                label: 'Tasks',
                color: Color(0.6, 0.3, 0.9),
                height: 7,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _CrossAxisExample extends StatelessWidget {
  const _CrossAxisExample({required this.label, required this.alignment});

  final String label;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Container(
    height: 6,
    padding: EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.3))),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TextStyle(color: Color(0.85, 0.9, 1))),
        Expanded(
          child: Row(
            crossAxisAlignment: alignment,
            children: const [
              _DemoBlock(
                label: 'A',
                color: Color(0.9, 0.4, 0.4),
                height: 2,
                width: 5,
              ),
              SizedBox(width: 1),
              _DemoBlock(
                label: 'B',
                color: Color(0.4, 0.9, 0.6),
                height: 4,
                width: 5,
              ),
              SizedBox(width: 1),
              _DemoBlock(
                label: 'C',
                color: Color(0.4, 0.6, 0.9),
                height: 3,
                width: 5,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DemoBlock extends StatelessWidget {
  const _DemoBlock({
    required this.label,
    required this.color,
    this.width,
    this.height,
  });

  final String label;
  final Color color;
  final int? width;
  final int? height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    color: color,
    child: Text(label, style: TextStyle(color: Color.black)),
  );
}
