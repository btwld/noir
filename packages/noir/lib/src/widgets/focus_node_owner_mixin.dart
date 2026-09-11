import '../framework/focus_manager.dart';
import '../framework/widget.dart';

/// State mixin for widgets that want to optionally own a [FocusNode].
///
/// Consolidates the boilerplate previously duplicated across `Focus`,
/// `FocusScope`, `TextInput`, `Select`, `ScrollBox`, and `TextArea`:
///
/// - If the widget supplies a [FocusNode] via constructor, the mixin uses it
///   and does not dispose it on unmount (the caller owns the lifecycle).
/// - If the widget does not supply a [FocusNode], the mixin creates one via
///   [createDefaultFocusNode] and disposes it in [dispose].
/// - On [didUpdateWidget], if the widget switched to a different
///   `widgetFocusNode`, [syncFocusNode] adopts the new node (or creates a
///   fresh default), notifies subclasses through [onFocusNodeReplaced] so they
///   can re-attach listeners, and only then disposes the previously-owned
///   node. A failure anywhere in that sequence keeps the old node current.
///
/// Subclasses must override [widgetFocusNode] to forward the constructor
/// parameter from their `StatefulWidget`. Example:
///
/// ```dart
/// class _MyState extends State<MyWidget> with FocusNodeOwnerStateMixin {
///   @override
///   FocusNode? get widgetFocusNode => widget.focusNode;
/// }
/// ```
///
/// Subclasses that need a specific [FocusNode] subtype (e.g. `FocusScope`
/// needing a [FocusScopeNode]) override [createDefaultFocusNode] to mint
/// the right type when the caller did not supply one. They are responsible
/// for validating the constructor parameter type (the mixin only enforces
/// it is a [FocusNode]).
mixin FocusNodeOwnerStateMixin<T extends StatefulWidget> on State<T> {
  /// The [FocusNode] supplied by the host widget's constructor, or null to use one created by this mixin.
  FocusNode? get widgetFocusNode;

  late FocusNode _focusNode;
  late bool _ownsFocusNode;

  /// Active focus node for this state — either the widget-supplied node or the mixin-owned default.
  FocusNode get focusNode => _focusNode;

  /// Subclasses override this to construct a default node when the widget
  /// did not supply one (e.g. `FocusScope` returns a `FocusScopeNode`).
  FocusNode createDefaultFocusNode() => FocusNode();

  /// Hook fired after [syncFocusNode] publishes the replacement node and
  /// before the old one is disposed, so `oldNode` is still usable here.
  /// Subclasses override to re-wire listeners, attachment, etc. If this
  /// throws, [syncFocusNode] rolls the swap back. The rollback restores only
  /// this mixin's fields: side effects the override applied before throwing —
  /// listeners already detached from `oldNode`, wiring already put on the new
  /// [focusNode] — are not undone, so overrides must validate before they
  /// mutate. The mixin does NOT call this from [initState]; subclasses that
  /// need post-init wiring should do it directly there (see `_FocusState`).
  void onFocusNodeReplaced(FocusNode oldNode) {}

  @override
  void initState() {
    super.initState();
    final supplied = widgetFocusNode;
    _focusNode = supplied ?? createDefaultFocusNode();
    _ownsFocusNode = supplied == null;
  }

  /// Subclasses that override [didUpdateWidget] must call
  /// `syncFocusNode(oldWidget.focusNode)` (or the equivalent accessor) to
  /// keep ownership in sync.
  void syncFocusNode(FocusNode? oldWidgetFocusNode) {
    if (identical(oldWidgetFocusNode, widgetFocusNode)) {
      return;
    }
    // The swap is transactional: the old node stays current and live until a
    // validated replacement exists and every subclass has re-wired onto it.
    // A failure at any step leaves exactly one usable node behind — the old
    // one — and destroys nothing this mixin cannot re-mint.
    final old = _focusNode;
    final oldOwned = _ownsFocusNode;
    final supplied = widgetFocusNode;
    if (supplied != null) {
      validateFocusNodeReplacementTarget(supplied, old, context);
    }
    final candidate = supplied ?? createDefaultFocusNode();
    _focusNode = candidate;
    _ownsFocusNode = supplied == null;
    try {
      // Fired before the old node is destroyed so subclasses can still detach
      // listeners and attachments from it.
      onFocusNodeReplaced(old);
    } on Object {
      _focusNode = old;
      _ownsFocusNode = oldOwned;
      if (supplied == null) {
        try {
          candidate.dispose();
        } on Object {
          // The hook failure remains primary after rollback is attempted.
        }
      }
      rethrow;
    }
    if (oldOwned) {
      old.dispose();
    }
  }

  @override
  void dispose() {
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
    super.dispose();
  }
}
