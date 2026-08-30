import 'dart:async';

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/first_error.dart';
import '../foundation/listenable.dart';
import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/stack.dart';
import 'actions.dart';
import 'align.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'intents.dart';
import 'overlay.dart';
import 'pointer_listener.dart';
import 'shortcuts.dart';
import 'sized_box.dart';
import 'stack.dart';

final _openModals = Expando<List<_ModalState>>('open modals');

/// Opens and closes exactly one attached [Modal].
///
/// [isOpen] is false while detached. [open] throws in every build mode until
/// a [Modal] attaches; modals have no pending-open contract. [close] is a
/// no-op while detached or already closed. Replacing a controller on a live
/// modal transfers control without changing visibility.
final class ModalController {
  /// Starts detached; [open] throws until a [Modal] attaches.
  ModalController();

  _ModalState? _client;

  /// Whether the attached modal is currently open, or false while detached.
  bool get isOpen => _client?._isOpen ?? false;

  /// Opens the attached modal.
  ///
  /// An already-open call preserves the modal subtree and moves its overlay
  /// entry to the top, reestablishing focus inside it, without invoking
  /// [Modal.onOpen] again. Throws a [StateError] when this controller is
  /// detached.
  void open() {
    final client = _client;
    if (client == null) {
      throw StateError(
        'ModalController.open() was called before the controller was '
        'attached to a Modal.',
      );
    }
    client.open();
  }

  /// Closes the attached modal.
  ///
  /// Detached and already-closed calls are no-ops.
  void close() {
    _client?.close();
  }

  void _attach(_ModalState state) {
    _validateAttachment(state);
    _client = state;
  }

  void _validateAttachment(_ModalState state) {
    if (_client != null && !identical(_client, state)) {
      throw StateError('ModalController is already attached to another Modal.');
    }
  }

  void _detach(_ModalState state) {
    if (identical(_client, state)) {
      _client = null;
    }
  }
}

/// Hosts an unstyled modal behavior boundary above [child].
///
/// [modalBuilder] runs only while the modal is open. Closing destroys that
/// subtree; opening again builds fresh state. The visible child is centered in
/// the current terminal and applications provide their own chrome, typically
/// with `Panel`. Resize recenters the same open subtree.
///
/// Opening snapshots the current focus. After the overlay mounts, focus moves
/// to a live modal [initialFocusNode], or otherwise to its first live focusable
/// descendant. Closing restores the snapshot only while it remains attached
/// to the same focus manager and can still request focus. Tab and Shift+Tab
/// form a live closed loop over the modal's requestable descendants; a modal
/// with no such descendants keeps focus on its private scope.
///
/// All pointer events outside the modal content are consumed at render-tree
/// priority. [dismissOnOutsideClick] optionally closes on a primary-button
/// down, while other outside events remain blocked. App-priority mouse
/// observers may still see the raw event. Escape closes by default.
/// When several modals share a focus manager, the topmost open entry owns
/// focus repair. Closing it preserves a valid restored focus inside the modal
/// below, or repairs that newly exposed modal to an available descendant.
///
/// Transition callbacks observe the new [ModalController.isOpen] value. A
/// callback error does not leave the requested transition half-finished: the
/// first error is rethrown after cleanup. Reentrant [ModalController.open] or
/// [ModalController.close] calls determine the final state. Controller
/// replacement preserves an open subtree without callbacks, and teardown does
/// not invoke [onClose].
class Modal extends StatefulWidget {
  /// Creates an unstyled modal behavior boundary.
  const Modal({
    required this.controller,
    required this.modalBuilder,
    required this.child,
    super.key,
    this.initialFocusNode,
    this.dismissOnEscape = true,
    this.dismissOnOutsideClick = false,
    this.onOpen,
    this.onClose,
  });

  /// Controller attached exclusively to this modal while it is mounted.
  final ModalController controller;

  /// Builds the centered overlay subtree only while open.
  ///
  /// Closing destroys the subtree, so each later open receives fresh [State].
  final WidgetBuilder modalBuilder;

  /// Ordinary subtree retained and painted below the modal.
  final Widget child;

