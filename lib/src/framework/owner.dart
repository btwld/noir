import 'dart:collection';

import 'package:meta/meta.dart';

import '../animation/ticker.dart';
import '../core/cursor.dart';
import '../core/input.dart';
import '../core/renderer.dart';
import '../foundation/first_error.dart';
import '../rendering/object.dart';
import 'element.dart';
import 'focus_manager.dart';
import 'key.dart';
import 'pointer_router.dart';
import 'widget.dart';

/// Signature for callbacks invoked when a frame is scheduled.
typedef FrameCallback = void Function();

/// Coordinates the build pipeline, render root, focus, and input for an app.
class BuildOwner {
  /// Creates an advanced build and frame coordinator.
  BuildOwner({InputManager? inputManager, TickerScheduler? tickerScheduler})
    : this._(inputManager: inputManager, tickerScheduler: tickerScheduler);

  /// Creates a build owner with an injected render pipeline for tests.
  @internal
  BuildOwner.test({
    required PipelineOwner pipelineOwner,
    InputManager? inputManager,
    TickerScheduler? tickerScheduler,
  }) : this._(
         inputManager: inputManager,
         tickerScheduler: tickerScheduler,
         pipelineOwner: pipelineOwner,
       );

  BuildOwner._({
    InputManager? inputManager,
    TickerScheduler? tickerScheduler,
    PipelineOwner? pipelineOwner,
  }) : inputManager = inputManager ?? InputManager(),
       _tickerScheduler = tickerScheduler ?? TickerScheduler() {
    _pipelineOwner =
        pipelineOwner ??
        PipelineOwner(onNeedVisualUpdate: _handleNeedVisualUpdate);
    _ownsPipelineOwner = pipelineOwner == null;
    focusManager = FocusManager(this.inputManager);
    _pointerRouter = PointerRouter(this.inputManager);
  }

  /// Maintained element depths (identity map). Root is 0.
  final Map<Element, int> _depths = HashMap<Element, int>.identity();

  /// Current dirty reservation per element: generation + first-schedule ordinal.
  final Map<Element, _DirtyReservation> _dirtyReservations =
      HashMap<Element, _DirtyReservation>.identity();

  /// Pending dirty buckets: depth → (ordinal → entry).
  _DirtyBuckets _pendingBuckets = _DirtyBuckets();

  int _dirtyGeneration = 0;
  int _scheduleOrdinal = 0;

  /// Elements currently bound to a [GlobalKey], keyed by the key instance.
  /// [BuildOwner] owns tree-wide placement validation; [GlobalKey] stores the
  /// single read-only pointer used by app queries and cross-owner validation.
  final Map<GlobalKey, Element> _globalKeyRegistry = <GlobalKey, Element>{};

  /// Elements deactivated during the current build pass, pending permanent
  /// disposal via [finalizeTree]. Identity-based so equality overrides cannot
  /// corrupt teardown membership.
  final Set<Element> _inactiveElements = HashSet<Element>.identity();

  FrameCallback? _onFrame;
  late final bool _ownsPipelineOwner;
  RenderObjectWithSingleChild? _rootRenderObject;

  /// Controls terminal cursor position and visibility.
  final CursorController cursorController = CursorController();

  /// Routes keyboard and pointer input for this owner.
  final InputManager inputManager;

  /// Manages focus traversal and the primary focus node.
  late final FocusManager focusManager;

  late final PointerRouter _pointerRouter;
  final TickerScheduler _tickerScheduler;
  bool _building = false;
  int _activeRebuilds = 0;

  /// Whether an element rebuild is in flight.
  ///
  /// Includes the first `mount` rebuild, which runs outside [buildScope].
  /// Disposing the owner while this is true leaves that rebuild without a
  /// registered parent.
  @internal
  bool get isBuilding => _building || _activeRebuilds > 0;

  /// Starts one rebuild counted by [isBuilding].
  @internal
  void beginRebuild() => _activeRebuilds++;

  /// Ends the matching [beginRebuild].
  @internal
  void endRebuild() {
    if (_activeRebuilds > 0) _activeRebuilds--;
  }

  bool _disposing = false;
  bool _disposed = false;

  late final PipelineOwner _pipelineOwner;

  /// The render pipeline owner used by framework element adapters.
  @internal
  PipelineOwner get pipelineOwner => _pipelineOwner;

