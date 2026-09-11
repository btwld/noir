import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/hello.dart' as hello;
import '../../example/src/shared/demo_scaffold.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

/// The example card: a themed surface, a titled panel, and hello as the
/// reference composition. Token colors are overridden so assertions are
/// exact.
void main() {
  const theme = ThemeData(
    surface: Color.blue,
    surfaceVariant: Color.red,
    border: Color.white,
    accent: Color.yellow,
    textMuted: Color.cyan,
  );

  group('DemoScaffold', () {
    test('title sits two cells in and the surface fills the terminal', () {
      final capture = BufferCapture(
        width: 24,
        height: 8,
        layoutConstraints: const BoxConstraints.tight(width: 24, height: 8),
      );
      try {
        final frame = capture.capture(
          const Theme(
            data: theme,
            child: DemoScaffold(
              title: 'Title',
              hint: 'Hint',
              child: Text('Body'),
            ),
          ),
        );

        final title = frame.findText('Title').single;
        expect(title.x, 2, reason: 'scaffold left inset is 2 cells');
        expect(title.y, 1, reason: 'scaffold top inset is 1 cell');
        expect(frame.getForegroundColor(title.x, title.y), Color.white);
        expect(frame.getCell(title.x, title.y).isBold, isTrue);

        final hint = frame.findText('Hint').single;
        expect(frame.getForegroundColor(hint.x, hint.y), Color.cyan);

        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 0, Color.blue),
          reason: 'surface owns the terminal, including the inset cells',
        );
        expect(frame, BufferMatchers.hasBackgroundAt(23, 7, Color.blue));
      } finally {
        capture.dispose();
      }
    });
  });

  test('hello is the reference composition of scaffold plus two panels', () {
    final app = createTuiTestApp(const hello.HelloApp());
    try {
      app.pumpFrame();
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('Flutter-like widgets'));
      expect(frame, BufferMatchers.containsText('Layout'));
      expect(frame, BufferMatchers.containsText('State'));

      final title = frame.findText('Noir').single;
      expect(title.x, 2);
      expect(title.y, 1);

      final layout = frame.findText('Layout').single;
      final body = frame.findText('Row, Column').single;
      expect(body.y, layout.y + 1);
      expect(frame.getChar(2, layout.y), '┌');

      final card = frame.getBackgroundColor(body.x, body.y);
      final surface = frame.getBackgroundColor(0, 0);
      expect(surface, isNot(Color.black));
      expect(card, isNot(surface));
    } finally {
      app.dispose();
    }
  });
}
