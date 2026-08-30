// The option builder keeps `highlighted` positional beside the option it
// describes, matching ListViewItemBuilder.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:async';
import 'dart:math' as math;

import '../core/color.dart';
import '../core/input.dart';
import '../foundation/listenable.dart';
import '../foundation/text_editing_controller.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'actions.dart';
import 'container.dart';
import 'focus_node_owner_mixin.dart';
import 'input.dart';
import 'intents.dart';
import 'list_view.dart';
import 'overlay.dart' show WidgetBuilder;
import 'row_column.dart';
import 'shortcuts.dart';
import 'sized_box.dart';
import 'text.dart';
import 'theme.dart';

/// Presentation supplied to a controlled [Autocomplete].
enum AutocompleteStatus {
  /// Only the text field is visible.
  idle,

  /// An attached loading surface is visible.
  loading,

  /// The supplied non-empty option list is visible and selectable.
  ready,

  /// An attached empty-result surface is visible.
  empty,

  /// An attached failure surface is visible.
  error,
}

/// Builds one option in an [Autocomplete] suggestion list.
///
/// [highlighted] reports the active row. Long content should use a bounded
/// widget such as `Text(maxLines: 1, overflow: TextOverflow.ellipsis)`.
typedef AutocompleteOptionBuilder<T> =
    Widget Function(BuildContext context, T option, bool highlighted);

/// A controlled text field with an attached suggestion presentation.
///
/// The caller owns [controller], [options], and [status]. This widget owns only
/// terminal interaction and presentation: it never fetches, filters,
/// debounces, or suppresses stale asynchronous results.
///
/// Tab follows ordinary focus traversal from the field into a ready option
/// list. List navigation moves the highlight; Enter in either the field or
/// list and a primary click select through [onSelected]. Escape invokes
/// [onDismiss] only while a presentation is visible. Selection and dismissal
/// restore field focus when that node remains live and requestable.
///
/// Omitted focus nodes are created and disposed by this widget. Supplied nodes
/// and the required text controller are borrowed and never disposed.
class Autocomplete<T> extends StatefulWidget {
  /// Creates a controlled autocomplete field and attached presentation.
  const Autocomplete({
    required this.controller,
    required this.options,
    required this.status,
    required this.optionBuilder,
    required this.onChanged,
    required this.onSelected,
    required this.onDismiss,
    super.key,
    this.focusNode,
    this.optionsFocusNode,
    this.placeholder,
    this.autofocus = false,
    this.maxOptionsHeight = 5,
    this.showScrollIndicator = false,
    this.loadingBuilder,
    this.emptyBuilder,
    this.errorBuilder,
    this.inputBackgroundColor,
    this.optionsBackgroundColor,
    this.selectedBackgroundColor,
  }) : assert(maxOptionsHeight >= 1),
       assert(
         focusNode == null ||
             optionsFocusNode == null ||
             !identical(focusNode, optionsFocusNode),
         'Autocomplete field and options must use different FocusNodes.',
       );

  /// Borrowed owner of the field's text and selection.
  final TextEditingController controller;

  /// Controlled options displayed when [status] is [AutocompleteStatus.ready].
  final List<T> options;

  /// Controlled presentation shown below the field.
  final AutocompleteStatus status;

  /// Builds one visible option row.
  final AutocompleteOptionBuilder<T> optionBuilder;

  /// Receives every edit made by the internal text field.
  final ValueChanged<String> onChanged;

  /// Receives the option chosen by Enter or a primary click.
  final ValueChanged<T> onSelected;

  /// Must update controlled state to hide the presentation after Escape.
  final VoidCallback onDismiss;

  /// Borrowed field focus node, or null for an internally owned node.
  ///
  /// When both focus nodes are supplied, this must differ from
  /// [optionsFocusNode].
  final FocusNode? focusNode;