  /// Preferred caller-owned focus node for each fresh open.
  ///
  /// The node is used only when it is attached, can request focus, and belongs
  /// to this modal. Otherwise the first live focusable descendant is used.
  final FocusNode? initialFocusNode;

  /// Whether Escape closes the modal.
  ///
  /// Defaults to true. When false, Escape remains available to an ancestor.
  final bool dismissOnEscape;

  /// Whether an outside primary-button press closes the modal.
  ///
  /// All outside pointer events are blocked regardless of this value.
  final bool dismissOnOutsideClick;

  /// Invoked after each closed-to-open transition starts.
  ///
  /// [ModalController.isOpen] is true, but the overlay has not mounted yet.
  final VoidCallback? onOpen;

  /// Invoked after each open-to-close transition starts, except teardown.
  ///
  /// [ModalController.isOpen] is false, before the overlay is removed and
  /// captured focus is restored.
  final VoidCallback? onClose;

  @override
  State<Modal> createState() => _ModalState();

  @override
  @internal
  Element createElement() => _ModalElement(this);
}

class _ModalElement extends StatefulElement {
  _ModalElement(Modal super.widget);

  @override
  void update(Widget newWidget) {
    final previous = widget as Modal;
    final next = newWidget as Modal;
    if (!identical(previous.controller, next.controller)) {
      next.controller._validateAttachment(state as _ModalState);
    }
    super.update(newWidget);
  }
}

class _ModalState extends State<Modal> with FocusNodeOwnerStateMixin<Modal> {
  final _portalController = OverlayPortalController();
  final _traversalPolicy = const _ModalFocusTraversalPolicy();
  var _isOpen = false;
  var _hasRestoreSnapshot = false;
  var _focusRequest = 0;
  var _focusRepairScheduled = false;
  FocusManager? _openManager;
  FocusManager? _restoreManager;
  FocusNode? _restoreNode;

  @override
  FocusNode? get widgetFocusNode => null;

  @override
  FocusNode createDefaultFocusNode() => FocusScopeNode(
    debugLabel: 'Modal Focus Scope',
    traversalPolicy: _traversalPolicy,
  );

  FocusScopeNode get _scopeNode => focusNode as FocusScopeNode;

  void open() {
    if (_isOpen) {
      _portalController.show();
      _moveToTop();
      _scheduleFocusRepair();
      return;
    }
    if (!_hasRestoreSnapshot) {
      final manager = context.owner.focusManager;
      _restoreManager = manager;
      _restoreNode = manager.primaryFocus;
      _hasRestoreSnapshot = true;
    }
    _isOpen = true;
    final request = ++_focusRequest;
    final failures = FirstErrorRecorder();
    failures.attempt(() => widget.onOpen?.call());
    if (_isOpen) {
      failures.attempt(_portalController.show);
      _moveToTop();
      failures.attempt(() => setState(() {}));
      scheduleMicrotask(() => _focusAfterMount(request));
    }
    failures.rethrowFirst();
  }

  void close() {
    if (!_isOpen) {
      return;
    }
    _isOpen = false;
    _removeFromOpenModals();
    _focusRequest++;
    final failures = FirstErrorRecorder();
    failures.attempt(() => widget.onClose?.call());
    if (!_isOpen) {
      failures.attempt(_portalController.hide);
      failures.attempt(_restoreFocus);
      failures.attempt(() => setState(() {}));
    }
    failures.rethrowFirst();
  }

  void _focusAfterMount(int request) {
    if (!mounted || !_isOpen || request != _focusRequest || !_isTopModal) {
      return;
    }
    final scope = _scopeNode;
    if (!scope.isAttached) {
      return;
    }
    // Batched portals can mount by element depth instead of open-call order.
    _portalController.show();
    final preferred = widget.initialFocusNode;
    if (preferred != null &&
        preferred.isAttached &&
        preferred.canRequestFocus &&
        _isBelowScope(preferred, scope)) {
      preferred.requestFocus();
      return;
    }
    final descendants = _focusableDescendants(scope);
    (descendants.isEmpty ? scope : descendants.first).requestFocus();
  }

  void _handleScopeFocusChanged() {
    _scheduleFocusRepair();
  }

