import 'dart:convert';
import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;
import 'package:noir/src/app/driver.dart';
import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

void main() {
  group('createDriveModeHost', () {
    test('stays inert without NOIR_DRIVE=1', () {
      expect(createDriveModeHost(const <String, String>{}), isNull);
      expect(
        createDriveModeHost(const <String, String>{'NOIR_DRIVE': '0'}),
        isNull,
      );
    });

    test('defaults to 80x24 and honours NOIR_DRIVE_SIZE', () {
      final defaultHost = createDriveModeHost(const <String, String>{
        'NOIR_DRIVE': '1',
      })!;
      addTearDown(defaultHost.dispose);
      expect(defaultHost.info()['width'], 80);
      expect(defaultHost.info()['height'], 24);

      final sizedHost = createDriveModeHost(const <String, String>{
        'NOIR_DRIVE': '1',
        'NOIR_DRIVE_SIZE': '100x30',
      })!;
      addTearDown(sizedHost.dispose);
      expect(sizedHost.info()['width'], 100);
      expect(sizedHost.info()['height'], 30);
    });

    test('falls back to the default size for an unparseable size', () {
      final host = createDriveModeHost(const <String, String>{
        'NOIR_DRIVE': '1',
        'NOIR_DRIVE_SIZE': 'wide',
      })!;
      addTearDown(host.dispose);
      expect(host.info()['width'], 80);
      expect(host.info()['height'], 24);
    });
  });

  group('DriverHost', () {
    test('capture matches a BufferCapture snapshot of the same widget', () {
      const widget = _Scene();
      final host = DriverHost.create(width: 20, height: 5);
      addTearDown(host.dispose);
      host.binding
        ..runApp(widget)
        ..debugFlushFrame();

      final capture = BufferCapture(
        width: 20,
        height: 5,
        layoutConstraints: BoxConstraints.tight(width: 20, height: 5),
      );
      addTearDown(capture.dispose);
      final expected = capture.capture(widget);

      final text = host.capture();
      expect(text['type'], 'Success');
      expect(text['format'], 'text');
      expect(text['width'], 20);
      expect(text['height'], 5);
      expect(text['lines'], expected.toLines());
      expect(text.containsKey('rows'), isFalse);
      expect(text['cursor'], <String, Object?>{
        'visible': expected.cursor.visible,
        'x': expected.cursor.x,
        'y': expected.cursor.y,
        'style': expected.cursor.style.name,
        'color': expected.cursor.color.toHex(),
        'blinking': expected.cursor.blinking,
      });

      final cells = host.capture(format: DriverCaptureFormat.cells);
      expect(cells['format'], 'cells');
      expect(cells['lines'], expected.toLines());
      final rows = (cells['rows']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(rows, hasLength(5));
      for (var y = 0; y < 5; y++) {
        expect(
          (rows[y]['chars']! as List<Object?>).cast<String>(),
          <String>[for (var x = 0; x < 20; x++) expected.getChar(x, y)],
          reason: 'row $y characters',
        );
        expect(
          (rows[y]['fg']! as List<Object?>).cast<String>(),
          <String>[
            for (var x = 0; x < 20; x++)
              expected.getForegroundColor(x, y).toHex(),
          ],
          reason: 'row $y foregrounds',
        );
        expect(
          (rows[y]['bg']! as List<Object?>).cast<String>(),
          <String>[
            for (var x = 0; x < 20; x++)
              expected.getBackgroundColor(x, y).toHex(),
          ],
          reason: 'row $y backgrounds',
        );
        expect(
          (rows[y]['attrs']! as List<Object?>).cast<int>(),
          <int>[for (var x = 0; x < 20; x++) expected.getCell(x, y).attributes],
          reason: 'row $y attributes',
        );
        expect(rows[y]['links'], <String?>[
          for (var x = 0; x < 20; x++) null,
        ], reason: 'row $y links');
      }
    });

    test('cell capture resolves semantic links without exposing IDs', () {
      final host = DriverHost.create(width: 8, height: 1);
      addTearDown(host.dispose);
      host.binding
        ..runApp(
          RichText(
            text: TextSpan(
              text: 'Noir',
              uri: Uri.parse('https://example.test/noir'),
            ),
          ),
        )
        ..debugFlushFrame();

      final capture = host.capture(format: DriverCaptureFormat.cells);
      final rows = (capture['rows']! as List<Object?>)
          .cast<Map<String, Object?>>();
      expect(rows.single['links'], <String?>[
        'https://example.test/noir',
        'https://example.test/noir',
        'https://example.test/noir',
        'https://example.test/noir',
        null,
        null,
        null,
        null,
      ]);
    });

    test('sendBytes drives an arrow key through the ANSI parser', () async {
      final host = DriverHost.create(width: 12, height: 1);
      addTearDown(host.dispose);
      host.binding.runApp(const _Counter());
      // The driver's own settle primitive: autofocus resolves across event
      // loop turns, so a synchronous flush would send to an unfocused tree.
      await host.waitStable();
      expect(host.capture()['lines'], <String>['count 0']);

      final ack = host.sendBytes(base64Encode(utf8.encode('\x1b[A')));
      expect(ack, <String, Object?>{
        'type': 'Success',
        'bytes': 3,
        'frames': host.info()['frames'],
      });

      await host.waitStable();
      expect(host.capture()['lines'], <String>['count 1']);
    });

    test(
      'tree returns a structured snapshot with stable diagnostics',
      () async {
        final host = DriverHost.create(width: 24, height: 6);
        addTearDown(host.dispose);
        host.binding.runApp(const _DriverTreeScene());
        await host.waitStable();

        final tree = host.tree();
        expect(tree['type'], 'Success');
        expect(tree, isNot(contains('lines')));
        final root = tree['root']! as Map<String, Object?>;
        expect(root['type'], '_DriverTreeScene');
        expect(root['key'], 'scene');
        expect(root['text'], isNull);
        expect(root['focused'], isFalse);
        expect(root['hasFocusedDescendant'], isTrue);
        expect(root['hitPoint'], isNull);

        final nodes = _flattenDriverNodes(root);
        expect(
          nodes.singleWhere((node) => node['key'] == 'plain')['text'],
          'plain source',
        );
        expect(
          nodes.singleWhere((node) => node['key'] == 'rich')['text'],
          'rich source text',
        );
        expect(
          nodes.singleWhere((node) => node['key'] == 'text-rich')['text'],
          ' exact source ',
          reason: 'source whitespace must not be normalized',
        );
        expect(
          nodes.singleWhere((node) => node['key'] == 'empty')['text'],
          '',
          reason: 'empty source text is distinct from no text diagnostic',
        );
        expect(
          nodes.singleWhere((node) => node['key'] == 'focused')['focused'],
          isTrue,
        );
        expect(
          nodes.singleWhere((node) => node['text'] == 'numeric key')['key'],
          isNull,
          reason: 'non-string ValueKey values are not serialized',
        );
        expect(
          nodes.singleWhere((node) => node['text'] == 'object key')['key'],
          isNull,
          reason: 'arbitrary ObjectKey values are not serialized',
        );
        expect(
          nodes.singleWhere((node) => node['text'] == 'dynamic key')['key'],
          isNull,
          reason: 'ValueKey<dynamic> is a distinct key namespace',
        );
        expect(
          nodes.singleWhere((node) => node['text'] == 'subclass key')['key'],
          isNull,
          reason: 'ValueKey subclasses retain distinct runtime-type namespaces',
        );
      },
    );

    test('tree depth truncation does not truncate focus derivation', () async {
      final host = DriverHost.create(width: 24, height: 6);
      addTearDown(host.dispose);
      host.binding.runApp(const _DriverTreeScene());
      await host.waitStable();

      final root = host.tree(maxDepth: 0)['root']! as Map<String, Object?>;
      expect(root['children'], isEmpty);
      expect(root['hasFocusedDescendant'], isTrue);
    });

    test('tree reports a null root when no app is mounted', () {
      WidgetInspectorService.instance.clear();
      final host = DriverHost.create(width: 12, height: 1);
      addTearDown(host.dispose);

      expect(host.tree()['root'], isNull);
    });

    test('tree hit points follow ScrollBox translation and clipping', () async {
      final host = DriverHost.create(width: 8, height: 2);
      addTearDown(host.dispose);
      host.binding.runApp(const _ScrollHitScene());
      await host.waitStable();

      final nodes = _flattenDriverNodes(
        host.tree()['root']! as Map<String, Object?>,
      );
      expect(
        nodes.singleWhere((node) => node['key'] == 'offscreen')['hitPoint'],
        isNull,
      );
      final target = nodes.singleWhere(
        (node) => node['key'] == 'scrolled-target',
      );
      final point = target['hitPoint']! as Map<String, Object?>;
      expect(point['y'], inInclusiveRange(0, 1));

      host.sendBytes(_encodedClick(point['x']! as int, point['y']! as int));
      await host.waitStable();
      expect(
        _flattenDriverNodes(
          host.tree()['root']! as Map<String, Object?>,
        ).any((node) => node['text'] == 'clicked 1'),
        isTrue,
      );
    });

    test(
      'tree hit points exclude obscured cells and keep stable ties',
      () async {
        final host = DriverHost.create(width: 6, height: 3);
        addTearDown(host.dispose);
        host.binding.runApp(const _OverlapHitScene());
        await host.waitStable();

        final nodes = _flattenDriverNodes(
          host.tree()['root']! as Map<String, Object?>,
        );
        final behind = nodes.singleWhere((node) => node['key'] == 'behind');
        expect(behind['hitPoint'], <String, Object?>{'x': 4, 'y': 1});
        expect(
          nodes.singleWhere((node) => node['key'] == 'hidden')['hitPoint'],
          isNull,
        );

        host.sendBytes(_encodedClick(4, 1));
        await host.waitStable();
        expect(
          _flattenDriverNodes(
            host.tree()['root']! as Map<String, Object?>,
          ).any((node) => node['text'] == 'behind 1'),
          isTrue,
        );
      },
    );

    test(
      'tree does not mark an offscreen descendant through its ancestor',
      () async {
        final host = DriverHost.create(width: 8, height: 2);
        addTearDown(host.dispose);
        host.binding.runApp(const _AncestorVisibilityScene());
        await host.waitStable();

        final nodes = _flattenDriverNodes(
          host.tree()['root']! as Map<String, Object?>,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'content-target',
          )['hitPoint'],
          isNotNull,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'offscreen-label',
          )['hitPoint'],
          isNull,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'visible-label',
          )['hitPoint'],
          isNotNull,
        );
      },
    );

    test(
      'tree does not mark an obscured descendant through its ancestor',
      () async {
        final host = DriverHost.create(width: 6, height: 2);
        addTearDown(host.dispose);
        host.binding.runApp(const _ObscuredDescendantScene());
        await host.waitStable();

        final nodes = _flattenDriverNodes(
          host.tree()['root']! as Map<String, Object?>,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'partly-visible',
          )['hitPoint'],
          isNotNull,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'obscured-label',
          )['hitPoint'],
          isNull,
        );
        expect(
          nodes.singleWhere(
            (node) => node['key'] == 'visible-label',
          )['hitPoint'],
          isNotNull,
        );
      },
    );

    test('tree does not borrow a hit from a transparent sibling', () async {
      final host = DriverHost.create(width: 6, height: 2);
      addTearDown(host.dispose);
      host.binding.runApp(const _TransparentSiblingScene());
      await host.waitStable();

      final nodes = _flattenDriverNodes(
        host.tree()['root']! as Map<String, Object?>,
      );
      expect(
        nodes.singleWhere(
          (node) => node['key'] == 'behind-transparent',
        )['hitPoint'],
        isNotNull,
      );
      expect(
        nodes.singleWhere(
          (node) => node['key'] == 'transparent-label',
        )['hitPoint'],
        isNull,
      );
    });

    test('tree does not borrow a hit from a descendant target', () async {
      final host = DriverHost.create(width: 6, height: 2);
      addTearDown(host.dispose);
      host.binding.runApp(const _NonPointerParentScene());
      await host.waitStable();

      final nodes = _flattenDriverNodes(
        host.tree()['root']! as Map<String, Object?>,
      );
      expect(
        nodes.singleWhere(
          (node) => node['key'] == 'non-pointer-parent',
        )['hitPoint'],
        isNull,
      );
      expect(
        nodes.singleWhere((node) => node['key'] == 'first-child')['hitPoint'],
        isNotNull,
      );
      expect(
        nodes.singleWhere((node) => node['key'] == 'second-child')['hitPoint'],
        isNotNull,
      );

      final clicked = <DriverPoint>[];
      await expectLater(
        clickDriverLocator(
          const DriverLocator.byKey('non-pointer-parent'),
          fetchTree: () async => DriverTree.fromJson(host.tree()),
          click: clicked.add,
        ),
        throwsStateError,
      );
      expect(clicked, isEmpty);
    });

    test(
      'locator clicks a custom HitTestTarget on the same cell as dispatch',
      () async {
        final hits = <MouseEvent>[];
        final host = DriverHost.create(width: 4, height: 3);
        addTearDown(host.dispose);
        host.binding.runApp(
          _CustomHitTargetWidget(
            key: const ValueKey<String>('custom-target'),
            onPointerDown: hits.add,
          ),
        );
        await host.waitStable();

        expect(_CustomHitTarget(onPointerDown: (_) {}), isA<RenderObject>());
        expect(_CustomHitTarget(onPointerDown: (_) {}), isA<HitTestTarget>());
        expect(
          _CustomHitTarget(onPointerDown: (_) {}),
          isNot(isA<RenderBox>()),
        );

        host.sendBytes(_encodedClick(1, 0));
        await host.waitStable();
        expect(hits, hasLength(1));
        expect(hits.single.x, 1);
        expect(hits.single.y, 0);

        final target = _flattenDriverNodes(
          host.tree()['root']! as Map<String, Object?>,
        ).singleWhere((node) => node['key'] == 'custom-target');
        expect(target['hitPoint'], <String, Object?>{'x': 1, 'y': 0});

        final clicked = <DriverPoint>[];
        await clickDriverLocator(
          const DriverLocator.byKey('custom-target'),
          fetchTree: () async => DriverTree.fromJson(host.tree()),
          click: (cell) {
            clicked.add(cell);
            host.sendBytes(_encodedClick(cell.x, cell.y));
          },
        );
        await host.waitStable();
        expect(clicked, const <DriverPoint>[DriverPoint(1, 0)]);
        expect(hits, hasLength(2));
        expect(hits.last.x, 1);
        expect(hits.last.y, 0);
      },
    );

    test('resize rejects non-positive dimensions', () {
      final host = DriverHost.create(width: 12, height: 2);
      addTearDown(host.dispose);
      host.binding
        ..runApp(const _Counter())
        ..debugFlushFrame();

      expect(() => host.resize(0, 10), throwsArgumentError);
      expect(() => host.resize(10, 0), throwsArgumentError);
      expect(() => host.resize(-1, 4), throwsArgumentError);
      expect(host.info()['width'], 12);
      expect(host.info()['height'], 2);
    });

    test('resize republishes the painted dimensions', () {
      final host = DriverHost.create(width: 12, height: 2);
      addTearDown(host.dispose);
      host.binding
        ..runApp(const _Counter())
        ..debugFlushFrame();

      final ack = host.resize(24, 4);
      expect(ack, <String, Object?>{
        'type': 'Success',
        'width': 24,
        'height': 4,
        'frames': host.info()['frames'],
      });
      host.binding.debugFlushFrame();

      final captured = host.capture();
      expect(captured['width'], 24);
      expect(captured['height'], 4);
      expect(host.info()['width'], 24);
      expect(host.info()['height'], 4);
    });

    test('info counts painted frames and reports drive mode', () {
      final host = DriverHost.create(width: 8, height: 1);
      addTearDown(host.dispose);
      host.binding.runApp(const _Counter());

      expect(host.info(), <String, Object?>{
        'type': 'Success',
        'driveMode': true,
        'width': 8,
        'height': 1,
        'frames': 0,
      });

      host.binding.debugFlushFrame();
      expect(host.info()['frames'], 1);
    });

    test('waitStable resolves once the scheduler goes quiet', () async {
      final host = DriverHost.create(width: 8, height: 1);
      addTearDown(host.dispose);
      host.binding.runApp(const _Counter());
      expect(host.binding.debugHasScheduledFrame, isTrue);

      final stable = await host.waitStable();
      expect(stable['type'], 'Success');
      expect(stable['stable'], isTrue);
      expect(stable['frames'], 1);
      expect(host.binding.debugHasScheduledFrame, isFalse);
    });

    test('waitStable reports instability at the timeout', () async {
      final host = DriverHost.create(width: 8, height: 1);
      addTearDown(host.dispose);
      host.binding.runApp(const _Repainter());

      final stable = await host.waitStable(timeoutMs: 100);
      expect(stable['stable'], isFalse);
    });

    test('quit acknowledges before disposing and exiting', () async {
      final exitCodes = <int>[];
      final host = DriverHost.create(
        width: 8,
        height: 1,
        exitProcess: exitCodes.add,
      );
      addTearDown(host.dispose);
      host.binding
        ..runApp(const _Counter())
        ..debugFlushFrame();

      expect(host.quit(), <String, Object?>{
        'type': 'Success',
        'quitting': true,
      });
      expect(exitCodes, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(exitCodes, <int>[0]);
    });
  });

  test('an in-app exit shuts the driven session down', () async {
    // Without the host following TuiApp.exit, the keep-alive timer outlives
    // the UI.
    final exits = <int>[];
    final host = DriverHost.create(
      width: 20,
      height: 4,
      exitProcess: exits.add,
    );
    final app = mountTuiAppForTesting(
      host.binding,
      const _QuitOnQ(),
      exitCodeSink: host.handleAppExit,
    );
    host.start(app);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    host.sendBytes(base64Encode(utf8.encode('q')));
    expect(
      exits,
      isEmpty,
      reason: 'shutdown is deferred so the in-flight command can finish',
    );
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(exits, [0], reason: 'the driven process ends with the app');
    expect(host.info, throwsStateError, reason: 'the host is disposed too');
  });

  test('runTuiApp wires a driven in-app exit to the host', () {
    // The test above mounts through the host directly; this asserts the
    // runTuiApp wiring.
    final source = io.File('lib/src/app/app.dart').readAsStringSync();
    expect(source, contains('exitCodeSink: host.handleAppExit'));
  });
}

