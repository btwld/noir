import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/focus_form.dart';
import '../../example/layout_basics.dart';
import '../../example/layout_demo.dart';
import '../../example/scrollbox_demo.dart';
import '../../example/select_demo.dart';
import '../../example/textarea_demo.dart';
import '../../example/widgets_tour.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('mouse-capable example entrypoints enable mouse reporting once', () {
    for (final path in <String>[
      'example/chat_demo.dart',
      'example/focus_form.dart',
      'example/like_reactor.dart',
      'example/layout_demo.dart',
      'example/select_demo.dart',
      'example/scrollbox_demo.dart',
      'example/widgets_tour.dart',
    ]) {
      final source = io.File(path).readAsStringSync();
      expect(
        RegExp(r'app\.enableMouse\(\);').allMatches(source),
        hasLength(1),
        reason: path,
      );
      expect(
        source,
        isNot(contains('enableMouse(enableMovement: true)')),
        reason: '$path does not need movement reports',
      );
    }
  });

  test('layout examples delegate q to their quit owner exactly once', () async {
    final cases = <(String, Widget Function(VoidCallback))>[
      ('layout basics', (onQuit) => LayoutBasics(onQuit: onQuit)),
      ('layout showcase', (onQuit) => FlexLayoutShowcase(onQuit: onQuit)),
    ];

    for (final (name, build) in cases) {
      var quits = 0;
      final app = createTuiTestApp(
        build(() => quits++),
        width: 100,
        height: 40,
      );

      try {
        await _settleAutofocus(app);
        app.mockInput.typeText('q');
        await _settleInput();
        expect(quits, 1, reason: name);
      } finally {
        app.dispose();
      }
    }
  });

  test('focus form types across Tab and submits the email field', () async {
    final app = createTuiTestApp(const FocusFormApp());

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..typeText('Ada')
        ..pressTab()
        ..typeText('ada@example.com')
        ..pressEnter();
      await _settleInput();

      final frame = _render(app);
      expect(frame, contains('Ada'));
      expect(frame, contains('ada@example.com'));
      expect(frame, contains('Saved: Ada - ada@example.com'));
    } finally {
      app.dispose();
    }
  });

  test('focus form placeholders are hints, not submitted values', () async {
    final app = createTuiTestApp(const FocusFormApp());

    try {
      await _settleAutofocus(app);
      expect(_render(app), contains('Enter name'));
      expect(_render(app), contains('Enter email'));
      expect(_render(app), isNot(contains('Jane Doe')));

      app.mockInput
        ..pressTab()
        ..pressEnter();
      await _settleInput();

      expect(_render(app), contains('Saved:  - '));
    } finally {
      app.dispose();
    }
  });

  test('focus form fields can be selected and submitted by mouse', () async {
    final app = createTuiTestApp(const FocusFormApp());
    try {
      await _settleAutofocus(app);
      var frame = app.captureFrame();
      final name = frame.findText('Enter name').single;
      app.mockMouse.click(name.x, name.y);
      app.mockInput.typeText('Ada');
      await _settleInput();
      app.pumpFrame();

      frame = app.captureFrame();
      final email = frame.findText('Enter email').single;
      app.mockMouse.click(email.x, email.y);
      app.mockInput
        ..typeText('ada@example.com')
        ..pressEnter();
      await _settleInput();

      expect(_render(app), contains('Saved: Ada - ada@example.com'));
    } finally {
      app.dispose();
    }
  });

  test('scroll demo reaches the final row and q invokes quit', () async {
    var quits = 0;
    final app = createTuiTestApp(
      ScrollDemoApp(onQuit: () => quits++),
      width: 56,
      height: 18,
    );

    try {
      await _settleAutofocus(app);
      expect(_render(app), contains('Line 1'));

      app.mockInput.pressKittyKey(57357); // End.
      await _settleInput();
      final frame = _render(app);
      expect(frame, contains('Line 40'));
      expect(frame, isNot(contains('offset: 0 /')));

      app.mockInput.typeText('q');
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test('scrollbox responds to a wheel event inside its viewport', () async {
    final app = createTuiTestApp(
      ScrollDemoApp(onQuit: () {}),
      width: 56,
      height: 18,
    );
    try {
      await _settleAutofocus(app);
      final firstLine = app.captureFrame().findText('Line 1').single;
      app.mockMouse.scroll(firstLine.x, firstLine.y, ScrollDirection.down);
      await _settleInput();

      expect(_render(app), isNot(contains('offset: 0 /')));
    } finally {
      app.dispose();
    }
  });

  test('select demo distinguishes highlight, confirmation, and quit', () async {
    var quits = 0;
    final app = createTuiTestApp(
      SelectDemoApp(onQuit: () => quits++),
      width: 56,
      height: 20,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..pressArrow(ArrowDirection.down)
        ..pressArrow(ArrowDirection.down);
      await _settleInput();
      expect(_render(app), contains('Highlight: Cherry'));

      app.mockInput.pressEnter();
      await _settleInput();
      expect(_render(app), contains('You picked: cherry'));

      app.mockInput.typeText('q');
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test('select option can be confirmed by mouse', () async {
    final app = createTuiTestApp(
      SelectDemoApp(onQuit: () {}),
      width: 56,
      height: 20,
    );
    try {
      await _settleAutofocus(app);
      final cherry = app.captureFrame().findText('Cherry').single;
      app.mockMouse.click(cherry.x, cherry.y);
      await _settleInput();

      expect(_render(app), contains('You picked: cherry'));
    } finally {
      app.dispose();
    }
  });

  test('select demo clips safely in a terminal shorter than its content', () {
    final app = createTuiTestApp(
      SelectDemoApp(onQuit: () {}),
      width: 35,
      height: 9,
    );
    try {
      expect(app.pumpFrame, returnsNormally);
      expect(app.captureFrame().toText(), contains('Select demo'));
    } finally {
      app.dispose();
    }
  });

  test('textarea demo submits portable and xterm modified input', () async {
    var quits = 0;
    final app = createTuiTestApp(
      TextAreaDemoApp(onQuit: () => quits++),
      width: 64,
      height: 22,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..typeText('first')
        ..pressEnter()
        ..typeText('second')
        ..pressCtrl('d');
      await _settleInput();

      final frame = _render(app);
      expect(frame, contains('Length: 12'));
      expect(frame, contains('Last submitted:'));
      expect(frame, contains('first'));
      expect(frame, contains('second'));

      app.mockInput
        ..typeText('!')
        ..pressModifyOtherKey(13, modifiers: KeyModifiers.ctrl);
      await _settleInput();
      final modifiedEnterFrame = _render(app);
      expect(modifiedEnterFrame, contains('Length: 13'));
      expect(
        _submittedLines(modifiedEnterFrame),
        ['first', 'second!'],
        reason: 'xterm Ctrl+Enter must update the submitted snapshot',
      );

      app.mockInput.pressEscape();
      expect(quits, 1);
    } finally {
      app.dispose();
    }
  });

  test('textarea demo reports grapheme clusters as its length', () async {
    final app = createTuiTestApp(
      TextAreaDemoApp(onQuit: () {}),
      width: 64,
      height: 22,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput.typeText('👩‍💻e\u0301');
      await _settleInput();

      expect(_render(app), contains('Length: 2'));
    } finally {
      app.dispose();
    }
  });

  test(
    'widget tour drives all panels and submits text before quitting',
    () async {
      var quits = 0;
      final app = createTuiTestApp(WidgetsTourApp(onQuit: () => quits++));

      try {
        await _settleAutofocus(app);
        app.mockInput
          ..pressArrow(ArrowDirection.down)
          ..pressEnter()
          ..pressTab()
          ..pressPageDown()
          ..pressTab()
          ..typeText('draft')
          ..pressCtrl('d');
        await _settleInput();

        final frame = _render(app);
        expect(frame, contains('Selected: Orange'));
        expect(frame, isNot(contains('ScrollY: 0')));
        expect(frame, contains('Typed: 5 chars'));
        expect(frame, contains('Submitted: 5 chars'));

        app.mockInput.typeText('q');
        await _settleInput();
        expect(quits, 0, reason: 'q remains editable while TextArea has focus');
        expect(_render(app), contains('Typed: 6 chars'));

        app.mockInput.pressEscape();
        expect(quits, 1);
      } finally {
        app.dispose();
      }
    },
  );

  test('textarea keeps typing after Tab leaves the quit wrapper', () async {
    final app = createTuiTestApp(
      TextAreaDemoApp(onQuit: () {}),
      width: 64,
      height: 22,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..typeText('before')
        ..pressTab()
        ..typeText('after');
      await _settleInput();

      expect(_render(app), contains('after'));
    } finally {
      app.dispose();
    }
  });

  test('select keeps highlight movement after Tab', () async {
    final app = createTuiTestApp(
      SelectDemoApp(onQuit: () {}),
      width: 56,
      height: 20,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..pressTab()
        ..pressArrow(ArrowDirection.down)
        ..pressArrow(ArrowDirection.down);
      await _settleInput();

      expect(_render(app), contains('Highlight: Cherry'));
    } finally {
      app.dispose();
    }
  });

  test('scroll demo keeps paging after Tab', () async {
    final app = createTuiTestApp(
      ScrollDemoApp(onQuit: () {}),
      width: 56,
      height: 18,
    );

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..pressTab()
        ..pressPageDown();
      await _settleInput();

      expect(_render(app), isNot(contains('offset: 0 /')));
    } finally {
      app.dispose();
    }
  });

  test('layout showcase pages with keyboard at 80x24', () async {
    final app = createTuiTestApp(FlexLayoutShowcase(onQuit: () {}));

    try {
      await _settleAutofocus(app);
      expect(_render(app), contains('Start'));
      expect(_render(app), isNot(contains('End')));

      app.mockInput.pressPageDown();
      await _settleInput();

      expect(_render(app), contains('End'));
    } finally {
      app.dispose();
    }
  });

  test(
    'layout showcase PageDown does not leak box drawing onto the footer',
    () async {
      final app = createTuiTestApp(FlexLayoutShowcase(onQuit: () {}));

      try {
        await _settleAutofocus(app);
        app.mockInput.pressPageDown();
        await _settleInput();

        final frame = _render(app);
        expect(frame, contains('End'));
        final lines = frame.split('\n');
        final footer = lines.indexWhere(
          (line) => line.contains('Flex Layout Demo'),
        );
        expect(footer, greaterThanOrEqualTo(0), reason: frame);
        final rows = <int>[footer, if (footer + 1 < lines.length) footer + 1];
        const boxDrawing = <String>[
          '│',
          '─',
          '┌',
          '┐',
          '└',
          '┘',
          '┬',
          '┴',
          '├',
          '┤',
          '┼',
        ];
        for (final row in rows) {
          for (final glyph in boxDrawing) {
            expect(
              lines[row],
              isNot(contains(glyph)),
              reason: 'row $row leaked $glyph: ${lines[row]}',
            );
          }
        }
      } finally {
        app.dispose();
      }
    },
  );

  test('widget tour Shift+Tab wraps to the TextArea', () async {
    final app = createTuiTestApp(WidgetsTourApp(onQuit: () {}));

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..pressShiftTab()
        ..typeText('x');
      await _settleInput();

      expect(_render(app), contains('Typed: 1 chars'));
    } finally {
      app.dispose();
    }
  });

  test('widget tour reports and submits grapheme-cluster counts', () async {
    final app = createTuiTestApp(WidgetsTourApp(onQuit: () {}));

    try {
      await _settleAutofocus(app);
      app.mockInput
        ..pressTab()
        ..pressTab()
        ..typeText('👩‍💻e\u0301')
        ..pressCtrl('d');
      await _settleInput();

      final frame = _render(app);
      expect(frame, contains('Typed: 2 chars'));
      expect(frame, contains('Submitted: 2 chars'));
    } finally {
      app.dispose();
    }
  });
}

String _render(TuiTestApp app) {
  app.pumpFrame();
  return app.captureFrame().toText();
}

Future<void> _settleAutofocus(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}

Future<void> _settleInput() => Future<void>.delayed(Duration.zero);

List<String> _submittedLines(String frame) {
  final lines = frame.split('\n').map((line) => line.trim()).toList();
  final label = lines.indexOf('Last submitted:');
  if (label == -1) return const [];
  return lines
      .skip(label + 1)
      .where((line) => line.isNotEmpty)
      .take(2)
      .toList();
}