  /// Registers [cb] to run whenever a frame is scheduled.
  void setFrameCallback(FrameCallback cb) {
    _onFrame = cb;
    _tickerScheduler.setFrameCallback(cb);
  }

  /// Attaches [renderer] as the output target for this owner.
  void setRenderer(Renderer renderer) {
    cursorController.attachRenderer(renderer);
  }

  /// Detaches the current renderer and cursor controller.
  void clearRenderer() {
    cursorController.detachRenderer();
  }

  /// The scheduler driving animation ticker callbacks.
  TickerScheduler get tickerScheduler => _tickerScheduler;

  /// Attach the root render object used as the pipeline frame root.
  void attachRootRenderObject(RenderObjectWithSingleChild root) {
    final existing = _rootRenderObject;
    if (existing != null && !identical(existing, root)) {
      throw StateError('BuildOwner already has a root render object');
    }
    (root as RenderObject).attach(pipelineOwner);
    _rootRenderObject = root;
    _pointerRouter.root = root;
  }

  /// Clear the attached root render object without disposing render resources.
  void clearRootRenderObject(RenderObjectWithSingleChild root) {
    if (!identical(_rootRenderObject, root)) {
      return;
    }
    final failures = FirstErrorRecorder();
    try {
      failures.attempt(() => root.setChild(null));
      failures.attempt((root as RenderObject).detach);
    } finally {
      _rootRenderObject = null;
      _pointerRouter.root = null;
    }
    failures.rethrowFirst();
  }

  /// Insert a top-level render child into the attached root render object.
  void insertRootRenderObjectChild(RenderObject child) {
    _rootRenderObject?.setChild(child);
  }

  /// Remove a top-level render child from the attached root render object.
  void removeRootRenderObjectChild(RenderObject child) {
    final root = _rootRenderObject;
    if (root != null && identical(child.parent, root)) {
      root.setChild(null);
    }
  }

  /// Marks element [e] dirty (deduped) and requests a frame.
  @internal
  void scheduleBuild(Element e) {
    if (!e.active) {
      return;
    }
    final depth = _depths[e];
    if (depth == null) {
      throw StateError('Cannot schedule build for an unregistered element');
    }
    if (!_dirtyReservations.containsKey(e)) {
      final generation = ++_dirtyGeneration;
      final ordinal = ++_scheduleOrdinal;
      _dirtyReservations[e] = _DirtyReservation(generation, ordinal);
      _pendingBuckets.insert(_DirtyElement(e, depth, generation, ordinal));
    }
    _onFrame?.call();
  }

  /// Removes [e] from the live dirty reservation without rebuilding it.
  ///
  /// Called by [Element.rebuild] as its first statement, so an element
  /// rebuilt via a direct cascade drops its reservation. Stale bucket entries
  /// then skip by generation mismatch. Framework wiring only.
  @internal
  void clearDirty(Element e) {
    _dirtyReservations.remove(e);
  }

  /// Rebuilds all dirty elements in maintained-depth order under a reentrancy
  /// guard. Performs zero Element parent walks.
  void buildScope() {
    if (_building) {
      throw StateError('BuildOwner.buildScope cannot be re-entered');
    }
    _building = true;
    try {
      while (!_pendingBuckets.isEmpty) {
        final batch = _pendingBuckets;
        _pendingBuckets = _DirtyBuckets();
        for (final dirty in batch.entriesInOrder()) {
          final element = dirty.element;
          final reservation = _dirtyReservations[element];
          if (reservation == null ||
              reservation.generation != dirty.generation) {
            // Stale: cascade rebuild, rebucket, or clearDirty already won.
            continue;
          }
          _dirtyReservations.remove(element);
          if (!element.active) {
            continue;
          }
          element.rebuild();
        }
      }
      finalizeTree();
    } finally {
      _building = false;
    }
  }