  /// Borrowed suggestion-list focus node, or null for an internally owned node.
  ///
  /// When both focus nodes are supplied, this must differ from [focusNode].
  final FocusNode? optionsFocusNode;

  /// Hint painted by the text field while its value is empty.
  final String? placeholder;

  /// Whether the field requests focus when first mounted.
  final bool autofocus;

  /// Maximum number of ready option rows painted at once. Must be at least 1.
  final int maxOptionsHeight;

  /// Whether the ready list reserves a scroll-indicator gutter.
  final bool showScrollIndicator;

  /// Replaces the default one-row `Loading…` presentation.
  final WidgetBuilder? loadingBuilder;

  /// Replaces the default one-row `No options.` presentation.
  final WidgetBuilder? emptyBuilder;

  /// Replaces the default one-row `Options unavailable.` presentation.
  final WidgetBuilder? errorBuilder;

  /// Fill passed to the internal text field.
  final Color? inputBackgroundColor;

  /// Fill behind every attached status or option surface.
  ///
  /// Falls back to [ThemeData.surfaceVariant], including the dark fallback
  /// when no [Theme] ancestor exists.
  final Color? optionsBackgroundColor;

  /// Fill behind the highlighted option while its list has focus.
  ///
  /// Falls back through [ListView] to [ThemeData.selectedBackground].
  final Color? selectedBackgroundColor;

  @override
  State<Autocomplete<T>> createState() => _AutocompleteState<T>();
}