class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0.1, 0.2, 0.3),
    child: const Text(
      'drive',
      style: TextStyle(color: Color.yellow, fontWeight: FontWeight.bold),
    ),
  );
}

class _DriverTreeScene extends StatelessWidget {
  const _DriverTreeScene() : super(key: const ValueKey<String>('scene'));

  @override
  Widget build(BuildContext context) => Column(
    children: const <Widget>[
      Text('plain source', key: ValueKey<String>('plain')),
      RichText(
        key: ValueKey<String>('rich'),
        text: TextSpan(
          text: 'rich ',
          children: <InlineSpan>[TextSpan(text: 'source text')],
        ),
      ),
      Text.rich(
        TextSpan(
          text: ' exact ',
          children: <InlineSpan>[TextSpan(text: 'source ')],
        ),
        key: ValueKey<String>('text-rich'),
      ),
      Text('', key: ValueKey<String>('empty')),
      Text('numeric key', key: ValueKey<int>(7)),
      Text('object key', key: ObjectKey<String>('not stable')),
      Text('dynamic key', key: ValueKey<dynamic>('dynamic')),
      Text('subclass key', key: _StringValueKey('subclass')),
      Focus(
        key: ValueKey<String>('focused'),
        autofocus: true,
        child: Text('focus child'),
      ),
    ],
  );
}

