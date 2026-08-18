import '../render/geometry.dart';
import '../widgets/flexible.dart';
import '../widgets/row_column.dart';
import 'box.dart';
import 'object.dart';

/// Data for each child in a flex layout.
class FlexChildData {
  /// Creates flex child data.
  FlexChildData({this.flex, this.fit});

  /// How much of the available main-axis space this child may consume.
  ///
  /// Null and zero both mean that the child is not flexible.
  final int? flex;

  /// How to size the child in its allotted main-axis extent.
  final FlexFit? fit;
}

/// A render object that displays its children in a flex layout.
///
/// [RenderFlex] performs all allocation and positioning in whole terminal
/// cells. Flexible quotas use exact largest-remainder apportionment, so every
/// bounded main-axis cell has one deterministic owner.
class RenderFlex extends RenderBox {
  /// Creates a flex render object.
  RenderFlex({
    required Axis direction,
    MainAxisAlignment mainAxisAlignment = MainAxisAlignment.start,
    MainAxisSize mainAxisSize = MainAxisSize.max,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    int spacing = 0,
    List<RenderBox>? children,
  }) : _direction = direction,
       _mainAxisAlignment = mainAxisAlignment,
       _mainAxisSize = mainAxisSize,
       _crossAxisAlignment = crossAxisAlignment,
       _spacing = _validatedSpacing(spacing) {
    if (children != null) {
      addAll(children);
    }
  }

  final Map<RenderBox, FlexChildData> _childrenData =
      Map<RenderBox, FlexChildData>.identity();

  Axis _direction;
  MainAxisAlignment _mainAxisAlignment;
  MainAxisSize _mainAxisSize;
  CrossAxisAlignment _crossAxisAlignment;
  int _spacing;
  bool _hasOverflow = false;

