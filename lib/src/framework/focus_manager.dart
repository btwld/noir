// ignore_for_file: avoid_positional_boolean_parameters, unnecessary_getters_setters
import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/change_notifier.dart';
import '../widgets/actions.dart';
import '../widgets/intents.dart';
import '../widgets/shortcuts.dart';
import 'build_context.dart';
import 'element.dart';

/// Handles a key event at [FocusNode] scope; the result decides whether
/// routing continues.
typedef FocusOnKeyEvent =
    KeyEventResult Function(FocusNode node, KeyEvent event);

/// Determines how focus moves through a [FocusScopeNode].
abstract class FocusTraversalPolicy {
  /// Initializes a policy that defines first, last, next, and previous focus.
  const FocusTraversalPolicy();

  /// Finds the first focusable node in [scope].
  FocusNode? findFirstFocus(FocusScopeNode scope);

  /// Finds the last focusable node in [scope].
  FocusNode? findLastFocus(FocusScopeNode scope);

  /// Moves to the next node from [currentNode].
  bool next(FocusNode currentNode);

  /// Moves to the previous node from [currentNode].
  bool previous(FocusNode currentNode);
}

class _WidgetOrderTraversalPolicy extends FocusTraversalPolicy {
  const _WidgetOrderTraversalPolicy();

  @override
  FocusNode? findFirstFocus(FocusScopeNode scope) {
    final manager = scope._manager;
    if (manager == null) return null;
    final order = manager._ensureTraversalOrder();
    return order.isEmpty ? null : order.first;
  }

  @override
  FocusNode? findLastFocus(FocusScopeNode scope) {
    final manager = scope._manager;
    if (manager == null) return null;
    final order = manager._ensureTraversalOrder();
    return order.isEmpty ? null : order.last;
  }

  @override
  bool next(FocusNode currentNode) =>
      currentNode._manager?._moveFocus(forward: true) ?? false;

  @override
  bool previous(FocusNode currentNode) =>
      currentNode._manager?._moveFocus(forward: false) ?? false;
}

const FocusTraversalPolicy _defaultTraversalPolicy =
    _WidgetOrderTraversalPolicy();

/// Owns one node-to-element binding: attach, reparent, and detach it in the
/// focus manager.
@internal
class FocusAttachment {
  FocusAttachment._(this._node, this._manager, {required this.isScope});

  final FocusNode _node;
  final FocusManager _manager;

  /// Whether the attached node is a [FocusScopeNode].
  final bool isScope;
  Element? _element;

  /// Whether this attachment currently maps its node to an [Element].
  bool get isAttached => _element != null;

  /// Binds the node to [context]'s element in this attachment's manager.
  void attach(BuildContext context) {
    final element = context.element;
    _manager._attachNode(_node, element);
    _element = element;
  }

  /// Remaps the node to [context], attaching it first when necessary.
  void reparent(BuildContext context) {
    final element = context.element;
    if (!isAttached) {
      attach(context);
      return;
    }
    if (identical(_element, element)) {
      return;
    }
    _manager._reparentNode(_node, _element!, element);
    _element = element;
  }

  /// Removes the node mapping; does nothing when already detached.
  void detach() {
    final element = _element;
    if (element == null) return;
    _manager._detachNode(_node, expectedElement: element);
    _element = null;
  }

  /// Element currently mapped by this attachment, or `null` when detached.
  Element? get element => _element;
}

/// A focusable point in the focus tree that notifies listeners when its
/// focus state changes.
class FocusNode extends ChangeNotifier {
  /// Configures a detached node with optional diagnostics and key handling.
  FocusNode({
    this.debugLabel,
    FocusOnKeyEvent? onKeyEvent,
    bool canRequestFocus = true,
  }) : _onKeyEvent = onKeyEvent,
       _canRequestFocus = canRequestFocus;

  FocusManager? _manager;
  FocusNode? _parent;
  final Set<FocusNode> _children = Set<FocusNode>.identity();
  late final Set<FocusNode> _childrenView = UnmodifiableSetView<FocusNode>(
    _children,
  );
  bool _hasFocus = false;
  bool _descendantsHaveFocus = false;
  bool _isAttached = false;
  FocusOnKeyEvent? _onKeyEvent;
  bool _canRequestFocus;

