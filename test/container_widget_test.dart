import 'package:noir/noir.dart';
import 'package:test/test.dart';

import 'helpers/buffer_capture.dart';

void main() {
  void expectCapturedTextContains(Widget widget, String expected) {
    expect(
      BufferCapture(width: 20, height: 10).capture(widget).toText(),
      contains(expected),
    );
  }

  test('simple container with text', () async {
    const widget = Container(child: Text('Hello'));

    expectCapturedTextContains(widget, 'Hello');
  });

  test('container with alignment', () async {
    const widget = Container(
      alignment: Alignment.center,
      child: Text('Centered'),
    );

    expectCapturedTextContains(widget, 'Centered');
  });

  test('direct align widget', () async {
    const widget = Align(child: Text('Aligned'));

    expectCapturedTextContains(widget, 'Aligned');
  });

  test('text widget alone', () async {
    const widget = Text('Hello');

    expectCapturedTextContains(widget, 'Hello');
  });
}
