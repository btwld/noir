@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  late Directory consumer;

  setUpAll(() async {
    final packageRoot = Directory.current.resolveSymbolicLinksSync();
    consumer = await Directory.systemTemp.createTemp('noir_run_consumer_');
    await File('${consumer.path}/pubspec.yaml').writeAsString('''
name: noir_run_consumer
publish_to: none

environment:
  sdk: '>=3.10.0 <4.0.0'

dependencies:
  noir:
    path: ${jsonEncode(packageRoot)}
''');
    final pubGet = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: consumer.path);
    expect(
      pubGet.exitCode,
      0,
      reason: 'stdout:\n${pubGet.stdout}\n\nstderr:\n${pubGet.stderr}',
    );

    final exitProbe = File('${consumer.path}/bin/exit_probe.dart');
    await exitProbe.parent.create(recursive: true);
    await exitProbe.writeAsString(r'''
import 'dart:io';

void main(List<String> arguments) {
  stdout.writeln('ARGS:${arguments.join('|')}');
  exitCode = 23;
}
''');

    final label = File('${consumer.path}/lib/label.dart');
    await label.parent.create(recursive: true);
    await label.writeAsString("String frameLabel() => 'before';\n");
    await File('${consumer.path}/bin/reload_probe.dart').writeAsString(r'''
import 'dart:async';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir_run_consumer/label.dart';

late final Timer keepAlive;

void main() {
  runTuiApp(const Probe(), headless: true);
  keepAlive = Timer.periodic(const Duration(seconds: 1), (_) {});
}

class Probe extends StatelessWidget {
  const Probe();

  @override
  Widget build(BuildContext context) {
    final label = frameLabel();
    stdout.writeln('FRAME:$label');
    if (label == 'after') {
      Timer.run(() {
        keepAlive.cancel();
        TuiApp.exit(context, code: 17);
      });
    }
    return const SizedBox();
  }
}
''');
  });

  tearDownAll(() async {
    if (consumer.existsSync()) {
      await consumer.delete(recursive: true);
    }
  });

  test('packaged run command reports usage without an entry point', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'noir:run',
    ], workingDirectory: consumer.path);

    expect(result.exitCode, 64);
    expect(
      result.stderr,
      contains(
        'Usage: dart run noir:run <entry-point.dart> [app arguments...]',
      ),
    );
  });

  test('packaged run command rejects a missing entry point', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'noir:run',
      'bin/missing.dart',
    ], workingDirectory: consumer.path);

    expect(result.exitCode, 66);
    expect(result.stderr, contains('No such entry point: bin/missing.dart'));
  });

  test('packaged run command forwards arguments and child exit code', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      'noir:run',
      'bin/exit_probe.dart',
      'alpha',
      'beta',
    ], workingDirectory: consumer.path);

    expect(
      result.exitCode,
      23,
      reason: 'stdout:\n${result.stdout}\n\nstderr:\n${result.stderr}',
    );
    expect(result.stdout, contains('ARGS:alpha|beta'));
    final log = File('${consumer.path}/.dart_tool/noir/run.log');
    expect(
      result.stderr,
      contains(
        'Noir hot reload diagnostics: ${log.resolveSymbolicLinksSync()}',
      ),
    );
    expect(log.existsSync(), isTrue);
    expect(log.readAsStringSync(), contains('launching bin/exit_probe.dart'));
  });

  test(
    'packaged run command reloads, reassembles, and returns the app code',
    () async {
      final label = File('${consumer.path}/lib/label.dart');
      await label.writeAsString("String frameLabel() => 'before';\n");
      final runner = await _RunningProbe.start(consumer);
      addTearDown(runner.stop);

      await _waitUntil(
        () => runner.frames.contains('FRAME:before'),
        what: 'the initial frame',
        diagnostics: runner.output,
      );
      final log = File('${consumer.path}/.dart_tool/noir/run.log');
      await _waitUntil(
        () => log.existsSync() && log.readAsStringSync().contains('watching '),
        what: 'the source watcher',
        diagnostics: runner.output,
      );

      await label.writeAsString("String frameLabel() => 'after';\n");
      await _waitUntil(
        () => runner.frames.contains('FRAME:after'),
        what: 'the reassembled frame',
        diagnostics: runner.output,
      );

      expect(await runner.exitCode, 17, reason: runner.output.toString());
      expect(
        runner.frames,
        containsAllInOrder(['FRAME:before', 'FRAME:after']),
      );
      expect(log.readAsStringSync(), contains('reloaded'));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'packaged run command keeps the last good app after a rejected reload',
    () async {
      final label = File('${consumer.path}/lib/label.dart');
      await label.writeAsString("String frameLabel() => 'before';\n");
      final runner = await _RunningProbe.start(consumer);
      addTearDown(runner.stop);

      await _waitUntil(
        () => runner.frames.contains('FRAME:before'),
        what: 'the initial frame',
        diagnostics: runner.output,
      );
      final log = File('${consumer.path}/.dart_tool/noir/run.log');
      await _waitUntil(
        () => log.existsSync() && log.readAsStringSync().contains('watching '),
        what: 'the source watcher',
        diagnostics: runner.output,
      );

      await label.writeAsString('String frameLabel() => ;\n');
      await _waitUntil(
        () => log.readAsStringSync().contains('reload rejected'),
        what: 'the rejected reload diagnostic',
        diagnostics: runner.output,
      );
      expect(runner.hasExited, isFalse, reason: runner.output.toString());

      await label.writeAsString("String frameLabel() => 'after';\n");
      await _waitUntil(
        () => runner.frames.contains('FRAME:after'),
        what: 'recovery after the rejected reload',
        diagnostics: runner.output,
      );

      expect(await runner.exitCode, 17, reason: runner.output.toString());
      expect(log.readAsStringSync(), contains('reloaded'));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

class _RunningProbe {
  _RunningProbe._(this.process) {
    exitCode = process.exitCode.then((code) {
      hasExited = true;
      return code;
    });
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          output.writeln(line);
          final frameStart = line.indexOf('FRAME:');
          if (frameStart >= 0) {
            frames.add(line.substring(frameStart));
          }
        });
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(output.writeln);
  }

  static Future<_RunningProbe> start(Directory consumer) async {
    final process = await Process.start(Platform.resolvedExecutable, [
      'run',
      'noir:run',
      'bin/reload_probe.dart',
    ], workingDirectory: consumer.path);
    return _RunningProbe._(process);
  }

  final Process process;
  final StringBuffer output = StringBuffer();
  final List<String> frames = <String>[];
  late final Future<int> exitCode;
  bool hasExited = false;

  Future<void> stop() async {
    if (hasExited) {
      return;
    }
    process.kill(ProcessSignal.sigint);
    try {
      await exitCode.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      await exitCode;
    }
  }
}

Future<void> _waitUntil(
  bool Function() condition, {
  required String what,
  required StringBuffer diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for $what.\n$diagnostics');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
