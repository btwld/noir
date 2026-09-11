import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  const palette = ThemeData(
    surfaceVariant: Color.red,
    border: Color.white,
    accent: Color.yellow,
  );

  test(
    'title occupies the border and content starts on the first inner row',
    () {
      final frame = _capture(
        const Theme(
          data: palette,
          child: Panel(title: 'Pane', width: 16, child: Text('Body')),
        ),
      );

      final title = frame.findText('Pane').single;
      final body = frame.findText('Body').single;
      expect(frame.getChar(0, title.y), '┌');
      expect(body.y, title.y + 1);
    },
  );

  test('untitled panel leaves the top border unlabelled', () {
    final frame = _capture(const Panel(width: 8, child: Text('Body')));

    expect(frame.getRegion(0, 0, 8, 1), '┌──────┐');
    expect(frame.findText(Icons.chevronRight), isEmpty);
  });

  test('shrink-wraps content and honors fixed viewport dimensions', () {
    final natural = _capture(const Panel(child: Text('Body')));
    expect(natural.getChar(0, 0), '┌');
    expect(natural.getChar(5, 0), '┐');
    expect(natural.getChar(0, 2), '└');
    expect(natural.getChar(5, 2), '┘');

    final fixed = _capture(
      const Panel(width: 10, height: 5, child: Text('Body')),
    );
    expect(fixed.getChar(9, 0), '┐');
    expect(fixed.getChar(0, 4), '└');
    expect(fixed.getChar(9, 4), '┘');
  });

  test('uses the default and nearest overridden palette', () {
    final unthemed = _capture(const Panel(width: 10, child: Text('Body')));
    final unthemedBody = unthemed.findText('Body').single;
    expect(
      unthemed.getBackgroundColor(unthemedBody.x, unthemedBody.y),
      _painted(ThemeData.dark.surfaceVariant),
    );
    expect(unthemed.getForegroundColor(0, 0), _painted(ThemeData.dark.border));

    final themed = _capture(
      const Theme(
        data: palette,
        child: Panel(width: 10, child: Text('Body')),
      ),
    );
    final themedBody = themed.findText('Body').single;
    expect(themed.getBackgroundColor(themedBody.x, themedBody.y), Color.red);
    expect(themed.getForegroundColor(0, 0), Color.white);
  });

  test('focused chrome uses accent and a non-color marker', () {
    final frame = _capture(
      const Theme(
        data: palette,
        child: Panel(
          title: 'Pane',
          focused: true,
          width: 16,
          child: Text('Body'),
        ),
      ),
    );

    final title = frame.findText('${Icons.chevronRight} Pane').single;
    expect(frame.getForegroundColor(title.x, title.y), Color.yellow);
    expect(frame.getForegroundColor(0, title.y), Color.yellow);
  });

  test('untitled focused chrome still exposes its marker', () {
    final frame = _capture(
      const Panel(focused: true, width: 10, child: Text('Body')),
    );

    expect(frame.findText(Icons.chevronRight), hasLength(1));
  });

  test('explicit fill and border colors take precedence over the theme', () {
    final frame = _capture(
      const Theme(
        data: palette,
        child: Panel(
          title: 'Pane',
          focused: true,
          width: 16,
          color: Color.green,
          borderColor: Color.magenta,
          child: Text('Body'),
        ),
      ),
    );

    final body = frame.findText('Body').single;
    expect(frame.getBackgroundColor(body.x, body.y), Color.green);
    expect(frame.getForegroundColor(0, 0), Color.magenta);
    final title = frame.findText('${Icons.chevronRight} Pane').single;
    expect(frame.getForegroundColor(title.x, title.y), Color.magenta);
  });

  test('rejects negative fixed dimensions in debug mode', () {
    expect(
      () => Panel(width: -1, child: const SizedBox.shrink()),
      throwsA(isA<AssertionError>()),
    );
    expect(
      () => Panel(height: -1, child: const SizedBox.shrink()),
      throwsA(isA<AssertionError>()),
    );
  });
}

CapturedBuffer _capture(Widget widget) {
  final capture = BufferCapture(width: 20, height: 8);
  try {
    return capture.capture(widget);
  } finally {
    capture.dispose();
  }
}

Color _painted(Color color) => Color.fromHex(color.toHex());
