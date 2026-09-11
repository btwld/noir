import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

/// Phase D retrofit contract for the four widgets that predate [Theme]:
/// an unthemed widget renders exactly as it did before, an ancestor [Theme]
/// supplies every unset color, and an explicit parameter always wins.
void main() {
  group('TextInput theming', () {
    test('unthemed text and cursor keep their original literals', () {
      final capture = BufferCapture(width: 8, height: 1);
      try {
        final frame = capture.capture(
          TextInput(controller: TextEditingController(text: 'ab')),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.white));
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(0, 0, Color.black),
          reason: 'no ancestor Theme still means no field fill',
        );
      } finally {
        capture.dispose();
      }
    });

    test('an ancestor Theme supplies text and surface', () {
      final capture = BufferCapture(width: 8, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(
              text: Color.yellow,
              surface: Color.blue,
            ),
            child: TextInput(controller: TextEditingController(text: 'ab')),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.yellow));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.blue));
      } finally {
        capture.dispose();
      }
    });

    test('an explicit color wins over the theme', () {
      final capture = BufferCapture(width: 8, height: 1);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(text: Color.yellow),
            child: TextInput(
              color: Color.red,
              controller: TextEditingController(text: 'ab'),
            ),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.red));
      } finally {
        capture.dispose();
      }
    });
  });

  group('TextArea theming', () {
    test('unthemed text keeps its original literal', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          TextArea(height: 2, controller: TextEditingController(text: 'ab')),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.white));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.black));
      } finally {
        capture.dispose();
      }
    });

    test('an ancestor Theme supplies text and surface', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          Theme(
            data: ThemeData.dark.copyWith(
              text: Color.yellow,
              surface: Color.blue,
            ),
            child: TextArea(
              height: 2,
              controller: TextEditingController(text: 'ab'),
            ),
          ),
        );
        expect(frame, BufferMatchers.hasColorAt(0, 0, Color.yellow));
        expect(frame, BufferMatchers.hasBackgroundAt(0, 0, Color.blue));
      } finally {
        capture.dispose();
      }
    });
  });

  group('ScrollBox theming', () {
    Widget scrollBox({Color? scrollbarColor, ThemeData? theme}) {
      final box = SizedBox(
        width: 6,
        height: 3,
        child: ScrollBox(
          scrollbarColor: scrollbarColor,
          child: const Column(
            children: [Text('a'), Text('b'), Text('c'), Text('d')],
          ),
        ),
      );
      return theme == null ? box : Theme(data: theme, child: box);
    }

    test('unthemed thumb and track keep their original literals', () {
      final capture = BufferCapture(width: 6, height: 3);
      try {
        final frame = capture.capture(scrollBox());
        // Rendered cells store normalized colors at 8-bit precision, so the
        // 0.7 thumb comes back as #b3b3b3 rather than exactly 0.7.
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(5, 0, Color.fromHex('#b3b3b3')),
        );
        expect(
          frame,
          BufferMatchers.hasBackgroundAt(5, 2, Color.fromHex('#333333')),
        );
      } finally {
        capture.dispose();
      }
    });

    test('an ancestor Theme supplies thumb and track', () {
      final capture = BufferCapture(width: 6, height: 3);
      try {
        final frame = capture.capture(
          scrollBox(
            theme: ThemeData.dark.copyWith(
              scrollbarThumb: Color.magenta,
              scrollbarTrack: Color.blue,
            ),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(5, 0, Color.magenta));
        expect(frame, BufferMatchers.hasBackgroundAt(5, 2, Color.blue));
      } finally {
        capture.dispose();
      }
    });

    test('an explicit thumb color wins over the theme', () {
      final capture = BufferCapture(width: 6, height: 3);
      try {
        final frame = capture.capture(
          scrollBox(
            scrollbarColor: Color.red,
            theme: ThemeData.dark.copyWith(scrollbarThumb: Color.magenta),
          ),
        );
        expect(frame, BufferMatchers.hasBackgroundAt(5, 0, Color.red));
      } finally {
        capture.dispose();
      }
    });
  });
}
