import 'dart:collection';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/key.dart';
import '../framework/owner.dart';
import '../framework/widget.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import '../rendering/overlay.dart';

/// Builds a widget from the supplied [BuildContext].
typedef WidgetBuilder = Widget Function(BuildContext context);

/// Shows and hides the overlay child of a single [OverlayPortal].
///
/// Unattached [show] records pending visibility so the next valid attachment
/// builds the child. [hide] while unattached clears that pending request.
/// Replacing the controller on a live portal does not transfer visibility:
/// the old controller resets false and the previous overlay [State] is
/// destroyed. [show] on an already shown portal keeps that subtree and moves
/// only that identity to the top; rebuilds do not reorder entries.
final class OverlayPortalController {
  /// Retains [debugLabel] only for [toString] diagnostics.
  OverlayPortalController({this.debugLabel});

  /// Optional label included from [toString].
  final String? debugLabel;

  _OverlayPortalState? _client;
  var _pendingShow = false;

  /// Whether the overlay child is shown or a pending unattached show is set.
  bool get isShowing => _client?._wantsShow ?? _pendingShow;

  /// Shows the overlay child, or records a pending show while unattached.
  void show() {
    final client = _client;
    if (client == null) {
      _pendingShow = true;
      return;
    }
    client.show();
  }

  /// Hides the overlay child. Unattached calls clear a pending show.
  void hide() {
    final client = _client;
    if (client == null) {
      _pendingShow = false;
      return;
    }
    client.hide();
  }

  /// Shows the overlay child when hidden and hides it when shown.
  void toggle() {
    if (isShowing) {
      hide();
    } else {
      show();
    }
  }

  void _attach(_OverlayPortalState state) {
    _validateAttachment(state);
    _client = state;
    state._wantsShow = _pendingShow;
    _pendingShow = false;
  }

  void _validateAttachment(_OverlayPortalState state) {
    if (_client != null && !identical(_client, state)) {
      throw StateError(
        'OverlayPortalController is already attached to another OverlayPortal.',
      );
    }
  }

  void _detach(_OverlayPortalState state) {
    if (!identical(_client, state)) {
      return;
    }
    _client = null;
    _pendingShow = false;
  }

  @override
  String toString() {
    final label = debugLabel;
    final identity = identityHashCode(this).toRadixString(16);
    if (label == null) {
      return 'OverlayPortalController#$identity';
    }
    return 'OverlayPortalController#$identity($label)';
  }
}

/// Keeps [child] in the ordinary tree and hosts [overlayChildBuilder] on the
/// package-owned root overlay without changing logical ancestry.
///
/// The overlay subtree remains a logical descendant of this portal, so
/// inherited widgets, [Actions], [Shortcuts], and focus ancestry resolve
/// through the portal rather than the root host. Hiding destroys overlay
/// [State]; showing again builds a fresh subtree. Raw overlay content is laid
/// out at natural size from the terminal origin, clipped to the terminal, and
/// hit-tested only within its own bounds. Anchored placement belongs to
/// [MenuAnchor].
///
/// [runTuiApp] installs the host. Mounting this widget without that host
/// throws a [StateError] in every build mode. Bare `TuiBinding.runApp` does
/// not install one. One controller may attach to at most one live portal.
class OverlayPortal extends StatefulWidget {
  /// Binds [controller] to this portal and optionally paints [child] below.
  const OverlayPortal({
    required this.controller,
    required this.overlayChildBuilder,
    super.key,
    this.child,
  }) : _wrapEntry = true;

  const OverlayPortal._raw({
    required this.controller,
    required this.overlayChildBuilder,
    this.child,
  }) : _wrapEntry = false;

  /// Exclusive controller for this portal.
  final OverlayPortalController controller;

  /// Builds the overlay subtree only while the portal is shown.
  final WidgetBuilder overlayChildBuilder;

  /// Ordinary child whose render edge stays in the parent chain.
  final Widget? child;

  final bool _wrapEntry;

  @override
  State<OverlayPortal> createState() => _OverlayPortalState();

  @override
  @internal
  Element createElement() => _OverlayPortalElement(this);
}

class _OverlayPortalElement extends StatefulElement {
  _OverlayPortalElement(OverlayPortal super.widget);

  @override
  void update(Widget newWidget) {
    final previous = widget as OverlayPortal;
    final next = newWidget as OverlayPortal;
    if (!identical(previous.controller, next.controller)) {
      next.controller._validateAttachment(state as _OverlayPortalState);
    }
    super.update(newWidget);
  }
}

class _OverlayPortalState extends State<OverlayPortal> {
  final _portalKey = GlobalKey();
  var _wantsShow = false;
  var _overlayGeneration = 0;

  void show() {
    if (_wantsShow) {
      _bringToTop();
      return;
    }
    setState(() => _wantsShow = true);
  }

