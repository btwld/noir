import 'dart:collection';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import '../rendering/box.dart';
import '../rendering/object.dart';
import 'build_context.dart';
import 'key.dart';
import 'owner.dart';
import 'widget.dart';

/// Signature for callbacks that visit an [Element].
typedef ElementVisitor = void Function(Element element);

/// An instantiation of a [Widget] at a location in the element tree.
abstract class Element {
  /// Creates an element backed by [widget].
  Element(this.widget);

  /// The widget this element currently represents.
  Widget widget;

  Element? _parent;

  /// The parent element, or null for the root.
  Element? get parent => _parent;

  /// Maintained tree depth: root is 0, each child is parent depth + 1.
  ///
  /// Owned by [BuildOwner] structural transitions so dirty scheduling never
  /// walks ancestors.
  int _depth = 0;

  /// Maintained depth used for dirty-bucket ordering.
  int get depth => _depth;

  /// The direct child elements of this element in document order.
  ///
  /// The returned list has stable identity, remains live across framework
  /// updates, and cannot be mutated by callers.
  List<Element> get children => const <Element>[];

  /// Whether this element is currently in the tree.
  ///
  /// Stays `true` for a deactivated-but-not-yet-finalized element (see
  /// [deactivate]) — it is inactive, not gone. Use [active] to ask "is this
  /// element live and safe to rebuild right now."
  bool mounted = false;

  /// The owner that manages this element's build pipeline.
  late final BuildOwner owner;

  bool _deactivated = false;

  /// Whether this element is live: [mounted] and not [deactivate]d.
  ///
  /// [BuildOwner.scheduleBuild] and [BuildOwner.buildScope] gate on this
  /// (not [mounted] alone) so a dirty element deactivated earlier in the
  /// same build pass — by a shallower, depth-first-processed relative
  /// removing it — is never rebuilt as a ghost. `false` while deactivated
  /// and pending [BuildOwner.finalizeTree].
  bool get active => mounted && !_deactivated;

  Map<InheritedElement, Object?>? _dependencies;
  Set<InheritedElement>? _dependenciesToRemove;

  /// The [BuildContext] for this element.
  BuildContext get buildContext => _ctx;
  late final _BuildContextImpl _ctx = _BuildContextImpl(this);

  /// Inserts this element into the tree under [parent] and builds it.
  void mount(Element? parent, BuildOwner owner) {
    this.owner = owner;
    registerElementWithBuildOwner(owner, this, parent);
    mounted = true;
    _registerGlobalKey();
    performRebuild();
  }