class _AutocompleteState<T> extends State<Autocomplete<T>>
    with FocusNodeOwnerStateMixin<Autocomplete<T>> {
  late FocusNode _optionsFocusNode;
  late bool _ownsOptionsFocusNode;
  var _highlightedIndex = 0;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  FocusNode createDefaultFocusNode() =>
      FocusNode(debugLabel: 'Autocomplete Field');

  bool get _isReady => widget.status == AutocompleteStatus.ready;

  bool get _hasPresentation => widget.status != AutocompleteStatus.idle;

  @override
  void initState() {
    super.initState();
    final supplied = widget.optionsFocusNode;
    _optionsFocusNode =
        supplied ?? FocusNode(debugLabel: 'Autocomplete Options');
    _ownsOptionsFocusNode = supplied == null;
    // Initialize every owned field before validation so failed mounts can
    // dispose both nodes during framework rollback.
    _validateConfiguration();
  }

  @override
  void didUpdateWidget(Autocomplete<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
    final optionsHadFocus = _optionsFocusNode.hasFocus;
    syncFocusNode(oldWidget.focusNode);
    _syncOptionsFocusNode(oldWidget.optionsFocusNode);

    if (_isReady) {
      _highlightedIndex = oldWidget.status == AutocompleteStatus.ready
          ? _highlightedIndex.clamp(0, widget.options.length - 1)
          : 0;
    } else {
      _highlightedIndex = 0;
    }

    if (optionsHadFocus) {
      if (_isReady) {
        _scheduleOptionsFocus();
      } else {
        _scheduleFieldFocus();
      }
    }
  }

  void _validateConfiguration() {
    if (widget.maxOptionsHeight < 1) {
      throw ArgumentError.value(
        widget.maxOptionsHeight,
        'maxOptionsHeight',
        'must be at least 1',
      );
    }
    if (widget.status == AutocompleteStatus.ready && widget.options.isEmpty) {
      throw StateError(
        'AutocompleteStatus.ready requires at least one option.',
      );
    }
    if (widget.focusNode != null &&
        identical(widget.focusNode, widget.optionsFocusNode)) {
      throw StateError(
        'Autocomplete field and options must use different FocusNodes.',
      );
    }
  }

  void _syncOptionsFocusNode(FocusNode? oldWidgetNode) {
    if (identical(oldWidgetNode, widget.optionsFocusNode)) {
      return;
    }
    final old = _optionsFocusNode;
    final oldOwned = _ownsOptionsFocusNode;
    final supplied = widget.optionsFocusNode;
    if (supplied != null) {
      validateFocusNodeReplacementTarget(supplied, old, context);
    }
    _optionsFocusNode =
        supplied ?? FocusNode(debugLabel: 'Autocomplete Options');
    _ownsOptionsFocusNode = supplied == null;
    if (oldOwned) {
      old.dispose();
    }
  }

  void _scheduleFieldFocus() {
    scheduleMicrotask(() {
      if (mounted) _requestFocus(focusNode);
    });
  }

  void _scheduleOptionsFocus() {
    scheduleMicrotask(() {
      if (mounted && _isReady) _requestFocus(_optionsFocusNode);
    });
  }

  void _requestFocus(FocusNode node) {
    if (node.isAttached && node.canRequestFocus) {
      node.requestFocus();
    }
  }

  void _setHighlighted(int index) {
    final next = index.clamp(0, widget.options.length - 1);
    if (next == _highlightedIndex) return;
    setState(() => _highlightedIndex = next);
  }

  KeyEventResult _select(int index) {
    if (!_isReady || index < 0 || index >= widget.options.length) {
      return KeyEventResult.ignored;
    }
    widget.onSelected(widget.options[index]);
    if (mounted) _requestFocus(focusNode);
    return KeyEventResult.handled;
  }

  KeyEventResult _dismiss() {
    if (!_hasPresentation) return KeyEventResult.ignored;
    widget.onDismiss();
    if (mounted) _requestFocus(focusNode);
    return KeyEventResult.handled;
  }

  Widget _buildStatus(
    BuildContext context,
    WidgetBuilder? builder,
    String fallback,
  ) => SizedBox(
    height: 1,
    child: Container(
      padding: const EdgeInsets.only(left: 1, right: 1),
      child: builder?.call(context) ?? Text(fallback),
    ),
  );

  Widget _buildPresentation(BuildContext context) => switch (widget.status) {
    AutocompleteStatus.idle => const SizedBox.shrink(),
    AutocompleteStatus.loading => _buildStatus(
      context,
      widget.loadingBuilder,
      'Loading…',
    ),
    AutocompleteStatus.empty => _buildStatus(
      context,
      widget.emptyBuilder,
      'No options.',
    ),
    AutocompleteStatus.error => _buildStatus(
      context,
      widget.errorBuilder,
      'Options unavailable.',
    ),
    AutocompleteStatus.ready => ListView(
      itemCount: widget.options.length,
      height: math.min(widget.options.length, widget.maxOptionsHeight),
      selectedIndex: _highlightedIndex,
      showScrollIndicator: widget.showScrollIndicator,
      backgroundColor: Color.transparent,
      selectedBackgroundColor: widget.selectedBackgroundColor,
      focusNode: _optionsFocusNode,
      onChanged: _setHighlighted,
      onSelect: _select,
      itemBuilder: (context, index, selected) =>
          widget.optionBuilder(context, widget.options[index], selected),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final palette = Theme.maybeOf(context) ?? ThemeData.dark;
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        if (_hasPresentation)
          const SingleActivator(LogicalKeyboardKey.escape):
              const _DismissAutocompleteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _DismissAutocompleteIntent:
              CallbackAction<_DismissAutocompleteIntent>(
                (intent, context) => _dismiss(),
              ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextInput(
              controller: widget.controller,
              placeholder: widget.placeholder,
              backgroundColor: widget.inputBackgroundColor,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              onChanged: widget.onChanged,
              onSubmit: () => _select(_highlightedIndex),
            ),
            if (_hasPresentation)
              Container(
                color: widget.optionsBackgroundColor ?? palette.surfaceVariant,
                child: _buildPresentation(context),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_ownsOptionsFocusNode) {
      _optionsFocusNode.dispose();
    }
    super.dispose();
  }
}

class _DismissAutocompleteIntent extends Intent {
  const _DismissAutocompleteIntent();
}