  /// Optional label used only for diagnostics.
  final String? debugLabel;

  /// Whether this node itself currently holds focus.
  bool get hasFocus => _hasFocus;

  /// Whether this node is its manager's current primary focus.
  bool get hasPrimaryFocus => identical(_manager?._primaryFocus, this);

  /// Direct parent in the focus tree, or `null` when none is assigned.
  FocusNode? get parent => _parent;

  /// Live read-only view of direct focus children in insertion order.
  Iterable<FocusNode> get children => _childrenView;

  /// Whether the focus manager may assign primary focus to this node.
  bool get canRequestFocus => _canRequestFocus;

  /// Updates the canRequestFocus value.
  ///
  /// Disabling the node that currently holds focus is involuntary loss, not an
  /// intentional [unfocus]: the application disabled a control, it did not ask
  /// for an unfocused tree. The scope disposition still runs first, and the
  /// manager schedules recovery for the case where it leaves nothing focused.
  set canRequestFocus(bool value) {
    if (_canRequestFocus == value) return;
    _canRequestFocus = value;
    _manager?._invalidateTraversalCache();
    if (!value && hasFocus) {
      final manager = _manager;
      if (manager == null) return;
      final anchor = _parent;
      manager._unfocus(this, descendants: false);
      manager._scheduleFocusRecovery(anchor);
    }
  }

  /// Handler consulted while a key event bubbles through this node.
  FocusOnKeyEvent? get onKeyEvent => _onKeyEvent;

  /// Updates the onKeyEvent value.
  set onKeyEvent(FocusOnKeyEvent? handler) => _onKeyEvent = handler;

  /// Registers this node with [context]'s manager and returns its attachment.
  @internal
  FocusAttachment attach(BuildContext context) {
    final manager = FocusManager.of(context);
    final attachment = FocusAttachment._(
      this,
      manager,
      isScope: this is FocusScopeNode,
    );
    attachment.attach(context);
    _isAttached = true;
    return attachment;
  }

  /// Unregisters this node from its manager and marks it detached.
  @internal
  void detach() {
    final manager = _manager;
    if (manager != null) {
      manager._detachNode(this);
    }
    _isAttached = false;
  }

  /// Detaches this node before releasing its notifier listeners.
  @override
  void dispose() {
    detach();
    super.dispose();
  }

  /// Requests primary focus, throwing unless this node is attached to a manager.
  ///
  /// This is a deliberate focus decision, so it also drops any focus recovery
  /// the manager has queued for an earlier involuntary loss.
  void requestFocus() {
    if (_manager == null) {
      throw StateError('FocusNode is not attached to a FocusManager');
    }
    _manager!
      .._cancelFocusRecovery()
      .._requestFocus(this);
  }

  /// Unfocuses this node or its currently focused descendant; [descendants]
  /// also recurses through every child subtree. Unattached nodes are a no-op.
  ///
  /// This is the intentional form: focus moves to the nearest enclosing scope
  /// that can hold it, and clears when only the synthetic root scope remains.
  /// An empty focus is the requested outcome here, so the manager does not
  /// recover it, and it drops any recovery queued for an earlier involuntary
  /// loss. Disabling or removing the focused control is the involuntary form,
  /// and the manager does recover that.
  void unfocus({bool descendants = false}) {
    final manager = _manager;
    if (manager == null) return;
    manager
      .._cancelFocusRecovery()
      .._unfocus(this, descendants: descendants);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    final handler = _onKeyEvent;
    if (handler == null) {
      return KeyEventResult.ignored;
    }
    return handler(this, event);
  }

  void _adoptChild(FocusNode child) {
    _children.add(child);
    child._parent = this;
  }

  void _dropChild(FocusNode child) {
    if (_children.remove(child)) {
      if (identical(child._parent, this)) {
        child._parent = null;
      }
    }
  }

  void _setHasFocus(bool value) {
    if (_hasFocus == value) {
      return;
    }
    _hasFocus = value;
    notifyListeners();
  }

