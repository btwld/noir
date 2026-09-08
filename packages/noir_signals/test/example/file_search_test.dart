import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../../example/file_search.dart';
import '../../example/models/file_search_model.dart';
import '../helpers/noir_test_helpers.dart';
import '../helpers/package_paths.dart';

void main() {
  test('file search filters the list from parsed keystrokes', () async {
    final app = createTuiTestApp(const FileSearchApp());

    try {
      await _settle(app);
      expect(app.captureFrame(), BufferMatchers.containsText('7 files'));
      expect(
        app.captureFrame(),
        BufferMatchers.containsText('test/signals/reactivity_test.dart'),
      );

      app.mockInput.typeText('example/');
      await _settle(app);

      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('2 files'));
      expect(frame, BufferMatchers.containsText('example/counter.dart'));
      expect(frame, BufferMatchers.containsText('example/file_search.dart'));
      expect(frame.findText('test/signals/reactivity_test.dart'), isEmpty);

      app.mockInput.typeText('zzz');
      await _settle(app);
      expect(app.captureFrame(), BufferMatchers.containsText('0 files'));
    } finally {
      app.dispose();
    }
  });

  test('file search keeps one field across the filtered rebuilds', () async {
    final app = createTuiTestApp(const FileSearchApp());

    try {
      // Each keystroke rebuilds the host through the signal observation. The
      // accumulated text only survives that if one controller is retained.
      for (final chunk in <String>['l', 'i', 'b', '/', 'src']) {
        app.mockInput.typeText(chunk);
        await _settle(app);
      }

      final frame = app.captureFrame();
      expect(frame, BufferMatchers.containsText('lib/src'));
      expect(frame, BufferMatchers.containsText('3 files'));
      expect(
        frame,
        BufferMatchers.containsText('lib/src/hooks/framework.dart'),
      );
    } finally {
      app.dispose();
    }
  });

  test('the example teardown releases its controller and model', () {
    final host = TestElementHost();
    final log = <String>[];
    late TextEditingController controller;
    late FileSearchModel model;
    TextEditingController? first;

    // The same ownership shape the example uses, with the owned objects
    // published so the test can check them after teardown.
    host.mount(
      SignalBuilder(
        builder: (context) {
          controller = useTextEditingController();
          model = useMemoized(() => FileSearchModel(const <String>['a.dart']));
          useOnDispose(() {
            model.dispose();
            log.add('model-disposed');
          });
          first ??= controller;
          return Text('${useSignalValue(model.visibleCount)}');
        },
      ),
    );

    model.query.value = 'a';
    host.pumpBuild();
    expect(controller, same(first));

    host.dispose();

    expect(log, <String>['model-disposed']);
    expect(model.query.disposed, isTrue);
    expect(model.visibleFiles.disposed, isTrue);
    expect(
      () => controller.addListener(() {}),
      throwsA(anyOf(isA<StateError>(), isA<AssertionError>())),
    );
  });

  test('the example entry point enables basic mouse reporting once', () {
    final source = companionFile('example/file_search.dart').readAsStringSync();

    expect(RegExp('enableMouse: true').allMatches(source), hasLength(1));
    expect(source, isNot(contains('enableMouse(enableMovement: true)')));
  });
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
