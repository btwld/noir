import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/listenable.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/key.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/box.dart';
import '../rendering/overlay.dart';
import 'actions.dart';
import 'focus.dart';
import 'intents.dart';
import 'overlay.dart';
import 'row_column.dart';
import 'shortcuts.dart';

/// Builds the [MenuAnchor] launcher from the attached [MenuController].
typedef MenuAnchorChildBuilder =
    Widget Function(
      BuildContext context,
      MenuController controller,
      Widget? child,
    );

/// Opens and closes a single [MenuAnchor].
///
/// [isOpen] is false while detached. [open] throws in every build mode until a
/// [MenuAnchor] attaches; menus have no pending-open contract. [close] is a
/// no-op while detached or already closed. [maybeOf] returns the nearest
/// logical ancestor's controller without registering an inherited dependency.
final class MenuController {
  /// Starts detached; [open] throws until a [MenuAnchor] attaches.
  MenuController();

  _MenuAnchorState? _client;

  /// Whether the attached anchor currently has an open menu.
  bool get isOpen => _client?._isOpen ?? false;

  /// Opens the attached menu. Throws if this controller is not attached.
  void open({Offset? position}) {
    final client = _client;
    if (client == null) {
      throw StateError(
        'MenuController.open() was called before the controller was attached '
        'to a MenuAnchor.',
      );
    }
    client.open(position: position);
  }

  /// Closes the attached menu. Unattached or already-closed calls are no-ops.
  void close() {
    _client?.close();
  }

  /// The nearest enclosing [MenuAnchor] controller, without a dependency.
  static MenuController? maybeOf(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<_MenuAnchorScope>()
        ?.widget;
    return scope is _MenuAnchorScope ? scope.controller : null;
  }

  void _attach(_MenuAnchorState state) {
    if (_client != null && !identical(_client, state)) {
      throw StateError(
        'MenuController is already attached to another MenuAnchor.',
      );
    }
    _client = state;
  }

  void _detach(_MenuAnchorState state) {
    if (!identical(_client, state)) {
      return;
    }
    _client = null;
  }
}

/// Shows [menuChildren] on the package-owned root overlay, anchored to the
/// launcher.
///
/// Placement uses integer terminal cells and follows the current-frame
/// launcher geometry. Resize or ancestor movement repositions an open menu in
/// that same frame; unlike Flutter, Noir does not close on view resize or
/// anchor movement. [MenuController.open]'s optional [Offset] is launcher-local
/// and ignores [alignmentOffset].
///
/// Outside pointer events are consumed at render-tree priority so they cannot
/// reach lower targets. Only a left-button down closes the topmost menu;
/// other outside pointer kinds are consumed without closing. [TuiApp.onMouse]
/// remains app-priority and may still observe the raw event.
///
/// Escape, Tab, and Shift+Tab close the open menu, consume the key, and
/// restore focus. Tab does not advance on that dismissal event. Independent
/// anchors do not form a group. Caller-supplied [controller] replacement
/// preserves the current open subtree without firing [onOpen] or [onClose];
/// teardown also skips those callbacks.
class MenuAnchor extends StatefulWidget {
  /// Anchors [menuChildren] to [builder] or [child] on the root overlay.
  const MenuAnchor({
    required this.menuChildren,
    super.key,
    this.controller,
    this.childFocusNode,
    this.alignmentOffset = Offset.zero,
    this.reservedPadding,
    this.onOpen,
    this.onClose,
    this.builder,
    this.child,
  });

  /// Caller-owned controller, or null to use an internal one.
  final MenuController? controller;

  /// Focus node restored when the menu closes, when supplied.
  final FocusNode? childFocusNode;

  /// Extra offset from the launcher's bottom-start. Null is [Offset.zero].
  final Offset? alignmentOffset;

  /// Safe-area padding inside the terminal. Null is [EdgeInsets.zero].
  final EdgeInsets? reservedPadding;

  /// Invoked once on each closed-to-open transition.
  final VoidCallback? onOpen;

  /// Invoked once on each open-to-close transition, except teardown.
  final VoidCallback? onClose;

  /// Unstyled vertical children of the open menu.
  final List<Widget> menuChildren;

  /// Builds the launcher from the active controller.
  final MenuAnchorChildBuilder? builder;

  /// Launcher widget when [builder] is omitted.
  final Widget? child;

  @override
  State<MenuAnchor> createState() => _MenuAnchorState();
}

class _MenuAnchorState extends State<MenuAnchor> {
  final _portalController = OverlayPortalController();
  final _anchorKey = GlobalKey();
  MenuController? _owned;
  var _isOpen = false;
  Offset? _explicitAnchorLocal;
  FocusNode? _restoreNode;
  FocusManager? _restoreManager;

  MenuController get _controller => widget.controller ?? _owned!;

