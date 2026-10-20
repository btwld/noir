import 'package:noir/noir.dart';
import 'package:test/test.dart';

import 'helpers/buffer_capture.dart';

void main() {
  test('simple container with text', () async {
    const widget = Container(child: Text('Hello'));

    expect(
      BufferCapture(width: 20, height: 10).capture(widget).toText(),
      contains('Hello'),
    );
  });
}
