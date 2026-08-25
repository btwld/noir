import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/components_demo.dart';
import '../../example/data_table_demo.dart';
import '../../example/listview_demo.dart';
import '../../example/parity_components_demo.dart';
import '../../example/theme_demo.dart';
import '../helpers/tui_test_app.dart';

/// Behavior coverage for catalog demos added with the tree-scoped exit and
/// component-parity work.
void main() {
  test('components demo toggles a control and ends through the tree', () async {
    final app = createTuiTestApp(
      const ComponentsDemoApp(),
      width: 62,
      height: 16,
    );
    try {
      await _settle(app);
      expect(_render(app), contains('■ soft wrap'));

      // Autofocus lands on the first checkbox; Space toggles it.
      app.mockInput.typeText(' ');
      await _settle(app);
      expect(_render(app), contains('□ soft wrap'));

      app.mockInput.typeText('q');
      await _settle(app);
      expect(app.exitRequests, [0]);
    } finally {
      app.dispose();
    }
  });

  test('components demo steps and resets its progress', () async {
    final app = createTuiTestApp(
      const ComponentsDemoApp(),
      width: 62,
      height: 16,
    );
    try {
      await _settle(app);
      expect(_render(app), contains('3/10'));

      // Tab past the two toggles (the disabled one is skipped) to Step.
      app.mockInput
        ..pressTab()
        ..pressTab()
        ..typeText(' ');
      await _settle(app);
      expect(_render(app), contains('4/10'));
    } finally {
      app.dispose();
    }
  });

  test('data table demo sorts by a clicked header and opens a row', () async {
    final app = createTuiTestApp(
      const DataTableDemoApp(),
      width: 50,
      height: 20,
    );
    try {
      await _settle(app);
      // The window shows the head of the list, so the first body row is the
      // only order fact visible without scrolling.
      expect(_firstBodyRow(app), 'noir');

      final header = app.captureFrame().findText('package').single;
      app.mockMouse.click(header.x, header.y);
      await _settle(app);

      expect(_render(app), contains('package▲'));
      expect(
        _firstBodyRow(app),
        'analyzer',
        reason: 'the demo owns row order and reordered its own list',
      );

      app.mockInput.pressEnter();
      await _settle(app);
      expect(_render(app), contains('Opened analyzer.'));
    } finally {
      app.dispose();
    }
  });

  test('data table demo cycles sortable columns from the keyboard', () async {
    final app = createTuiTestApp(
      const DataTableDemoApp(),
      width: 50,
      height: 20,
    );
    try {
      await _settle(app);

      app.mockInput.typeText('s');
      await _settle(app);
      expect(_render(app), contains('package▲'));
      expect(_firstBodyRow(app), 'analyzer');

      app.mockInput.typeText('s');
      await _settle(app);
      expect(_render(app), contains('package▼'));
      expect(_firstBodyRow(app), 'yaml');

      app.mockInput.typeText('s');
      await _settle(app);
      expect(_render(app), contains('state▲'));
      expect(_firstBodyRow(app), 'test');
    } finally {
      app.dispose();
    }
  });

  test('listview demo moves its highlight and confirms a row', () async {
    final app = createTuiTestApp(
      const ListViewDemoApp(),
      width: 60,
      height: 18,
    );
    try {
      await _settle(app);
      expect(_render(app), contains('Enter or click a row'));

      app.mockInput
        ..pressArrow(ArrowDirection.down)
        ..pressArrow(ArrowDirection.down)
        ..pressEnter();
      await _settle(app);

      expect(_render(app), contains('Confirmed item 2 of 500.'));
    } finally {
      app.dispose();
    }
  });

  test('theme demo swaps every chrome token with one keypress', () async {
    final app = createTuiTestApp(const ThemeDemoApp(), width: 60, height: 14);
    try {
      await _settle(app);
      expect(_render(app), contains('midnight'));
      final midnight = app.captureFrame();
      final midnightTitle = midnight.findText('Theme demo').single;
      expect(
        midnight.getForegroundColor(midnightTitle.x, midnightTitle.y),
        Color.white,
      );

      app.mockInput.typeText('t');
      await _settle(app);

      final sunset = app.captureFrame();
      expect(_render(app), contains('sunset'));
      final sunsetTitle = sunset.findText('Theme demo').single;
      expect(
        sunset.getForegroundColor(sunsetTitle.x, sunsetTitle.y),
        isNot(Color.white),
        reason: 'the scaffold title reads the swapped text token',
      );
    } finally {
      app.dispose();
    }
  });

  test('parity components demo renders its document viewport', () async {
    final app = createTuiTestApp(const ParityComponentsDemoApp());
    try {
      await _settle(app);
      final rendered = app.captureFrame().toText();
      expect(rendered, contains('ASCII'));
      expect(rendered, contains('void main'));
    } finally {
      app.dispose();
    }
  });
}

/// The package name in the table's first body row, immediately under the
/// header. A titled DemoPanel may put a box-drawing cell in column 0.
String _firstBodyRow(TuiTestApp app) {
  final frame = app.captureFrame();
  final header = frame.findText('package').single;
  return frame
      .getRegion(0, header.y + 1, frame.width, 1)
      .replaceAll(RegExp('[┌┐└┘─│]'), '')
      .trim()
      .split(RegExp(r'\s+'))
      .first;
}

String _render(TuiTestApp app) {
  app.pumpFrame();
  return app.captureFrame().toText();
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