  /// Removes this element and its descendants from the tree permanently.
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    _deactivated = true;
    failures.attempt(_unregisterGlobalKey);
    _dropAllDependencies(failures);
    mounted = false;
    final childSnapshot = List<Element>.from(children);
    for (final child in childSnapshot) {
      failures.attempt(child.unmount);
    }
    failures.attempt(() => unregisterElementFromBuildOwner(owner, this));
    failures.rethrowFirst();
  }

  /// Marks this element's subtree inactive without destroying [State] or
  /// child render objects.
  ///
  /// Called by [BuildOwner.deactivateChild] when reconciliation removes this
  /// element from its parent. Idempotent — a no-op if already deactivated,
  /// so a subtree deactivated once during reconciliation is not deactivated
  /// again when [unmount] eventually runs on it. The element remains
  /// [mounted] until [BuildOwner.finalizeTree] permanently [unmount]s it.
  void deactivate() {
    if (_deactivated) {
      return;
    }
    _deactivated = true;
    final failures = FirstErrorRecorder();
    final childSnapshot = List<Element>.from(children);
    for (final child in childSnapshot) {
      failures.attempt(child.deactivate);
    }
    failures.rethrowFirst();
  }

  /// Creates the [Element] for [newWidget] as a child of [parentForNewChild].
  static Element inflateWidget(Widget newWidget, Element parentForNewChild) {
    final key = newWidget.key;
    if (key is GlobalKey) {
      parentForNewChild.owner.validateGlobalKeyPlacement(
        key,
        newWidget,
        parentForNewChild,
      );
    }
    final newChild = newWidget.createElement();
    try {
      newChild.mount(parentForNewChild, parentForNewChild.owner);
    } on Object catch (error, stackTrace) {
      if (newChild.mounted) {
        try {
          newChild.unmount();
        } on Object {
          // The mount failure remains primary after rollback is attempted.
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return newChild;
  }

  /// Updates this element to represent [newWidget] and rebuilds it.
  void update(Widget newWidget) {
    _validateGlobalKeyForUpdate(newWidget);
    final oldWidget = widget;
    widget = newWidget;
    _updateGlobalKeyForUpdate(oldWidget, newWidget);
    rebuild();
  }

  /// Rebuilds this element, refreshing its inherited-widget dependencies.
  void rebuild() {
    // Deduplicate against `BuildOwner`'s dirty queue: this rebuild may be
    // happening via a direct cascade (e.g. an `InheritedElement` rebuilding
    // a dependent that `notifyDependents` already scheduled) rather than via
    // `BuildOwner.buildScope`'s own loop. Clearing the dirty-set entry here
    // makes a later, now-stale queue entry for this element a no-op instead
    // of a second rebuild. Harmless (and a no-op) when this element was
    // never dirty in the first place.
    owner.clearDirty(this);
    final deps = _dependencies;
    if (deps != null && deps.isNotEmpty) {
      _dependenciesToRemove = Set<InheritedElement>.identity()
        ..addAll(deps.keys);
    } else {
      _dependenciesToRemove = null;
    }

    performRebuild();

    final toRemove = _dependenciesToRemove;
    if (toRemove != null) {
      for (final inherited in toRemove) {
        inherited.removeDependent(this);
      }
      _dependenciesToRemove = null;
    }
  }

  /// Rebuilds this element's subtree from its current widget configuration.
  void performRebuild();

  /// Walk up the element tree calling [visitor] for each ancestor until it
  /// returns `false` or the root is reached.
  void visitAncestorElements(bool Function(Element element) visitor) {
    var ancestor = parent;
    while (ancestor != null && visitor(ancestor)) {
      ancestor = ancestor.parent;
    }
  }

  /// Calls [visitor] for each child element of this element.
  void visitChildren(ElementVisitor visitor) {
    for (final child in children) {
      visitor(child);
    }
  }

  /// Recursively searches for a [RenderObjectElement] in the element tree.
  ///
  /// This utility method traverses the element tree starting from [element],
  /// returning the first [RenderObjectElement] found (depth-first search).
  /// Returns null if no [RenderObjectElement] is found.
  ///
  /// This is commonly used when attaching child render objects to their
  /// parents, as the child widget may not directly produce a render object
  /// (e.g., when wrapped in a [StatelessWidget]).
  static RenderObjectElement? findRenderObjectElement(Element element) {
    if (element is RenderObjectElement) {
      return element;
    }
    for (final child in element.children) {
      final found = findRenderObjectElement(child);
      if (found != null) {
        return found;
      }
    }
    return null;
  }

  /// Recursively searches for a [RenderObject] in the element tree.
  ///
  /// This is a convenience method that calls [findRenderObjectElement] and
  /// returns its render object if found.
  static RenderObject? findDescendantRenderObject(Element element) =>
      findRenderObjectElement(element)?.renderObject;

  /// Registers this element as dependent on the nearest inherited widget of type [T].
  ///
  /// Deliberate deviation: matches `is T` subtypes, unlike Flutter's
  /// exact-runtimeType lookup.
  InheritedElement? dependOnInheritedElementOfExactType<
    T extends InheritedWidget
  >({Object? aspect}) {
    final inherited = _findAncestorInheritedElementOfExactType<T>();
    if (inherited != null) {
      _dependencies ??= Map<InheritedElement, Object?>.identity();
      _dependencies![inherited] = aspect;
      _dependenciesToRemove?.remove(inherited);
      inherited.updateDependencies(this, aspect);
    }
    return inherited;
  }

  /// Returns the nearest inherited element of type [T] without registering a dependency.
  InheritedElement?
  getElementForInheritedWidgetOfExactType<T extends InheritedWidget>() =>
      _findAncestorInheritedElementOfExactType<T>();

  InheritedElement?
  _findAncestorInheritedElementOfExactType<T extends InheritedWidget>() {
    InheritedElement? result;
    visitAncestorElements((ancestor) {
      if (ancestor is InheritedElement && ancestor.widget is T) {
        result = ancestor;
        return false;
      }
      return true;
    });
    return result;
  }

  /// Returns the nearest ancestor widget of type [T].
  ///
  /// Deliberate deviation: matches `is T` subtypes, unlike Flutter's
  /// exact-runtimeType lookup.
  T? findAncestorWidgetOfExactType<T extends Widget>() {
    T? result;
    visitAncestorElements((ancestor) {
      if (ancestor.widget is T) {
        result = ancestor.widget as T;
        return false;
      }
      return true;
    });
    return result;
  }

  /// Returns the nearest ancestor state of type [T].
  T? findAncestorStateOfType<T extends State<StatefulWidget>>() {
    var ancestor = parent;
    while (ancestor != null) {
      if (ancestor is StatefulElement) {
        final state = ancestor.state;
        if (state is T) {
          return state;
        }
      }
      ancestor = ancestor.parent;
    }
    return null;
  }

  /// Returns the nearest ancestor render object of type [T].
  T? findAncestorRenderObjectOfType<T extends RenderObject>() {
    T? result;
    visitAncestorElements((ancestor) {
      final renderObject = ancestor.findRenderObject();
      if (renderObject is T) {
        result = renderObject;
        return false;
      }
      return true;
    });
    return result;
  }

  /// The render object associated with this element, if any.
  RenderObject? findRenderObject() => null;

  /// Bubble a render-object child insertion toward the nearest render parent.
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    final parentElement = parent;
    if (parentElement != null) {
      parentElement.insertRenderObjectChild(child, childElement);
      return;
    }
    owner.insertRootRenderObjectChild(child);
  }

  /// Bubble a render-object child removal toward the nearest render parent.
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    final parentElement = parent;
    if (parentElement != null) {
      parentElement.removeRenderObjectChild(child, childElement);
      return;
    }
    owner.removeRootRenderObjectChild(child);
  }

  /// Called by [inherited] when it changes; schedules this element to rebuild.
  void notifyDependent(InheritedElement inherited, Object? aspect) {
    owner.scheduleBuild(this);
  }

  /// Called when [inherited] removes this element from its dependents.
  void didLoseDependency(InheritedElement inherited) {
    _dependencies?.remove(inherited);
  }

  void _registerGlobalKey() {
    final key = widget.key;
    if (key is GlobalKey) {
      owner.registerGlobalKey(key, this);
    }
  }

  void _validateGlobalKeyForUpdate(Widget newWidget) {
    final key = newWidget.key;
    if (key is GlobalKey) {
      owner.validateGlobalKeyPlacement(
        key,
        newWidget,
        parent,
        retainedElement: this,
      );
    }
  }

  void _updateGlobalKeyForUpdate(Widget oldWidget, Widget newWidget) {
    final oldKey = oldWidget.key;
    final newKey = newWidget.key;
    if (identical(oldKey, newKey)) {
      // Same key (or both null): `widget` is already reassigned by the
      // caller, so the registry's `element.widget` lookup already reflects
      // the new configuration. Nothing to rebind.
      return;
    }
    if (oldKey is GlobalKey) {
      owner.unregisterGlobalKey(oldKey, this);
    }
    if (newKey is GlobalKey) {
      owner.registerGlobalKey(newKey, this);
    }
  }

  void _unregisterGlobalKey() {
    final key = widget.key;
    if (key is GlobalKey) {
      owner.unregisterGlobalKey(key, this);
    }
  }

  void _dropAllDependencies(FirstErrorRecorder failures) {
    final deps = _dependencies;
    final copy = deps == null
        ? const <InheritedElement>[]
        : List<InheritedElement>.from(deps.keys);
    for (final inherited in copy) {
      failures.attempt(() => inherited.removeDependent(this));
    }
    _dependencies = null;
    _dependenciesToRemove = null;
  }

  /// Short debug description of this element's widget and key.
  String debugDescribeWidget() {
    final widgetId =
        '${widget.runtimeType}#${identityHashCode(widget).toRadixString(16)}';
    final key = widget.key;
    if (key == null) {
      return widgetId;
    }
    final keyId =
        '${key.runtimeType}#${identityHashCode(key).toRadixString(16)}';
    return '$widgetId(key: $keyId)';
  }
}

