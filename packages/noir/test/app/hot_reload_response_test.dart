import 'package:noir/src/app/hot_reload_response.dart';
import 'package:test/test.dart';

void main() {
  test('accepts only an explicit true reassembled result', () {
    expect(hotReloadResponseSucceeded({'reassembled': true}), isTrue);
    expect(hotReloadResponseSucceeded({'reassembled': false}), isFalse);
    expect(hotReloadResponseSucceeded({'reassembled': 'true'}), isFalse);
    expect(hotReloadResponseSucceeded({}), isFalse);
    expect(hotReloadResponseSucceeded(null), isFalse);
  });
}
