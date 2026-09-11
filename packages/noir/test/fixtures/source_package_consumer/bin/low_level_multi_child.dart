import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

/// A supported multi-child custom render widget. It uses the generic retained
/// render-child protocol and never names or subclasses Element.
final class ConsumerMultiWidget extends MultiChildRenderObjectWidget {
  const ConsumerMultiWidget({super.children, super.key});

  @override
  ConsumerMultiBox createRenderObject(BuildContext context) =>
      ConsumerMultiBox();

  @override
  void updateRenderObject(
    BuildContext context,
    ConsumerMultiBox renderObject,
  ) {}
}

/// Compiles the framework-owned adapter with an explicit two-child value.
const Widget consumerTwoChildValue = ConsumerMultiWidget(
  children: <Widget>[
    SizedBox(width: 1, height: 1),
    SizedBox(width: 2, height: 1),
  ],
);

final class ConsumerMultiBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    var width = constraints.minWidth;
    var height = constraints.minHeight;
    var x = 0;
    for (final child in children.whereType<RenderBox>()) {
      child.layout(
        BoxConstraints.loose(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
        ),
      );
      positionChild(child, x, 0);
      x += child.size.width;
      width = constraints.constrainWidth(x);
      height = constraints.constrainHeight(
        child.size.height > height ? child.size.height : height,
      );
    }
    size = Size(width, height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawText('multi', offset, Color.white);
    visitChildren((child) {
      if (child is RenderBox) {
        context.paintChild(child, offset + Offset(child.x, child.y));
      }
    });
  }
}

/// Keeps the promoted low-level contracts nameable under the companion import.
void typeCheckPromotedContracts({
  required TextLayoutEngine textLayout,
  required TickerScheduler ticker,
}) {
  final Object values = (textLayout, ticker);
  values.toString();
}
