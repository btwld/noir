import 'dart:collection';

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../painting/tui_canvas.dart';
import '../render/geometry.dart';

/// Terminal geometry available during a render-tree paint walk.
@immutable
final class TerminalCellMetrics {
  /// Creates cell metrics for a terminal viewport.
  const TerminalCellMetrics({
    required this.columns,
    required this.rows,
    this.pixelWidth,
    this.pixelHeight,
  });

  /// Terminal viewport width in cells.
  final int columns;

  /// Terminal viewport height in cells.
  final int rows;

  /// Measured terminal viewport width in pixels, when positive and available.
  final int? pixelWidth;

  /// Measured terminal viewport height in pixels, when positive and available.
  final int? pixelHeight;

  /// Measured pixels per cell column, when resolution is usable.
  double? get pixelsPerCellX {
    final width = pixelWidth;
    if (width == null || width <= 0 || columns <= 0) return null;
    return width / columns;
  }

  /// Measured pixels per cell row, when resolution is usable.
  double? get pixelsPerCellY {
    final height = pixelHeight;
    if (height == null || height <= 0 || rows <= 0) return null;
    return height / rows;
  }

  /// Nominal terminal cell width-to-height ratio used without measurement.
  double get nominalCellAspectRatio => 0.5;

  @override
  bool operator ==(Object other) =>
      other is TerminalCellMetrics &&
      other.columns == columns &&
      other.rows == rows &&
      other.pixelWidth == pixelWidth &&
      other.pixelHeight == pixelHeight;

  @override
  int get hashCode => Object.hash(columns, rows, pixelWidth, pixelHeight);
}

/// Callback invoked when the render pipeline needs another visual update.
typedef PipelineVisualUpdateCallback = void Function();

/// Result of a render-tree hit test.
final class HitTestResult {
  /// Hit-test path from topmost leaf target toward its ancestors.
  final List<HitTestEntry> path = <HitTestEntry>[];

  final Set<RenderObject> _visitedRenderObjects = Set<RenderObject>.identity();

  /// Render objects whose bounds were visited for the queried point.
  ///
  /// A caller that needs only the winning branch must compare these objects
  /// with [path], because a pointer-transparent sibling can also be visited.
  @internal
  Iterable<RenderObject> get visitedRenderObjects => _visitedRenderObjects;

  /// Records that [renderObject] contains the queried point.
  @internal
  void recordVisit(RenderObject renderObject) {
    _visitedRenderObjects.add(renderObject);
  }

  /// Add [entry] to the path.
  void add(HitTestEntry entry) {
    path.add(entry);
  }
}

/// A target and target-local position produced by hit testing.
final class HitTestEntry {
  /// Creates a hit-test path entry.
  const HitTestEntry(this.target, this.localPosition);

  /// Target that should receive a pointer event.
  final HitTestTarget target;

  /// Position in [target]'s local coordinate space.
  final Offset localPosition;
}

/// Render object contract for pointer-event targets.
abstract interface class HitTestTarget {
  /// Handle [event] at this target using the resolved hit-test [entry].
  void handleEvent(MouseEvent event, HitTestEntry entry);
}

/// Context passed through the render-tree paint walk.
final class PaintingContext {
  /// Creates a painting context backed by [canvas].
  const PaintingContext(
    this.canvas, {
    this.cellMetrics = const TerminalCellMetrics(columns: 0, rows: 0),
  });

  /// Canvas that records paint commands for the current frame.
  final TuiCanvas canvas;

  /// Terminal cell and optional physical-pixel metrics for this frame.
  final TerminalCellMetrics cellMetrics;

  /// Paint [child] at [offset].
  void paintChild(RenderObject child, Offset offset) {
    child.paint(this, offset);
  }
}

/// Owns render-object layout and paint invalidation for the current tree.
final class PipelineOwner {
  /// Creates a pipeline owner.
  PipelineOwner({PipelineVisualUpdateCallback? onNeedVisualUpdate})
    : _onNeedVisualUpdate = onNeedVisualUpdate;

  final PipelineVisualUpdateCallback? _onNeedVisualUpdate;
  final Set<RenderObject> _nodesNeedingLayout = Set<RenderObject>.identity();

  /// Nodes that requested layout while [flushLayout] was running a pass and
  /// that no later layout in that pass satisfied. Every pass lays the whole
  /// tree out and starts this empty, so what remains when a pass ends is what
  /// that pass raised and did not answer, and the flush owes another pass.
  final Set<RenderObject> _relayoutRequests = Set<RenderObject>.identity();
  bool _flushingLayout = false;
  final Set<RenderObject> _nodesNeedingPaint = Set<RenderObject>.identity();
  Constraints? _lastRootConstraints;
  bool _disposed = false;

