import 'dart:collection';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import '../framework/build_context.dart';
import '../framework/element.dart';
import '../framework/key.dart';
import '../framework/owner.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';
import '../rendering/proxy_box.dart';

/// Signature for building a widget from the space its parent offers.
///
/// [constraints] are the same constraints the built child is laid out with in
/// this frame. An unbounded axis reports a `null` maximum.
typedef LayoutWidgetBuilder =
    Widget Function(BuildContext context, BoxConstraints constraints);

/// Builds its child from the [BoxConstraints] its parent offers.
///
/// This is the only widget that lets an application read the space it was
/// given. Everything else in Noir declares a size and lets layout resolve it,
/// so a widget that wants to show more rows in a tall pane and fewer in a
/// short one has to ask:
///
/// ```dart
/// LayoutBuilder(
///   builder: (context, constraints) => ListView(
///     itemCount: items.length,
///     height: constraints.maxHeight ?? 8,
///     itemBuilder: buildRow,
///   ),
/// )
/// ```
///
/// [builder] runs during layout, and its result is laid out in the same frame,
/// so the constraints it reads and the constraints its child receives are
/// always the same. It runs on the first layout, whenever the incoming
/// constraints change, whenever this widget is updated, whenever an inherited
/// dependency it read changes, and on reassembly. Laying the same subtree out
/// again at unchanged constraints does not run it.
///
/// The builder must return a widget that this widget's constraints can hold.
/// Reading `constraints.maxHeight` on an unbounded axis returns `null`; supply
/// a fallback, as the example does.
///
/// The builder reads inherited widgets exactly as an ordinary `build` method
/// does: a dependency it stops reading stops rebuilding it.
///
/// Do not depend on the builder running a fixed number of times, and do not
/// perform work in it that a repeated run would duplicate: it is called from
/// layout, which the framework may run more than once for one visible change.
/// Return this widget's child and nothing else. The builder runs inside the
/// layout pass, so work that reaches outside its own subtree — mutating
/// another render object, or driving an overlay — has no defined order against
/// the rest of that pass.
class LayoutBuilder extends RenderObjectWidget {
  /// Creates a widget that builds its child from its own constraints.
  const LayoutBuilder({required this.builder, super.key});

  /// Called with the constraints this widget's parent offers.
  final LayoutWidgetBuilder builder;

  @override
  @internal
  Element createElement() => _LayoutBuilderElement(this);

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLayoutBuilder();

  /// Nothing to update: the render object holds only the layout-time build
  /// hook, which the element owns, and the element reads [builder] from the
  /// current widget each time it builds.
  @override
  @internal
  void updateRenderObject(BuildContext context, RenderObject renderObject) {}
}

/// Element that defers its build to its render object's layout.
///
/// An ordinary element builds during [BuildOwner.buildScope], which runs
/// before layout and therefore before any constraints exist. This element
/// records that it needs a build, marks its render object for layout, and
/// builds when the render object hands it the constraints.
class _LayoutBuilderElement extends RenderObjectElement {
  _LayoutBuilderElement(LayoutBuilder super.widget);

  final _children = <Element>[];

  @override
  late final List<Element> children = UnmodifiableListView(_children);

  @override
  LayoutBuilder get widget => super.widget as LayoutBuilder;

  /// The render object once [mount] has created it.
  _RenderLayoutBuilder get _renderObject =>
      renderObject! as _RenderLayoutBuilder;

  /// The render object, or null while a failed mount is rolled back.
  _RenderLayoutBuilder? get _renderObjectOrNull =>
      renderObject as _RenderLayoutBuilder?;

  bool _needsBuild = true;
  BoxConstraints? _lastConstraints;

  /// Constraints the deferred [performRebuild] must build against. Null until
  /// the render object has handed this element its first layout.
  BoxConstraints? _buildConstraints;

  @override
  void mount(Element? parent, BuildOwner owner) {
    super.mount(parent, owner);
    _renderObject.callback = _buildWithConstraints;
  }

  /// Marks this element for a layout-time build instead of building now.
  ///
  /// Running [Element.rebuild] here would sweep away every inherited
  /// dependency, because the builder — the only thing that reads inherited
  /// widgets — has not run yet. [_buildWithConstraints] runs the base
  /// implementation instead, once it has constraints, so the snapshot and the
  /// sweep still wrap the build that registers the dependencies.
  @override
  void rebuild() {
    owner.clearDirty(this);
    _needsBuild = true;
    renderObject?.markNeedsLayout();
  }

  /// Builds against the constraints [_buildWithConstraints] recorded.
  ///
  /// Does nothing during [mount], which builds before the render object
  /// exists and therefore before any constraints do.
  @override
  void performRebuild() {
    final constraints = _buildConstraints;
    if (constraints == null) {
      return;
    }
    _updateChild(widget.builder(buildContext, constraints));
  }

  /// Builds and reconciles the child for [constraints], from layout.
  ///
  /// Delegates to [Element.rebuild] so this element keeps the ordinary
  /// dependency lifecycle: the base implementation snapshots the current
  /// inherited registrations, runs [performRebuild], and then releases the
  /// ones the builder no longer read.
  ///
  /// Nothing is recorded until the build succeeds, so a builder that throws
  /// leaves this element marked and the next layout retries it.
  ///
  /// [BuildOwner.finalizeTree] runs here for the same reason
  /// [BuildOwner.buildScope] runs it: a replaced child is only deactivated by
  /// reconciliation, and nothing disposes its `State` until the tree is
  /// finalized. This build happens after the frame's `buildScope` has already
  /// finalized, so without this call the old child would keep its focus
  /// registrations, tickers, and subscriptions for at least one more frame.
  void _buildWithConstraints(BoxConstraints constraints) {
    if (!_needsBuild && constraints == _lastConstraints) {
      return;
    }
    _buildConstraints = constraints;
    super.rebuild();
    owner.finalizeTree();
    _needsBuild = false;
    _lastConstraints = constraints;
  }

  void _updateChild(Widget newWidget) {
    final currentChild = _children.isEmpty ? null : _children.single;
    final key = newWidget.key;
    if (key is GlobalKey) {
      owner.validateGlobalKeyPlacement(
        key,
        newWidget,
        this,
        retainedElement:
            currentChild != null &&
                Widget.canUpdate(currentChild.widget, newWidget)
            ? currentChild
            : null,
      );
    }
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
      // BuildOwner.deactivateChild owns preflight, render detach, and
      // publication; dropping the render edge first would split ownership.
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
      return;
    }
    _renderObject.setChild(
      Element.findRenderObjectElement(_children.single)?.renderObject,
    );
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    final render = _renderObjectOrNull;
    if (render != null && identical(render.child, child)) {
      render.setChild(null);
    }
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    // Null only while a failed mount is rolled back: the render object is
    // created after `Element.mount` has already marked this element mounted.
    final render = _renderObjectOrNull;
    failures.attempt(() => render?.callback = null);
    failures.attempt(() => render?.setChild(null));
    final childSnapshot = List<Element>.from(_children);
    for (final child in childSnapshot) {
      failures.attempt(child.unmount);
    }
    _children.clear();
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }
}

/// Proxy box that asks its element to build before it lays its child out.
class _RenderLayoutBuilder extends RenderProxyBox {
  /// Build hook installed by the owning element, cleared on unmount.
  void Function(BoxConstraints constraints)? callback;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    callback?.call(constraints);
    super.performBoxLayout(constraints);
  }
}