  void open({Offset? position}) {
    _validatePadding();
    _explicitAnchorLocal = position;
    if (_isOpen) {
      _portalController.show();
      setState(() {});
      return;
    }
    _restoreManager = context.owner.focusManager;
    _restoreNode =
        widget.childFocusNode ?? context.owner.focusManager.primaryFocus;
    _isOpen = true;
    widget.onOpen?.call();
    _portalController.show();
    setState(() {});
  }

  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    widget.onClose?.call();
    _portalController.hide();
    _restoreFocus();
    setState(() {});
  }

  void _restoreFocus() {
    final node = _restoreNode;
    final manager = _restoreManager;
    _restoreNode = null;
    _restoreManager = null;
    if (node == null || manager == null) {
      return;
    }
    if (node.isAttachedTo(manager) && node.canRequestFocus) {
      node.requestFocus();
    }
  }

  void _handleOutsidePointer(MouseEvent event) {
    event.consume();
    if (event.type == MouseEventType.down && event.button == MouseButton.left) {
      close();
    }
  }

  void _validatePadding() {
    final padding = widget.reservedPadding ?? EdgeInsets.zero;
    if (padding.left < 0 ||
        padding.top < 0 ||
        padding.right < 0 ||
        padding.bottom < 0) {
      throw ArgumentError.value(
        widget.reservedPadding,
        'reservedPadding',
        'must be non-negative',
      );
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _owned = MenuController();
    }
    _controller._attach(this);
  }

  @override
  void didUpdateWidget(MenuAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.controller ?? _owned;
    if (oldWidget.controller == null && widget.controller != null) {
      _owned!._detach(this);
      _owned = null;
      widget.controller!._attach(this);
    } else if (oldWidget.controller != null && widget.controller == null) {
      oldWidget.controller!._detach(this);
      _owned = MenuController().._attach(this);
    } else if (!identical(oldController, _controller)) {
      oldController!._detach(this);
      _controller._attach(this);
    }
  }

  @override
  void dispose() {
    _isOpen = false;
    _controller._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _validatePadding();
    if (widget.builder == null && widget.child == null) {
      throw StateError('MenuAnchor requires builder or child.');
    }
    return Shortcuts(
      shortcuts: _isOpen
          ? const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.tab): DismissIntent(),
              SingleActivator(LogicalKeyboardKey.tab, shift: true):
                  DismissIntent(),
            }
          : const <ShortcutActivator, Intent>{},
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>((intent, context) {
            close();
            return KeyEventResult.handled;
          }),
        },
        child: _MenuAnchorScope(
          controller: _controller,
          child: rawOverlayPortal(
            controller: _portalController,
            overlayChildBuilder: _buildOverlay,
            child: _MenuLauncher(
              key: _anchorKey,
              controller: _controller,
              builder: widget.builder,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverlay(BuildContext context) {
    final renderObject = _anchorKey.currentContext?.findRenderObject();
    final anchor = renderObject is RenderBox ? renderObject : null;
    return FocusScope(
      child: _MenuOverlay(
        anchor: anchor,
        alignmentOffset: widget.alignmentOffset ?? Offset.zero,
        reservedPadding: widget.reservedPadding ?? EdgeInsets.zero,
        explicitAnchorLocal: _explicitAnchorLocal,
        onOutsidePointer: _handleOutsidePointer,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widget.menuChildren,
        ),
      ),
    );
  }
}

class _MenuAnchorScope extends InheritedWidget {
  const _MenuAnchorScope({required this.controller, required super.child});

  final MenuController controller;

  @override
  bool updateShouldNotify(_MenuAnchorScope oldWidget) =>
      !identical(oldWidget.controller, controller);
}

class _MenuLauncher extends StatelessWidget {
  const _MenuLauncher({
    required this.controller,
    super.key,
    this.builder,
    this.child,
  });

  final MenuController controller;
  final MenuAnchorChildBuilder? builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      builder?.call(context, controller, child) ?? child!;
}

class _MenuOverlay extends SingleChildRenderObjectWidget {
  const _MenuOverlay({
    required super.child,
    this.anchor,
    this.alignmentOffset = Offset.zero,
    this.reservedPadding = EdgeInsets.zero,
    this.explicitAnchorLocal,
    this.onOutsidePointer,
  });

  final RenderBox? anchor;
  final Offset alignmentOffset;
  final EdgeInsets reservedPadding;
  final Offset? explicitAnchorLocal;
  final PointerBarrierHandler? onOutsidePointer;

  @override
  @internal
  RenderOverlayEntry createRenderObject(BuildContext context) =>
      RenderOverlayEntry(
        modalBarrier: true,
        onOutsidePointer: onOutsidePointer,
        anchor: anchor,
        alignmentOffset: alignmentOffset,
        reservedPadding: reservedPadding,
        explicitAnchorLocal: explicitAnchorLocal,
      );

  @override
  @internal
  void updateRenderObject(
    BuildContext context,
    RenderOverlayEntry renderObject,
  ) {
    renderObject
      ..modalBarrier = true
      ..onOutsidePointer = onOutsidePointer
      ..anchor = anchor
      ..alignmentOffset = alignmentOffset
      ..reservedPadding = reservedPadding
      ..explicitAnchorLocal = explicitAnchorLocal;
  }
}