/// Element backing a [StatelessWidget].
class StatelessElement extends _ElementBase {
  /// Creates an element for a [StatelessWidget].
  StatelessElement(StatelessWidget super.widget);

  @override
  void performRebuild() {
    final w = widget as StatelessWidget;
    final built = w.build(buildContext);
    _updateChild(built);
  }
}

/// Element backing a [StatefulWidget], owning its [State].
class StatefulElement extends _ElementBase {
  /// Creates an element for a [StatefulWidget] and its [State].
  StatefulElement(StatefulWidget super.widget) : _state = widget.createState();

  final State _state;

  /// Whether an inherited dependency changed since the last rebuild.
  ///
  /// Set by [notifyDependent] and consumed by [performRebuild], so
  /// `State.didChangeDependencies()` fires immediately before the next
  /// `build()` — never eagerly at notification time, when the dependent may
  /// still be mid-cascade with stale derived state, or about to be
  /// deactivated before it ever rebuilds (see
  /// `InheritedElement.notifyDependents`'s liveness guard).
  bool _dependenciesChanged = false;

  /// The [State] owned by this element.
  State get state => _state;

  @override
  void mount(Element? parent, BuildOwner owner) {
    this.owner = owner;
    registerElementWithBuildOwner(owner, this, parent);
    mounted = true;
    _state.attach(widget as StatefulWidget, buildContext, _markNeedsBuild);
    _registerGlobalKey();
    _state.initState();
    _state.didChangeDependencies();
    performRebuild();
  }

