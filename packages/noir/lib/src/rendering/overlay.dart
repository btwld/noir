import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../foundation/first_error.dart';
import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// Package-owned root overlay: one generic base slot plus ordered entries.
final class RenderOverlay extends RenderBox {
  RenderObject? _base;
  final List<RenderBox> _entries = <RenderBox>[];

  /// Base content, which may be a non-box [RenderObject].
  RenderObject? get base => _base;

  /// Portal entry roots in show order.
  List<RenderBox> get entries => List<RenderBox>.unmodifiable(_entries);

  /// Adopts or replaces the generic base child.
  void setBase(RenderObject? next) {
    if (identical(_base, next)) {
      return;
    }
    final previous = _base;
    if (previous != null && !_isDirectChild(previous)) {
      throw StateError('Overlay base is not hosted by this overlay.');
    }
    if (next != null) {
      _validateAdoption(next);
      try {
        adoptChild(next);
        _moveBaseToFront(next);
      } on Object catch (error, stackTrace) {
        _rollbackAdoption(next);
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    if (previous != null) {
      try {
        dropChild(previous);
      } on Object catch (error, stackTrace) {
        if (_isDirectChild(previous)) {
          if (next != null) {
            _rollbackAdoption(next);
          }
        } else {
          _base = next;
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    _base = next;
  }

  /// Adopts [entry] as the topmost portal entry.
  void adoptEntry(RenderBox entry) {
    final index = _identityEntryIndex(entry);
    if (index >= 0) {
      if (identical(entry.parent, this)) {
        return;
      }
      throw StateError(
        'Overlay entry ${entry.runtimeType} is registered without being '
        'hosted by this overlay.',
      );
    }
    _validateAdoption(entry);
    try {
      adoptChild(entry);
    } on Object catch (error, stackTrace) {
      _rollbackAdoption(entry);
      Error.throwWithStackTrace(error, stackTrace);
    }
    _entries.add(entry);
    markNeedsLayout();
  }

  /// Drops [entry] when it is still this overlay's child.
  void dropEntry(RenderBox entry) {
    final index = _identityEntryIndex(entry);
    if (index < 0) {
      if (entry.parent == null) {
        return;
      }
      throw StateError(
        'Overlay entry ${entry.runtimeType} is parented but not registered by '
        'this overlay.',
      );
    }
    if (!identical(entry.parent, this)) {
      throw StateError(
        'Cannot drop overlay entry ${entry.runtimeType} because its registered '
        'parent is not this overlay.',
      );
    }
    try {
      dropChild(entry);
    } finally {
      final detached =
          entry.parent == null &&
          !children.any((candidate) => identical(candidate, entry));
      if (detached) {
        _entries.removeWhere((candidate) => identical(candidate, entry));
        markNeedsPaint();
      }
    }
  }

  /// Moves an already-shown [entry] to the top of paint and hit-test order.
  void moveEntryToTop(RenderBox entry) {
    final index = _identityEntryIndex(entry);
    if (index < 0 || !identical(entry.parent, this)) {
      throw StateError(
        'Overlay entry ${entry.runtimeType} is not hosted by this overlay.',
      );
    }
    if (index == _entries.length - 1) {
      markNeedsPaint();
      return;
    }
    _entries
      ..removeAt(index)
      ..add(entry);
    final previous = _entries.length > 1
        ? _entries[_entries.length - 2]
        : _base;
    moveChild(entry, after: previous);
    markNeedsPaint();
  }

  /// Target rectangle in root terminal coordinates, failing closed.
  Rect rootRectOf(RenderBox target) {
    final expectedBase = _base;
    if (expectedBase == null) {
      throw StateError('Overlay host has no base content to resolve against.');
    }
    if (target.pipelineOwner != expectedBase.pipelineOwner) {
      throw StateError(
        'Anchor is detached or belongs to another PipelineOwner.',
      );
    }
    var x = 0;
    var y = 0;
    RenderObject? node = target;
    while (node != null && !identical(node, expectedBase)) {
      x += node.x;
      y += node.y;
      node = node.parent;
    }
    if (!identical(node, expectedBase)) {
      throw StateError('Anchor is not below the overlay base content.');
    }
    return Rect.fromLTWH(x, y, target.width, target.height);
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
    final base = _base;
    if (base != null) {
      base.layout(constraints);
      if (base is RenderBox) {
        base
          ..x = 0
          ..y = 0;
      }
    }
    final entryConstraints = BoxConstraints.tight(
      width: size.width,
      height: size.height,
    );
    for (final entry in _entries) {
      entry.layout(entryConstraints);
      entry
        ..x = 0
        ..y = 0;
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    final base = _base;
    if (base != null) {
      context.paintChild(base, origin);
    }
    final clip = Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height);
    for (final entry in _entries) {
      context.canvas.save();
      try {
        context.canvas.clipRect(clip);
        context.paintChild(entry, origin + Offset(entry.x, entry.y));
      } finally {
        context.canvas.restore();
      }
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, Offset position) {
    for (var index = _entries.length - 1; index >= 0; index--) {
      final entry = _entries[index];
      if (entry.hitTest(result, position - Offset(entry.x, entry.y))) {
        return true;
      }
    }
    final base = _base;
    if (base != null) {
      return base.hitTest(result, position - Offset(base.x, base.y));
    }
    return false;
  }

  void _validateAdoption(RenderObject child) {
    if (child.parent != null) {
      throw StateError(
        'Cannot adopt ${child.runtimeType} already parented to '
        '${child.parent.runtimeType}.',
      );
    }
    final childOwner = child.pipelineOwner;
    if (childOwner != null && !identical(childOwner, pipelineOwner)) {
      throw StateError(
        'Cannot adopt a render object owned by another PipelineOwner.',
      );
    }
  }

  bool _isDirectChild(RenderObject child) =>
      identical(child.parent, this) &&
      children.any((candidate) => identical(candidate, child));

  void _rollbackAdoption(RenderObject child) {
    if (!_isDirectChild(child)) {
      return;
    }
    try {
      dropChild(child);
    } on Object {
      // The adoption failure remains primary. A committed drop still leaves
      // the edge detached; a failed preflight leaves it visible to invariants.
    }
  }

  void _moveBaseToFront(RenderObject base) {
    if (!identical(base.parent, this)) {
      return;
    }
    moveChild(base);
  }

  /// Drops residual entries during host teardown. Portal lifecycle remains
  /// the primary owner of shown edges.
  void drainEntries() {
    final failures = FirstErrorRecorder();
    for (final entry in List<RenderBox>.from(_entries)) {
      failures.attempt(() => dropEntry(entry));
    }
    failures.rethrowFirst();
  }

  int _identityEntryIndex(RenderBox entry) {
    var result = -1;
    for (var index = 0; index < _entries.length; index++) {
      if (!identical(_entries[index], entry)) {
        continue;
      }
      if (result != -1) {
        throw StateError('Overlay entry is duplicated in the identity store.');
      }
      result = index;
    }
    return result;
  }
}

/// Full-terminal wrapper for one overlay entry.
final class RenderOverlayEntry extends RenderBox
    with RenderObjectWithSingleChild
    implements HitTestTarget {
  /// Creates an entry that fills the terminal and hosts one child.
  RenderOverlayEntry({
    this.modalBarrier = false,
    this.onOutsidePointer,
    RenderBox? anchor,
    Offset alignmentOffset = Offset.zero,
    EdgeInsets reservedPadding = EdgeInsets.zero,
    Offset? explicitRootPosition,
    Offset? explicitAnchorLocal,
    RenderBox? child,
  }) : _anchor = anchor,
       _alignmentOffset = alignmentOffset,
       _reservedPadding = reservedPadding,
       _explicitRootPosition = explicitRootPosition,
       _explicitAnchorLocal = explicitAnchorLocal {
    if (child != null) {
      setChild(child);
    }
  }

  /// Whether this entry hit-tests itself as a modal pointer barrier.
  bool modalBarrier;

  /// Invoked for pointer events that miss the visible child.
  PointerBarrierHandler? onOutsidePointer;

  RenderBox? _anchor;
  Offset _alignmentOffset;
  EdgeInsets _reservedPadding;
  Offset? _explicitRootPosition;
  Offset? _explicitAnchorLocal;

  /// Anchor whose current-frame geometry drives placement when non-null.
  RenderBox? get anchor => _anchor;
  set anchor(RenderBox? value) {
    if (identical(_anchor, value)) {
      return;
    }
    _anchor = value;
    markNeedsLayout();
  }

  /// Extra offset from the anchor's bottom-start when no explicit point.
  Offset get alignmentOffset => _alignmentOffset;
  set alignmentOffset(Offset value) {
    if (_alignmentOffset == value) {
      return;
    }
    _alignmentOffset = value;
    markNeedsLayout();
  }

  /// Terminal-edge padding used as the safe placement rectangle.
  EdgeInsets get reservedPadding => _reservedPadding;
  set reservedPadding(EdgeInsets value) {
    if (_reservedPadding == value) {
      return;
    }
    _reservedPadding = value;
    markNeedsLayout();
  }

  /// Optional root-space point supplied by `MenuController.open`.
  Offset? get explicitRootPosition => _explicitRootPosition;
  set explicitRootPosition(Offset? value) {
    if (_explicitRootPosition == value) {
      return;
    }
    _explicitRootPosition = value;
    markNeedsLayout();
  }

  /// Optional anchor-local point converted to root space during layout.
  Offset? get explicitAnchorLocal => _explicitAnchorLocal;
  set explicitAnchorLocal(Offset? value) {
    if (_explicitAnchorLocal == value) {
      return;
    }
    _explicitAnchorLocal = value;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
    final child = this.child;
    if (child is! RenderBox) {
      if (child != null) {
        child.layout(constraints);
      }
      return;
    }
    final safe = deflateSafeRect(size, _reservedPadding);
    child.layout(
      BoxConstraints.loose(maxWidth: safe.width, maxHeight: safe.height),
    );
    final origin = _resolveChildOrigin(safe, child.size);
    child
      ..x = origin.dx
      ..y = origin.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = offset + Offset(x, y);
    final child = this.child;
    if (child == null) {
      return;
    }
    context.canvas.save();
    try {
      context.canvas.clipRect(
        Rect.fromLTWH(origin.dx, origin.dy, size.width, size.height),
      );
      final safe = deflateSafeRect(size, _reservedPadding);
      context.canvas.clipRect(
        Rect.fromLTWH(
          origin.dx + safe.left,
          origin.dy + safe.top,
          safe.width,
          safe.height,
        ),
      );
      context.paintChild(child, origin);
    } finally {
      context.canvas.restore();
    }
  }

  @override
  bool hitTestSelf(Offset position) => modalBarrier;

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {
    if (!modalBarrier) {
      return;
    }
    if (_insideChild(entry.localPosition)) {
      return;
    }
    onOutsidePointer?.call(event);
  }

  Offset _resolveChildOrigin(Rect safe, Size menuSize) {
    if (_anchor == null && _explicitRootPosition == null) {
      return Offset(safe.left, safe.top);
    }
    final overlay = parent;
    final anchor = _anchor;
    final anchorRect = overlay is RenderOverlay && anchor != null
        ? overlay.rootRectOf(anchor)
        : Rect.zero;
    final explicitLocal = _explicitAnchorLocal;
    final explicitRoot = explicitLocal == null
        ? _explicitRootPosition
        : Offset(
            anchorRect.left + explicitLocal.dx,
            anchorRect.top + explicitLocal.dy,
          );
    return resolveAnchoredMenuOrigin(
      safeRect: safe,
      anchor: anchorRect,
      menuSize: menuSize,
      alignmentOffset: _alignmentOffset,
      explicitRootPosition: explicitRoot,
    );
  }

  bool _insideChild(Offset local) {
    final child = this.child;
    if (child is! RenderBox) {
      return false;
    }
    final point = local - Offset(child.x, child.y);
    return point.dx >= 0 &&
        point.dy >= 0 &&
        point.dx < child.width &&
        point.dy < child.height;
  }
}

/// Callback for modal overlay-entry pointer events outside the popup.
typedef PointerBarrierHandler = void Function(MouseEvent event);

/// Deflates [terminal] by [padding] without creating negative extents.
@internal
Rect deflateSafeRect(Size terminal, EdgeInsets padding) {
  final width = terminal.width;
  final height = terminal.height;
  final safeLeft = math.min(padding.left, width);
  final safeRight = math.max(safeLeft, width - padding.right);
  final safeTop = math.min(padding.top, height);
  final safeBottom = math.max(safeTop, height - padding.bottom);
  return Rect.fromLTRB(safeLeft, safeTop, safeRight, safeBottom);
}

/// Resolves the integer origin of an anchored menu inside [safeRect].
@internal
Offset resolveAnchoredMenuOrigin({
  required Rect safeRect,
  required Rect anchor,
  required Size menuSize,
  required Offset alignmentOffset,
  Offset? explicitRootPosition,
}) {
  final belowPoint =
      explicitRootPosition ??
      Offset(
        anchor.left + alignmentOffset.dx,
        anchor.bottom + alignmentOffset.dy,
      );
  final abovePoint =
      explicitRootPosition ??
      Offset(anchor.left + alignmentOffset.dx, anchor.top + alignmentOffset.dy);
  final belowTop = belowPoint.dy;
  final aboveTop = abovePoint.dy - menuSize.height;
  final belowFits =
      belowTop >= safeRect.top && belowTop + menuSize.height <= safeRect.bottom;
  final aboveFits =
      aboveTop >= safeRect.top && aboveTop + menuSize.height <= safeRect.bottom;
  var top = belowTop;
  if (!belowFits) {
    if (aboveFits) {
      top = aboveTop;
    } else {
      final belowAvailable = math.max(0, safeRect.bottom - belowPoint.dy);
      final aboveAvailable = math.max(0, abovePoint.dy - safeRect.top);
      top = aboveAvailable > belowAvailable ? aboveTop : belowTop;
    }
  }
  final maxLeft = math.max(safeRect.left, safeRect.right - menuSize.width);
  final maxTop = math.max(safeRect.top, safeRect.bottom - menuSize.height);
  final left = _clampInt(belowPoint.dx, safeRect.left, maxLeft);
  top = _clampInt(top, safeRect.top, maxTop);
  return Offset(left, top);
}

int _clampInt(int value, int min, int max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
