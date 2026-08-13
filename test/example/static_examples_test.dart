import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/hello.dart' as hello;
import '../../example/inherited_example.dart' as inherited;
import '../../example/layout_demo.dart' as layout_demo;
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('hello renders its message, feature panels, and exit guidance', () {
    final app = createTuiTestApp(const hello.HelloApp());

    try {
      final frame = _render(app);
      expect(frame, BufferMatchers.containsText('Flutter-like widgets'));
      expect(frame, BufferMatchers.containsText('Layout'));
      expect(frame, BufferMatchers.containsText('State'));
      expect(frame, BufferMatchers.containsText('Press Ctrl+C to exit.'));

      final title = frame.findText('Noir').single;
      expect(frame.getForegroundColor(title.x, title.y), Color.yellow);
      expect(frame.getCell(title.x, title.y).isBold, isTrue);
    } finally {
      app.dispose();
    }
  });

  test('inherited theme reaches both text and surface paint', () {
    final app = createTuiTestApp(
      const inherited.ThemedApp(),
      width: 64,
      height: 12,
    );

    try {
      final frame = _render(app);
      expect(frame, BufferMatchers.containsText('Welcome to OpenTUI'));
      expect(
        frame,
        BufferMatchers.containsText('This text uses inherited theme colors'),
      );

      final message = frame.findText('Welcome to OpenTUI').single;
      expect(frame.getForegroundColor(message.x, message.y), Color.white);
      expect(
        frame.getBackgroundColor(message.x, message.y),
        const Color(0.2, 0.4, 0.8),
      );
    } finally {
      app.dispose();
    }
  });

  test('layout showcase renders all major regions in one terminal frame', () {
    final app = createTuiTestApp(
      const layout_demo.FlexLayoutShowcase(onQuit: _noop),
      width: 100,
      height: 40,
    );

    try {
      final frame = _render(app);
      expect(frame, BufferMatchers.containsText('Noir Flex Layout Showcase'));
      expect(frame, BufferMatchers.containsText('Sections'));
      expect(frame, BufferMatchers.containsText('MainAxisAlignment Examples'));
      expect(frame, BufferMatchers.containsText('Flex Layout Demo'));
      expect(frame, BufferMatchers.containsText('Press Ctrl+C to exit'));
    } finally {
      app.dispose();
    }
  });
}

void _noop() {}

CapturedBuffer _render(TuiTestApp app) {
  app.pumpFrame();
  return app.captureFrame();
}
