import 'dart:collection';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import '../foundation/listenable.dart';
import '../rendering/object.dart';
import 'build_context.dart';
import 'element.dart';
import 'key.dart';

part '../widgets/inherited.dart';

/// Immutable description of part of the user interface.
abstract class Widget {
  /// Creates a widget with an optional [key].
  const Widget({this.key});

  /// Controls how this widget replaces another of the same type.
  final Key? key;

  /// Inflates this widget into a concrete [Element].
  @internal
  Element createElement();

  /// Whether [oldWidget]'s element can be updated to [newWidget].
  ///
  /// True when both share the same runtime type and key.
  static bool canUpdate(Widget oldWidget, Widget newWidget) =>
      oldWidget.runtimeType == newWidget.runtimeType &&
      oldWidget.key == newWidget.key;
}

/// A widget that describes its UI by building other widgets.
abstract class StatelessWidget extends Widget {
  /// Creates a stateless widget with an optional [key].
  const StatelessWidget({super.key});

  /// Describes the part of the UI represented by this widget.
  Widget build(BuildContext context);

  @override
  @internal
  Element createElement() => StatelessElement(this);
}

/// A widget that has mutable state managed by a [State] object.
abstract class StatefulWidget extends Widget {
  /// Creates a stateful widget with an optional [key].
  const StatefulWidget({super.key});

  /// Creates the mutable [State] for this widget.
  State<StatefulWidget> createState();

  @override
  @internal
  Element createElement() => StatefulElement(this);
}

/// Mutable state for a [StatefulWidget].
abstract class State<T extends StatefulWidget> {
  /// The current widget configuration this state is bound to.
  T get widget => _widget!;
  T? _widget;
  bool _mounted = false;
  bool _disposing = false;

  /// Whether this state is currently attached to the tree.
  bool get mounted => _mounted;

  /// The [BuildContext] this state was attached with.
  BuildContext get context => _context!;
  BuildContext? _context;

  void Function()? _requestRebuild;

  /// Cleanups registered since the last successful reconciliation.
  Queue<VoidCallback> _pendingDeferredDisposals = Queue<VoidCallback>();

  /// Retired batches queued with [BuildOwner], newest last.
  final Queue<DeferredDisposalBatch> _retiredDeferredDisposals =
      Queue<DeferredDisposalBatch>();

  /// The queue a running drain appends to, so nested registrations join it.
  Queue<VoidCallback>? _deferredDrainTarget;

  /// Nesting depth of the reconciliation currently running for this state.
  int _reconcileDepth = 0;

  /// Called when this object is inserted into the tree.
  ///
  /// Override this to perform initialization that depends on the location at
  /// which this object was inserted into the tree.
  @mustCallSuper
  void initState() {}

  /// Called when a dependency of this [State] object changes.
  @mustCallSuper
  void didChangeDependencies() {}

  /// Called whenever the widget configuration changes.
  @mustCallSuper
  void didUpdateWidget(covariant T oldWidget) {}

  /// Called when this object is removed from the tree.
  ///
  /// This is called before [dispose]. Unlike [dispose], this method is called
  /// whenever the element is removed from the tree, even if it might be
  /// reinserted later.
  ///
  /// If an override throws, framework-owned subtree deactivation still
  /// completes before the original error is rethrown, and permanent teardown
  /// remains scheduled for finalization. The hook is not retried for the same
  /// removal.
  @mustCallSuper
  void deactivate() {}

  /// Called when a hot reload has swapped this app's code.
  ///
  /// Hot reload replaces method bodies in the live isolate and then re-runs
  /// `build()`; it never recreates a [State] or re-runs [initState]. Override
  /// this to re-derive whatever [initState] computed from code that may have
  /// just changed — a parsed table, a precomputed layout, a cached format —
  /// so a reloaded body is not left reading values the old body produced.
  ///
  /// Never called in a release build. The tree is rebuilt whether or not this
  /// throws, so a failure here degrades the reload rather than aborting it.
  @mustCallSuper
  void reassemble() {}

  /// Called when this object is removed from the tree permanently.
  ///
  /// Override this to clean up any resources held by this object (cancel
  /// timers, close streams, etc).
  ///
  /// [mounted] and [context] stay readable for the whole call, but [setState]
  /// is already rejected: teardown has begun and no rebuild can follow.
  @mustCallSuper
  void dispose() {}

