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

  test(
    'inherited theme repaints dependents when t changes the theme',
    () async {
      final app = createTuiTestApp(
        const inherited.ThemedApp(),
        width: 64,
        height: 12,
      );

      try {
        await _settleAutofocus(app);
        var frame = _render(app);
        expect(frame, BufferMatchers.containsText('Theme: ocean'));
        expect(frame, BufferMatchers.containsText('Welcome to Noir'));
        final oceanMessage = frame.findText('Welcome to Noir').single;
        final oceanUpdates = frame.findText('Dependency updates: 1').single;
        expect(
          frame.getForegroundColor(oceanMessage.x, oceanMessage.y),
          Color.white,
        );
        expect(
          frame.getBackgroundColor(oceanMessage.x, oceanMessage.y),
          const Color(0.2, 0.4, 0.8),
        );
        expect(
          frame.getForegroundColor(oceanUpdates.x, oceanUpdates.y),
          Color.white,
        );

        app.mockInput.typeText('t');
        await Future<void>.delayed(Duration.zero);
        frame = _render(app);

        expect(frame, BufferMatchers.containsText('Theme: forest'));
        final forestMessage = frame.findText('Welcome to Noir').single;
        final forestUpdates = frame.findText('Dependency updates: 2').single;
        expect(
          frame.getForegroundColor(forestMessage.x, forestMessage.y),
          Color.yellow,
        );
        expect(
          frame.getBackgroundColor(forestMessage.x, forestMessage.y),
          Color.fromHex('#1a8040'),
          reason: 'rendered cells store normalized colors at 8-bit precision',
        );
        expect(
          frame.getForegroundColor(forestUpdates.x, forestUpdates.y),
          Color.yellow,
        );
        expect(
          frame.getBackgroundColor(forestUpdates.x, forestUpdates.y),
          Color.fromHex('#1a8040'),
        );
      } finally {
        app.dispose();
      }
    },
  );

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
      expect(
        frame,
        BufferMatchers.containsText('↑/↓ to scroll · q or Ctrl+C to exit'),
      );
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

Future<void> _settleAutofocus(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