  /// Whether any attached render object is waiting for layout.
  bool get debugNeedsLayout => _nodesNeedingLayout.isNotEmpty;

  /// Whether any attached render object is waiting for paint.
  bool get debugNeedsPaint => _nodesNeedingPaint.isNotEmpty;

  /// Schedule [node] for layout and paint.
  void scheduleLayout(RenderObject node) {
    if (!identical(node._pipelineOwner, this)) {
      throw StateError(
        'Cannot schedule layout for a detached render object or one owned by '
        'another PipelineOwner.',
      );
    }
    if (_disposed) {
      return;
    }
    node
      .._needsLayout = true
      .._needsPaint = true;
    if (_flushingLayout) {
      _relayoutRequests.add(node);
    }
    final changed =
        _nodesNeedingLayout.add(node) | _nodesNeedingPaint.add(node);
    if (changed) {
      _onNeedVisualUpdate?.call();
    }
  }

  /// Schedule [node] for paint.
  void schedulePaint(RenderObject node) {
    if (!identical(node._pipelineOwner, this)) {
      throw StateError(
        'Cannot schedule paint for a detached render object or one owned by '
        'another PipelineOwner.',
      );
    }
    if (_disposed) {
      return;
    }
    node._needsPaint = true;
    if (_nodesNeedingPaint.add(node)) {
      _onNeedVisualUpdate?.call();
    }
  }

  /// Flush the layout queue, laying [root] out under [constraints] until no
  /// layout request is outstanding.
  ///
  /// A request raised during a pass, for example by a `LayoutBuilder` whose
  /// build touches a render object already laid out or still performing
  /// layout, is answered by another full pass in the same flush. A request
  /// followed by that object's layout in the same pass needs no retry.
  /// A request still outstanding after [maxLayoutPasses] throws, rather than
  /// looping or dropping it silently.
  void flushLayout(RenderObject root, Constraints constraints) {
    if (_disposed) {
      return;
    }
    final constraintsChanged = _lastRootConstraints != constraints;
    if (_nodesNeedingLayout.isEmpty && !constraintsChanged) {
      return;
    }

    var passes = 0;
    _flushingLayout = true;
    try {
      do {
        _relayoutRequests.clear();
        root.layout(constraints);
        passes += 1;
      } while (_relayoutRequests.isNotEmpty && passes < maxLayoutPasses);
    } finally {
      _flushingLayout = false;
    }
    root._clearLayoutDirtySubtree();
    _nodesNeedingLayout.clear();
    _lastRootConstraints = constraints;

    root._needsPaint = true;
    _nodesNeedingPaint.add(root);

    if (_relayoutRequests.isNotEmpty) {
      final offenders = _relayoutRequests
          .map((node) => node.runtimeType.toString())
          .join(', ');
      _relayoutRequests.clear();
      throw StateError(
        'Layout did not settle after $maxLayoutPasses passes. These render '
        'objects kept requesting layout during layout: $offenders.',
      );
    }
  }

  /// Passes one [flushLayout] may run before it reports a layout that never
  /// settles.
  ///
  /// A tree still dirty after this many is being invalidated from inside its
  /// own layout on every pass.
  static const int maxLayoutPasses = 3;

  /// Flush the paint queue by delegating root painting to [paintRoot].
  bool flushPaint(
    RenderObject root,
    void Function(RenderObject root) paintRoot,
  ) {
    if (_disposed || _nodesNeedingPaint.isEmpty) {
      return false;
    }

    paintRoot(root);
    root._clearPaintDirtySubtree();
    _nodesNeedingPaint.clear();
    return true;
  }

  /// Dispose this pipeline owner and clear pending work.
  void dispose() {
    _disposed = true;
    _nodesNeedingLayout.clear();
    _relayoutRequests.clear();
    _nodesNeedingPaint.clear();
    _lastRootConstraints = null;
  }

  void _forget(RenderObject node) {
    _nodesNeedingLayout.remove(node);
    _relayoutRequests.remove(node);
    _nodesNeedingPaint.remove(node);
  }
}

/// Base class for objects in the render tree.
///
/// RenderObjects know how to layout themselves and record paint commands.
abstract class RenderObject {
  RenderObject? _parent;

  /// Parent RenderObject in the tree.
  RenderObject? get parent => _parent;

  final List<RenderObject> _children = <RenderObject>[];

