import 'package:test/test.dart';

import '../../example/task_list.dart';
import '../helpers/noir_test_helpers.dart';

void main() {
  test('task list derives its initial remaining count', () async {
    final app = createTuiTestApp(const TaskListApp());
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('2 of 3 remaining'));
      expect(frame, BufferMatchers.containsText('Read the hooks guide'));
      expect(frame, BufferMatchers.containsText('Run the counter example'));
      expect(frame, BufferMatchers.containsText('Build a Signals app'));
    } finally {
      app.dispose();
    }
  });

  test(
    'Enter and Add append tasks, clear the draft and ignore blanks',
    () async {
      final app = createTuiTestApp(const TaskListApp());
      try {
        await _settle(app);
        app.mockInput.typeText('   ');
        app.mockInput.pressEnter();
        await _settle(app);
        expect(
          app.captureFrame(),
          BufferMatchers.containsText('2 of 3 remaining'),
        );

        app.mockInput.typeText('Ship a demo  ');
        app.mockInput.pressEnter();
        await _settle(app);
        var frame = app.captureFrame();
        expect(frame, BufferMatchers.containsText('3 of 4 remaining'));
        expect(frame, BufferMatchers.containsText('New task'));
        expect(frame, BufferMatchers.containsText('Ship a demo'));
        expect(frame.findText('Ship a demo'), hasLength(1));

        app.mockInput.typeText('Write the guide');
        await _settle(app);
        await _click(app, 'Add');
        frame = app.captureFrame();
        expect(frame, BufferMatchers.containsText('4 of 5 remaining'));
        expect(frame, BufferMatchers.containsText('New task'));
        expect(frame, BufferMatchers.containsText('Write the guide'));
      } finally {
        app.dispose();
      }
    },
  );

  test('completion, filtering and resize retain tasks and the draft', () async {
    final app = createTuiTestApp(const TaskListApp());
    try {
      await _settle(app);
      app.mockInput.typeText('Unsubmitted draft');
      await _settle(app);
      await _click(app, 'Read the hooks guide');
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('1 of 3 remaining'),
      );
      await _click(app, 'Hide completed');
      var frame = app.captureFrame();
      expect(frame.findText('Read the hooks guide'), isEmpty);
      expect(frame.findText('Run the counter example'), isEmpty);
      expect(frame, BufferMatchers.containsText('Build a Signals app'));
      expect(frame, BufferMatchers.containsText('Unsubmitted draft'));

      app.resize(100, 30);
      await _settle(app);
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('1 of 3 remaining'),
      );
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('Unsubmitted draft'),
      );
      await _click(app, 'Hide completed');
      await _click(app, 'Read the hooks guide');
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('2 of 3 remaining'),
      );
      await _click(app, 'Clear completed');
      frame = app.captureFrame();
      expect(frame.findText('Run the counter example'), isEmpty);
      expect(frame, BufferMatchers.containsText('2 of 2 remaining'));
      expect(frame, BufferMatchers.containsText('Unsubmitted draft'));
    } finally {
      app.dispose();
    }
  });

  test(
    'keyboard traversal can complete tasks and reach the empty states',
    () async {
      final app = createTuiTestApp(const TaskListApp());
      try {
        await _settle(app);
        // Draft -> Add -> Hide completed. Toggle the filter, then the first task.
        for (var i = 0; i < 2; i++) {
          app.mockInput.pressTab();
          await _settle(app);
        }
        app.mockInput.typeText(' ');
        await _settle(app);
        expect(app.captureFrame().findText('Run the counter example'), isEmpty);
        app.mockInput.pressTab();
        await _settle(app);
        // ScrollBox has its own focus stop for scrolling before its children.
        app.mockInput.pressTab();
        await _settle(app);
        app.mockInput.typeText(' ');
        await _settle(app);
        expect(
          app.captureFrame(),
          BufferMatchers.containsText('1 of 3 remaining'),
        );

        await _click(app, 'Build a Signals app');
        expect(app.captureFrame(), BufferMatchers.containsText('All done!'));
        await _click(app, 'Clear completed');
        expect(
          app.captureFrame(),
          BufferMatchers.containsText('0 of 0 remaining'),
        );
        expect(
          app.captureFrame(),
          BufferMatchers.containsText('Add your first task.'),
        );
      } finally {
        app.dispose();
      }
    },
  );
}

Future<void> _click(TuiTestApp app, String label) async {
  final point = app.captureFrame().findText(label).single;
  app.mockMouse.pressDown(point.x, point.y);
  await _settle(app);
}

Future<void> _settle(TuiTestApp app) async {
  app.pumpFrame();
  await Future<void>.microtask(() {});
  app.pumpFrame();
}