  void _setDescendantsHaveFocus(bool value) {
    if (_descendantsHaveFocus == value) {
      return;
    }
    _descendantsHaveFocus = value;
    notifyListeners();
  }

  /// Whether this node is registered with a [FocusManager].
  bool get isAttached => _isAttached;

  /// Whether this node is currently attached to [manager].
  @internal
  bool isAttachedTo(FocusManager manager) => identical(_manager, manager);

  bool _isAncestorOf(FocusNode? node) {
    var ancestor = node?._parent;
    while (ancestor != null) {
      if (identical(ancestor, this)) {
        return true;
      }
      ancestor = ancestor._parent;
    }
    return false;
  }
}

/// A [FocusNode] that records its [focusedChild] and owns a traversal
/// policy for its subtree.
class FocusScopeNode extends FocusNode {
  /// Configures a detached scope with the supplied or widget-order policy.
  FocusScopeNode({
    super.debugLabel,
    super.onKeyEvent,
    FocusTraversalPolicy traversalPolicy = _defaultTraversalPolicy,
  }) : _traversalPolicy = traversalPolicy;

  FocusNode? _focusedChild;
  FocusTraversalPolicy _traversalPolicy;

  /// Recorded preferred direct child; focus changes update it, but it may be
  /// set without current primary focus beneath this scope.
  FocusNode? get focusedChild => _focusedChild;

  /// Policy used to resolve focus movement within this scope.
  FocusTraversalPolicy get traversalPolicy => _traversalPolicy;

  /// Updates the traversalPolicy value.
  set traversalPolicy(FocusTraversalPolicy value) {
    if (identical(_traversalPolicy, value)) return;
    _traversalPolicy = value;
  }

  void _setFocusedChild(FocusNode? node) {
    if (identical(_focusedChild, node)) {
      return;
    }
    _focusedChild = node;
  }
}

/// Owns the focus tree, tracks [primaryFocus], and routes focus-priority
/// key events.
class FocusManager {
  /// Creates the root scope and owns a focus-priority key subscription.
  FocusManager(this.inputManager) {
    rootScope._manager = this;
    rootScope._isAttached = true;
    rootScope.canRequestFocus = false;
    _keySubscription = inputManager.dispatcher.onKey(
      _handleKeyEvent,
      priority: InputPriority.focus,
    );
  }

  /// Input manager whose dispatcher delivers focus-priority key events.
  final InputManager inputManager;

  /// Synthetic attached, non-requestable root for the focus tree.
  final FocusScopeNode rootScope = FocusScopeNode(
    debugLabel: 'Root Focus Scope',
  );
  late final InputSubscription _keySubscription;
  FocusNode? _primaryFocus;
  final Map<FocusNode, Element> _nodeToElement =
      Map<FocusNode, Element>.identity();
  final Expando<FocusNode> _elementToNode = Expando<FocusNode>('FocusNode');

  /// Enclosing scopes of the node that most recently lost focus
  /// involuntarily, nearest first. Read once by [_recoverFocus], then cleared.
  List<FocusScopeNode>? _recoveryScopes;

  /// Whether a queued [_recoverFocus] should still act. A later explicit focus
  /// decision clears this without cancelling the microtask itself.
  bool _recoveryPending = false;
  bool _recoveryScheduled = false;
  bool _disposed = false;

  /// Cached depth-first, tree-order list of attached focus nodes used by the
  /// default Tab / Shift-Tab traversal. Null when the cache is dirty.
  List<FocusNode>? _traversalOrderCache;

  /// Node that currently holds primary focus, or `null` when none.
  FocusNode? get primaryFocus => _primaryFocus;

  /// Returns the focus manager owned by [context]'s build owner.
  static FocusManager of(BuildContext context) {
    final element = context.element;
    return element.owner.focusManager;
  }

  /// Release input subscriptions owned by this focus manager.
  void dispose() {
    _disposed = true;
    _cancelFocusRecovery();
    _keySubscription.cancel();
  }

  Element? _elementIfAttachedHere(FocusNode node) =>
      identical(node._manager, this) ? _nodeToElement[node] : null;