class _StringValueKey extends ValueKey<String> {
  const _StringValueKey(super.value);
}

List<Map<String, Object?>> _flattenDriverNodes(Map<String, Object?> root) {
  final nodes = <Map<String, Object?>>[];
  void visit(Map<String, Object?> node) {
    nodes.add(node);
    for (final child in (node['children']! as List<Object?>)) {
      visit(child! as Map<String, Object?>);
    }
  }

  visit(root);
  return nodes;
}

String _encodedClick(int x, int y) => base64Encode(
  utf8.encode('\x1b[<0;${x + 1};${y + 1}M\x1b[<0;${x + 1};${y + 1}m'),
);

class _ScrollHitScene extends StatefulWidget {
  const _ScrollHitScene();

  @override
  State<_ScrollHitScene> createState() => _ScrollHitSceneState();
}

class _ScrollHitSceneState extends State<_ScrollHitScene> {
  final ScrollController _controller = ScrollController(initialOffset: 2);
  var _clicks = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollBox(
    controller: _controller,
    showScrollbar: false,
    child: Column(
      children: <Widget>[
        PointerListener(
          key: const ValueKey<String>('offscreen'),
          onPointerDown: (_) {},
          child: const SizedBox(width: 8, height: 1, child: Text('offscreen')),
        ),
        const SizedBox(width: 8, height: 1, child: Text('spacer')),
        PointerListener(
          key: const ValueKey<String>('scrolled-target'),
          onPointerDown: (_) => setState(() => _clicks++),
          child: SizedBox(width: 8, height: 1, child: Text('clicked $_clicks')),
        ),
        const SizedBox(width: 8, height: 1, child: Text('tail')),
      ],
    ),
  );
}

