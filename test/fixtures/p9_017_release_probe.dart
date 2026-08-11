import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/flex.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/widgets/flexible.dart';

void main() {
  _expectArgumentError(
    'constructor-spacing',
    () => RenderFlex(direction: Axis.horizontal, spacing: -1),
  );

  final spacingFlex = RenderFlex(direction: Axis.horizontal, spacing: 1);
  _attachAndFlush(spacingFlex);
  _expectArgumentError('setter-spacing', () => spacingFlex.spacing = -1);
  _requireClean('setter-spacing', spacingFlex);
  if (spacingFlex.spacing != 1) {
    throw StateError('setter-spacing replaced the retained value');
  }

  final addFlex = RenderFlex(direction: Axis.horizontal);
  final child = _ProbeBox();
  _expectArgumentError('add-flex', () => addFlex.add(child, flex: -1));
  if (child.parent != null || addFlex.childrenBoxes.isNotEmpty) {
    throw StateError('add-flex mutated adoption or child order');
  }

  final metadataFlex = RenderFlex(direction: Axis.horizontal);
  final metadataChild = _ProbeBox();
  metadataFlex.add(metadataChild, flex: 1, fit: FlexFit.tight);
  _attachAndFlush(metadataFlex);
  _expectArgumentError(
    'metadata-flex',
    () => metadataFlex.add(metadataChild, flex: -1),
  );
  _requireClean('metadata-flex', metadataFlex);
  metadataFlex.layout(const BoxConstraints.tight(width: 5, height: 1));
  if (metadataChild.width != 5) {
    throw StateError('metadata-flex replaced retained metadata');
  }

  final unboundedChild = _ProbeBox();
  final unbounded = RenderFlex(direction: Axis.horizontal)
    ..add(unboundedChild, flex: 1, fit: FlexFit.tight);
  _expectStateError(
    'unbounded-flex',
    () => unbounded.layout(const BoxConstraints(maxHeight: 1)),
  );
  if (unboundedChild.layoutCount != 0) {
    throw StateError('unbounded-flex laid out a child before rejection');
  }
}

void _attachAndFlush(RenderFlex flex) {
  final owner = PipelineOwner();
  flex.attach(owner);
  owner
    ..flushLayout(flex, const BoxConstraints.tight(width: 4, height: 1))
    ..flushPaint(flex, (_) {});
}

void _expectArgumentError(String label, void Function() action) {
  Object? error;
  try {
    action();
  } catch (caught) {
    error = caught;
  }
  if (error is! ArgumentError) {
    throw StateError('$label did not throw ArgumentError: $error');
  }
  print('PASS:$label');
}

void _expectStateError(String label, void Function() action) {
  Object? error;
  try {
    action();
  } catch (caught) {
    error = caught;
  }
  if (error is! StateError) {
    throw StateError('$label did not throw StateError: $error');
  }
  print('PASS:$label');
}

void _requireClean(String label, RenderFlex flex) {
  final owner = flex.pipelineOwner;
  if (owner == null ||
      flex.debugNeedsLayout ||
      flex.debugNeedsPaint ||
      owner.debugNeedsLayout ||
      owner.debugNeedsPaint) {
    throw StateError('$label scheduled work');
  }
}

final class _ProbeBox extends RenderBox {
  int layoutCount = 0;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    layoutCount++;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
