@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

void main() {
  test(
    'NOIR_DRIVE drives an unmodified consumer app over the VM service',
    () async {
      final packageRoot = Directory.current.resolveSymbolicLinksSync();
      final consumer = await Directory.systemTemp.createTemp(
        'noir_driver_consumer_',
      );
      addTearDown(() => _deleteTempDirectory(consumer));

      await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: noir_driver_consumer
publish_to: none

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  noir:
    path: ${jsonEncode(packageRoot)}
''');

      // Deliberately ordinary: `main()` calls `runTuiApp` and nothing else,
      // which is what makes drive mode zero-modification for every example
      // and consumer app.
      final entryPoint = File('${consumer.path}/bin/app.dart')
        ..parent.createSync(recursive: true);
      await entryPoint.writeAsString(r'''
import 'dart:typed_data';

import 'package:noir/noir.dart';

void main() {
  runTuiApp(const Probe());
}

class Probe extends StatefulWidget {
  const Probe({super.key});

  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  static final Uint8List _pixels = Uint8List.fromList(<int>[
    255, 0, 0, 255,
    0, 255, 0, 255,
  ]);
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('COUNT $_count'),
        Image.rgba(
          _pixels,
          pixelWidth: 2,
          pixelHeight: 1,
          rowStride: 8,
          width: 4,
          height: 2,
        ),
      ],
    ),
  );
}
''');

      final pubGet = await Process.run(Platform.resolvedExecutable, <String>[
        'pub',
        'get',
        '--offline',
      ], workingDirectory: consumer.path);
      expect(
        pubGet.exitCode,
        0,
        reason: 'stdout:\n${pubGet.stdout}\n\nstderr:\n${pubGet.stderr}',
      );

      final serviceInfo = File('${consumer.path}/service_info.json');
      final process = await Process.start(
        Platform.resolvedExecutable,
        <String>[
          'run',
          '--enable-vm-service=0',
          '--write-service-info=${serviceInfo.path}',
          'bin/app.dart',
        ],
        workingDirectory: consumer.path,
        environment: <String, String>{
          'NOIR_DRIVE': '1',
          'NOIR_DRIVE_SIZE': '24x3',
        },
      );
      var exited = false;
      final childExit = process.exitCode.whenComplete(() => exited = true);
      addTearDown(() async {
        process.kill(ProcessSignal.sigkill);
        // Await the exit rather than just signalling it. Windows refuses to
        // delete a directory another process still holds a handle in, and the
        // child runs `bin/app.dart` from inside the temp directory a later
        // teardown deletes.
        await childExit;
      });

      final diagnostics = StringBuffer();
      for (final stream in <Stream<List<int>>>[
        process.stdout,
        process.stderr,
      ]) {
        stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(diagnostics.writeln);
      }

      final service = await _connect(serviceInfo, diagnostics);
      addTearDown(service.dispose);
      final isolateId = (await service.getVM()).isolates!.single.id!;

      final info = await _waitForDriver(service, isolateId);
      expect(info['driveMode'], isTrue, reason: '$diagnostics');
      expect(info['width'], 24);
      expect(info['height'], 3);

      await _call(service, isolateId, 'waitStable');
      final before = await _call(service, isolateId, 'capture');
      final beforeLines = (before['lines']! as List<Object?>).cast<String>();
      expect(beforeLines, contains('COUNT 0'), reason: '$diagnostics');
      expect(beforeLines, contains('▀▀▀▀'), reason: '$diagnostics');

      await _call(
        service,
        isolateId,
        'sendBytes',
        args: <String, Object?>{'bytes': base64Encode(utf8.encode('\x1b[A'))},
      );
      await _call(service, isolateId, 'waitStable');

      final after = await _call(service, isolateId, 'capture');
      final afterLines = (after['lines']! as List<Object?>).cast<String>();
      expect(
        afterLines,
        isNot(beforeLines),
        reason: 'the injected arrow key must repaint the app\n$diagnostics',
      );
      expect(afterLines, contains('COUNT 1'), reason: '$diagnostics');
      expect(afterLines, contains('▀▀▀▀'), reason: '$diagnostics');

      final resized = await _call(
        service,
        isolateId,
        'resize',
        args: <String, Object?>{'width': 12, 'height': 4},
      );
      expect(resized['width'], 12);
      expect(resized['height'], 4);
      await _call(service, isolateId, 'waitStable');
      final resizedCapture = await _call(service, isolateId, 'capture');
      expect(resizedCapture['width'], 12);
      expect(
        (resizedCapture['lines']! as List<Object?>).cast<String>(),
        contains('▀▀▀▀'),
      );

      final quit = await _call(service, isolateId, 'quit');
      expect(quit['quitting'], isTrue);
      expect(
        await childExit.timeout(const Duration(seconds: 30)),
        0,
        reason: 'quit must end the driven process cleanly\n$diagnostics',
      );
      expect(exited, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

/// Polls `info` until the driven app has registered `ext.noir.driver.*`.
///
/// The VM publishes its service URI before `main()` runs, so a driver that
/// connects promptly gets "method not found" for a moment.
Future<Map<String, dynamic>> _waitForDriver(
  VmService service,
  String isolateId,
) async {
  const methodNotFound = -32601;
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (true) {
    try {
      return await _call(service, isolateId, 'info');
    } on RPCError catch (error) {
      if (error.code != methodNotFound || !DateTime.now().isBefore(deadline)) {
        rethrow;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<Map<String, dynamic>> _call(
  VmService service,
  String isolateId,
  String method, {
  Map<String, Object?>? args,
}) async {
  final response = await service.callServiceExtension(
    'ext.noir.driver.$method',
    isolateId: isolateId,
    args: args,
  );
  final json = response.json;
  expect(json, isNotNull, reason: 'ext.noir.driver.$method returned no JSON');
  expect(json!['type'], 'Success', reason: 'ext.noir.driver.$method: $json');
  return json;
}

Future<VmService> _connect(File serviceInfo, StringBuffer diagnostics) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    if (serviceInfo.existsSync()) {
      final contents = serviceInfo.readAsStringSync();
      if (contents.isNotEmpty) {
        // `--write-service-info` writes `{"uri":"http://host:port/token/"}`.
        final uri = (jsonDecode(contents) as Map<String, Object?>)['uri'];
        if (uri is String && uri.isNotEmpty) {
          return vmServiceConnectUri(
            convertToWebSocketUrl(
              serviceProtocolUrl: Uri.parse(uri),
            ).toString(),
          );
        }
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError(
    'The child VM never published ${serviceInfo.path}\n$diagnostics',
  );
}

/// Removes [directory], retrying briefly while the filesystem still refuses.
///
/// The child process has already exited by the time this runs, but Windows can
/// hold its handles a moment longer, which surfaces as a `FileSystemException`.
/// A temp directory that outlives the run is not worth failing a green driver
/// result over, so this gives up quietly once the retries are spent.
Future<void> _deleteTempDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (!directory.existsSync()) {
      return;
    }
    try {
      await directory.delete(recursive: true);
      return;
    } on FileSystemException {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}
