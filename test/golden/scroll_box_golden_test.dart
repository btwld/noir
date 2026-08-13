import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

Column _longColumn(int n) =>
    Column(children: List<Widget>.generate(n, (i) => Text('Item ${i + 1}')));

void main() {
  group('ScrollBox Golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester(width: 16, height: 6);
    });

    tearDownAll(() {
      tester.dispose();
    });

    test(
      'content shorter than viewport (no scroll, no scrollbar fill)',
      () async {
        final widget = SizedBox(
          width: 14,
          height: 4,
          child: ScrollBox(showScrollbar: false, child: _longColumn(3)),
        );
        await tester.expectGolden(
          widget,
          'scroll_box_short_no_scrollbar',
          updateGoldens: _updateGoldens,
        );
      },
    );

    test('content overflow shows clipped child and scrollbar gutter', () async {
      final widget = SizedBox(
        width: 14,
        height: 4,
        child: ScrollBox(child: _longColumn(10)),
      );
      await tester.expectGolden(
        widget,
        'scroll_box_overflow_at_top',
        updateGoldens: _updateGoldens,
      );
    });

    test('scrolled to mid offset shows correct content', () async {
      final controller = ScrollController(initialOffset: 3);
      final widget = SizedBox(
        width: 14,
        height: 4,
        child: ScrollBox(controller: controller, child: _longColumn(10)),
      );
      await tester.expectGolden(
        widget,
        'scroll_box_scrolled_mid',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
