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
  test('mouse-capable example entrypoints ask runTuiApp for mouse once', () {
    for (final path in <String>[
      'example/chat_demo.dart',
      'example/components_demo.dart',
      'example/data_table_demo.dart',
      'example/focus_form.dart',
      'example/like_reactor.dart',
      'example/layout_demo.dart',
      'example/listview_demo.dart',
      'example/select_demo.dart',
      'example/scrollbox_demo.dart',
      'example/widgets_tour.dart',
    ]) {
      final source = io.File(path).readAsStringSync();
      expect(
        RegExp('enableMouse: true').allMatches(source),
        hasLength(1),
        reason: path,
      );
      expect(
        source,
        isNot(contains('app.enableMouse(')),
        reason: '$path enables mouse at the entry point, not after it',
      );
      expect(
        source,
        isNot(contains('enableMouse(enableMovement: true)')),
        reason: '$path does not need movement reports',
      );
    }
  });

  test('no example threads a quit callback or hard-exits', () {
    for (final file
        in io.Directory('example').listSync().whereType<io.File>().where(
          (file) => file.path.endsWith('.dart'),
        )) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('onQuit')), reason: file.path);
      expect(source, isNot(contains('io.exit(')), reason: file.path);
      expect(
        source,
        isNot(contains('registerHotReloadExtension')),
        reason: '${file.path}: runTuiApp registers hot reload itself',
      );
    }
  });

  test('pub search client is a hosted 4.x pub.dev dependency', () {
    final pubspec = io.File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      matches(RegExp(r'^  pub_api_client:\s+\^4\.\d+', multiLine: true)),
    );
    expect(
      pubspec,
      isNot(contains(RegExp(r'pub_api_client:\s*\n\s+git:', multiLine: true))),
    );

    final lockfile = io.File('pubspec.lock').readAsStringSync();
    final lockEntry = RegExp(
      r'  pub_api_client:\n(?:    .*\n)*?    source: (\w+)\n    version: "([^"]+)"',
    ).firstMatch(lockfile);
    expect(
      lockEntry,
      isNotNull,
      reason: 'pubspec.lock must list pub_api_client',
    );
    expect(lockEntry!.group(1), 'hosted');
    expect(lockEntry.group(2), startsWith('4.'));
    expect(lockfile, isNot(contains('github.com/leoafarias/pub_api_client')));
  });

  test('pub search executable is live-only with fresh completion', () {
    final entrypoint = io.File('example/pub_search.dart').readAsStringSync();
    final app = io.File('example/pub_search/app.dart').readAsStringSync();
    final catalog = io.File(
      'example/pub_search/catalog.dart',
    ).readAsStringSync();

    expect(
      entrypoint,
      matches(
        RegExp(
          r'runTuiApp\s*\(\s*PubSearchApp\s*\(\s*'
          r'catalog:\s*PubApiCatalog\s*\(\s*\)\s*,?\s*\)\s*,\s*'
          r'enableMouse:\s*true\s*,?\s*\)',
          dotAll: true,
        ),
      ),
    );
    expect(entrypoint, isNot(contains('PubSearchConnection')));
    expect(app, isNot(contains('PubSearchConnection')));
    expect(app, isNot(contains('LIVE PUB.DEV')));
    expect(app, isNot(contains('OFFLINE DATA')));
    final fields = RegExp(
      r'final class PubApiCatalog implements PubCatalog\s*\{(.*?)^\s*@override',
      dotAll: true,
      multiLine: true,
    ).firstMatch(catalog);
    expect(fields, isNotNull, reason: 'locate PubApiCatalog instance fields');
    expect(
      fields!.group(1),
      isNot(
        matches(
          RegExp(
            r'^\s*(?:final|var)?\s*'
            r'(?:Future\s*<\s*(?:List\s*<\s*String\s*>|'
            r'Map\s*<\s*String\s*,\s*int\s*>)\s*>|'
            r'List\s*<\s*String\s*>|Map\s*<\s*String\s*,\s*int\s*>)'
            r'\s*\?\s+_[A-Za-z]*(?:package|topic)[A-Za-z]*\s*;',
            caseSensitive: false,
            multiLine: true,
          ),
        ),
      ),
      reason:
          'PubApiCatalog must not retain nullable completion datasets or futures',
    );
  });

  test('layout examples exit through the tree exactly once', () async {
    final cases = <(String, Widget)>[
      ('layout basics', const LayoutBasics()),
      ('layout showcase', const FlexLayoutShowcase()),
    ];

    for (final (name, widget) in cases) {
      final app = createTuiTestApp(widget, width: 100, height: 40);

      try {
        await _settleAutofocus(app);
        app.mockInput.typeText('q');
        await _settleInput();
        expect(app.exitRequests, [0], reason: name);
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
    final app = createTuiTestApp(const ScrollDemoApp(), width: 56, height: 18);

    try {
      await _settleAutofocus(app);
      expect(_render(app), contains('Line 1'));

      app.mockInput.pressKittyKey(57357); // End.
      await _settleInput();
      final frame = _render(app);
      expect(frame, contains('Line 40'));
      expect(frame, isNot(contains('offset: 0 /')));

      app.mockInput.typeText('q');
      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test('scrollbox responds to a wheel event inside its viewport', () async {
    final app = createTuiTestApp(const ScrollDemoApp(), width: 56, height: 18);
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
    final app = createTuiTestApp(const SelectDemoApp(), width: 56, height: 20);

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
      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test('select option can be confirmed by mouse', () async {
    final app = createTuiTestApp(const SelectDemoApp(), width: 56, height: 20);
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
    final app = createTuiTestApp(const SelectDemoApp(), width: 35, height: 9);
    try {
      expect(app.pumpFrame, returnsNormally);
      expect(app.captureFrame().toText(), contains('Select demo'));
    } finally {
      app.dispose();
    }
  });

  test('textarea demo submits portable and xterm modified input', () async {
    final app = createTuiTestApp(
      const TextAreaDemoApp(),
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
      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test('textarea demo reports grapheme clusters as its length', () async {
    final app = createTuiTestApp(
      const TextAreaDemoApp(),
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
      final app = createTuiTestApp(const WidgetsTourApp());

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
        expect(
          app.exitRequests,
          isEmpty,
          reason: 'q remains editable while TextArea has focus',
        );
        expect(_render(app), contains('Typed: 6 chars'));

        app.mockInput.pressEscape();
        expect(app.exitRequests, [0]);
      } finally {
        app.dispose();
      }
    },
  );

  test('textarea keeps typing after Tab leaves the quit wrapper', () async {
    final app = createTuiTestApp(
      const TextAreaDemoApp(),
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
    final app = createTuiTestApp(const SelectDemoApp(), width: 56, height: 20);

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
    final app = createTuiTestApp(const ScrollDemoApp(), width: 56, height: 18);

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
    final app = createTuiTestApp(const FlexLayoutShowcase());

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
      final app = createTuiTestApp(const FlexLayoutShowcase());

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
    final app = createTuiTestApp(const WidgetsTourApp());

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
    final app = createTuiTestApp(const WidgetsTourApp());

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
