import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('private ScrollBox viewport extent validates before mutation', () {
    final source = File('lib/src/widgets/scroll_box.dart').readAsStringSync();
    final method = RegExp(
      r'void _updateViewportExtent\(int extent\) \{([\s\S]*?)\n  \}',
    ).firstMatch(source)?.group(1);

    expect(method, isNotNull);
    final guard = method!.indexOf("requireNonNegativeExtent(extent, 'extent')");
    final equality = method.indexOf('if (_viewportExtent == extent)');
    final store = method.indexOf('_viewportExtent = extent');
    expect(guard, greaterThanOrEqualTo(0));
    expect(equality, greaterThan(guard));
    expect(store, greaterThan(equality));
  });
}