  /// The direction to use as the main axis.
  Axis get direction => _direction;
  set direction(Axis value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  /// How the children should be placed along the main axis.
  MainAxisAlignment get mainAxisAlignment => _mainAxisAlignment;
  set mainAxisAlignment(MainAxisAlignment value) {
    if (_mainAxisAlignment == value) return;
    _mainAxisAlignment = value;
    markNeedsLayout();
  }

  /// How much space should be occupied in the main axis.
  MainAxisSize get mainAxisSize => _mainAxisSize;
  set mainAxisSize(MainAxisSize value) {
    if (_mainAxisSize == value) return;
    _mainAxisSize = value;
    markNeedsLayout();
  }

  /// How the children should be placed along the cross axis.
  CrossAxisAlignment get crossAxisAlignment => _crossAxisAlignment;
  set crossAxisAlignment(CrossAxisAlignment value) {
    if (_crossAxisAlignment == value) return;
    _crossAxisAlignment = value;
    markNeedsLayout();
  }

  /// The fixed whole-cell gap between adjacent children.
  int get spacing => _spacing;
  set spacing(int value) {
    _validatedSpacing(value);
    if (_spacing == value) return;
    _spacing = value;
    markNeedsLayout();
  }

  /// Adds [child] at the end of the child list with optional flex metadata.
  void add(RenderBox child, {int? flex, FlexFit? fit}) {
    _validateFlex(flex);
    final wasChild = identical(child.parent, this);
    final previous = _childrenData[child];
    final metadataChanged = previous?.flex != flex || previous?.fit != fit;
    if (!wasChild) {
      adoptChild(child);
    }
    _childrenData[child] = FlexChildData(flex: flex, fit: fit);
    if (wasChild && metadataChanged) {
      markNeedsLayout();
    }
  }

  /// Adds every child in document order.
  void addAll(List<RenderBox> children) {
    for (final child in children) {
      add(child);
    }
  }

  /// Removes [child].
  void remove(RenderBox child) {
    final wasOwned =
        identical(child.parent, this) &&
        children.any((candidate) => identical(candidate, child));
    try {
      dropChild(child);
    } finally {
      if (wasOwned &&
          child.parent == null &&
          !children.any((candidate) => identical(candidate, child))) {
        _childrenData.remove(child);
      }
    }
  }

  /// The render children in document order.
  List<RenderBox> get childrenBoxes => children.cast<RenderBox>();

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final boxes = childrenBoxes;
    final metadata = <FlexChildData>[];
    final positiveFlexIndexes = <int>[];
    for (var index = 0; index < boxes.length; index++) {
      // Stored metadata was validated by [add]; absent metadata is inert.
      final data = _childrenData[boxes[index]] ?? FlexChildData();
      metadata.add(data);
      if ((data.flex ?? 0) > 0) {
        positiveFlexIndexes.add(index);
      }
    }

    final gapCount = boxes.isEmpty ? 0 : boxes.length - 1;
    // [_spacing] is validated at both assignment sites.
    final fixedGapCells = BigInt.from(_spacing) * BigInt.from(gapCount);
    _checkedExtent(fixedGapCells, 'fixed flex gaps');

    final maxMain = _direction == Axis.horizontal
        ? constraints.maxWidth
        : constraints.maxHeight;
    final maxCross = _direction == Axis.horizontal
        ? constraints.maxHeight
        : constraints.maxWidth;
    final minCross = _direction == Axis.horizontal
        ? constraints.minHeight
        : constraints.minWidth;

    final hasPositiveFlex = positiveFlexIndexes.isNotEmpty;
    final unboundedMain = maxMain == null;
    if (unboundedMain && hasPositiveFlex) {
      final allLoose = positiveFlexIndexes.every(
        (index) => metadata[index].fit != FlexFit.tight,
      );
      if (_mainAxisSize != MainAxisSize.min || !allLoose) {
        throw StateError(_unboundedFlexMessage());
      }
    }

    final childMainSizes = List<int>.filled(boxes.length, 0);
    final childCrossSizes = List<int>.filled(boxes.length, 0);
    var measuredMain = BigInt.zero;
    var measuredMaxCross = 0;

    BoxConstraints naturalConstraints() => _direction == Axis.horizontal
        ? BoxConstraints(maxHeight: maxCross)
        : BoxConstraints(maxWidth: maxCross);

    void recordSize(int index) {
      final child = boxes[index];
      final childMain = _direction == Axis.horizontal
          ? child.size.width
          : child.size.height;
      final childCross = _direction == Axis.horizontal
          ? child.size.height
          : child.size.width;
      childMainSizes[index] = childMain;
      childCrossSizes[index] = childCross;
      measuredMain += BigInt.from(childMain);
      if (childCross > measuredMaxCross) {
        measuredMaxCross = childCross;
      }
    }

    if (unboundedMain) {
      final childConstraints = naturalConstraints();
      for (var index = 0; index < boxes.length; index++) {
        boxes[index].layout(childConstraints);
        recordSize(index);
      }
    } else {
      final childConstraints = naturalConstraints();
      for (var index = 0; index < boxes.length; index++) {
        if ((metadata[index].flex ?? 0) <= 0) {
          boxes[index].layout(childConstraints);
          recordSize(index);
        }
      }

      final measuredWithGaps = measuredMain + fixedGapCells;
      _checkedExtent(measuredWithGaps, 'measured non-flex extent and gaps');
      var available = BigInt.from(maxMain) - measuredWithGaps;
      if (available.isNegative) {
        available = BigInt.zero;
      }
      if (available > BigInt.from(maxMain)) {
        throw _arithmeticError('available flex extent');
      }
      final total = available.toInt();
      final weights = positiveFlexIndexes
          .map((index) => metadata[index].flex!)
          .toList(growable: false);
      final quotas = weights.isEmpty
          ? const <int>[]
          : _allocateExactCells(total, weights);

      for (
        var quotaIndex = 0;
        quotaIndex < positiveFlexIndexes.length;
        quotaIndex++
      ) {
        final childIndex = positiveFlexIndexes[quotaIndex];
        final childData = metadata[childIndex];
        final quota = quotas[quotaIndex];
        final tight = childData.fit == FlexFit.tight;
        final childConstraints = _direction == Axis.horizontal
            ? BoxConstraints(
                minWidth: tight ? quota : 0,
                maxWidth: quota,
                maxHeight: maxCross,
              )
            : BoxConstraints(
                maxWidth: maxCross,
                minHeight: tight ? quota : 0,
                maxHeight: quota,
              );
        boxes[childIndex].layout(childConstraints);
        recordSize(childIndex);
      }
    }

    final occupiedMain = measuredMain + fixedGapCells;
    final occupiedMainInt = _checkedExtent(
      occupiedMain,
      'occupied flex extent',
    );
    final idealMain = maxMain != null && _mainAxisSize == MainAxisSize.max
        ? maxMain
        : occupiedMainInt;
    final finalMain = _direction == Axis.horizontal
        ? constraints.constrainWidth(idealMain)
        : constraints.constrainHeight(idealMain);
    final idealCross = measuredMaxCross < minCross
        ? minCross
        : measuredMaxCross;
    final finalCross = _direction == Axis.horizontal
        ? constraints.constrainHeight(idealCross)
        : constraints.constrainWidth(idealCross);

    final positions = _computePositions(
      childMainSizes: childMainSizes,
      childCrossSizes: childCrossSizes,
      finalMain: finalMain,
      finalCross: finalCross,
      occupiedMain: occupiedMain,
    );

    size = _direction == Axis.horizontal
        ? Size(finalMain, finalCross)
        : Size(finalCross, finalMain);

    if (_crossAxisAlignment == CrossAxisAlignment.stretch) {
      for (var index = 0; index < boxes.length; index++) {
        _stretchChild(boxes[index], finalCross);
      }
    }
    for (var index = 0; index < boxes.length; index++) {
      final position = positions[index];
      if (_direction == Axis.horizontal) {
        positionChild(boxes[index], position.main, position.cross);
      } else {
        positionChild(boxes[index], position.cross, position.main);
      }
    }

    // Children keep their natural size when the box is too small (Flutter's
    // flex behavior), so a child can end past this box's own edge. Record
    // that here; [paint] clips exactly when it happened, keeping the common
    // fits-fine path free of clip bookkeeping.
    var hasOverflow = false;
    for (final child in boxes) {
      if (child.x + child.size.width > size.width ||
          child.y + child.size.height > size.height) {
        hasOverflow = true;
        break;
      }
    }
    _hasOverflow = hasOverflow;
  }