  /// Live read-only view of direct children in traversal order.
  late final List<RenderObject> children = UnmodifiableListView<RenderObject>(
    _children,
  );

  PipelineOwner? _pipelineOwner;
  bool _needsLayout = false;
  bool _needsPaint = false;

  /// Horizontal position in terminal cells, relative to the parent.
  int x = 0;

  /// Vertical position in terminal cells, relative to the parent.
  int y = 0;

  /// Width in terminal cells, assigned during layout.
  int width = 0;

  /// Height in terminal cells, assigned during layout.
  int height = 0;

  /// The pipeline owner this render object is attached to, if any.
  @internal
  PipelineOwner? get pipelineOwner => _pipelineOwner;

  /// Whether this render object is waiting for layout.
  bool get debugNeedsLayout => _needsLayout;

  /// Whether this render object is waiting for paint.
  bool get debugNeedsPaint => _needsPaint;

  /// Layout protocol: given constraints, compute size and position.
  ///
  /// Subclasses implement [performLayout]; parents must invoke [layout],
  /// which runs it and then clears the needs-layout flag.
  void performLayout(Constraints constraints);

  /// Entry point for layout.
  ///
  /// Settling the owner's mid-pass request here is what lets
  /// [PipelineOwner.flushLayout] tell a satisfied request from one to retry.
  void layout(Constraints constraints) {
    _pipelineOwner?._relayoutRequests.remove(this);
    performLayout(constraints);
    _needsLayout = false;
  }

  /// Paint protocol: record drawing commands at [offset].
  void paint(PaintingContext context, Offset offset);

  /// Hit-test this render object using [position] in local coordinates.
  bool hitTest(HitTestResult result, Offset position) {
    final snapshot = _children.toList(growable: false);
    for (final child in snapshot.reversed) {
      if (child.hitTest(result, position - Offset(child.x, child.y))) {
        return true;
      }
    }
    return false;
  }

  /// Add a child to this render object
  void adoptChild(RenderObject child) {
    _adoptChild(child);
  }

  void _adoptChild(RenderObject child, {bool invalidateParent = true}) {
    if (child._parent != null) {
      throw StateError(
        'Child ${child.runtimeType} already has parent '
        '${child._parent.runtimeType}.',
      );
    }
    if (_children.any((candidate) => identical(candidate, child))) {
      throw StateError(
        'Child ${child.runtimeType} is already present in '
        '$runtimeType children.',
      );
    }
    final owner = _pipelineOwner;
    final attachment = _inspectSubtree(child, owner);
    if (owner == null && attachment.state != _SubtreeState.detached) {
      throw StateError(
        'A detached render object cannot adopt an attached child.',
      );
    }

    child._parent = this;
    _children.add(child);
    if (owner != null && attachment.state == _SubtreeState.detached) {
      _attachInspectedSubtree(attachment.nodes, owner);
    }
    if (invalidateParent) {
      markNeedsLayout();
    }
  }

  /// Remove a child from this render object
  void dropChild(RenderObject child) {
    _dropChild(child);
  }

  void _dropChild(RenderObject child, {bool invalidateParent = true}) {
    final childIndex = _identityChildIndex(child);
    if (!identical(child._parent, this) || childIndex < 0) {
      throw StateError(
        'Child ${child.runtimeType} is not exactly one live child of '
        '$runtimeType.',
      );
    }
    final owner = _pipelineOwner;
    final attachment = _inspectSubtree(child, owner);
    if (owner == null && attachment.state != _SubtreeState.detached) {
      throw StateError(
        'A detached render object cannot retain an attached child.',
      );
    }
    if (owner != null && attachment.state != _SubtreeState.attached) {
      throw StateError(
        'An attached render object cannot retain a detached child.',
      );
    }

    child._parent = null;
    _children.removeAt(childIndex);
    if (owner != null) {
      child.detach();
    }
    if (invalidateParent) {
      markNeedsLayout();
    }
  }