  void hide() {
    if (!_wantsShow) {
      return;
    }
    setState(() => _wantsShow = false);
  }

  void _bringToTop() {
    final box = _overlayBox();
    if (box != null) {
      RootOverlay.of(context).moveEntryToTop(box);
    }
  }

  RenderBox? _overlayBox() {
    final element = _portalKey.currentContext?.element;
    if (element is _PortalElement) {
      return element.overlayBox;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
  }

  @override
  void didUpdateWidget(OverlayPortal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }
    oldWidget.controller._detach(this);
    _overlayGeneration++;
    _wantsShow = false;
    widget.controller._attach(this);
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Portal(
    key: _portalKey,
    showing: _wantsShow,
    overlayChildBuilder: widget._wrapEntry
        ? (context) => _OverlayEntry(
            key: ValueKey<int>(_overlayGeneration),
            child: widget.overlayChildBuilder(context),
          )
        : widget.overlayChildBuilder,
    child: widget.child,
  );
}

/// Builds an [OverlayPortal] that hosts the builder output as the entry root.
@internal
OverlayPortal rawOverlayPortal({
  required OverlayPortalController controller,
  required WidgetBuilder overlayChildBuilder,
  Widget? child,
}) => OverlayPortal._raw(
  controller: controller,
  overlayChildBuilder: overlayChildBuilder,
  child: child,
);

/// Package-owned root overlay installed by [runTuiApp].
@internal
class RootOverlay extends StatefulWidget {
  /// Wraps [child] with the private overlay theater.
  const RootOverlay({required this.child, super.key});

  /// Ordinary application content hosted in the base slot.
  final Widget child;

  /// The installed overlay state, or a [StateError] when none exists.
  static RootOverlayState of(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<_RootOverlayScope>()
        ?.widget;
    if (scope is! _RootOverlayScope) {
      throw StateError(
        'OverlayPortal was mounted without the package-owned root overlay. '
        'Mount the application through runTuiApp or mountTuiAppForTesting.',
      );
    }
    return scope.state;
  }

  @override
  State<RootOverlay> createState() => RootOverlayState();
}

/// State that adopts portal entry render boxes onto the theater.
@internal
class RootOverlayState extends State<RootOverlay> {
  final _theaterKey = GlobalKey();

  /// Adopts [entry] as the topmost overlay entry.
  void adoptEntry(RenderBox entry) => _overlay.adoptEntry(entry);

  /// Drops [entry] when it is still hosted here.
  void dropEntry(RenderBox entry) => _overlay.dropEntry(entry);

  /// Moves an already shown [entry] to the top.
  void moveEntryToTop(RenderBox entry) => _overlay.moveEntryToTop(entry);

  RenderOverlay get _overlay {
    final element = _theaterKey.currentContext?.element;
    if (element is! _OverlayTheaterElement) {
      throw StateError('Root overlay theater is not mounted.');
    }
    return element.overlay;
  }

  @override
  Widget build(BuildContext context) => _RootOverlayScope(
    state: this,
    child: _OverlayTheater(key: _theaterKey, child: widget.child),
  );
}

class _RootOverlayScope extends InheritedWidget {
  const _RootOverlayScope({required this.state, required super.child});

  final RootOverlayState state;

  @override
  bool updateShouldNotify(_RootOverlayScope oldWidget) =>
      !identical(oldWidget.state, state);
}

class _OverlayTheater extends RenderObjectWidget {
  const _OverlayTheater({required this.child, super.key});

  final Widget child;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderOverlay();

  @override
  @internal
  Element createElement() => _OverlayTheaterElement(this);
}

class _OverlayTheaterElement extends RenderObjectElement {
  _OverlayTheaterElement(_OverlayTheater super.widget);

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  RenderOverlay get overlay => renderObject! as RenderOverlay;

  @override
  void mount(Element? parent, BuildOwner owner) {
    super.mount(parent, owner);
    _updateChild(_widget.child);
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    _updateChild(_widget.child);
  }

  _OverlayTheater get _widget => widget as _OverlayTheater;

  void _updateChild(Widget newWidget) {
    final currentChild = _children.isEmpty ? null : _children.single;
    if (currentChild == null) {
      _children.add(Element.inflateWidget(newWidget, this));
      _attachChildRenderObject();
      return;
    }
    if (Widget.canUpdate(currentChild.widget, newWidget)) {
      currentChild.update(newWidget);
      _attachChildRenderObject();
      return;
    }
    try {
      owner.deactivateChild(currentChild);
    } finally {
      if (currentChild.parent == null && !currentChild.active) {
        _children.clear();
      }
    }
    _children.add(Element.inflateWidget(newWidget, this));
    _attachChildRenderObject();
  }

  void _attachChildRenderObject() {
    if (_children.isEmpty) {
      overlay.setBase(null);
      return;
    }
    overlay.setBase(
      Element.findRenderObjectElement(_children.single)?.renderObject,
    );
  }

