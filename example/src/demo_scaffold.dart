/// Shared chrome for the Noir example apps.
///
/// Every demo used to hand-roll the same three shapes — a padded surface with
/// a bold title and muted hint, a bordered panel, and a focused-panel accent —
/// each with its own color literals. This file is the one copy: all chrome
/// colors come from `Theme.of(context)`, so the demos render on
/// `ThemeData.dark` by default and re-skin together under any `Theme`.
///
/// The card is content-sized vertically. Horizontal room comes from the
/// scaffold owning the terminal (`alignment: topLeft`) and a 2-cell side
/// inset so the page title is not glued to the edge. A panel title lives
/// on the top border (`Border.title`, `┌─ Name ─┐`); the body starts on
/// the first inner row. Horizontal pad 1 is free (maxed with the border).
/// Do not set [DemoPanel.height] unless the child is a viewport. The
/// panel fill is [ThemeData.surfaceVariant] — the token whose job is a
/// nested region.
///
/// Content colors (chat speakers, layout blocks, particles) stay in each demo:
/// there the color is the subject, not the frame.
library;

import 'package:noir/noir.dart';

/// The standard demo frame: themed surface, bold title, muted hint, body.
class DemoScaffold extends StatelessWidget {
  /// Frames [child] under a bold [title], an optional muted [hint], and any
  /// [titleTrailing] widgets laid on the title row.
  const DemoScaffold({
    required this.title,
    required this.child,
    this.hint,
    this.titleTrailing = const [],
    super.key,
  });

  /// Bold heading on the first row.
  final String title;

  /// Muted instruction line under the title; omitted when null.
  final String? hint;

  /// Widgets laid after the title on the same row — a badge, a spinner.
  final List<Widget> titleTrailing;

  /// Demo body below the header.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = this.hint;
    return Container(
      color: theme.surface,
      alignment: Alignment.topLeft,
      padding: const EdgeInsets(left: 2, top: 1, right: 2, bottom: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            spacing: 1,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: theme.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...titleTrailing,
            ],
          ),
          if (hint != null)
            Text(hint, style: TextStyle(color: theme.textMuted)),
          const SizedBox(height: 1),
          child,
        ],
      ),
    );
  }
}

/// A bordered, optionally titled panel whose border turns to the theme accent
/// while [focused] is true — the demos' shared "this pane owns the keyboard"
/// affordance.
class DemoPanel extends StatelessWidget {
  /// Wraps [child] in a themed border, titled when [title] is non-null.
  const DemoPanel({
    required this.child,
    this.title,
    this.focused = false,
    this.width,
    this.height,
    super.key,
  });

  /// Label drawn on the top border; omitted when null.
  final String? title;

  /// Whether to paint the border and title in the theme accent.
  final bool focused;

  /// Fixed width in cells, or null to size to content.
  final int? width;

  /// Fixed height in cells, or null to size to content.
  final int? height;

  /// Panel content below the optional title.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = this.title;
    final chrome = focused ? theme.accent : theme.border;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        border: Border.all(
          color: chrome,
          title: title == null ? null : ' $title ',
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: child,
    );
  }
}
