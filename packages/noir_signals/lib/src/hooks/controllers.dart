import 'package:noir/noir.dart';

import 'primitives.dart';

/// Creates and owns a [TextEditingController].
///
/// [text] is used only when the controller is created. Change the returned
/// controller directly for later text updates.
TextEditingController useTextEditingController({
  String text = '',
  List<Object?> keys = const <Object?>[],
}) => useDisposable<TextEditingController>(
  () => TextEditingController(text: text),
  keys,
);

/// Creates and owns a [FocusNode].
///
/// [onKeyEvent] and [canRequestFocus] update the retained node. [debugLabel]
/// is used only when the node is created because Noir exposes it as immutable.
/// Use an explicit key when a changed label should recreate the node.
FocusNode useFocusNode({
  String? debugLabel,
  FocusOnKeyEvent? onKeyEvent,
  bool canRequestFocus = true,
  List<Object?> keys = const <Object?>[],
}) {
  final node = useDisposable<FocusNode>(
    () => FocusNode(
      debugLabel: debugLabel,
      onKeyEvent: onKeyEvent,
      canRequestFocus: canRequestFocus,
    ),
    keys,
  );
  node
    ..onKeyEvent = onKeyEvent
    ..canRequestFocus = canRequestFocus;
  return node;
}

/// Creates and owns a [ScrollController].
///
/// [initialOffset] is used only when the controller is created.
ScrollController useScrollController({
  double initialOffset = 0,
  List<Object?> keys = const <Object?>[],
}) => useDisposable<ScrollController>(
  () => ScrollController(initialOffset: initialOffset),
  keys,
);

/// Creates and owns a [ViewportController].
///
/// Initial extents and offset are used only when the controller is created.
ViewportController useViewportController({
  int initialContentExtent = 0,
  int initialViewportExtent = 0,
  int initialScrollOffset = 0,
  List<Object?> keys = const <Object?>[],
}) => useDisposable<ViewportController>(
  () => ViewportController(
    contentExtent: initialContentExtent,
    viewportExtent: initialViewportExtent,
    scrollOffset: initialScrollOffset,
  ),
  keys,
);