class _OverlapHitScene extends StatefulWidget {
  const _OverlapHitScene();

  @override
  State<_OverlapHitScene> createState() => _OverlapHitSceneState();
}

class _OverlapHitSceneState extends State<_OverlapHitScene> {
  var _behindClicks = 0;

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned(
        left: 0,
        top: 0,
        width: 6,
        height: 3,
        child: PointerListener(
          key: const ValueKey<String>('behind'),
          onPointerDown: (_) => setState(() => _behindClicks++),
          child: Container(child: Text('behind $_behindClicks')),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: 2,
        height: 1,
        child: PointerListener(
          key: const ValueKey<String>('hidden'),
          onPointerDown: (_) {},
          child: const Text('xx'),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: 4,
        height: 3,
        child: PointerListener(
          key: const ValueKey<String>('overlay'),
          onPointerDown: (_) {},
          child: const Text('over'),
        ),
      ),
    ],
  );
}

class _AncestorVisibilityScene extends StatefulWidget {
  const _AncestorVisibilityScene();

  @override
  State<_AncestorVisibilityScene> createState() =>
      _AncestorVisibilitySceneState();
}

class _AncestorVisibilitySceneState extends State<_AncestorVisibilityScene> {
  final ScrollController _controller = ScrollController(initialOffset: 2);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollBox(
    controller: _controller,
    showScrollbar: false,
    child: PointerListener(
      key: const ValueKey<String>('content-target'),
      onPointerDown: (_) {},
      child: const Column(
        children: <Widget>[
          Text('offscreen', key: ValueKey<String>('offscreen-label')),
          Text('spacer'),
          Text('visible', key: ValueKey<String>('visible-label')),
          Text('tail'),
        ],
      ),
    ),
  );
}

