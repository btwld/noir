import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/widget_tester.dart';

void main() {
  group('One-dimension sizing', () {
    late WidgetTester tester;

    setUp(() {
      tester = WidgetTester(maxWidth: 40, maxHeight: 20);
    });

    tearDown(() {
      tester.dispose();
    });

    group('Container', () {
      test('Container(height: 2) should not collapse width', () {
        const widget = Container(height: 2, child: Text('Hi'));

        tester.pumpWidget(widget);

        // Height should be exactly 2, width should be child's natural width (>= 1)
        expect(tester.height, equals(2), reason: 'Height should be exactly 2');
        expect(
          tester.width,
          greaterThanOrEqualTo(1),
          reason: 'Width should not collapse to 0',
        );
      });

      test('Container(width: 10) should not collapse height', () {
        const widget = Container(width: 10, child: Text('Hi'));

        tester.pumpWidget(widget);

        // Width should be exactly 10, height should be child's natural height (>= 1)
        expect(tester.width, equals(10), reason: 'Width should be exactly 10');
        expect(
          tester.height,
          greaterThanOrEqualTo(1),
          reason: 'Height should not collapse to 0',
        );
      });

      test(
        'Container(width: 10) should respect additional constraints maxWidth',
        () {
          const widget = Container(
            width: 10,
            constraints: BoxConstraints(maxWidth: 5, maxHeight: 20),
            child: Text('Hi'),
          );

          tester.pumpWidget(widget);

          expect(
            tester.width,
            equals(5),
            reason: 'Width should be clamped by maxWidth',
          );
          expect(tester.height, greaterThanOrEqualTo(1));
        },
      );

      test('Container(width: 10, height: 5) should set both dimensions', () {
        const widget = Container(width: 10, height: 5, child: Text('Hi'));

        tester.pumpWidget(widget);

        expect(tester.width, equals(10));
        expect(tester.height, equals(5));
      });
    });

    group('SizedBox', () {
      test('SizedBox(height: 2) should not collapse width', () {
        const widget = SizedBox(height: 2, child: Text('Hi'));

        tester.pumpWidget(widget);

        // Height should be exactly 2, width should be child's natural width (>= 1)
        expect(tester.height, equals(2), reason: 'Height should be exactly 2');
        expect(
          tester.width,
          greaterThanOrEqualTo(1),
          reason: 'Width should not collapse to 0',
        );
      });

      test('SizedBox(width: 10) should not collapse height', () {
        const widget = SizedBox(width: 10, child: Text('Hi'));

        tester.pumpWidget(widget);

        // Width should be exactly 10, height should be child's natural height (>= 1)
        expect(tester.width, equals(10), reason: 'Width should be exactly 10');
        expect(
          tester.height,
          greaterThanOrEqualTo(1),
          reason: 'Height should not collapse to 0',
        );
      });

      test('SizedBox(width: 10, height: 5) should set both dimensions', () {
        const widget = SizedBox(width: 10, height: 5, child: Text('Hi'));

        tester.pumpWidget(widget);

        expect(tester.width, equals(10));
        expect(tester.height, equals(5));
      });

      test('SizedBox.shrink() should collapse to 0x0', () {
        const widget = SizedBox.shrink();

        tester.pumpWidget(widget);

        expect(tester.width, equals(0));
        expect(tester.height, equals(0));
      });
    });
  });
}