  void _attachNode(FocusNode node, Element element) {
    _validateNodeAttachment(node, element);
    if (identical(node._manager, this) &&
        identical(_nodeToElement[node], element)) {
      return;
    }

    final previousElement = _elementIfAttachedHere(node);
    if (previousElement != null) {
      // Reconciliation has already made the outgoing element inactive, so
      // transfer the existing attachment instead of clearing focus between
      // the old and new Focus widgets.
      _reparentNode(node, previousElement, element);
      return;
    }

    node._manager = this;
    node._isAttached = true;
    _bindNodeToElement(node, element);
  }

  void _validateNodeAttachment(
    FocusNode node,
    Element element, {
    FocusNode? replacing,
  }) {
    validateChangeNotifierNotDisposed(node, name: 'FocusNode');
    if (identical(node._manager, this) &&
        identical(_nodeToElement[node], element)) {
      return;
    }
    final previousElement = _elementIfAttachedHere(node);
    final canTransfer = previousElement != null && !previousElement.active;
    if (node._manager != null && !canTransfer) {
      throw StateError(
        'FocusNode${node.debugLabel == null ? '' : ' "${node.debugLabel}"'} '
        'is already attached to a live Focus widget. Detach it before reuse.',
      );
    }
    final elementNode = _elementToNode[element];
    if (elementNode != null &&
        !identical(elementNode, node) &&
        !identical(elementNode, replacing)) {
      throw StateError('The target element already owns a FocusNode.');
    }
  }

  void _reparentNode(FocusNode node, Element expectedElement, Element element) {
    final oldElement = _nodeToElement[node];
    if (!identical(node._manager, this) ||
        !identical(oldElement, expectedElement)) {
      throw StateError('Cannot reparent a stale FocusNode attachment.');
    }
    if (identical(oldElement, element)) {
      return;
    }
    final carriesFocus = node._hasFocus || node._descendantsHaveFocus;
    final oldParent = node._parent;
    if (identical(_elementToNode[expectedElement], node)) {
      _elementToNode[expectedElement] = null;
    }
    _detachFromParent(node, preserveFocus: true);
    if (carriesFocus) {
      _updateAncestorChainForLoss(oldParent, node);
    }
    _bindNodeToElement(node, element);
    if (carriesFocus) {
      _updateAncestorsForGain(node);
    }
  }

  /// Records the node/element mapping and adopts [node] under the focus
  /// parent derived from [element]'s ancestors — the shared tail of
  /// [_attachNode] and [_reparentNode].
  void _bindNodeToElement(FocusNode node, Element element) {
    _nodeToElement[node] = element;
    _elementToNode[element] = node;
    _invalidateTraversalCache();

    final parentNode = _findParentForElement(element);
    parentNode._adoptChild(node);
    if (parentNode is FocusScopeNode && parentNode.focusedChild == null) {
      parentNode._setFocusedChild(node);
    }
  }

  void _detachNode(FocusNode node, {Element? expectedElement}) {
    if (expectedElement != null &&
        !identical(_nodeToElement[node], expectedElement)) {
      return;
    }
    final element = _nodeToElement.remove(node);
    if (element != null) {
      _elementToNode[element] = null;
    }
    final carriesFocus = node._hasFocus || node._descendantsHaveFocus;
    final oldParent = node._parent;
    _detachFromParent(node);
    if (carriesFocus && oldParent != null) {
      _updateAncestorChainForLoss(oldParent, node);
    }
    if (identical(_primaryFocus, node) || node._isAncestorOf(_primaryFocus)) {
      _clearFocus(node);
      _scheduleFocusRecovery(oldParent);
    }
    node._manager = null;
    node._isAttached = false;
    _invalidateTraversalCache();
  }

