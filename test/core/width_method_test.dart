import 'package:noir/noir_low_level.dart' show WidthMethod;
import 'package:test/test.dart';

void main() {
  test('WidthMethod exactly matches the two native modes', () {
    expect(
      WidthMethod.values.map((method) => (method.name, method.value)).toList(),
      equals(<(String, int)>[('wcwidth', 0), ('unicode', 1)]),
    );
  });
}
