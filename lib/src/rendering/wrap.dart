import '../render/geometry.dart';
import 'box.dart';
import 'integer_allocation.dart';

/// Main-axis or run-axis distribution used by [RenderWrap].
enum WrapAlignment {
  /// Place content at the start.
  start,

  /// Place content at the end.
  end,

  /// Center content.
  center,

  /// Divide free cells between items.
  spaceBetween,

  /// Divide free cells around items.
  spaceAround,

  /// Divide free cells before, between, and after items.
  spaceEvenly,
}

/// Cross-axis placement of children within one run.
enum WrapCrossAlignment {
  /// Place children at the run's cross-axis start.
  start,

  /// Place children at the run's cross-axis end.
  end,

  /// Center children within the run's cross-axis extent.
  center,
}

/// A render box that lays children into multiple runs.
final class RenderWrap extends RenderBox {
  /// Creates a wrapping layout.
  RenderWrap({
    Axis direction = Axis.horizontal,
    int spacing = 0,
    int runSpacing = 0,
    WrapAlignment alignment = WrapAlignment.start,
    WrapAlignment runAlignment = WrapAlignment.start,
    WrapCrossAlignment crossAxisAlignment = WrapCrossAlignment.start,
    List<RenderBox>? children,
  }) : _direction = direction,
       _spacing = _validatedGap(spacing, 'spacing'),
       _runSpacing = _validatedGap(runSpacing, 'runSpacing'),
       _alignment = alignment,
       _runAlignment = runAlignment,
       _crossAxisAlignment = crossAxisAlignment {
    if (children != null) {
      for (final child in children) {
        adoptChild(child);
      }
    }
  }

  Axis _direction;
  int _spacing;
  int _runSpacing;
  WrapAlignment _alignment;
  WrapAlignment _runAlignment;
  WrapCrossAlignment _crossAxisAlignment;

  /// Axis along which children are added to a run.
  Axis get direction => _direction;

  /// Updates the run direction.
  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  /// Cells between adjacent children in a run.
  int get spacing => _spacing;