  void _detachFromParent(FocusNode node, {bool preserveFocus = false}) {
    final parent = node._parent;
    if (parent != null) {
      parent._dropChild(node);
      if (parent is FocusScopeNode && identical(parent.focusedChild, node)) {
        parent._setFocusedChild(_findFirstFocusableChild(parent));
      }
      _updateAncestorsForLoss(parent, child: node);
    }
    node._parent = null;
    if (!preserveFocus) {
      node._setDescendantsHaveFocus(false);
      node._setHasFocus(false);
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event.isConsumed) return;

    final focusNode = _primaryFocus;
    final focusElement = focusNode == null ? null : _nodeToElement[focusNode];
    final focusContext = focusElement?.buildContext;
    if (focusNode != null && focusContext != null) {
      if (_stopIfResolved(
        event,
        Shortcuts.handleKeyEvent(focusContext, event),
      )) {
        return;
      }
      if (_stopIfResolved(event, _dispatchPrintableText(focusContext, event))) {
        return;
      }

      FocusNode? node = focusNode;
      while (node != null) {
        if (_stopIfResolved(event, node._handleKeyEvent(event))) {
          return;
        }
        node = node._parent;
      }

      if (_stopIfResolved(event, _dispatchDefaultTraversal(focusNode, event))) {
        return;
      }
    }
  }

  bool _stopIfResolved(KeyEvent event, KeyEventResult result) {
    if (result == KeyEventResult.ignored) return false;
    if (result == KeyEventResult.handled) {
      event.consume();
    }
    return true;
  }