  void _scheduleFocusRepair() {
    if (!_isOpen || _focusRepairScheduled) {
      return;
    }
    _focusRepairScheduled = true;
    scheduleMicrotask(() {
      _focusRepairScheduled = false;
      if (!mounted || !_isOpen) {
        return;
      }
      if (!_isTopModal) {
        return;
      }
      final current = context.owner.focusManager.primaryFocus;
      final descendants = _focusableDescendants(_scopeNode);
      if (current != null &&
          current is! FocusScopeNode &&
          current.canRequestFocus &&
          _isBelowScope(current, _scopeNode)) {
        return;
      }
      if (descendants.isEmpty && identical(current, _scopeNode)) {
        return;
      }
      _focusAfterMount(_focusRequest);
    });
  }

  KeyEventResult _moveFocus({required bool forward}) {
    _traversalPolicy.moveWithin(
      _scopeNode,
      current: context.owner.focusManager.primaryFocus,
      forward: forward,
    );
    return KeyEventResult.handled;
  }

  void _restoreFocus() {
    final node = _restoreNode;
    final manager = _restoreManager;
    _restoreNode = null;
    _restoreManager = null;
    _hasRestoreSnapshot = false;
    if (node == null || manager == null) {
      return;
    }
    if (node.isAttachedTo(manager) && node.canRequestFocus) {
      node.requestFocus();
    }
  }

  void _moveToTop() {
    final manager = context.owner.focusManager;
    final stack = _openModals[manager] ?? <_ModalState>[];
    _openModals[manager] = stack;
    stack
      ..remove(this)
      ..add(this);
    _openManager = manager;
  }

  void _removeFromOpenModals() {
    final manager = _openManager;
    if (manager == null) {
      return;
    }
    final stack = _openModals[manager];
    final wasTop =
        stack != null && stack.isNotEmpty && identical(stack.last, this);
    stack?.remove(this);
    _openManager = null;
    if (wasTop && stack.isNotEmpty) {
      stack.last._scheduleFocusRepair();
    }
  }

  bool get _isTopModal {
    final manager = _openManager;
    if (manager == null) {
      return false;
    }
    final stack = _openModals[manager];
    return stack != null && stack.isNotEmpty && identical(stack.last, this);
  }

  @override
  void initState() {
    super.initState();
    _scopeNode.addListener(_handleScopeFocusChanged);
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(Modal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
  }

  @override
  void dispose() {
    _isOpen = false;
    _removeFromOpenModals();
    _focusRequest++;
    _restoreNode = null;
    _restoreManager = null;
    _hasRestoreSnapshot = false;
    _scopeNode.removeListener(_handleScopeFocusChanged);
    widget.controller._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: <ShortcutActivator, Intent>{
      if (_isOpen) ...{
        const SingleActivator(LogicalKeyboardKey.tab):
            const _ModalNextFocusIntent(),
        const SingleActivator(LogicalKeyboardKey.tab, shift: true):
            const _ModalPreviousFocusIntent(),
        if (widget.dismissOnEscape)
          const SingleActivator(LogicalKeyboardKey.escape):
              const _ModalDismissIntent(),
      },
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _ModalNextFocusIntent: CallbackAction<_ModalNextFocusIntent>(
          (intent, context) => _moveFocus(forward: true),
        ),
        _ModalPreviousFocusIntent: CallbackAction<_ModalPreviousFocusIntent>(
          (intent, context) => _moveFocus(forward: false),
        ),
        _ModalDismissIntent: CallbackAction<_ModalDismissIntent>((
          intent,
          context,
        ) {
          close();
          return KeyEventResult.handled;
        }),
      },
      child: OverlayPortal(
        controller: _portalController,
        overlayChildBuilder: _buildOverlay,
        child: widget.child,
      ),
    ),
  );

