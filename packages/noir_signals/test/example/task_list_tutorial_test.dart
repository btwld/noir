import 'package:test/test.dart';

import '../../example/task_list.dart' as lesson5;
import '../../example/tutorials/task_list/step_01.dart' as lesson1;
import '../../example/tutorials/task_list/step_02.dart' as lesson2;
import '../../example/tutorials/task_list/step_03.dart' as lesson3;
import '../../example/tutorials/task_list/step_04.dart' as lesson4;
import '../helpers/noir_test_helpers.dart';

/// Each task-list lesson promises one visible result. These checks hold the
/// runnable checkpoints to the counts and labels the lessons print, so a
/// screenshot and its prose cannot survive a change to the code.
void main() {
  test('lesson 1 mounts the empty screen', () async {
    final app = createTuiTestApp(const lesson1.TaskListApp());
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('Task list'));
      expect(frame, BufferMatchers.containsText('Your tasks will appear here'));
      expect(frame, BufferMatchers.containsText('Ctrl+C exits'));
    } finally {
      app.dispose();
    }
  });

  test('lesson 2 derives 2 of 3 remaining from the seed tasks', () async {
    final app = createTuiTestApp(const lesson2.TaskListApp());
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

  test('lesson 3 completes the first task and reaches 1 of 3', () async {
    final app = createTuiTestApp(const lesson3.TaskListApp());
    try {
      await _settle(app);
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('2 of 3 remaining'),
      );
      await _click(app, 'Read the hooks guide');
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('1 of 3 remaining'));
      expect(frame, BufferMatchers.containsText('Space toggles'));
    } finally {
      app.dispose();
    }
  });

  test('lesson 4 adds Ship the guide and clears the draft', () async {
    final app = createTuiTestApp(const lesson4.TaskListApp());
    try {
      await _settle(app);
      app.mockInput.typeText('Ship the guide');
      app.mockInput.pressEnter();
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('3 of 4 remaining'));
      expect(frame, BufferMatchers.containsText('Ship the guide'));
      // The placeholder is only visible again once the controller is empty.
      expect(frame, BufferMatchers.containsText('New task'));
    } finally {
      app.dispose();
    }
  });

  test('lesson 5 is the shipped example', () async {
    final app = createTuiTestApp(const lesson5.TaskListApp());
    try {
      await _settle(app);
      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('2 of 3 remaining'));
      expect(frame, BufferMatchers.containsText('Hide completed'));
      expect(frame, BufferMatchers.containsText('Clear completed'));
    } finally {
      app.dispose();
    }
  });
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