  /// Marks every live element dirty so the next [buildScope] re-runs its
  /// `build()`.
  ///
  /// This is hot reload's second step: `reloadSources` swaps method bodies but
  /// leaves the element tree untouched, so nothing re-executes an edited
  /// `build()` until something marks it dirty. No `State` is recreated and no
  /// `initState` re-runs — only `build()` bodies re-execute.
  ///
  /// Deliberate design decision: every registered element is marked, not only
  /// the root. Reconciliation currently has no identical-widget short-circuit,
  /// so marking the root alone would happen to cascade through the whole tree
  /// — but that is a property of reconciliation, not a guarantee this method
  /// should depend on. Marking directly keeps reassemble correct if such a
  /// short-circuit is ever added. [scheduleBuild]'s generation-stamped
  /// reservations still collapse the marks with the parent cascade, so each
  /// element rebuilds exactly once.
  ///
  /// Safe with nothing mounted, after [dispose], and from inside a `build()`:
  /// an in-build call drains in a later batch of the same [buildScope] pass
  /// rather than re-entering it.
  void reassemble() {
    if (_disposed) {
      return;
    }
    // Snapshot first: `scheduleBuild` requests a frame through `_onFrame`, and
    // a host callback may mount elements before this loop finishes.
    for (final element in _depths.keys.toList(growable: false)) {
      scheduleBuild(element);
    }
  }

  void _registerElement(Element element, Element? parent) {
    if (_depths.containsKey(element)) {
      throw StateError('Element is already registered with BuildOwner');
    }
    if (parent != null && !_depths.containsKey(parent)) {
      throw StateError('Parent element is not registered with BuildOwner');
    }
    final depth = parent == null ? 0 : _depths[parent]! + 1;
    updateElementParent(element, parent);
    updateElementDepth(element, depth);
    _depths[element] = depth;
  }

  /// Computes the failure-atomic transition that detaches [element] from its
  /// parent and rebases the detached subtree to depth zero.
  ///
  /// Order: identity-based preflight and complete next-state computation,
  /// followed by one publication pass for parent/depths/dirty rebuckets.
  /// A rejection throws before structural mutation.
  _DeactivatePlan _preflightDeactivate(Element element) {
    if (!_depths.containsKey(element)) {
      throw StateError('Element is not registered with BuildOwner');
    }

    // Identity-based snapshot of the complete subtree.
    final subtree = <Element>[];
    final seen = HashSet<Element>.identity();
    void collect(Element node) {
      if (!seen.add(node)) {
        throw StateError('Element child graph contains a cycle');
      }
      if (!_depths.containsKey(node)) {
        throw StateError('Subtree element is not registered with BuildOwner');
      }
      subtree.add(node);
      node.visitChildren((child) {
        // Edge agreement: child's readable parent must be this node.
        if (!identical(child.parent, node)) {
          throw StateError(
            'Subtree parent edge is inconsistent with visitChildren',
          );
        }
        collect(child);
      });
    }

    collect(element);

    // Depth consistency for every non-root node in the snapshot.
    for (final node in subtree) {
      if (identical(node, element)) continue;
      final readableParent = node.parent;
      if (readableParent == null || !seen.contains(readableParent)) {
        throw StateError(
          'Subtree parent edge is inconsistent with owner registry',
        );
      }
      if (_depths[node] != _depths[readableParent]! + 1) {
        throw StateError('Subtree depth is inconsistent with parent depth');
      }
    }

    final oldRootDepth = _depths[element]!;
    final nextDepths = HashMap<Element, int>.identity();
    final dirtyRebuckets = <_DirtyElement>[];
    // Provisional generations: rejection leaves `_dirtyGeneration` unchanged.
    var provisionalGeneration = _dirtyGeneration;
    for (final node in subtree) {
      final relative = _depths[node]! - oldRootDepth;
      final nextDepth = relative;
      if (nextDepth < 0) {
        throw StateError('Computed next depth is negative');
      }
      nextDepths[node] = nextDepth;
      final reservation = _dirtyReservations[node];
      if (reservation != null) {
        provisionalGeneration++;
        dirtyRebuckets.add(
          _DirtyElement(
            node,
            nextDepth,
            provisionalGeneration,
            reservation.ordinal,
          ),
        );
      }
    }

    return _DeactivatePlan(
      root: element,
      subtree: subtree,
      nextDepths: nextDepths,
      dirtyRebuckets: dirtyRebuckets,
      nextDirtyGeneration: provisionalGeneration,
    );
  }

  void _publishDeactivate(_DeactivatePlan plan) {
    updateElementParent(plan.root, null);
    for (final node in plan.subtree) {
      final nextDepth = plan.nextDepths[node]!;
      updateElementDepth(node, nextDepth);
      _depths[node] = nextDepth;
    }
    for (final entry in plan.dirtyRebuckets) {
      _dirtyReservations[entry.element] = _DirtyReservation(
        entry.generation,
        entry.ordinal,
      );
      _pendingBuckets.insert(entry);
    }
    _dirtyGeneration = plan.nextDirtyGeneration;
  }

