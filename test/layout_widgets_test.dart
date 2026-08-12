import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

Element layoutWidget(Widget widget, {int maxWidth = 100, int maxHeight = 100}) {
  final element = widget.createElement();
  final owner = BuildOwner();
  element.mount(null, owner);

  final renderObject = Element.findDescendantRenderObject(element);
  if (renderObject != null) {
    final constraints = BoxConstraints(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
    renderObject.layout(constraints);
  }

  return element;
}

int getElementWidth(Element element) {
  final renderObject = Element.findDescendantRenderObject(element);
  if (renderObject is RenderBox) {
    return renderObject.size.width;
  }
  return 0;
}

int getElementHeight(Element element) {
  final renderObject = Element.findDescendantRenderObject(element);
  if (renderObject is RenderBox) {
    return renderObject.size.height;
  }
  return 0;
}

void main() {
  group('Layout Widgets Tests', () {
    group('Text Widget (RenderObject)', () {
      test('should use RenderParagraph for text rendering', () {
        final textWidget = Text('Hello World', style: const TextStyle());
        final element = layoutWidget(textWidget);

        expect(element is RenderObjectElement, isTrue);
        final renderObject = (element as RenderObjectElement).renderObject;
        expect(renderObject.runtimeType.toString(), equals('RenderParagraph'));
      });

      test('should handle text measurement correctly', () {
        final textWidget = Text('Hello', style: const TextStyle());
        final element = layoutWidget(textWidget);

        // Text width should be character count, height should be 1
        expect(getElementWidth(element), equals(5));
        expect(getElementHeight(element), equals(1));
      });

      test('should support text alignment', () {
        final textWidget = Text(
          'Test',
          style: const TextStyle(),
          textAlign: TextAlign.center,
        );
        final element = layoutWidget(textWidget);

        // Should still work with alignment specified
        expect(getElementWidth(element), equals(4));
        expect(getElementHeight(element), equals(1));
      });
    });

    group('Enhanced Border Features', () {
      test('should support border titles', () {
        final border = Border.all(
          color: Color.white,
          title: 'Test Title',
          titleAlignment: TextAlign.center,
        );

        expect(border.title, equals('Test Title'));
        expect(border.titleAlignment, equals(TextAlign.center));
        expect(border.fill, isFalse);
      });

      test('should support custom border characters', () {
        final customChars = [
          0x2554,
          0x2550,
          0x2557,
          0x2551,
          0x255A,
          0x2550,
          0x255D,
          0x2551,
        ];
        final border = Border.all(color: Color.white, borderChars: customChars);

        expect(border.borderChars, equals(customChars));
      });

      test('should support fill mode', () {
        final border = Border.all(color: Color.red, fill: true);

        expect(border.fill, isTrue);
      });
    });

    group('Container Enhancements', () {
      test('should support basic container layout', () {
        final container = Container(
          child: Text('Centered', style: const TextStyle()),
        );

        final element = layoutWidget(container);
        // Container should layout successfully
        expect(getElementWidth(element), greaterThan(0));
        expect(getElementHeight(element), greaterThan(0));
      });

      test('should support color decoration', () {
        final container = Container(
          color: Color.red,
          child: Text('Red Background', style: const TextStyle()),
        );

        final element = layoutWidget(container);
        // Container with decoration should layout successfully
        expect(getElementWidth(element), greaterThan(0));
        expect(getElementHeight(element), greaterThan(0));
      });
    });
  });

  group('Original Layout Tests', () {
    group('Padding Widget', () {
      test('should work without child', () {
        final paddedWidget = Padding(padding: EdgeInsets.all(3));

        final element = layoutWidget(paddedWidget, maxWidth: 20, maxHeight: 10);

        expect(getElementWidth(element), equals(6));
        expect(getElementHeight(element), equals(6));
        expect(element.children.length, equals(0));
      });
    });

    group('Primitive Widget Architecture', () {
      test('DecoratedBox should work as primitive', () {
        final decoratedBox = DecoratedBox(
          decoration: BoxDecoration(
            color: Color.red,
            border: Border.all(color: Color.white),
          ),
        );

        final element = layoutWidget(decoratedBox, maxWidth: 10, maxHeight: 8);

        expect(
          getElementWidth(element),
          equals(0),
        ); // No child, so minimum size
        expect(getElementHeight(element), equals(0));
      });

      test('ConstrainedBox should work as primitive', () {
        final constrainedBox = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 5,
            minHeight: 3,
            maxWidth: 10,
            maxHeight: 8,
          ),
        );

        final element = layoutWidget(
          constrainedBox,
          maxWidth: 10,
          maxHeight: 8,
        );

        expect(getElementWidth(element), equals(5)); // Min width constraint
        expect(getElementHeight(element), equals(3)); // Min height constraint
      });
    });

    group('BoxConstraints', () {
      test('should constrain values correctly', () {
        final constraints = BoxConstraints(
          minWidth: 5,
          minHeight: 3,
          maxWidth: 20,
          maxHeight: 15,
        );

        expect(constraints.constrainWidth(3), equals(5));
        expect(constraints.constrainWidth(10), equals(10));
        expect(constraints.constrainWidth(25), equals(20));

        expect(constraints.constrainHeight(1), equals(3));
        expect(constraints.constrainHeight(8), equals(8));
        expect(constraints.constrainHeight(20), equals(15));
      });

      test('tight constraints should work', () {
        final constraints = BoxConstraints.tight(width: 10, height: 5);

        expect(constraints.minWidth, equals(10));
        expect(constraints.maxWidth, equals(10));
        expect(constraints.minHeight, equals(5));
        expect(constraints.maxHeight, equals(5));
        expect(constraints.isTight, isTrue);
      });

      test('loose constraints should work', () {
        final constraints = BoxConstraints.loose(maxWidth: 100, maxHeight: 50);

        expect(constraints.minWidth, equals(0));
        expect(constraints.maxWidth, equals(100));
        expect(constraints.minHeight, equals(0));
        expect(constraints.maxHeight, equals(50));
        expect(constraints.isTight, isFalse);
      });
    });
  });
}