  Widget _buildOverlay(BuildContext context) {
    final request = _focusRequest;
    return Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        Positioned(
          left: 0,
          top: 0,
          right: 0,
          bottom: 0,
          child: PointerListener(
            onPointerDown: _handleOutsidePointer,
            onPointerUp: _handleOutsidePointer,
            onPointerMove: _handleOutsidePointer,
            onPointerScroll: _handleOutsidePointer,
            child: const Align(child: SizedBox.shrink()),
          ),
        ),
        Align(
          child: _ModalFocusBoundary(
            scopeNode: _scopeNode,
            onReady: () => _focusAfterMount(request),
            child: PointerListener(
              onPointerDown: _claimInsidePointer,
              onPointerUp: _claimInsidePointer,
              onPointerMove: _claimInsidePointer,
              onPointerScroll: _claimInsidePointer,
              child: widget.modalBuilder(context),
            ),
          ),
        ),
      ],
    );
  }

  void _handleOutsidePointer(MouseEvent event) {
    event.consume();
    if (widget.dismissOnOutsideClick &&
        event.type == MouseEventType.down &&
        event.button == MouseButton.left) {
      close();
    }
  }

  void _claimInsidePointer(MouseEvent event) {}
}

class _ModalFocusBoundary extends StatefulWidget {
  const _ModalFocusBoundary({
    required this.scopeNode,
    required this.onReady,
    required this.child,
  });

  final FocusScopeNode scopeNode;
  final VoidCallback onReady;
  final Widget child;

  @override
  State<_ModalFocusBoundary> createState() => _ModalFocusBoundaryState();
}

class _ModalFocusBoundaryState extends State<_ModalFocusBoundary> {
  @override
  void initState() {
    super.initState();
    final onReady = widget.onReady;
    scheduleMicrotask(onReady);
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: widget.scopeNode, child: widget.child);
}

final class _ModalNextFocusIntent extends Intent {
  const _ModalNextFocusIntent();
}

final class _ModalPreviousFocusIntent extends Intent {
  const _ModalPreviousFocusIntent();
}

final class _ModalDismissIntent extends Intent {
  const _ModalDismissIntent();
}

final class _ModalFocusTraversalPolicy extends FocusTraversalPolicy {
  const _ModalFocusTraversalPolicy();

  @override
  FocusNode? findFirstFocus(FocusScopeNode scope) {
    final nodes = _focusableDescendants(scope);
    return nodes.isEmpty ? scope : nodes.first;
  }

  @override
  FocusNode? findLastFocus(FocusScopeNode scope) {
    final nodes = _focusableDescendants(scope);
    return nodes.isEmpty ? scope : nodes.last;
  }

  @override
  bool next(FocusNode currentNode) => _moveFrom(currentNode, forward: true);

  @override
  bool previous(FocusNode currentNode) =>
      _moveFrom(currentNode, forward: false);

  bool moveWithin(
    FocusScopeNode scope, {
    required FocusNode? current,
    required bool forward,
  }) {
    final nodes = _focusableDescendants(scope);
    if (nodes.isEmpty) {
      scope.requestFocus();
      return true;
    }
    final currentIndex = current == null
        ? -1
        : nodes.indexWhere((node) => identical(node, current));
    final nextIndex = currentIndex < 0
        ? (forward ? 0 : nodes.length - 1)
        : (currentIndex + (forward ? 1 : -1) + nodes.length) % nodes.length;
    nodes[nextIndex].requestFocus();
    return true;
  }

  bool _moveFrom(FocusNode currentNode, {required bool forward}) {
    final scope = _owningScope(currentNode);
    if (scope == null) {
      return false;
    }
    return moveWithin(scope, current: currentNode, forward: forward);
  }

  FocusScopeNode? _owningScope(FocusNode node) {
    FocusNode? current = node;
    while (current != null) {
      if (current is FocusScopeNode &&
          identical(current.traversalPolicy, this)) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }
}

List<FocusNode> _focusableDescendants(FocusScopeNode scope) {
  final result = <FocusNode>[];

  void visit(FocusNode parent) {
    for (final child in parent.children) {
      if (!child.isAttached) {
        continue;
      }
      if (child is! FocusScopeNode && child.canRequestFocus) {
        result.add(child);
      }
      visit(child);
    }
  }

  visit(scope);
  return result;
}

bool _isBelowScope(FocusNode node, FocusScopeNode scope) {
  FocusNode? current = node;
  while (current != null) {
    if (identical(current, scope)) {
      return true;
    }
    current = current.parent;
  }
  return false;
}