  /// Paints children, clipped to this box's bounds when layout overflowed.
  ///
  /// Without the clip an overflowing child paints into whatever region the
  /// parent assigned to a following sibling — rows interleave and content
  /// escapes its box. Clipping only on recorded overflow mirrors Flutter's
  /// `RenderFlex` and leaves the ordinary fitting layout untouched.
  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_hasOverflow) {
      super.paint(context, offset);
      return;
    }
    context.canvas.save();
    try {
      context.canvas.clipRect(
        Rect.fromLTWH(offset.dx + x, offset.dy + y, size.width, size.height),
      );
      super.paint(context, offset);
    } finally {
      context.canvas.restore();
    }
  }

  List<_ChildPosition> _computePositions({
    required List<int> childMainSizes,
    required List<int> childCrossSizes,
    required int finalMain,
    required int finalCross,
    required BigInt occupiedMain,
  }) {
    final childCount = childMainSizes.length;
    if (childCount == 0) return const <_ChildPosition>[];

    var freeMain = BigInt.from(finalMain) - occupiedMain;
    if (freeMain.isNegative) {
      freeMain = BigInt.zero;
    }
    final free = _checkedBoundedExtent(
      freeMain,
      finalMain,
      'main-axis alignment space',
    );
    var leading = 0;
    final extraInternal = List<int>.filled(childCount - 1, 0);

    switch (_mainAxisAlignment) {
      case MainAxisAlignment.start:
        break;
      case MainAxisAlignment.end:
        leading = free;
      case MainAxisAlignment.center:
        leading = _allocateExactCells(free, const [1, 1])[0];
      case MainAxisAlignment.spaceBetween:
        if (childCount > 1) {
          extraInternal.setAll(
            0,
            _allocateExactCells(free, List<int>.filled(childCount - 1, 1)),
          );
        }
      case MainAxisAlignment.spaceAround:
        if (childCount == 1) {
          leading = _allocateExactCells(free, const [1, 1])[0];
        } else {
          final weights = <int>[1, ...List<int>.filled(childCount - 1, 2), 1];
          final slots = _allocateExactCells(free, weights);
          leading = slots.first;
          extraInternal.setAll(0, slots.sublist(1, childCount));
        }
      case MainAxisAlignment.spaceEvenly:
        final slots = _allocateExactCells(
          free,
          List<int>.filled(childCount + 1, 1),
        );
        leading = slots.first;
        if (childCount > 1) {
          extraInternal.setAll(0, slots.sublist(1, childCount));
        }
    }

    final mainPositions = <int>[];
    var nextMain = BigInt.from(leading);
    for (var index = 0; index < childCount; index++) {
      mainPositions.add(_checkedPosition(nextMain, 'child main position'));
      if (index < childCount - 1) {
        nextMain =
            nextMain +
            BigInt.from(childMainSizes[index]) +
            BigInt.from(_spacing) +
            BigInt.from(extraInternal[index]);
      }
    }

    return List<_ChildPosition>.generate(childCount, (index) {
      var crossSlack = finalCross - childCrossSizes[index];
      if (crossSlack < 0) crossSlack = 0;
      final cross = switch (_crossAxisAlignment) {
        CrossAxisAlignment.start || CrossAxisAlignment.stretch => 0,
        CrossAxisAlignment.end => crossSlack,
        CrossAxisAlignment.center => _allocateExactCells(crossSlack, const [
          1,
          1,
        ])[0],
      };
      return _ChildPosition(mainPositions[index], cross);
    }, growable: false);
  }

  void _stretchChild(RenderBox child, int crossAxisSize) {
    final currentCrossAxisSize = _direction == Axis.horizontal
        ? child.size.height
        : child.size.width;
    if (currentCrossAxisSize == crossAxisSize) return;
    final constraints = _direction == Axis.horizontal
        ? BoxConstraints.tight(width: child.size.width, height: crossAxisSize)
        : BoxConstraints.tight(width: crossAxisSize, height: child.size.height);
    child.layout(constraints);
  }

  String _unboundedFlexMessage() {
    final axis = _direction == Axis.horizontal ? 'width' : 'height';
    return 'RenderFlex children have non-zero flex but $axis constraints are '
        'unbounded. Use MainAxisSize.min with FlexFit.loose children, avoid '
        'Expanded, or provide a finite main-axis constraint.';
  }
}

