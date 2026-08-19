import '../core/input.dart';
import '../foundation/text_editing_controller.dart';
import '../foundation/text_selection.dart';
import '../framework/widget.dart';
import 'focus_node_owner_mixin.dart';
import 'text_input_connection.dart';

/// State mixin for the editable text widgets (`TextInput`, `TextArea`) that own
/// a [TextEditingController] and route paste/pointer/focus input.
///
/// Consolidates the controller lifecycle and input-event plumbing that is
/// identical between the two fields. Subclasses supply the widget-specific
/// [connection] (single- vs multi-line parameters differ) and may override
/// [onControllerChanged] to react to edits — `TextArea` scrolls the cursor into
/// view; single-line `TextInput` just rebuilds.
///
/// Composes on [FocusNodeOwnerStateMixin] so [focusNode] is shared and the
/// dispose chain runs this mixin's teardown before the focus node's. Internal
/// to the widgets layer — not exported from any barrel.
mixin TextEditingOwnerStateMixin<T extends StatefulWidget>
    on State<T>, FocusNodeOwnerStateMixin<T> {
  late TextEditingController _controller;
  bool _ownsController = false;
  bool _controllerListenerAttached = false;
  bool _repairingActiveSelection = false;
  InputSubscription? _pasteSubscription;

  /// Controller that owns the field's text and selection state.
  TextEditingController get controller => _controller;

  /// The [TextEditingController] supplied by the host widget's constructor,
  /// or null to have this mixin create and own one.
  TextEditingController? get widgetController;

  /// The widget's initial/current text value, used only when
  /// [widgetController] is null.
  String? get widgetValue;

  /// Input connection that routes key events into edits for this field.
  TextInputConnection get connection;

  /// Hook fired on every controller change, before the rebuild. Subclasses
  /// override to react (e.g. scroll the cursor into view); the default no-op
  /// means a plain single-line field simply rebuilds.
  void onControllerChanged() {}

  /// Adopts [next], owning its disposal only when [ownsController], and
  /// releases whichever controller this state had attached before.
  ///
  /// The swap is transactional: [next] is subscribed before the previous
  /// controller is released, so a failing `addListener` — reachably, a caller
  /// supplying an already-disposed controller — leaves this state on its
  /// previous, still-live controller with its ownership unchanged.
  ///
  /// Deliberate design decision: attaching subsumes detaching. This replaced
  /// an earlier guard that threw when a controller was already attached —
  /// that guard would force callers to detach first, reopening the window
  /// where the old controller is gone before the new one is proven usable.
  void attachController(
    TextEditingController next, {
    required bool ownsController,
  }) {
    next.addListener(handleControllerChanged);
    detachController();
    _controller = next;
    _ownsController = ownsController;
    _controllerListenerAttached = true;
  }

  /// Drops the current controller, disposing it when this state owns it.
  void detachController() {
    if (!_controllerListenerAttached) return;
    _controllerListenerAttached = false;
    _controller.removeListener(handleControllerChanged);
    final disposeController = _ownsController;
    _ownsController = false;
    if (disposeController) {
      _controller.dispose();
    }
  }

  /// Adopts the widget-configured controller and subscribes to terminal
  /// paste events at focus priority. Call from `initState`, after any
  /// widget-parameter validation.
  void initController() {
    attachController(
      _createWidgetController(),
      ownsController: widgetController == null,
    );
    _pasteSubscription = context.owner.inputManager.onPaste(
      handlePasteEvent,
      priority: InputPriority.focus,
    );
  }

  /// Reconciles the controller with an updated widget configuration.
  /// Subclasses that override `didUpdateWidget` must call
  /// `syncController(oldWidget.controller, oldWidget.value)` exactly once,
  /// after `syncFocusNode`.
  void syncController(
    TextEditingController? oldWidgetController,
    String? oldWidgetValue,
  ) {
    var controllerChanged = false;
    if (!identical(widgetController, oldWidgetController)) {
      attachController(
        _createWidgetController(),
        ownsController: widgetController == null,
      );
      controllerChanged = true;
    } else if (widgetController == null &&
        widgetValue != oldWidgetValue &&
        widgetValue != null &&
        widgetValue != controller.text) {
      controller.text = widgetValue!;
    }
    reconcileControllerUpdate(controllerChanged: controllerChanged);
  }

  TextEditingController _createWidgetController() =>
      widgetController ?? TextEditingController(text: widgetValue ?? '');

  /// Rebuilds on controller changes, after running [onControllerChanged].
  void handleControllerChanged() {
    if (_repairingActiveSelection) return;
    _repairActiveSelection();
    onControllerChanged();
    if (mounted) {
      setState(() {});
    }
  }

  /// Requests focus when the field's leaf is clicked.
  void handlePointerDown(MouseEvent event) {
    if (event.button == MouseButton.left && !focusNode.hasFocus) {
      focusNode.requestFocus();
    }
  }

  /// Rebuilds on focus changes so the leaf re-emits its `focused` prop and the
  /// cursor toggles.
  // Positional bool mirrors the `Focus(onFocusChange:)` ValueChanged<bool>.
  // ignore: avoid_positional_boolean_parameters
  void handleFocusChange(bool focused) {
    if (focused) {
      _repairActiveSelection();
      onControllerChanged();
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Reconciles selection after the widget has chosen its final controller
  /// and focus node for an update already owned by the parent rebuild.
  void reconcileControllerUpdate({required bool controllerChanged}) {
    final repaired = _repairActiveSelection();
    if (controllerChanged || repaired) {
      onControllerChanged();
    }
  }

  /// Rejects a focused build whose selection escaped lifecycle reconciliation.
  void requireUsableSelectionForBuild() {
    if (focusNode.hasFocus && !_hasUsableSelection) {
      throw StateError(
        'A focused text editor requires an in-range controller selection.',
      );
    }
  }

  bool get _hasUsableSelection => _controller.selectionWithinText;

  bool _repairActiveSelection() {
    if (!focusNode.hasFocus || _hasUsableSelection) return false;
    _repairingActiveSelection = true;
    try {
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    } finally {
      _repairingActiveSelection = false;
    }
    if (!_hasUsableSelection) {
      throw StateError(
        'Selection remained unusable after active-editor repair.',
      );
    }
    return true;
  }

  /// Inserts pasted text when focused and the event is not already consumed.
  void handlePasteEvent(PasteEvent event) {
    if (event.isConsumed || !focusNode.hasFocus) {
      return;
    }
    if (connection.insertText(event.text) == KeyEventResult.handled) {
      event.consume();
    }
  }

  @override
  void dispose() {
    _pasteSubscription?.cancel();
    detachController();
    super.dispose();
  }
}
