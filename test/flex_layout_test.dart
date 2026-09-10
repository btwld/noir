import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart' show RenderObjectElement;
import 'package:test/test.dart';

RenderFlex _mountFlex(Widget widget, {int maxWidth = 100, int maxHeight = 50}) {
  final owner = BuildOwner();
  final element = widget.createElement();
  element.mount(null, owner);

  expect(element, isA<RenderObjectElement>());
  final renderElement = element as RenderObjectElement;
  final renderObject = renderElement.renderObject;
  expect(
    renderObject,
    isA<RenderFlex>(),
    reason: 'Widget under test must produce RenderFlex',
  );

  final constraints = BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  renderObject!.layout(constraints);
  return renderObject as RenderFlex;
}

List<RenderBox> _children(RenderFlex flex) => flex.childrenBoxes;

void main() {
  group('Row layout', () {
    test('public Row allocates an odd width without overrun', () {
      final flex = _mountFlex(
        const Row(
          children: [
            Expanded(child: _FlexExpandingWidget()),
            Expanded(child: _FlexExpandingWidget()),
          ],
        ),
        maxWidth: 5,
        maxHeight: 1,
      );

      final children = _children(flex);
      expect(children.map((child) => child.width), [3, 2]);
      expect(children.map((child) => child.x), [0, 3]);
      expect(flex.width, 5);
    });

    test('public Flex spacing is integer cells with default zero', () {
      const row = Row();
      const spaced = Column(spacing: 2);

      expect(row.spacing, 0);
      expect(spaced.spacing, 2);
      expect(() => Row(spacing: -1), throwsA(isA<AssertionError>()));
    });

    test('lays out children horizontally with default alignment', () {
      final flex = _mountFlex(
        Row(
          children: const [
            SizedBox(width: 20, height: 10),
            SizedBox(width: 30, height: 15),
          ],
        ),
        maxHeight: 40,
      );

      final children = _children(flex);
      expect(children, hasLength(2));
      expect(children[0].x, equals(0));
      expect(children[0].width, equals(20));
      expect(children[1].x, equals(20));
      expect(children[1].width, equals(30));
    });

    test('honours MainAxisAlignment.center', () {
      final flex = _mountFlex(
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            SizedBox(width: 20, height: 10),
            SizedBox(width: 20, height: 10),
          ],
        ),
        maxHeight: 40,
      );

      final children = _children(flex);
      expect(children[0].x, equals(30));
      expect(children[1].x, equals(50));
    });

    test('honours MainAxisAlignment.spaceBetween', () {
      final flex = _mountFlex(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            SizedBox(width: 20, height: 10),
            SizedBox(width: 20, height: 10),
            SizedBox(width: 20, height: 10),
          ],
        ),
        maxWidth: 120,
        maxHeight: 40,
      );

      final children = _children(flex);
      expect(children[0].x, equals(0));
      expect(children[1].x, equals(50));
      expect(children[2].x, equals(100));
    });

    test('CrossAxisAlignment.stretch keeps children sized to row height', () {
      final flex = _mountFlex(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            SizedBox(width: 20, height: 10),
            SizedBox(width: 30, height: 5),
          ],
        ),
        maxHeight: 40,
      );

      final children = _children(flex);
      final rowHeight = flex.size.height;
      expect(children[0].height, equals(rowHeight));
      expect(children[1].height, equals(rowHeight));
    });

    test('Flexible and Expanded distribute extra space', () {
      final flex = _mountFlex(
        Row(
          children: const [
            Expanded(child: _FlexExpandingWidget()),
            Flexible(child: _FlexExpandingWidget(), flex: 2),
          ],
        ),
        maxWidth: 120,
        maxHeight: 20,
      );

      final children = _children(flex);
      expect(children[0].width, equals(40));
      expect(children[1].width, equals(80));
    });
  });

  group('Column layout', () {
    test('public Column uses the same weighted odd-cell allocation', () {
      final flex = _mountFlex(
        const Column(
          children: [
            Expanded(child: _FlexExpandingWidget()),
            Expanded(flex: 2, child: _FlexExpandingWidget()),
            Expanded(flex: 3, child: _FlexExpandingWidget()),
          ],
        ),
        maxWidth: 1,
        maxHeight: 11,
      );

      final children = _children(flex);
      expect(children.map((child) => child.height), [2, 4, 5]);
      expect(children.map((child) => child.y), [0, 2, 6]);
      expect(flex.height, 11);
    });

    test('lays out children vertically by default', () {
      final flex = _mountFlex(
        Column(
          children: const [
            SizedBox(width: 10, height: 15),
            SizedBox(width: 10, height: 20),
          ],
        ),
        maxWidth: 60,
        maxHeight: 100,
      );

      final children = _children(flex);
      expect(children[0].y, equals(0));
      expect(children[1].y, equals(15));
    });

    test('CrossAxisAlignment.stretch keeps children sized to column width', () {
      final flex = _mountFlex(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: const [
            SizedBox(width: 10, height: 10),
            SizedBox(width: 15, height: 10),
          ],
        ),
        maxWidth: 80,
        maxHeight: 60,
      );

      final children = _children(flex);
      final columnWidth = flex.size.width;
      expect(children[0].width, equals(columnWidth));
      expect(children[1].width, equals(columnWidth));
    });

    test('Flexible distributes vertical space', () {
      final flex = _mountFlex(
        Column(
          children: const [
            Flexible(child: _FlexExpandingWidget()),
            Flexible(child: _FlexExpandingWidget(), flex: 3),
          ],
        ),
        maxWidth: 40,
        maxHeight: 80,
      );

      final children = _children(flex);
      expect(children[0].height, equals(20));
      expect(children[1].height, equals(60));
    });
  });
}

class _FlexExpandingWidget extends RenderObjectWidget {
  const _FlexExpandingWidget();

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _FlexExpandingRenderBox();
}

class _FlexExpandingRenderBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
