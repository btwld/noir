import 'dart:io';

import 'package:test/test.dart';

import '../../example/layout_basics.dart';
import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Example Goldens', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester();
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('layout_basics buffer', () async {
      await tester.expectGolden(
        const LayoutBasics(onQuit: _noop),
        'layout_basics',
        updateGoldens: _updateGoldens,
      );
    });
  });
}

void _noop() {}
