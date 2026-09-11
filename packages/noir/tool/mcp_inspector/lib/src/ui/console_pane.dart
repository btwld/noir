import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';

/// The full-width console tab: child standard error and server notices.
///
/// The view follows the tail, so new output stays visible until the user
/// scrolls up.
class ConsolePane extends StatelessWidget {
  /// Creates the pane over [controller].
  const ConsolePane({
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    super.key,
  });

  /// The state owner this pane reads.
  final InspectorController controller;

  /// The follow-tail controller shared across rebuilds.
  final ScrollController scrollController;

  /// The node that owns keyboard focus for scrolling.
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = controller.consoleLines;
    return Panel(
      title: 'Console (${lines.length})',
      focused: focusNode.hasFocus,
      child: lines.isEmpty
          ? Text(
              'The server has written nothing yet.',
              style: TextStyle(color: theme.textMuted),
            )
          : ScrollBox(
              controller: scrollController,
              focusNode: focusNode,
              autofocus: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var index = 0; index < lines.length; index++)
                    Text(
                      lines[index],
                      key: ValueKey<String>('console:$index'),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
    );
  }
}