  /// Applies [fn] and schedules a rebuild.
  ///
  /// Throws a [StateError] — in every build mode, not just debug — once
  /// teardown has begun: from the moment [dispose] starts running (where
  /// [mounted] is still true) and forever after [detach] clears the
  /// State/Element association. This is almost always a timer, stream
  /// subscription, or callback that outlived the [State]; cancel it in
  /// [dispose] instead. [fn] is never invoked and no rebuild is requested
  /// when this throws.
  void setState(VoidCallback fn) {
    // Checked before _disposing: _disposing is never reset, so once detach()
    // clears _mounted this branch owns every later call and the message can
    // say the teardown already finished.
    if (!_mounted) {
      throw StateError(
        'setState() called after dispose(): $runtimeType is no longer '
        'mounted. This usually means a timer, stream subscription, or '
        'callback outlived the State and fired after dispose() ran; cancel '
        'it in dispose() instead.',
      );
    }
    if (_disposing) {
      throw StateError(
        'setState() called during dispose(): $runtimeType is tearing down '
        'and cannot rebuild. This usually means a listener, timer, or '
        'stream subscription fired while dispose() released it; cancel or '
        'detach it before it can call back.',
      );
    }
    fn();
    final cb = _requestRebuild;
    if (cb != null) cb();
  }

  /// Releases a retired resource after its previous consumers finish cleanup.
  ///
  /// Use this when this state replaces a resource that the descendants built
  /// by the previous configuration may still read — a controller, a signal, a
  /// subscription source. Disposing it inline would tear it down while the old
  /// children are still mounted; [deferDispose] holds [cleanup] until the
  /// replacement is safe.
  ///
  /// [cleanup] becomes eligible once this state successfully updates its
  /// descendants and the inactive descendants finish unmounting; the framework
  /// then runs it from [BuildOwner.finalizeTree]. A failed [initState],
  /// [didUpdateWidget], or [build] keeps the resource alive until a later
  /// reconciliation succeeds or the element unmounts. Descendant batches run
  /// before ancestor batches, and registration order is preserved inside one
  /// host.
  ///
  /// Timing at the edges: a call from inside [dispose] runs [cleanup]
  /// synchronously, a call while no reconciliation is running schedules the
  /// rebuild that retires it, and a cleanup registered while this host is
  /// draining joins the drain already in flight. Calling this after the
  /// State/Element association is severed throws a [StateError]; release the
  /// resource directly there instead.
  ///
  /// Every eligible cleanup is attempted even after one of them throws, and
  /// the first failure is rethrown once the drain completes.
  void deferDispose(VoidCallback cleanup) {
    // Ordered like setState(): _disposing is never reset, so the unmounted
    // branch must own every call that arrives after detach().
    if (!_mounted) {
      throw StateError(
        'deferDispose() called after dispose(): $runtimeType is no longer '
        'mounted. Nothing can retire the resource now; release it directly '
        'at the call site instead.',
      );
    }
    if (_disposing) {
      cleanup();
      return;
    }
    final drain = _deferredDrainTarget;
    if (drain != null) {
      drain.add(cleanup);
      return;
    }
    _pendingDeferredDisposals.add(cleanup);
    if (_reconcileDepth == 0) {
      // Retirement only happens at the end of a successful reconciliation, so
      // an idle registration has to ask for the build that retires it.
      final cb = _requestRebuild;
      if (cb != null) cb();
    }
  }

  /// Describes the part of the UI represented by this state.
  Widget build(BuildContext context);

  // Internal wiring from Element. Framework-internal: called only by
  // StatefulElement, never by application code.

  /// Opens a reconciliation window for this state, so [deferDispose] holds
  /// registrations instead of requesting another rebuild. Called only by
  /// [StatefulElement]; not public app API.
  @internal
  void beginReconcile() {
    _reconcileDepth++;
  }

  /// Closes the window opened by [beginReconcile] and, when the outermost one
  /// [succeeded], retires this state's pending cleanups to [BuildOwner].
  /// Called only by [StatefulElement]; not public app API.
  @internal
  void endReconcile({required bool succeeded}) {
    _reconcileDepth--;
    if (_reconcileDepth > 0 || !succeeded) {
      return;
    }
    if (_pendingDeferredDisposals.isEmpty) {
      return;
    }
    final batch = DeferredDisposalBatch._(this, _pendingDeferredDisposals);
    _pendingDeferredDisposals = Queue<VoidCallback>();
    _retiredDeferredDisposals.add(batch);
    _context!.owner.enqueueDeferredDisposal(batch);
  }