  /// Updates the child spacing.
  set spacing(int value) {
    _validatedGap(value, 'spacing');
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  /// Cells between adjacent runs.
  int get runSpacing => _runSpacing;

  /// Updates the run spacing.
  set runSpacing(int value) {
    _validatedGap(value, 'runSpacing');
    if (_runSpacing == value) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  /// Distribution of children within each run.
  WrapAlignment get alignment => _alignment;

  /// Updates child distribution.
  set alignment(WrapAlignment value) {
    if (_alignment == value) return;
    _alignment = value;
    markNeedsLayout();
  }

  /// Distribution of runs across the cross axis.
  WrapAlignment get runAlignment => _runAlignment;

  /// Updates run distribution.
  set runAlignment(WrapAlignment value) {
    if (_runAlignment == value) return;
    _runAlignment = value;
    markNeedsLayout();
  }

  /// Placement of children within each run's cross extent.
  WrapCrossAlignment get crossAxisAlignment => _crossAxisAlignment;

  /// Updates child cross-axis placement.
  set crossAxisAlignment(WrapCrossAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final horizontal = _direction == Axis.horizontal;
    final maxMain = horizontal ? constraints.maxWidth : constraints.maxHeight;
    final childConstraints = horizontal
        ? BoxConstraints(maxWidth: maxMain, maxHeight: constraints.maxHeight)
        : BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: maxMain);
    final runs = <_WrapRun>[];
    var current = _WrapRun();
    for (final child in children.whereType<RenderBox>()) {
      child.layout(childConstraints);
      final childMain = horizontal ? child.size.width : child.size.height;
      final childCross = horizontal ? child.size.height : child.size.width;
      final nextMain = current.items.isEmpty
          ? childMain
          : current.main + _spacing + childMain;
      if (maxMain != null && current.items.isNotEmpty && nextMain > maxMain) {
        runs.add(current);
        current = _WrapRun();
      }
      if (current.items.isNotEmpty) current.main += _spacing;
      current
        ..items.add(_WrapChild(child, childMain, childCross))
        ..main += childMain;
      if (childCross > current.cross) current.cross = childCross;
    }
    if (current.items.isNotEmpty) runs.add(current);

    final naturalMain = runs.fold<int>(
      0,
      (value, run) => run.main > value ? run.main : value,
    );
    final naturalCross = runs.isEmpty
        ? 0
        : runs.fold<int>(0, (value, run) => value + run.cross) +
              _runSpacing * (runs.length - 1);
    final width = horizontal
        ? constraints.constrainWidth(naturalMain)
        : constraints.constrainWidth(naturalCross);
    final height = horizontal
        ? constraints.constrainHeight(naturalCross)
        : constraints.constrainHeight(naturalMain);
    size = Size(width, height);

    final finalMain = horizontal ? width : height;
    final finalCross = horizontal ? height : width;
    final runCrossSizes = runs.map((run) => run.cross).toList(growable: false);
    final runOffsets = _alignedOffsets(
      finalCross,
      runCrossSizes,
      _runSpacing,
      _runAlignment,
    );
    for (var runIndex = 0; runIndex < runs.length; runIndex++) {
      final run = runs[runIndex];
      final mainOffsets = _alignedOffsets(
        finalMain,
        run.items.map((child) => child.main).toList(growable: false),
        _spacing,
        _alignment,
      );
      for (var index = 0; index < run.items.length; index++) {
        final child = run.items[index];
        final crossSlack = run.cross - child.cross;
        final childCross = switch (_crossAxisAlignment) {
          WrapCrossAlignment.start => 0,
          WrapCrossAlignment.end => crossSlack,
          WrapCrossAlignment.center => allocateExactCells(
            crossSlack,
            const <int>[1, 1],
          )[0],
        };
        final main = mainOffsets[index];
        final cross = runOffsets[runIndex] + childCross;
        positionChild(
          child.box,
          horizontal ? main : cross,
          horizontal ? cross : main,
        );
      }
    }
  }
}

final class _WrapChild {
  const _WrapChild(this.box, this.main, this.cross);
  final RenderBox box;
  final int main;
  final int cross;
}

final class _WrapRun {
  final List<_WrapChild> items = <_WrapChild>[];
  int main = 0;
  int cross = 0;
}

List<int> _alignedOffsets(
  int extent,
  List<int> sizes,
  int spacing,
  WrapAlignment alignment,
) {
  if (sizes.isEmpty) return const <int>[];
  final occupied =
      sizes.fold<int>(0, (sum, size) => sum + size) +
      spacing * (sizes.length - 1);
  final free = (extent - occupied).clamp(0, extent);
  var leading = 0;
  final extraInternal = List<int>.filled(sizes.length - 1, 0);
  switch (alignment) {
    case WrapAlignment.start:
      break;
    case WrapAlignment.end:
      leading = free;
    case WrapAlignment.center:
      leading = allocateExactCells(free, const <int>[1, 1])[0];
    case WrapAlignment.spaceBetween:
      if (sizes.length > 1) {
        extraInternal.setAll(
          0,
          allocateExactCells(free, List<int>.filled(sizes.length - 1, 1)),
        );
      }
    case WrapAlignment.spaceAround:
      if (sizes.length == 1) {
        leading = allocateExactCells(free, const <int>[1, 1])[0];
      } else {
        final slots = allocateExactCells(free, <int>[
          1,
          ...List<int>.filled(sizes.length - 1, 2),
          1,
        ]);
        leading = slots.first;
        extraInternal.setAll(0, slots.sublist(1, sizes.length));
      }
    case WrapAlignment.spaceEvenly:
      final slots = allocateExactCells(
        free,
        List<int>.filled(sizes.length + 1, 1),
      );
      leading = slots.first;
      if (sizes.length > 1) {
        extraInternal.setAll(0, slots.sublist(1, sizes.length));
      }
  }
  final offsets = <int>[];
  var cursor = leading;
  for (var index = 0; index < sizes.length; index++) {
    offsets.add(cursor);
    cursor += sizes[index];
    if (index < sizes.length - 1) {
      cursor += spacing + extraInternal[index];
    }
  }
  return offsets;
}

int _validatedGap(int value, String name) {
  if (value < 0) throw ArgumentError.value(value, name, 'must be non-negative');
  return value;
}