  @override
  void update(Widget newWidget) {
    _validateGlobalKeyForUpdate(newWidget);
    final oldWidget = widget;
    widget = newWidget;
    _updateGlobalKeyForUpdate(oldWidget, newWidget);
    _state.updateWidget(newWidget as StatefulWidget);
    rebuild();
  }

  @override
  void deactivate() {
    if (_deactivated) {
      return;
    }
    final failures = FirstErrorRecorder();
    failures.attempt(_state.deactivate);
    failures.attempt(super.deactivate);
    failures.rethrowFirst();
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    // `deactivate()` may already have run during reconciliation; guard
    // against calling `State.deactivate()` a second time while still
    // guaranteeing it runs once for the direct-unmount path below, where
    // reconciliation never deactivated this element first.
    if (!_deactivated) {
      failures.attempt(_state.deactivate);
    }
    // `dispose()` must run before `detach()`: Flutter keeps `State` attached
    // (mounted, with a readable context) through the entire `dispose()` call
    // so overrides can still read `mounted`/`context`/`widget`; only after
    // `dispose()` returns is the State/Element association actually severed.
    // `super.unmount()` recurses into children first (bottom-up: each
    // descendant fully disposes and detaches before this call returns), so
    // this node's own `dispose()`/`detach()` still run after every
    // descendant's.
    failures.attempt(super.unmount);
    failures.attempt(_state.disposeState);
    failures.attempt(_state.detach);
    failures.rethrowFirst();
  }

  @override
  void performRebuild() {
    if (_dependenciesChanged) {
      _state.didChangeDependencies();
      _dependenciesChanged = false;
    }
    final built = _state.build(buildContext);
    _updateChild(built);
  }

  @override
  void notifyDependent(InheritedElement inherited, Object? aspect) {
    _dependenciesChanged = true;
    super.notifyDependent(inherited, aspect);
  }
}

abstract class _ElementBase extends Element {
  _ElementBase(super.widget);

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

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
    } else if (Widget.canUpdate(currentChild.widget, newWidget)) {
      currentChild.update(newWidget);
    } else {
      try {
        owner.deactivateChild(currentChild);
      } finally {
        if (currentChild.parent == null && !currentChild.active) {
          _children.clear();
        }
      }
      final child = Element.inflateWidget(newWidget, this);
      _children.add(child);
    }
  }

  void _markNeedsBuild() => owner.scheduleBuild(this);

  @override
  RenderObject? findRenderObject() =>
      _children.isEmpty ? null : _children.single.findRenderObject();

  @override
  void unmount() {
    try {
      super.unmount();
    } finally {
      _children.clear();
    }
  }
}

/// Element backing a [ProxyWidget], building its single child.
class ProxyElement extends _ElementBase {
  /// Creates an element for a [ProxyWidget].
  ProxyElement(ProxyWidget super.widget);

  @override
  void performRebuild() {
    final proxy = widget as ProxyWidget;
    _updateChild(proxy.child);
  }
}

