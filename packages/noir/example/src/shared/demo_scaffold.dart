/// Shared chrome for the Noir example apps.
///
/// Every demo used to hand-roll the same padded surface with a bold title and
/// muted hint. This file keeps that application-specific page frame in one
/// place; reusable bordered regions use Noir's public [Panel]. All chrome
/// colors come from `Theme.of(context)`, so the demos render on
/// `ThemeData.dark` by default and re-skin together under any `Theme`.
///
/// The card is content-sized vertically. Horizontal room comes from the
/// scaffold owning the terminal (`alignment: topLeft`) and a 2-cell side
/// inset so the page title is not glued to the edge.
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
