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