final class _ChildPosition {
  const _ChildPosition(this.main, this.cross);

  final int main;
  final int cross;
}

int _validatedSpacing(int value) {
  if (value < 0) {
    throw ArgumentError.value(value, 'spacing', 'must be non-negative');
  }
  return value;
}

void _validateFlex(int? value) {
  if (value != null && value < 0) {
    throw ArgumentError.value(value, 'flex', 'must be null or non-negative');
  }
}

List<int> _allocateExactCells(int total, List<int> weights) {
  if (total < 0) {
    throw ArgumentError.value(total, 'total', 'must be non-negative');
  }
  if (weights.isEmpty) {
    if (total == 0) return const <int>[];
    throw ArgumentError.value(weights, 'weights', 'must not be empty');
  }
  if (weights.any((weight) => weight <= 0)) {
    throw ArgumentError.value(weights, 'weights', 'must all be positive');
  }

  final bigTotal = BigInt.from(total);
  var weightSum = BigInt.zero;
  final bigWeights = <BigInt>[];
  for (final weight in weights) {
    final bigWeight = BigInt.from(weight);
    bigWeights.add(bigWeight);
    weightSum += bigWeight;
  }

  var baseSum = BigInt.zero;
  final quotas = <BigInt>[];
  final ranked = <_Residue>[];
  for (var index = 0; index < bigWeights.length; index++) {
    final numerator = bigTotal * bigWeights[index];
    final base = numerator ~/ weightSum;
    quotas.add(base);
    baseSum += base;
    ranked.add(_Residue(index, numerator % weightSum));
  }
  final left = bigTotal - baseSum;
  if (left.isNegative || left >= BigInt.from(weights.length)) {
    throw _arithmeticError('largest-remainder cell count');
  }
  ranked.sort((a, b) {
    final residueOrder = b.value.compareTo(a.value);
    return residueOrder != 0 ? residueOrder : a.index.compareTo(b.index);
  });
  final leftCount = left.toInt();
  for (var index = 0; index < leftCount; index++) {
    quotas[ranked[index].index] += BigInt.one;
  }

  return quotas
      .map((quota) {
        if (quota.isNegative || quota > bigTotal) {
          throw _arithmeticError('allocated flex quota');
        }
        return quota.toInt();
      })
      .toList(growable: false);
}

final class _Residue {
  const _Residue(this.index, this.value);

  final int index;
  final BigInt value;
}

final BigInt _maxNativeInt = (BigInt.one << 63) - BigInt.one;
final BigInt _minNativeInt = -(BigInt.one << 63);

int _checkedExtent(BigInt value, String quantity) {
  if (value.isNegative || value > _maxNativeInt) {
    throw _arithmeticError(quantity);
  }
  return value.toInt();
}

int _checkedBoundedExtent(BigInt value, int maximum, String quantity) {
  if (value.isNegative || value > BigInt.from(maximum)) {
    throw _arithmeticError(quantity);
  }
  return value.toInt();
}

int _checkedPosition(BigInt value, String quantity) {
  if (value < _minNativeInt || value > _maxNativeInt) {
    throw _arithmeticError(quantity);
  }
  return value.toInt();
}

StateError _arithmeticError(String quantity) => StateError(
  'RenderFlex $quantity exceeds the supported terminal-cell integer range.',
);
