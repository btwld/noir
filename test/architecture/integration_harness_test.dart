import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('createTuiTestApp keeps integration input on the parser path', () {
    final helperSource = File(
      'test/helpers/tui_test_app.dart',
    ).readAsStringSync();
    final inputSource = File('test/helpers/mock_input.dart').readAsStringSync();
    final mouseSource = File('test/helpers/mock_mouse.dart').readAsStringSync();
    final combined = '$helperSource\n$inputSource\n$mouseSource';

    expect(combined, contains('StdinInputDriver'));
    expect(combined, contains('debugFeedBytes'));
    expect(combined, isNot(contains('dispatchKey(')));
    expect(combined, isNot(contains('dispatchMouse(')));
    expect(combined, isNot(contains('dispatchPaste(')));
  });

  test(
    'test-only binding injection is not exported from the public barrel',
    () {
      final publicBarrel = File('lib/noir.dart').readAsStringSync();

      expect(publicBarrel, isNot(contains('runTuiAppForTesting')));
    },
  );
}
