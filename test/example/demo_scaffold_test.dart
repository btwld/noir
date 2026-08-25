import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/hello.dart' as hello;
import '../../example/src/demo_scaffold.dart';
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

  group('DemoPanel', () {
    test('paints surfaceVariant inside a theme.border box', () {
      final capture = BufferCapture(
        width: 20,
        height: 6,
        layoutConstraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      try {
        final frame = capture.capture(
          const Theme(
            data: theme,
            child: DemoPanel(title: 'Pane', width: 16, child: Text('Body')),
          ),
        );

        expect(frame, BufferMatchers.containsText('Pane'));
        expect(frame, BufferMatchers.containsText('Body'));

        final title = frame.findText('Pane').single;
        final body = frame.findText('Body').single;
        expect(
          body.y,
          title.y + 1,
          reason: 'body starts on the first inner row; title is on the border',
        );
        expect(
          frame.getChar(0, title.y),
          '┌',
          reason: 'title lives on the top edge, not an inner header row',
        );
        expect(
          frame.getForegroundColor(title.x, title.y),
          Color.white,
          reason: 'unfocused title uses the border color',
        );
        expect(
          frame.getBackgroundColor(body.x, body.y),
          Color.red,
          reason: 'panel fill is surfaceVariant',
        );
      } finally {
        capture.dispose();
      }
    });

    test('focused chrome uses the accent and a structural marker', () {
      final capture = BufferCapture(
        width: 20,
        height: 6,
        layoutConstraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      try {
        final frame = capture.capture(
          const Theme(
            data: theme,
            child: DemoPanel(
              title: 'Pane',
              focused: true,
              width: 16,
              child: Text('Body'),
            ),
          ),
        );

        final title = frame.findText('› Pane').single;
        expect(frame.getForegroundColor(title.x, title.y), Color.yellow);
        expect(frame.getChar(0, title.y), '┌');
        expect(frame.getForegroundColor(0, title.y), Color.yellow);
      } finally {
        capture.dispose();
      }
    });

    test('untitled focused chrome still exposes a structural marker', () {
      final capture = BufferCapture(
        width: 20,
        height: 6,
        layoutConstraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      try {
        final frame = capture.capture(
          const Theme(
            data: theme,
            child: DemoPanel(focused: true, width: 16, child: Text('Body')),
          ),
        );

        final marker = frame.findText('›').single;
        expect(frame.getForegroundColor(marker.x, marker.y), Color.yellow);
        expect(frame.getChar(0, marker.y), '┌');
        expect(frame.getForegroundColor(0, marker.y), Color.yellow);
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