  /// Move an existing direct [child] after another direct child.
  ///
  /// Passing null for [after] moves [child] to the start. This changes only
  /// sibling order: the child remains attached to this parent and its current
  /// [PipelineOwner].
  @internal
  @protected
  void moveChild(RenderObject child, {RenderObject? after}) {
    final childIndex = _identityChildIndex(child);
    if (childIndex < 0 || !identical(child._parent, this)) {
      throw StateError(
        'Child ${child.runtimeType} is not exactly one live child of '
        '$runtimeType.',
      );
    }
    if (identical(child, after)) {
      throw StateError('A render child cannot be moved after itself.');
    }

    var afterIndex = -1;
    if (after != null) {
      afterIndex = _identityChildIndex(after);
      if (afterIndex < 0 || !identical(after._parent, this)) {
        throw StateError(
          'Move anchor ${after.runtimeType} is not exactly one live child of '
          '$runtimeType.',
        );
      }
    }

    final alreadyPlaced =
        (after == null && childIndex == 0) ||
        (after != null &&
            childIndex > 0 &&
            identical(_children[childIndex - 1], after));
    if (alreadyPlaced) {
      return;
    }

    _children.removeAt(childIndex);
    final adjustedAfterIndex = childIndex < afterIndex
        ? afterIndex - 1
        : afterIndex;
    _children.insert(adjustedAfterIndex + 1, child);
    markNeedsLayout();
  }

  int _identityChildIndex(RenderObject child) {
    var result = -1;
    for (var index = 0; index < _children.length; index++) {
      if (!identical(_children[index], child)) {
        continue;
      }
      if (result != -1) {
        throw StateError(
          'Child ${child.runtimeType} is duplicated in '
          '$runtimeType children.',
        );
      }
      result = index;
    }
    return result;
  }

  /// Visit all children with a callback
  void visitChildren(void Function(RenderObject child) visitor) {
    for (final child in _children) {
      visitor(child);
    }
  }

  /// Attach this render object and its existing children to [owner].
  @internal
  void attach(PipelineOwner owner) {
    final attachment = _inspectSubtree(this, owner);
    if (attachment.state == _SubtreeState.attached) {
      return;
    }
    _attachInspectedSubtree(attachment.nodes, owner);
  }

  /// Called after this render object has committed attachment to [owner].
  ///
  /// Package-owned lifecycle seam for render objects that subscribe to
  /// owner-correlated resources. External low-level subclasses must not rely
  /// on this internal hook.
  @internal
  @protected
  void didAttach(PipelineOwner owner) {}

  /// Mark this render object as needing layout and paint.
  void markNeedsLayout() {
    final owner = _pipelineOwner;
    if (owner == null) {
      _needsLayout = true;
      _needsPaint = true;
      return;
    }
    owner.scheduleLayout(this);
  }

  /// Mark this render object as needing paint.
  void markNeedsPaint() {
    final owner = _pipelineOwner;
    if (owner == null) {
      _needsPaint = true;
      return;
    }
    owner.schedulePaint(this);
  }

  void _clearLayoutDirtySubtree() {
    _needsLayout = false;
    visitChildren((child) {
      child._clearLayoutDirtySubtree();
    });
  }

  void _clearPaintDirtySubtree() {
    _needsPaint = false;
    visitChildren((child) {
      child._clearPaintDirtySubtree();
    });
  }

  /// Called when the render object is detached from the render tree.
  ///
  /// Subclasses can override to release resources or unregister handlers.
  void detach() {
    final formerOwner = _pipelineOwner;
    final attachment = _inspectSubtree(this, formerOwner);
    if (attachment.state == _SubtreeState.detached) {
      return;
    }
    if (formerOwner == null) {
      throw StateError('Attached subtree has no root PipelineOwner.');
    }

    final childSnapshot = <RenderObject>[];
    visitChildren(childSnapshot.add);
    formerOwner._forget(this);
    _pipelineOwner = null;
    for (final child in childSnapshot) {
      if (identical(child._pipelineOwner, formerOwner)) {
        child.detach();
      } else if (child._pipelineOwner != null) {
        throw StateError(
          'Render subtree changed owner while it was being detached.',
        );
      }
    }
  }
}

enum _SubtreeState { detached, attached }

final class _InspectedSubtree {
  const _InspectedSubtree(this.nodes, this.state);

  final List<RenderObject> nodes;
  final _SubtreeState state;
}

_InspectedSubtree _inspectSubtree(
  RenderObject root,
  PipelineOwner? requestedOwner,
) {
  final nodes = <RenderObject>[];
  final visited = Set<RenderObject>.identity();

  void visit(RenderObject node) {
    if (!visited.add(node)) {
      throw StateError('Render subtree contains a cycle or duplicate edge.');
    }
    nodes.add(node);
    final childSnapshot = <RenderObject>[];
    node.visitChildren(childSnapshot.add);
    for (final child in childSnapshot) {
      if (!identical(child._parent, node)) {
        throw StateError(
          'Render child ${child.runtimeType} has an inconsistent parent.',
        );
      }
      visit(child);
    }
  }

  visit(root);
  var detached = 0;
  var attached = 0;
  for (final node in nodes) {
    final owner = node._pipelineOwner;
    if (owner == null) {
      detached++;
    } else if (requestedOwner != null && identical(owner, requestedOwner)) {
      attached++;
    } else {
      throw StateError('Render subtree is owned by a different PipelineOwner.');
    }
  }
  if (detached != 0 && attached != 0) {
    throw StateError('Render subtree is only partially attached.');
  }
  return _InspectedSubtree(
    List<RenderObject>.unmodifiable(nodes),
    attached == 0 ? _SubtreeState.detached : _SubtreeState.attached,
  );
}

