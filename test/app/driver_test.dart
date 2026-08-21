import 'dart:convert';
import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;
import 'package:noir/src/app/driver.dart';
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
      expect(ack, <String, Object?>{'type': 'Success', 'bytes': 3});

      await host.waitStable();
      expect(host.capture()['lines'], <String>['count 1']);
    });

    test('tree reports the mounted root widget', () {
      final host = DriverHost.create(width: 12, height: 1);
      addTearDown(host.dispose);
      host.binding
        ..runApp(const _Counter())
        ..debugFlushFrame();

      final tree = host.tree();
      expect(tree['type'], 'Success');
      expect(tree['maxDepth'], 2);
      final lines = (tree['lines']! as List<Object?>).cast<String>();
      expect(lines, isNotEmpty);
      expect(lines.first, contains('_Counter'));
    });

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

      expect(host.resize(24, 4), <String, Object?>{
        'type': 'Success',
        'width': 24,
        'height': 4,
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