/// Element that manages an [InheritedWidget].
class InheritedElement extends ProxyElement {
  /// Creates an element for an [InheritedWidget].
  InheritedElement(InheritedWidget super.widget);

  final Map<Element, Object?> _dependents = Map<Element, Object?>.identity();

  @override
  InheritedWidget get widget => super.widget as InheritedWidget;

  /// Register [dependent] to receive notifications when this inherited widget
  /// updates.
  void updateDependencies(Element dependent, Object? aspect) {
    _dependents[dependent] = aspect;
  }

  /// Remove [dependent] from the notification set.
  void removeDependent(Element dependent) {
    final existed = _dependents.containsKey(dependent);
    _dependents.remove(dependent);
    if (existed) {
      dependent.didLoseDependency(this);
    }
  }

  @override
  void update(Widget newWidget) {
    // Flutter order: adopt the new widget and notify dependents *before*
    // rebuilding the proxy child, so a dependent's rebuild (whether via this
    // cascade or a later scheduled build) always sees the new value and is
    // never notified against a subtree that already rebuilt stale. This
    // inlines `Element.update`'s widget-assignment step instead of calling
    // `super.update(newWidget)`, because that base method rebuilds the child
    // (via `rebuild()`) as part of the same call — exactly the ordering this
    // element must not conflate.
    _validateGlobalKeyForUpdate(newWidget);
    final oldWidget = widget;
    widget = newWidget;
    _updateGlobalKeyForUpdate(oldWidget, newWidget);
    if (widget.updateShouldNotify(oldWidget)) {
      notifyDependents();
    }
    rebuild();
  }

  /// Notify registered dependents that this inherited widget has changed.
  void notifyDependents() {
    final dependents = List<Element>.from(_dependents.keys);
    for (final dependent in dependents) {
      if (!dependent.mounted) {
        // Truly gone: drop the registration. (In practice `unmount()`'s own
        // `_dropAllDependencies` already does this before we would ever see
        // it here; kept as a defensive backstop.)
        _dependents.remove(dependent);
        continue;
      }
      if (!dependent.active) {
        // Deactivated earlier in this same rebuild (see [Element.deactivate])
        // but still mounted: keep its registration until `finalizeTree()`
        // disposes it and drops dependencies via `_dropAllDependencies`.
        continue;
      }
      dependent.notifyDependent(this, _dependents[dependent]);
    }
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    final dependents = List<Element>.from(_dependents.keys);
    for (final dependent in dependents) {
      failures.attempt(() => removeDependent(dependent));
    }
    _dependents.clear();
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }
}

/// Element for widgets that manage RenderObjects
///
/// RenderObjectElement creates, manages, and attaches RenderObjects to the render tree.
class RenderObjectElement extends Element {
  /// Creates an element for a [RenderObjectWidget].
  RenderObjectElement(RenderObjectWidget super.widget);
  RenderObject? _renderObject;

  /// Get the RenderObject managed by this element
  RenderObject? get renderObject => _renderObject;

  @override
  void mount(Element? parent, BuildOwner owner) {
    super.mount(parent, owner);
    _renderObject = (widget as RenderObjectWidget).createRenderObject(
      buildContext,
    );
    _renderObject!.attach(owner.pipelineOwner);
    attachRenderObject();
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    final renderObject = _renderObject;
    failures.attempt(detachRenderObject);
    if (renderObject?.pipelineOwner != null) {
      failures.attempt(renderObject!.detach);
    }
    _renderObject = null;
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    final renderObjectWidget = newWidget as RenderObjectWidget;
    renderObjectWidget.updateRenderObject(buildContext, _renderObject!);
  }

  @override
  void performRebuild() {
    // RenderObjectWidgets don't rebuild like other widgets
    // Their updates happen through updateRenderObject
  }

  /// Attach the RenderObject to its parent in the render tree
  void attachRenderObject() {
    final renderObject = _renderObject;
    if (renderObject == null) return;
    final parentElement = parent;
    if (parentElement != null) {
      parentElement.insertRenderObjectChild(renderObject, this);
    } else {
      owner.insertRootRenderObjectChild(renderObject);
    }
  }

  /// Detach the RenderObject from its parent in the render tree
  void detachRenderObject() {
    final renderObject = _renderObject;
    if (renderObject == null) return;
    final parentElement = parent;
    if (parentElement != null) {
      parentElement.removeRenderObjectChild(renderObject, this);
    } else {
      owner.removeRootRenderObjectChild(renderObject);
    }
  }

