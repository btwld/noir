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
///   `widgetFocusNode`, [syncFocusNode] disposes the previously-owned node,
///   adopts the new one (or creates a fresh default), and notifies subclasses
///   through [onFocusNodeReplaced] so they can re-attach listeners.
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

  /// Hook fired after [syncFocusNode] swaps the underlying node. Subclasses
  /// override to re-wire listeners, attachment, etc. The mixin does NOT
  /// call this from [initState]; subclasses that need post-init wiring
  /// should do it directly there (see `_FocusState`).
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
    if (!identical(oldWidgetFocusNode, widgetFocusNode)) {
      final old = _focusNode;
      final supplied = widgetFocusNode;
      if (supplied != null) {
        validateFocusNodeReplacementTarget(supplied, old, context);
      }
      if (_ownsFocusNode) {
        old.dispose();
      }
      _focusNode = supplied ?? createDefaultFocusNode();
      _ownsFocusNode = supplied == null;
      onFocusNodeReplaced(old);
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
