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
    'a real reloadSources plus ext.noir.reassemble changes rendered output',
    () async {
      final packageRoot = Directory.current.resolveSymbolicLinksSync();
      final consumer = await Directory.systemTemp.createTemp(
        'noir_hot_reload_consumer_',
      );
      addTearDown(() async {
        if (consumer.existsSync()) {
          await consumer.delete(recursive: true);
        }
      });

      await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: noir_hot_reload_consumer
publish_to: none

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  noir:
    path: ${jsonEncode(packageRoot)}
''');

      // A top-level function body is the guaranteed `reloadSources` swap. The
      // pivot must not be a `const`, whose value is baked into every user.
      final label = File('${consumer.path}/lib/label.dart')
        ..parent.createSync(recursive: true);
      await label.writeAsString("String frameLabel() => 'before';\n");

      final entryPoint = File('${consumer.path}/bin/app.dart')
        ..parent.createSync(recursive: true);
      await entryPoint.writeAsString(r'''
import 'dart:async';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir_hot_reload_consumer/label.dart';

void main() {
  final app = runTuiApp(const Probe(), headless: true);
  registerHotReloadExtension(app);
  // A headless session owns no stdin and no signal handler, so hold the event
  // loop open for the driver instead of letting the isolate drain and exit.
  Timer.periodic(const Duration(milliseconds: 50), (_) {});
}

class Probe extends StatelessWidget {
  const Probe();

  @override
  Widget build(BuildContext context) {
    stdout.writeln('FRAME:${frameLabel()}');
    return const SizedBox();
  }
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
      final process = await Process.start(Platform.resolvedExecutable, <String>[
        'run',
        '--enable-vm-service=0',
        '--write-service-info=${serviceInfo.path}',
        'bin/app.dart',
      ], workingDirectory: consumer.path);
      addTearDown(() => process.kill(ProcessSignal.sigkill));

      final diagnostics = StringBuffer();
      final frames = <String>[];
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(diagnostics.writeln);
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            diagnostics.writeln(line);
            if (line.startsWith('FRAME:')) {
              frames.add(line);
            }
          });

      await _waitForFrames(
        frames,
        atLeast: 1,
        timeout: const Duration(seconds: 90),
        what: 'the child app to render its first frame',
        diagnostics: diagnostics,
      );
      expect(frames.single, 'FRAME:before');

      final service = await _connect(serviceInfo);
      addTearDown(service.dispose);
      final vm = await service.getVM();
      final isolateId = vm.isolates!.single.id!;

      await label.writeAsString("String frameLabel() => 'after';\n");
      final report = await service.reloadSources(isolateId);
      expect(
        report.success,
        isTrue,
        reason: 'reloadSources rejected the edit: $report\n$diagnostics',
      );

      // A source swap alone must not repaint: the app settled and nothing
      // marks the tree dirty. This is what makes the assertion below a proof
      // that reassemble rebuilt the tree, not that the VM accepted a patch.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        frames,
        hasLength(1),
        reason: 'reloadSources alone must not schedule a frame\n$diagnostics',
      );

      await service.callServiceExtension(
        'ext.noir.reassemble',
        isolateId: isolateId,
      );

      await _waitForFrames(
        frames,
        atLeast: 2,
        timeout: const Duration(seconds: 30),
        what: 'the reassembled frame',
        diagnostics: diagnostics,
      );
      expect(
        frames[1],
        'FRAME:after',
        reason: 'the reloaded build() body must render without a restart',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

Future<void> _waitForFrames(
  List<String> frames, {
  required int atLeast,
  required Duration timeout,
  required String what,
  required StringBuffer diagnostics,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (frames.length < atLeast) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what.\nchild output:\n$diagnostics');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

Future<VmService> _connect(File serviceInfo) async {
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
  throw StateError('The child VM never published ${serviceInfo.path}');
}
