// ignore_for_file: cascade_invocations
import 'dart:async';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('input dispatch requests frames through InputDispatcher', () {
    final bindingSource = File(
      'lib/src/app/tui_binding.dart',
    ).readAsStringSync();
    final appSource = File('lib/src/app/app.dart').readAsStringSync();

    expect(
      bindingSource,
      contains('_inputDispatcher.setEventDispatch(_scheduler.scheduleFrame)'),
    );
    expect(bindingSource, isNot(contains('_inputManager.setEventDispatch')));
    expect(appSource, isNot(contains('_inputManager.setEventDispatch')));
    expect(bindingSource, isNot(contains('scheduleMicrotask')));
    expect(appSource, isNot(contains('scheduleMicrotask')));
  });

  test('frame body delegates layout and paint to PipelineOwner RenderView', () {
    final source = File('lib/src/app/tui_binding.dart').readAsStringSync();
    final appSource = File('lib/src/app/app.dart').readAsStringSync();

    expect(source, contains('_renderView'));
    expect(source, contains('_owner.pipelineOwner.flushLayout'));
    expect(source, contains('_owner.pipelineOwner.flushPaint'));
    expect(
      source,
      matches(RegExp(r'flushLayout\(\s*_renderView', multiLine: true)),
    );
    expect(source, contains('flushPaint(_renderView'));
    expect(source, isNot(contains('Element.findDescendantRenderObject')));
    expect(source, isNot(contains('renderObject.layout(')));
    expect(source, isNot(contains('renderObject.paint(')));
    expect(appSource, isNot(contains('flushLayout')));
    expect(appSource, isNot(contains('flushPaint')));
  });

  test('key events schedule frames and rebuild state', () {
    final key = GlobalKey<_CounterAppState>();
    final app = createTuiTestApp(_CounterApp(key: key));
    InputSubscription? sub;

    try {
      final state = key.currentState!;
      sub = app.binding.inputManager.onKey((event) {
        state.recordKey(event.character ?? event.logicalKey.keyLabel);
      });
      expect(state.buildCount, 1);

      app.mockInput.typeText('a');
      app.pumpFrame();

      expect(state.receivedKeys, ['a']);
      expect(state.buildCount, 2);
    } finally {
      sub?.cancel();
      app.dispose();
    }
  });

  test(
    'headless injected renderer remains caller-owned after dispose',
    () async {
      final renderer = Renderer.create(8, 2, testing: true);
      final app = TuiBinding(
        width: 8,
        height: 2,
        headless: true,
        renderer: renderer,
      )..runApp(const Text('ok'));

      try {
        await Future<void>.delayed(Duration.zero);

        app.dispose();

        expect(() => renderer.nextBuffer.clear(Color.black), returnsNormally);
      } finally {
        renderer.dispose();
      }
    },
  );

  test('render-tree pointer hits survive input frames that skip paint', () {
    final hits = <MouseEvent>[];
    final paintLog = <String>[];
    final app = createTuiTestApp(
      PointerListener(
        onPointerDown: hits.add,
        child: _PaintProbe(log: paintLog),
      ),
      width: 8,
      height: 2,
    );

    try {
      app.pumpFrame();

      expect(paintLog, ['paint']);

      app.mockMouse.pressDown(0, 0);
      app.pumpFrame();

      expect(hits, hasLength(1));
      expect(paintLog, [
        'paint',
      ], reason: 'The input-scheduled clean frame must not repaint.');

      app.mockMouse.pressDown(0, 0);

      expect(hits, hasLength(2));
    } finally {
      app.dispose();
    }
  });
}

class _CounterApp extends StatefulWidget {
  const _CounterApp({super.key});

  @override
  State<StatefulWidget> createState() => _CounterAppState();
}

class _CounterAppState extends State<_CounterApp> {
  int buildCount = 0;
  final List<String> receivedKeys = [];

  void recordKey(String key) {
    setState(() {
      receivedKeys.add(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    buildCount++;
    return const Container();
  }
}

class _PaintProbe extends RenderObjectWidget {
  const _PaintProbe({required this.log});

  final List<String> log;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintProbe(log);
}

class _RenderPaintProbe extends RenderBox {
  _RenderPaintProbe(this.log);

  final List<String> log;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(2, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    log.add('paint');
  }
}