  void _unregisterElement(Element element) {
    _depths.remove(element);
    _dirtyReservations.remove(element);
    updateElementParent(element, null);
    updateElementDepth(element, 0);
  }

  /// Binds [key] to [element].
  ///
  /// Throws a descriptive [StateError] if a different element already holds
  /// this key, whether that holder belongs to this owner or another owner and
  /// whether it is active or pending [finalizeTree]. Called by [Element]
  /// during mount/update; not public app API.
  @internal
  void registerGlobalKey(GlobalKey key, Element element) {
    final existing = _globalKeyRegistry[key] ?? key.currentContext?.element;
    if (existing != null && !identical(existing, element)) {
      _throwGlobalKeyPlacementError(key, existing);
    }
    // `GlobalKey.register` repeats the one-live-binding check as a final
    // defense before either lookup surface publishes this element.
    key.register(element);
    _globalKeyRegistry[key] = element;
  }

  /// Removes [element]'s binding for [key], if it is still the current one.
  ///
  /// Called by [Element] during update/unmount; not public app API.
  @internal
  void unregisterGlobalKey(GlobalKey key, Element element) {
    if (identical(_globalKeyRegistry[key], element)) {
      _globalKeyRegistry.remove(key);
      key.unregister(element);
    }
  }

  /// Validates an incoming [GlobalKey] child before its owner mutates an edge.
  ///
  /// The only claimed-key placement accepted is the exact compatible Element
  /// retained by ordinary reconciliation under [intendedParent]. A binding in
  /// another parent, an incompatible same-parent binding, a duplicate, or a
  /// binding owned by another [BuildOwner] is rejected.
  @internal
  void validateGlobalKeyPlacement(
    GlobalKey key,
    Widget candidate,
    Element? intendedParent, {
    Element? retainedElement,
  }) {
    final registered = _globalKeyRegistry[key];
    final keyElement = key.currentContext?.element;
    if (registered != null &&
        keyElement != null &&
        !identical(registered, keyElement)) {
      _throwGlobalKeyPlacementError(key, registered);
    }
    final existing = registered ?? keyElement;
    if (existing == null) {
      return;
    }
    if (retainedElement != null &&
        identical(existing, retainedElement) &&
        identical(existing.parent, intendedParent) &&
        identical(existing.owner, this) &&
        Widget.canUpdate(existing.widget, candidate)) {
      return;
    }
    _throwGlobalKeyPlacementError(key, existing);
  }

  Never _throwGlobalKeyPlacementError(GlobalKey key, Element existing) {
    throw StateError(
      'GlobalKey $key is already bound to '
      '${existing.debugDescribeWidget()}. Cross-parent GlobalKey placement '
      'is unsupported, duplicate placement is not allowed, and one key '
      'cannot bind elements owned by different BuildOwners.',
    );
  }

  /// Detaches [child]'s render object from its external parent, marks its
  /// subtree inactive (see [Element.deactivate]), and holds it pending
  /// permanent disposal via [finalizeTree].
  ///
  /// Called by a parent element when reconciliation removes [child]; not
  /// public app API.
  @internal
  void deactivateChild(Element child) {
    // Sole owner of: preflight → render detach (old Element parent still
    // readable) → Element publication → inactive membership. Callers must
    // not drop render children before this entry point.
    // 1) Preflight without publishing.
    final plan = _preflightDeactivate(child);
    // 2) Detach render while old Element parent is still readable so single-
    //    child setChild(null) / multi-child dropChild / Flex remove all route
    //    through removeRenderObjectChild with a valid Element parent chain.
    final renderElement = Element.findRenderObjectElement(child);
    final renderObject = renderElement?.renderObject;
    final oldRenderParent = renderObject?.parent;
    Object? deferredError;
    StackTrace? deferredStackTrace;
    try {
      renderElement?.detachRenderObject();
    } on Object catch (error, stackTrace) {
      if (oldRenderParent == null ||
          renderObject == null ||
          renderObject.parent != null ||
          oldRenderParent.children.any(
            (candidate) => identical(candidate, renderObject),
          )) {
        rethrow;
      }
      deferredError = error;
      deferredStackTrace = stackTrace;
    }
    // 3) Publish Element parent/depth/dirty only after render detach returns.
    _publishDeactivate(plan);
    // 4) Mark inactive until finalizeTree.
    try {
      child.deactivate();
    } on Object catch (error, stackTrace) {
      deferredError ??= error;
      deferredStackTrace ??= stackTrace;
    }
    _inactiveElements.add(child);
    if (deferredError != null) {
      Error.throwWithStackTrace(deferredError, deferredStackTrace!);
    }
  }