  /// Hook for parents to place newly attached render object children.
  @override
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    if (_renderObject != null && !identical(child.parent, _renderObject)) {
      _renderObject!.adoptChild(child);
    }
  }

  /// Hook for parents to remove render object children on detach.
  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    if (identical(child.parent, _renderObject)) {
      _renderObject!.dropChild(child);
    }
  }

  /// Find the RenderObject managed by this element
  @override
  RenderObject? findRenderObject() => _renderObject;
}

class _BuildContextImpl extends BuildContext {
  _BuildContextImpl(this.element);
  @override
  final Element element;
}

/// Abstract base class for RenderObjectWidgets with multiple children
abstract class MultiChildRenderObjectWidget extends RenderObjectWidget {
  /// Creates a render-object widget with the given [children].
  const MultiChildRenderObjectWidget({
    super.key,
    this.children = const <Widget>[],
  });

  /// The widgets below this widget in the tree
  final List<Widget> children;

  @override
  @internal
  MultiChildRenderObjectElement createElement() =>
      MultiChildRenderObjectElement(this);
}

/// Element backing a [SingleChildRenderObjectWidget].
class SingleChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element for a [SingleChildRenderObjectWidget].
  SingleChildRenderObjectElement(SingleChildRenderObjectWidget super.widget);

  @override
  SingleChildRenderObjectWidget get widget =>
      super.widget as SingleChildRenderObjectWidget;

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  @override
  void mount(Element? parent, BuildOwner owner) {
    super.mount(parent, owner);
    _updateChild(widget.child);
  }

  @override
  void update(Widget newWidget) {
    super.update(newWidget);
    _updateChild(widget.child);
  }

  void _updateChild(Widget? newWidget) {
    final currentChild = _children.isEmpty ? null : _children.single;
    final key = newWidget?.key;
    if (newWidget != null && key is GlobalKey) {
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
    void deactivateCurrentChild(Element currentChild) {
      try {
        owner.deactivateChild(currentChild);
      } finally {
        if (currentChild.parent == null && !currentChild.active) {
          _children.clear();
        }
      }
    }

    if (newWidget == null) {
      if (currentChild != null) {
        // BuildOwner.deactivateChild owns preflight → render detach → publication.
        // Do not drop the render edge before that sequence or a rejected
        // preflight would leave render and Element ownership split.
        deactivateCurrentChild(currentChild);
      }
      return;
    }

    if (currentChild == null) {
      _children.add(Element.inflateWidget(newWidget, this));
      _attachChildRenderObject();
      return;
    }

    if (Widget.canUpdate(currentChild.widget, newWidget)) {
      currentChild.update(newWidget);
      _attachChildRenderObject();
    } else {
      deactivateCurrentChild(currentChild);
      final child = Element.inflateWidget(newWidget, this);
      _children.add(child);
      _attachChildRenderObject();
    }
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    failures.attempt(_detachChildRenderObject);
    final childSnapshot = List<Element>.from(_children);
    for (final child in childSnapshot) {
      failures.attempt(child.unmount);
    }
    _children.clear();
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }

  void _attachChildRenderObject() {
    if (_children.isEmpty) {
      return;
    }
    final parentRenderObject = renderObject;
    if (parentRenderObject is! RenderObjectWithSingleChild) {
      throw StateError(
        'SingleChildRenderObjectElement requires its render object to mix in '
        'RenderObjectWithSingleChild, got ${parentRenderObject.runtimeType}',
      );
    }
    final childRenderObject = Element.findRenderObjectElement(
      _children.single,
    )?.renderObject;
    parentRenderObject.setChild(childRenderObject);
  }

  void _detachChildRenderObject() {
    final parentRenderObject = renderObject;
    if (parentRenderObject is RenderObjectWithSingleChild) {
      parentRenderObject.setChild(null);
    }
  }

  /// Clear this element's authoritative single render edge when represented.
  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    final parentRenderObject = renderObject;
    if (parentRenderObject is! RenderObjectWithSingleChild) {
      return;
    }
    if (identical(parentRenderObject.child, child)) {
      parentRenderObject.setChild(null);
    }
  }
}