  @override
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    overlay.setBase(child);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    if (identical(overlay.base, child)) {
      overlay.setBase(null);
    }
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    failures.attempt(overlay.drainEntries);
    failures.attempt(_detachChildRenderObject);
    final childSnapshot = List<Element>.from(_children);
    for (final child in childSnapshot) {
      failures.attempt(child.unmount);
    }
    _children.clear();
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }

  void _detachChildRenderObject() {
    overlay.setBase(null);
  }
}

class _Portal extends Widget {
  const _Portal({
    required this.showing,
    required this.overlayChildBuilder,
    super.key,
    this.child,
  });

  final bool showing;
  final WidgetBuilder overlayChildBuilder;
  final Widget? child;

  @override
  @internal
  Element createElement() => _PortalElement(this);
}

class _PortalElement extends Element {
  _PortalElement(_Portal super.widget);

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  Element? _child;
  Element? _overlay;
  var _inflatingOverlay = false;
  RenderBox? overlayBox;

  _Portal get _widget => widget as _Portal;

  @override
  void performRebuild() {
    RootOverlay.of(buildContext);
    _updateSlot(
      current: _child,
      next: _widget.child,
      overlay: false,
      assign: (element) => _child = element,
    );
    final overlayWidget = _widget.showing
        ? _widget.overlayChildBuilder(buildContext)
        : null;
    _updateSlot(
      current: _overlay,
      next: overlayWidget,
      overlay: true,
      assign: (element) => _overlay = element,
    );
  }

  void _updateSlot({
    required Element? current,
    required Widget? next,
    required bool overlay,
    required void Function(Element? element) assign,
  }) {
    if (next == null) {
      if (current != null) {
        try {
          owner.deactivateChild(current);
        } finally {
          if (current.parent == null && !current.active) {
            _children.removeWhere((candidate) => identical(candidate, current));
            assign(null);
          }
        }
      }
      return;
    }
    if (current == null) {
      _inflatingOverlay = overlay;
      try {
        final child = Element.inflateWidget(next, this);
        _children.insert(overlay ? _children.length : 0, child);
        assign(child);
      } finally {
        _inflatingOverlay = false;
      }
      return;
    }
    if (Widget.canUpdate(current.widget, next)) {
      current.update(next);
      return;
    }
    try {
      owner.deactivateChild(current);
    } finally {
      if (current.parent == null && !current.active) {
        _children.removeWhere((candidate) => identical(candidate, current));
        assign(null);
      }
    }
    _inflatingOverlay = overlay;
    try {
      final child = Element.inflateWidget(next, this);
      _children.insert(overlay ? _children.length : 0, child);
      assign(child);
    } finally {
      _inflatingOverlay = false;
    }
  }

  @override
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    final overlayRender = _overlay == null
        ? null
        : Element.findRenderObjectElement(_overlay!);
    if (_inflatingOverlay || identical(childElement, overlayRender)) {
      if (child is! RenderBox) {
        throw StateError(
          'OverlayPortal overlay entry root must be a framework-owned '
          'RenderBox wrapper, got ${child.runtimeType}.',
        );
      }
      RootOverlay.of(buildContext).adoptEntry(child);
      overlayBox = child;
      return;
    }
    super.insertRenderObjectChild(child, childElement);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    final overlayRender = _overlay == null
        ? null
        : Element.findRenderObjectElement(_overlay!);
    if (identical(childElement, overlayRender) ||
        identical(child, overlayBox)) {
      if (child is RenderBox) {
        _dropOverlay(child);
      }
      return;
    }
    super.removeRenderObjectChild(child, childElement);
  }

  @override
  void collectOwnedExternalRenderEdges(List<ExternalRenderEdge> edges) {
    final child = overlayBox;
    if (child == null || child.parent == null) {
      return;
    }
    final parent = child.parent!;
    edges.add(
      ExternalRenderEdge(
        child: child,
        expectedParent: parent,
        detach: () => _dropOverlay(child),
      ),
    );
  }

  @override
  RenderObject? findRenderObject() => _child?.findRenderObject();

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final child = overlayBox;
    if (child != null) {
      _dropOverlay(child);
    }
    super.unmount();
  }

  void _dropOverlay(RenderBox child) {
    final parent = child.parent;
    if (parent is RenderOverlay) {
      parent.dropEntry(child);
    } else if (parent != null) {
      throw StateError(
        'Overlay entry is parented to ${parent.runtimeType} instead of the '
        'root overlay.',
      );
    }
    if (identical(overlayBox, child)) {
      overlayBox = null;
    }
  }
}

class _OverlayEntry extends SingleChildRenderObjectWidget {
  const _OverlayEntry({super.key, super.child});

  @override
  @internal
  RenderOverlayEntry createRenderObject(BuildContext context) =>
      RenderOverlayEntry();
}