  /// Releases this state's retired and still-pending cleanups, oldest first.
  ///
  /// Called only by [StatefulElement.unmount], after the descendants unmount
  /// and before [dispose] releases this state's current resources; not public
  /// app API.
  @internal
  void flushDeferredDisposals() {
    final failures = FirstErrorRecorder();
    while (_retiredDeferredDisposals.isNotEmpty) {
      final batch = _retiredDeferredDisposals.removeFirst();
      failures.attempt(batch.drain);
    }
    if (_pendingDeferredDisposals.isNotEmpty) {
      final pending = _pendingDeferredDisposals;
      _pendingDeferredDisposals = Queue<VoidCallback>();
      failures.attempt(() => _drainDeferred(pending));
    }
    failures.rethrowFirst();
  }

  void _drainDeferred(Queue<VoidCallback> callbacks) {
    final previous = _deferredDrainTarget;
    _deferredDrainTarget = callbacks;
    final failures = FirstErrorRecorder();
    try {
      // Removing before invoking keeps a throwing cleanup from being retried
      // and lets a nested registration join this same loop.
      while (callbacks.isNotEmpty) {
        failures.attempt(callbacks.removeFirst());
      }
    } finally {
      _deferredDrainTarget = previous;
      callbacks.clear();
    }
    failures.rethrowFirst();
  }

  /// Binds this state to its widget, context, and rebuild callback. Called
  /// only by [StatefulElement.mount]; not public app API.
  @internal
  void attach(T widget, BuildContext context, void Function() requestRebuild) {
    _widget = widget;
    _context = context;
    _requestRebuild = requestRebuild;
    _mounted = true;
  }

  /// Rebinds this state to [newWidget], invoking [didUpdateWidget]. Called
  /// only by [StatefulElement.update]; not public app API.
  @internal
  void updateWidget(T newWidget) {
    final old = _widget!;
    _widget = newWidget;
    didUpdateWidget(old);
  }

  /// Runs [dispose] with the teardown guard engaged, so a [setState] reached
  /// from inside a disposing subscription is rejected instead of scheduling a
  /// rebuild the element will never serve. Called only by
  /// [StatefulElement.unmount]; not public app API.
  @internal
  void disposeState() {
    _disposing = true;
    dispose();
  }

  /// Detaches this state from the tree, marking it unmounted. Called only
  /// by [StatefulElement.unmount], after [dispose] has already run; not
  /// public app API.
  @internal
  void detach() {
    _mounted = false;
    _requestRebuild = null;
    _context = null;
  }
}

/// One host's retired [State.deferDispose] cleanups, waiting for release.
///
/// [BuildOwner] queues these in reconciliation order — descendants before
/// ancestors — and drains them from [BuildOwner.finalizeTree]. A batch drains
/// once: [StatefulElement.unmount] may reach it first, and the queued entry is
/// then a no-op.
@internal
final class DeferredDisposalBatch {
  DeferredDisposalBatch._(this._state, this._callbacks);

  final State<StatefulWidget> _state;
  final Queue<VoidCallback> _callbacks;
  bool _drained = false;

  /// Runs this batch's cleanups once, oldest first.
  void drain() {
    if (_drained) {
      return;
    }
    _drained = true;
    _state._retiredDeferredDisposals.remove(this);
    _state._drainDeferred(_callbacks);
  }
}

/// A widget that proxies its configuration to a single child.
///
/// Used as the base for [InheritedWidget] and other single-child wrapper
/// widgets that typically modify inherited context without introducing their
/// own layout behaviour.
abstract class ProxyWidget extends Widget {
  /// Initializes a one-child wrapper that adds no render object of its own.
  const ProxyWidget({required this.child, super.key});

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  @internal
  Element createElement() => ProxyElement(this);
}

/// Base class for widgets that manage RenderObjects
///
/// RenderObjectWidget creates and configures RenderObjects that handle
/// layout and painting. This follows the Flutter pattern of Widget → Element → RenderObject.
abstract class RenderObjectWidget extends Widget {
  /// Initializes a widget whose element creates and configures a [RenderObject].
  const RenderObjectWidget({super.key});

  /// Create the RenderObject for this widget
  ///
  /// Called when the element is first mounted.
  RenderObject createRenderObject(BuildContext context);

  /// Update the RenderObject with new configuration
  ///
  /// Called when the widget is updated with new properties.
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    // Default implementation does nothing
  }

  /// Creates the framework-owned element adapter for this widget.
  @override
  @internal
  Element createElement() => RenderObjectElement(this);
}

/// A [RenderObjectWidget] whose render object adopts at most one [child].
abstract class SingleChildRenderObjectWidget extends RenderObjectWidget {
  /// Initializes a render-object widget with an optional single [child].
  const SingleChildRenderObjectWidget({super.key, this.child});

  /// Optional widget attached through this render object's single-child edge.
  final Widget? child;

  @override
  @internal
  SingleChildRenderObjectElement createElement() =>
      SingleChildRenderObjectElement(this);
}