/// Element for RenderObjectWidgets with multiple children.
///
/// Adopts each child's render object onto the parent render object via the
/// standard [RenderObject.adoptChild] / [RenderObject.dropChild] pair.
/// Subclasses can override [adoptChildRenderObject] / [dropChildRenderObject]
/// to plug into more specialised parents (e.g. [RenderFlex] needs flex
/// metadata; see [FlexRenderObjectElement]).
class MultiChildRenderObjectElement extends RenderObjectElement {
  /// Creates an element for a [MultiChildRenderObjectWidget].
  MultiChildRenderObjectElement(MultiChildRenderObjectWidget super.widget);

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  @override
  MultiChildRenderObjectWidget get widget =>
      super.widget as MultiChildRenderObjectWidget;

  @override
  void mount(Element? parent, BuildOwner owner) {
    _validateUniqueChildKeys(widget);
    super.mount(parent, owner);
    _buildChildren();
  }

  @override
  void update(Widget newWidget) {
    final nextWidget = newWidget as MultiChildRenderObjectWidget;
    _validateUniqueChildKeys(nextWidget);
    _validateGlobalKeyPlacements(nextWidget);
    super.update(newWidget);
    _updateChildren();
  }

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final failures = FirstErrorRecorder();
    final childSnapshot = List<Element>.from(_children);
    for (final child in childSnapshot) {
      failures.attempt(child.unmount);
    }
    _children.clear();
    failures.attempt(super.unmount);
    failures.rethrowFirst();
  }

  void _buildChildren() {
    _children.clear();
    for (final widget in this.widget.children) {
      final child = Element.inflateWidget(widget, this);
      _children.add(child);
    }
    _syncRenderChildren();
  }

  void _updateChildren() {
    final oldChildren = List<Element>.from(_children);
    final newWidgets = widget.children;
    final newChildren = <Element>[];
    var oldTop = 0;
    var newTop = 0;
    var oldBottom = oldChildren.length - 1;
    var newBottom = newWidgets.length - 1;

    // Compatible identity is positional at the list boundaries; keys opt into
    // movement only inside the unmatched middle. Updating the prefix now and
    // deferring the suffix keeps every update side effect in document order.
    while (oldTop <= oldBottom && newTop <= newBottom) {
      final oldChild = oldChildren[oldTop];
      final newWidget = newWidgets[newTop];
      if (!Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      oldChild.update(newWidget);
      newChildren.add(oldChild);
      oldTop++;
      newTop++;
    }

    while (oldTop <= oldBottom && newTop <= newBottom) {
      final oldChild = oldChildren[oldBottom];
      final newWidget = newWidgets[newBottom];
      if (!Widget.canUpdate(oldChild.widget, newWidget)) {
        break;
      }
      oldBottom--;
      newBottom--;
    }

    final oldKeyedChildren = <Key, Element>{};
    for (var i = oldTop; i <= oldBottom; i++) {
      final oldChild = oldChildren[i];
      final key = oldChild.widget.key;
      if (key == null) {
        _deactivateChild(oldChild);
      } else {
        oldKeyedChildren[key] = oldChild;
      }
    }

    for (var i = newTop; i <= newBottom; i++) {
      final newWidget = newWidgets[i];
      final key = newWidget.key;
      Element? child;
      if (key != null) {
        final candidate = oldKeyedChildren[key];
        if (candidate != null &&
            Widget.canUpdate(candidate.widget, newWidget)) {
          oldKeyedChildren.remove(key);
          child = candidate;
        }
      }

      if (child == null) {
        child = Element.inflateWidget(newWidget, this);
        _children.add(child);
      } else {
        child.update(newWidget);
      }
      newChildren.add(child);
    }

    var oldSuffix = oldBottom + 1;
    var newSuffix = newBottom + 1;
    while (oldSuffix < oldChildren.length && newSuffix < newWidgets.length) {
      final oldChild = oldChildren[oldSuffix];
      oldChild.update(newWidgets[newSuffix]);
      newChildren.add(oldChild);
      oldSuffix++;
      newSuffix++;
    }

    for (final oldChild in oldKeyedChildren.values) {
      _deactivateChild(oldChild);
    }

    _children
      ..clear()
      ..addAll(newChildren);
    _syncRenderChildren();
  }

  void _validateUniqueChildKeys(MultiChildRenderObjectWidget candidate) {
    final keys = <Key>{};
    for (final child in candidate.children) {
      final key = child.key;
      if (key != null && !keys.add(key)) {
        throw StateError(
          'Duplicate key $key found in ${candidate.runtimeType}. '
          'Sibling keys must be unique.',
        );
      }
    }
  }

  void _validateGlobalKeyPlacements(MultiChildRenderObjectWidget candidate) {
    final retainedByKey = <GlobalKey, Element>{};
    for (final child in _children) {
      final key = child.widget.key;
      if (key is GlobalKey) {
        retainedByKey[key] = child;
      }
    }
    for (final childWidget in candidate.children) {
      final key = childWidget.key;
      if (key is! GlobalKey) {
        continue;
      }
      final currentChild = retainedByKey[key];
      owner.validateGlobalKeyPlacement(
        key,
        childWidget,
        this,
        retainedElement:
            currentChild != null &&
                Widget.canUpdate(currentChild.widget, childWidget)
            ? currentChild
            : null,
      );
    }
  }

  void _deactivateChild(Element child) {
    // Render drop is owned by BuildOwner.deactivateChild while the Element
    // parent is still readable; pre-dropping here would split ownership on
    // preflight rejection.
    try {
      owner.deactivateChild(child);
    } finally {
      if (child.parent == null && !child.active) {
        _children.removeWhere((candidate) => identical(candidate, child));
      }
    }
  }

  void _syncRenderChildren() {
    final parentRenderObject = _renderObject;
    if (parentRenderObject == null) {
      return;
    }

    final desiredElements = <Element>[];
    final desiredRenderObjects = <RenderBox>[];
    final desiredIdentities = Set<RenderObject>.identity();
    for (var i = 0; i < _children.length; i++) {
      final element = _children[i];
      final renderElement = Element.findRenderObjectElement(element);
      final renderObject = renderElement?.renderObject;
      if (renderObject is RenderBox) {
        if (!desiredIdentities.add(renderObject)) {
          throw StateError(
            'Multiple child Elements resolved to the same RenderObject.',
          );
        }
        desiredElements.add(element);
        desiredRenderObjects.add(renderObject);
      }
    }

    // Genuine removals normally drop their render edge through
    // BuildOwner.deactivateChild. Keep this identity-based backstop for a
    // descendant whose render-object shape changed during its update.
    final existing = List<RenderObject>.from(parentRenderObject.children);
    for (final existingChild in existing) {
      if (!desiredIdentities.contains(existingChild)) {
        dropChildRenderObject(existingChild, null);
      }
    }

    RenderObject? previous;
    for (var slot = 0; slot < desiredRenderObjects.length; slot++) {
      final renderObject = desiredRenderObjects[slot];
      adoptChildRenderObject(renderObject, desiredElements[slot], slot);
      // Framework reconciliation owns this protected reorder hook.
      // ignore: invalid_use_of_protected_member
      parentRenderObject.moveChild(renderObject, after: previous);
      previous = renderObject;
    }
  }

  /// Adopt [child] onto this element's render object at [slot] (document
  /// order). Subclasses override to attach extra metadata such as flex
  /// factors.
  void adoptChildRenderObject(RenderBox child, Element childElement, int slot) {
    final parentRenderObject = _renderObject;
    if (parentRenderObject == null) return;
    if (identical(child.parent, parentRenderObject)) return;
    parentRenderObject.adoptChild(child);
  }

  /// Drop [child] from this element's render object.
  ///
  /// [childElement] is null only for the reconciliation consistency backstop;
  /// ordinary element removal provides the removed child.
  void dropChildRenderObject(RenderObject child, Element? childElement) {
    final parentRenderObject = _renderObject;
    if (parentRenderObject == null) return;
    if (!identical(child.parent, parentRenderObject)) return;
    parentRenderObject.dropChild(child);
  }

  @override
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    // Multi-child elements manage render children explicitly via
    // _syncRenderChildren. No-op here to avoid double adoption.
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    if (identical(child.parent, _renderObject)) {
      dropChildRenderObject(child, childElement);
    }
  }
}

/// Non-virtual parent write used only by [BuildOwner] structural transitions.
@internal
void updateElementParent(Element element, Element? parent) {
  element._parent = parent;
}

/// Non-virtual depth write used only by [BuildOwner] structural transitions.
@internal
void updateElementDepth(Element element, int depth) {
  element._depth = depth;
}