class _ObscuredDescendantScene extends StatelessWidget {
  const _ObscuredDescendantScene();

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned(
        left: 0,
        top: 0,
        width: 6,
        height: 2,
        child: PointerListener(
          key: const ValueKey<String>('partly-visible'),
          onPointerDown: (_) {},
          child: const Stack(
            children: <Widget>[
              Positioned(
                left: 0,
                top: 0,
                width: 2,
                height: 1,
                child: Text('xx', key: ValueKey<String>('obscured-label')),
              ),
              Positioned(
                left: 4,
                top: 0,
                width: 2,
                height: 1,
                child: Text('ok', key: ValueKey<String>('visible-label')),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 0,
        top: 0,
        width: 4,
        height: 2,
        child: PointerListener(
          onPointerDown: (_) {},
          child: const SizedBox(width: 4, height: 2),
        ),
      ),
    ],
  );
}

class _TransparentSiblingScene extends StatelessWidget {
  const _TransparentSiblingScene();

  @override
  Widget build(BuildContext context) => Stack(
    children: <Widget>[
      Positioned(
        left: 0,
        top: 0,
        width: 6,
        height: 2,
        child: PointerListener(
          key: const ValueKey<String>('behind-transparent'),
          onPointerDown: (_) {},
          child: const SizedBox(width: 6, height: 2),
        ),
      ),
      const Positioned(
        left: 0,
        top: 0,
        width: 2,
        height: 1,
        child: Text('xx', key: ValueKey<String>('transparent-label')),
      ),
    ],
  );
}

class _NonPointerParentScene extends StatelessWidget {
  const _NonPointerParentScene();

  @override
  Widget build(BuildContext context) => Column(
    key: const ValueKey<String>('non-pointer-parent'),
    children: <Widget>[
      PointerListener(
        key: const ValueKey<String>('first-child'),
        onPointerDown: (_) {},
        child: const SizedBox(width: 6, height: 1),
      ),
      PointerListener(
        key: const ValueKey<String>('second-child'),
        onPointerDown: (_) {},
        child: const SizedBox(width: 6, height: 1),
      ),
    ],
  );
}

/// Official low-level leaf: a [RenderObject] that is not a [RenderBox] and
/// still receives pointer events by adding itself to [HitTestResult.path].
class _CustomHitTargetWidget extends RenderObjectWidget {
  const _CustomHitTargetWidget({required this.onPointerDown, super.key});

  final MouseEventHandler onPointerDown;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CustomHitTarget(onPointerDown: onPointerDown);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _CustomHitTarget renderObject,
  ) {
    renderObject.onPointerDown = onPointerDown;
  }
}

class _CustomHitTarget extends RenderObject implements HitTestTarget {
  _CustomHitTarget({required this.onPointerDown});

  MouseEventHandler onPointerDown;

  @override
  void performLayout(Constraints constraints) {
    width = 3;
    height = 2;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}

  @override
  bool hitTest(HitTestResult result, Offset position) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx >= width ||
        position.dy >= height) {
      return false;
    }
    result.add(HitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {
    if (event.type == MouseEventType.down) {
      onPointerDown(event);
    }
  }
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int _count = 0;

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.isPress && event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _count++);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _handleKey,
    child: Text('count $_count'),
  );
}

/// Never settles: an active ticker requests the next frame from inside the
/// current one, which is exactly the continuously animating app that
/// `waitStable` must report as unstable.
class _Repainter extends StatefulWidget {
  const _Repainter();

  @override
  State<_Repainter> createState() => _RepainterState();
}

class _RepainterState extends State<_Repainter>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {})..start();
  }

  @override
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('animating');
}

class _QuitOnQ extends StatelessWidget {
  const _QuitOnQ();

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event.isPress && event.character == 'q') {
        TuiApp.exit(context);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: const Text('q'),
  );
}