  KeyEventResult _dispatchPrintableText(BuildContext context, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.character != null &&
        !event.isControlPressed &&
        !event.isAltPressed &&
        !event.isMetaPressed) {
      return Actions.maybeInvoke(context, InsertTextIntent(event.character!));
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _dispatchDefaultTraversal(
    FocusNode focusNode,
    KeyEvent event,
  ) {
    if (!event.isPress || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    final moved = event.isShiftPressed
        ? _policyFor(focusNode).previous(focusNode)
        : _policyFor(focusNode).next(focusNode);
    return moved ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Move focus to the next focusable node in widget-tree order.
  ///
  /// Walks the element subtree rooted at [rootScope] depth-first, collecting
  /// every attached [FocusNode] that can request focus, then moves to the
  /// node after the current [primaryFocus] (wrapping at the end). Returns
  /// true when focus was actually moved.
  bool focusNext() {
    final current = _primaryFocus;
    if (current == null) {
      final first = rootScope.traversalPolicy.findFirstFocus(rootScope);
      if (first == null) return false;
      first.requestFocus();
      return true;
    }
    return _policyFor(current).next(current);
  }

  FocusTraversalPolicy _policyFor(FocusNode node) =>
      _findEnclosingScope(node).traversalPolicy;

  bool _moveFocus({required bool forward}) {
    final order = _ensureTraversalOrder();
    if (order.isEmpty) return false;

    final current = _primaryFocus;
    int nextIndex;
    if (current == null) {
      nextIndex = forward ? 0 : order.length - 1;
    } else {
      final currentIndex = order.indexWhere(
        (candidate) => identical(candidate, current),
      );
      if (currentIndex < 0) {
        nextIndex = forward ? 0 : order.length - 1;
      } else {
        nextIndex = forward
            ? (currentIndex + 1) % order.length
            : (currentIndex - 1 + order.length) % order.length;
      }
    }

    final target = order[nextIndex];
    if (identical(target, current)) return false;
    target.requestFocus();
    return true;
  }

  /// Returns the cached tree-order traversal list, rebuilding it if dirty.
  ///
  /// Visible for tests and tooling; callers should treat the list as
  /// read-only.
  List<FocusNode> traversalOrder() =>
      List<FocusNode>.unmodifiable(_ensureTraversalOrder());

  List<FocusNode> _ensureTraversalOrder() {
    var cache = _traversalOrderCache;
    if (cache != null) return cache;
    cache = <FocusNode>[];
    final root = _findRootElement();
    if (root != null) {
      _collectTraversalOrder(root, cache);
    }
    _traversalOrderCache = cache;
    return cache;
  }

  /// Find the highest ancestor of any currently-attached focus node.
  ///
  /// The [rootScope] is a synthetic node not bound to a concrete element;
  /// we anchor traversal by walking up from any tracked element to its
  /// parent-less ancestor. All focus nodes attached to this manager share
  /// the same element tree (an app has exactly one root element).
  Element? _findRootElement() {
    if (_nodeToElement.isEmpty) return null;
    final any = _nodeToElement.values.first;
    Element? current = any;
    while (current?.parent != null) {
      current = current!.parent;
    }
    return current;
  }

  void _collectTraversalOrder(Element element, List<FocusNode> out) {
    final node = _elementToNode[element];
    // Tab traversal walks through leaf focusable widgets only. Scope nodes
    // act as grouping containers — they themselves do not participate.
    if (node != null && node is! FocusScopeNode && node.canRequestFocus) {
      out.add(node);
    }
    element.visitChildren((child) {
      _collectTraversalOrder(child, out);
    });
  }

  void _invalidateTraversalCache() {
    _traversalOrderCache = null;
  }

  void _requestFocus(FocusNode node) {
    if (!node.canRequestFocus) {
      return;
    }
    if (!node.isAttached) {
      throw StateError('FocusNode must be attached before requesting focus');
    }
    if (identical(_primaryFocus, node)) {
      return;
    }
    final previous = _primaryFocus;
    _primaryFocus = node;
    node._setHasFocus(true);
    _updateAncestorsForGain(node);

    if (previous != null) {
      previous._setHasFocus(false);
      _updateAncestorsForLoss(previous);
    }
  }

  void _unfocus(FocusNode node, {required bool descendants}) {
    if (descendants) {
      for (final child in List<FocusNode>.from(node._children)) {
        _unfocus(child, descendants: true);
      }
    }

    if (identical(_primaryFocus, node)) {
      node._setHasFocus(false);
      _primaryFocus = null;
      _updateAncestorsForLoss(node);
      // Flutter `scope` disposition (the `unfocus()` default): hand focus
      // to the nearest enclosing scope that can hold it, never back to a
      // sibling/first child (which could be `node` itself). If only the
      // synthetic root remains, focus clears.
      var scope = _findEnclosingScope(node);
      while (!scope.canRequestFocus && !identical(scope, rootScope)) {
        scope = _findEnclosingScope(scope);
      }
      if (scope.canRequestFocus && !identical(scope, node)) {
        _requestFocus(scope);
      }
      return;
    }

    if (node._descendantsHaveFocus) {
      for (final child in node._children) {
        if (child._hasFocus || child._descendantsHaveFocus) {
          _unfocus(child, descendants: descendants);
        }
      }
      node._setDescendantsHaveFocus(false);
    }
  }

  /// Queues focus recovery for the tree under [anchor] after the current
  /// synchronous tree updates finish.
  ///
  /// Recovery answers involuntary loss only: disabling the focused control, or
  /// removing it from the tree. Both leave [primaryFocus] null, and
  /// [Shortcuts] routes from the focused element, so an unfocused tree stops
  /// answering every binding without reporting anything.
  ///
  /// The work is deferred because the loss usually happens mid-build: the
  /// replacement subtree may not be mounted yet, and an explicit
  /// `requestFocus()` or an incoming `autofocus` may still claim focus first.
  /// A microtask runs after the whole build pass, so recovery sees the settled
  /// tree and yields to whoever already took focus.
  void _scheduleFocusRecovery(FocusNode? anchor) {
    if (_disposed) return;
    // Record the chain now, while it is still whole. Detaching a node clears
    // its own parent edge, so a scope that leaves in the same batch as the
    // control it held would otherwise end the walk at itself.
    _recoveryScopes = _enclosingScopes(anchor);
    _recoveryPending = true;
    if (_recoveryScheduled) return;
    _recoveryScheduled = true;
    scheduleMicrotask(_recoverFocus);
  }

  /// Drops a queued recovery because a later focus decision superseded it.
  ///
  /// The microtask stays queued and finds nothing to do. A new involuntary
  /// loss before it runs makes it pending again, with its own scope chain.
  void _cancelFocusRecovery() {
    _recoveryPending = false;
    _recoveryScopes = null;
  }

  /// Explicit scopes at or above [node], nearest first, excluding the
  /// synthetic [rootScope].
  List<FocusScopeNode> _enclosingScopes(FocusNode? node) {
    final scopes = <FocusScopeNode>[];
    var candidate = node;
    while (candidate != null) {
      if (candidate is FocusScopeNode && !identical(candidate, rootScope)) {
        scopes.add(candidate);
      }
      candidate = candidate._parent;
    }
    return scopes;
  }

  /// Gives focus back to the settled tree when involuntary loss left none.
  ///
  /// Takes the nearest scope, of those recorded at the loss, that is still
  /// attached and can hold focus. That keeps a modal, or any other focus
  /// region, in charge of its own repair. Falls back to the first node in
  /// traversal order, and leaves focus empty when the tree has no eligible
  /// node at all.
  void _recoverFocus() {
    _recoveryScheduled = false;
    final pending = _recoveryPending;
    final scopes = _recoveryScopes;
    _cancelFocusRecovery();
    // A later focus decision superseded this recovery, or someone already
    // claimed focus: an explicit request, an intentional `unfocus`, or the
    // autofocus of the subtree that replaced the lost one.
    if (!pending || _disposed || _primaryFocus != null) return;
    for (final scope in scopes ?? const <FocusScopeNode>[]) {
      if (scope.isAttachedTo(this) && scope.canRequestFocus) {
        _requestFocus(scope);
        return;
      }
    }
    final order = _ensureTraversalOrder();
    if (order.isEmpty) return;
    _requestFocus(order.first);
  }

  FocusScopeNode _findEnclosingScope(FocusNode node) {
    var ancestor = node._parent;
    while (ancestor != null) {
      if (ancestor is FocusScopeNode) {
        return ancestor;
      }
      ancestor = ancestor._parent;
    }
    return rootScope;
  }

  FocusNode? _findFirstFocusableChild(FocusNode node) {
    for (final child in node._children) {
      if (child.canRequestFocus) {
        return child;
      }
      final descendant = _findFirstFocusableChild(child);
      if (descendant != null) {
        return descendant;
      }
    }
    return null;
  }

  FocusNode _findParentForElement(Element element) {
    var current = element.parent;
    while (current != null) {
      final node = _elementToNode[current];
      if (node != null) {
        return node;
      }
      current = current.parent;
    }
    return rootScope;
  }

  void _clearFocus(FocusNode node) {
    if (identical(_primaryFocus, node)) {
      _primaryFocus = null;
    }
    node._setHasFocus(false);
    _updateAncestorsForLoss(node);
  }

  void _updateAncestorsForGain(FocusNode node) {
    FocusNode? child = node;
    var ancestor = node._parent;
    while (ancestor != null) {
      ancestor._setDescendantsHaveFocus(true);
      if (ancestor is FocusScopeNode) {
        ancestor._setFocusedChild(child);
      }
      child = ancestor;
      ancestor = ancestor._parent;
    }
  }

  void _updateAncestorsForLoss(FocusNode node, {FocusNode? child}) {
    _updateAncestorChainForLoss(node._parent, child ?? node);
  }

  void _updateAncestorChainForLoss(
    FocusNode? ancestor,
    FocusNode currentChild,
  ) {
    var currentAncestor = ancestor;
    var child = currentChild;
    while (currentAncestor != null) {
      final hasFocusedDescendant = currentAncestor._children.any(
        (c) => c._hasFocus || c._descendantsHaveFocus,
      );
      currentAncestor._setDescendantsHaveFocus(hasFocusedDescendant);
      if (currentAncestor is FocusScopeNode &&
          identical(currentAncestor.focusedChild, child)) {
        currentAncestor._setFocusedChild(
          hasFocusedDescendant
              ? _findFirstFocusableChild(currentAncestor)
              : null,
        );
      }
      child = currentAncestor;
      currentAncestor = currentAncestor._parent;
    }
  }

  /// Returns the focus node attached to [element], or `null` when absent.
  @internal
  FocusNode? nodeForElement(Element element) => _elementToNode[element];
}

/// Validates a widget-driven node replacement before the current attachment
/// is detached, so a rejected duplicate leaves both live trees authoritative.
@internal
void validateFocusNodeReplacementTarget(
  FocusNode nextNode,
  FocusNode currentNode,
  BuildContext context,
) {
  final manager = FocusManager.of(context);
  manager._validateNodeAttachment(
    nextNode,
    context.element,
    replacing: currentNode,
  );
}