  /// Permanently unmounts every inactive element at the end of a build pass.
  @internal
  void finalizeTree() {
    if (_inactiveElements.isEmpty) {
      return;
    }
    final leftover = _inactiveElements.toList();
    _inactiveElements.clear();
    final failures = FirstErrorRecorder();
    for (final element in leftover) {
      failures.attempt(element.unmount);
    }
    failures.rethrowFirst();
  }

  /// Advances animation tickers for the frame at [timeStamp].
  void handleBeginFrame(Duration timeStamp) {
    _tickerScheduler.handleFrame(timeStamp);
  }

  /// Dispose owned frame pipeline state.
  void dispose() {
    if (_disposed || _disposing) {
      return;
    }
    _disposing = true;
    final failures = FirstErrorRecorder();
    // Unmount anything still pending in the inactive set (deactivated by a
    // reconciliation that ran without a following `buildScope()`, e.g. torn
    // down mid-frame) before the pipeline/render teardown below, so no
    // `State.dispose()` is lost and `Element.unmount()`'s render-object
    // detach still runs against a live `PipelineOwner`. A no-op in the
    // normal case, since `buildScope()` already finalizes every pass.
    final root = _rootRenderObject;
    try {
      failures.attempt(finalizeTree);
      if (root != null) {
        failures.attempt(() => clearRootRenderObject(root));
      }
      if (_ownsPipelineOwner) {
        failures.attempt(pipelineOwner.dispose);
      }
      failures.attempt(_pointerRouter.dispose);
      failures.attempt(focusManager.dispose);
      final globalKeyEntries = _globalKeyRegistry.entries.toList(
        growable: false,
      );
      for (final entry in globalKeyEntries) {
        failures.attempt(() => unregisterGlobalKey(entry.key, entry.value));
      }
    } finally {
      _rootRenderObject = null;
      _pointerRouter.root = null;
      _depths.clear();
      _dirtyReservations.clear();
      _pendingBuckets = _DirtyBuckets();
      _globalKeyRegistry.clear();
      _inactiveElements.clear();
      _tickerScheduler.setFrameCallback(null);
      _onFrame = null;
      _building = false;
      _disposed = true;
      _disposing = false;
    }

    failures.rethrowFirst();
  }

  void _handleNeedVisualUpdate() {
    _onFrame?.call();
  }
}

final class _DeactivatePlan {
  const _DeactivatePlan({
    required this.root,
    required this.subtree,
    required this.nextDepths,
    required this.dirtyRebuckets,
    required this.nextDirtyGeneration,
  });

  final Element root;
  final List<Element> subtree;
  final Map<Element, int> nextDepths;
  final List<_DirtyElement> dirtyRebuckets;
  final int nextDirtyGeneration;
}

final class _DirtyReservation {
  const _DirtyReservation(this.generation, this.ordinal);
  final int generation;
  final int ordinal;
}

final class _DirtyElement {
  const _DirtyElement(this.element, this.depth, this.generation, this.ordinal);
  final Element element;
  final int depth;
  final int generation;
  final int ordinal;
}

final class _DirtyBuckets {
  final SplayTreeMap<int, SplayTreeMap<int, _DirtyElement>> _byDepth =
      SplayTreeMap<int, SplayTreeMap<int, _DirtyElement>>();

  bool get isEmpty => _byDepth.isEmpty;

  void insert(_DirtyElement entry) {
    final atDepth = _byDepth.putIfAbsent(
      entry.depth,
      SplayTreeMap<int, _DirtyElement>.new,
    );
    atDepth[entry.ordinal] = entry;
  }

  Iterable<_DirtyElement> entriesInOrder() sync* {
    for (final depthBucket in _byDepth.values) {
      yield* depthBucket.values;
    }
  }
}

/// Registers [element] under [parent] with maintained depth.
@internal
void registerElementWithBuildOwner(
  BuildOwner owner,
  Element element,
  Element? parent,
) {
  owner._registerElement(element, parent);
}

/// Unregisters [element] depth/dirty state after permanent unmount.
@internal
void unregisterElementFromBuildOwner(BuildOwner owner, Element element) {
  owner._unregisterElement(element);
}
