// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:async';

import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'focus_node_owner_mixin.dart';

T? _findAncestorFocusNode<T extends FocusNode>(Element element) {
  final owner = element.owner;
  Element? current = element;
  while (current != null) {
    final node = owner.focusManager.nodeForElement(current);
    if (node is T) {
      return node;
    }
    current = current.parent;
  }
  return null;
}

/// Attaches a [FocusNode] here and rebuilds when its focus state changes.
class Focus extends StatefulWidget {
  /// Configures a focus boundary that owns a node only when none is supplied.
  const Focus({
    required this.child,
    super.key,
    this.focusNode,
    this.autofocus = false,
    this.canRequestFocus = true,
    this.onFocusChange,
    this.onKeyEvent,
  });

  /// Caller-owned node to attach, or `null` for a state-owned node.
  final FocusNode? focusNode;

  /// Whether to request focus on mount or when changed from false to true.
  ///
  /// Keeping this true across updates does not reclaim focus, even when the
  /// node changes.
  final bool autofocus;

  /// Whether the attached node may become primary focus.
  final bool canRequestFocus;

  /// Called with this node's current focus state whenever the node notifies.
  final void Function(bool hasFocus)? onFocusChange;

  /// Handler used while key routing bubbles through the attached node.
  final FocusOnKeyEvent? onKeyEvent;

  /// Subtree associated with the attached focus node.
  final Widget child;

  /// Returns the nearest enclosing [FocusNode], or throws a [StateError]
  /// if none.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's `Focus.of`.
  static FocusNode of(BuildContext context) {
    final node = maybeOf(context);
    if (node == null) {
      throw StateError(
        'Focus.of() called with a context that has no Focus ancestor.',
      );
    }
    return node;
  }

  /// Returns the nearest enclosing [FocusNode], or null if none.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `Focus.maybeOf`.
  static FocusNode? maybeOf(BuildContext context) =>
      _findAncestorFocusNode<FocusNode>(context.element);

  @override
  State<StatefulWidget> createState() => _FocusState();
}

class _FocusState extends State<Focus> with FocusNodeOwnerStateMixin<Focus> {
  FocusAttachment? _attachment;
  bool _didAutofocus = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _configureNode(focusNode);
  }

  void _configureNode(FocusNode node) {
    node
      ..canRequestFocus = widget.canRequestFocus
      ..onKeyEvent = widget.onKeyEvent
      ..addListener(_handleFocusChanged);
    _applyTraversalPolicy(node);
  }

  void _applyTraversalPolicy(FocusNode node) {
    if (node is FocusScopeNode && widget is FocusScope) {
      final policy = (widget as FocusScope).traversalPolicy;
      if (policy != null) node.traversalPolicy = policy;
    }
  }

  void _teardownNode(FocusNode node) {
    node.removeListener(_handleFocusChanged);
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
      widget.onFocusChange?.call(focusNode.hasFocus);
    }
  }

  @override
  void onFocusNodeReplaced(FocusNode oldNode) {
    _attachment?.detach();
    _attachment = null;
    _teardownNode(oldNode);
    _configureNode(focusNode);
    _attachment = focusNode.attach(context);
    _didAutofocus = false;
  }

  @override
  void didUpdateWidget(Focus oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if (identical(oldWidget.focusNode, widget.focusNode)) {
      focusNode
        ..canRequestFocus = widget.canRequestFocus
        ..onKeyEvent = widget.onKeyEvent;
      _applyTraversalPolicy(focusNode);
      _attachment?.reparent(context);
    }
    if (!oldWidget.autofocus && widget.autofocus) {
      _didAutofocus = false;
      _scheduleAutofocus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachment ??= focusNode.attach(context);
    _attachment!.reparent(context);
    _scheduleAutofocus();
  }

  void _scheduleAutofocus() {
    if (widget.autofocus && !_didAutofocus) {
      _didAutofocus = true;
      final node = focusNode;
      scheduleMicrotask(() {
        if (!mounted) return; // widget unmounted before the microtask ran
        if (!identical(node, focusNode)) return; // node replaced meanwhile
        if (!widget.autofocus) return; // autofocus turned off meanwhile
        if (!node.isAttached) return; // node detached (owned or supplied)
        node.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _teardownNode(focusNode);
    _attachment?.detach();
    // Super's dispose (from the mixin) disposes the node when we own it.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A [Focus] whose [FocusScopeNode] groups descendant focus and remembers
/// its focused child.
class FocusScope extends Focus {
  /// Configures a scope with a supplied or state-owned scope node and policy.
  const FocusScope({
    required super.child,
    super.key,
    FocusScopeNode? node,
    this.traversalPolicy,
    super.autofocus,
    super.canRequestFocus,
    super.onFocusChange,
    super.onKeyEvent,
  }) : super(focusNode: node);

  /// Policy used for Tab and Shift+Tab traversal inside this scope.
  final FocusTraversalPolicy? traversalPolicy;

  /// Returns the nearest enclosing [FocusScopeNode], falling back to the
  /// root scope; [maybeOf] always resolves, so the no-ancestor [StateError]
  /// is a defensive backstop rather than a reachable outcome.
  ///
  /// Flutter-parity member; kept for API parity — see Flutter's
  /// `FocusScope.of`.
  static FocusScopeNode of(BuildContext context) {
    final node = maybeOf(context);
    if (node == null) {
      throw StateError(
        'FocusScope.of() called with a context that has no FocusScope ancestor.',
      );
    }
    return node;
  }

  /// Returns the nearest enclosing [FocusScopeNode], falling back to the
  /// root scope when no [FocusScope] ancestor exists.
  ///
  /// Local extension of Flutter's parity surface: Flutter exposes only
  /// `FocusScope.of`; this null-typed form has no Flutter counterpart.
  static FocusScopeNode? maybeOf(BuildContext context) {
    final element = context.element;
    return _findAncestorFocusNode<FocusScopeNode>(element) ??
        element.owner.focusManager.rootScope;
  }

  @override
  State<StatefulWidget> createState() => _FocusScopeState();
}

class _FocusScopeState extends _FocusState {
  @override
  FocusScope get widget => super.widget as FocusScope;

  @override
  FocusNode createDefaultFocusNode() {
    final policy = widget.traversalPolicy;
    return policy == null
        ? FocusScopeNode()
        : FocusScopeNode(traversalPolicy: policy);
  }

  @override
  void initState() {
    final supplied = widget.focusNode;
    if (supplied != null && supplied is! FocusScopeNode) {
      throw ArgumentError('FocusScope requires a FocusScopeNode.');
    }
    super.initState();
  }
}
