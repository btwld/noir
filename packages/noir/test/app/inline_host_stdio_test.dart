@Tags(['safe-process-spawning'])
@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test('a live row reaches only its sink and lets the process end', () async {
    // Process.run completing is itself the assertion that the host left no
    // timer or signal watcher behind: the probe never calls exit.
    final result = await Process.run(
      Platform.resolvedExecutable,
      <String>['run', 'test/fixtures/inline_host_stdio_probe.dart'],
      workingDirectory: Directory.current.path,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    final stdoutText = result.stdout as String;
    final stderrText = result.stderr as String;
    expect(result.exitCode, 0, reason: '$stdoutText\n$stderrText');

    // `dart run` reports build-hook progress itself, on stdout or on stderr
    // depending on the SDK, and with no line break after it.
    final hookProgress = RegExp(r'Running (build|link) hooks\.\.\.');
    expect(
      stdoutText.replaceAll(hookProgress, ''),
      isEmpty,
      reason: 'the host must never write to stdout',
    );

    final firstFrame = '\r${SpinnerFrames.dots.first} working\x1b[K';
    expect(stderrText, contains(firstFrame));
    expect(stderrText, contains('\r\x1b[Kstep done\n'));
    expect(stderrText, endsWith('\r\x1b[K'));
  });
}