void _attachInspectedSubtree(List<RenderObject> nodes, PipelineOwner owner) {
  for (final node in nodes) {
    node._pipelineOwner = owner;
  }

  Object? firstError;
  StackTrace? firstStackTrace;
  void attempt(void Function() action) {
    try {
      action();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  for (final node in nodes) {
    attempt(() => owner.scheduleLayout(node));
    attempt(() => node.didAttach(owner));
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStackTrace!);
  }
}

RenderObject? _singleRenderObjectChild(RenderObject owner) {
  if (owner._children.length > 1) {
    throw StateError(
      'A single-child render object has more than one direct child.',
    );
  }
  if (owner._children.isEmpty) {
    return null;
  }
  final child = owner._children.single;
  if (!identical(child._parent, owner)) {
    throw StateError('The single-child edge has an inconsistent parent.');
  }
  return child;
}

/// Validates and replaces one authoritative single-child render edge.
///
/// Package-internal framework wiring. Entry-state errors reject before
/// mutation. Once mutation starts, the generic render edge is the only child
/// state; scheduling errors are rethrown after parent invalidation is
/// attempted against the committed edge.
@internal
void setSingleRenderObjectChild(
  RenderObjectWithSingleChild owner,
  RenderObject? next,
) {
  final ownerObject = owner as RenderObject;
  final ownerChildren = List<RenderObject>.from(ownerObject._children);
  final current = _singleRenderObjectChild(ownerObject);

  if (current != null) {
    final attachment = _inspectSubtree(current, ownerObject._pipelineOwner);
    if (ownerObject._pipelineOwner == null &&
        attachment.state != _SubtreeState.detached) {
      throw StateError('A detached single-child owner has an attached child.');
    }
    if (ownerObject._pipelineOwner != null &&
        attachment.state != _SubtreeState.attached) {
      throw StateError('An attached single-child owner has a detached child.');
    }
  }

  if (identical(current, next)) {
    return;
  }

  if (next != null) {
    if (next._parent != null ||
        ownerChildren.any((child) => identical(child, next))) {
      throw StateError(
        'The proposed single child already has an incompatible render edge.',
      );
    }
    final attachment = _inspectSubtree(next, ownerObject._pipelineOwner);
    if (ownerObject._pipelineOwner == null &&
        attachment.state != _SubtreeState.detached) {
      throw StateError(
        'A detached single-child owner cannot install an attached subtree.',
      );
    }
  }

  Object? firstError;
  StackTrace? firstStackTrace;
  void attempt(void Function() action) {
    try {
      action();
    } catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }

  if (current != null) {
    attempt(() => ownerObject._dropChild(current, invalidateParent: false));
  }
  if (firstError == null && next != null) {
    attempt(() => ownerObject._adoptChild(next, invalidateParent: false));
  }
  attempt(ownerObject.markNeedsLayout);
  if (firstError != null) {
    Error.throwWithStackTrace(firstError!, firstStackTrace!);
  }
}

/// Mixin for render objects that own a single render child.
///
/// The generic render edge is the sole child state. This boundary enforces
/// zero-or-one cardinality for direct adoption, removal, traversal, and
/// replacement.
mixin RenderObjectWithSingleChild on RenderObject {
  /// The single direct render child, or `null` when there is none.
  RenderObject? get child => _singleRenderObjectChild(this);

  /// Replace this object's single render child.
  ///
  /// Reassigning the current child is a no-op.
  void setChild(RenderObject? child) {
    setSingleRenderObjectChild(this, child);
  }

  @override
  void adoptChild(RenderObject child) {
    final current = _singleRenderObjectChild(this);
    if (current != null && !identical(current, child)) {
      throw StateError(
        '$runtimeType already has a different single render child.',
      );
    }
    setChild(child);
  }

  @override
  void dropChild(RenderObject child) {
    if (!identical(_singleRenderObjectChild(this), child)) {
      throw StateError(
        'Child ${child.runtimeType} is not the single render child of '
        '$runtimeType.',
      );
    }
    setChild(null);
  }
}
