// ignore_for_file: prefer_constructors_over_static_methods
// Minimal Dart vs Baseline comparator.
// Usage:
//   dart run bin/parity_compare.dart --scenes S1,S2,S3 --width 20 --height 5
// Environment:
//   GO_SNAPSHOT_CMD: optional command to run the Go snapshotter, e.g.
//     "./scripts/run_go_snapshot.sh".
//   If not set, we print a SKIP notice and exit 0 (tests can decide to skip).

import 'dart:convert';
import 'dart:io' as io;

Future<void> main(List<String> args) async {
  final argz = _Args.parse(args);
  final scenes = argz.scenes
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  final hasGo = io.Platform.environment.containsKey('GO_SNAPSHOT_CMD');
  if (!hasGo) {
    io.stdout.writeln(
      'SKIP: GO_SNAPSHOT_CMD is not set; baseline unavailable.',
    );
    io.exit(0);
  }
  final goCmd = io.Platform.environment['GO_SNAPSHOT_CMD']!;

  var failures = 0;
  for (final scene in scenes) {
    final dartJson = await _runAndParse([
      'dart',
      'run',
      'bin/snapshot_scenes.dart',
      '--scene',
      scene,
      '--width',
      '${argz.width}',
      '--height',
      '${argz.height}',
    ], name: 'dart:$scene');

    final goArgs = [
      ...goCmd.split(' '),
      '--scene',
      scene,
      '--width',
      '${argz.width}',
      '--height',
      '${argz.height}',
    ];
    final goJson = await _runAndParse(goArgs, name: 'go:$scene');

    final ok = _compare(dartJson, goJson, tolerance: 1e-6);
    if (!ok) {
      failures++;
      io.stderr.writeln('FAIL: $scene');
    } else {
      io.stdout.writeln('PASS: $scene');
    }
  }

  if (failures > 0) io.exit(1);
}

Future<Map<String, dynamic>> _runAndParse(
  List<String> cmd, {
  required String name,
}) async {
  final proc = await io.Process.run(cmd.first, cmd.sublist(1));
  if (proc.exitCode != 0) {
    throw io.ProcessException(
      cmd.first,
      cmd.sublist(1),
      'Exit ${proc.exitCode} for $name. Stderr: ${proc.stderr}',
      proc.exitCode,
    );
  }
  final text = proc.stdout is String
      ? proc.stdout as String
      : String.fromCharCodes(proc.stdout as List<int>);
  return parseSnapshotJsonForTest(text);
}

/// Parses the snapshot JSON object from process stdout.
///
/// Exposed for regression tests because `dart run` can print build-hook status
/// before the snapshot payload.
Map<String, dynamic> parseSnapshotJsonForTest(String text) =>
    _parseSnapshotJson(text);

Map<String, dynamic> _parseSnapshotJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end < start) {
    throw FormatException(
      'Snapshot stdout did not contain a JSON object',
      text,
    );
  }
  final payload = text.substring(start, end + 1);
  final decoded = jsonDecode(payload);
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('Snapshot JSON was not an object', payload);
  }
  return decoded;
}

bool _compare(
  Map<String, dynamic> a,
  Map<String, dynamic> b, {
  double tolerance = 0.0,
}) {
  bool rgbaComponentMatches(
    String path,
    List<double> left,
    List<double> right,
    int component,
  ) {
    if ((left[component] - right[component]).abs() > tolerance) {
      return _diff('$path[$component]', left[component], right[component]);
    }
    return true;
  }

  if (a['version'] != b['version']) {
    return _diff('version', a['version'], b['version']);
  }
  if (a['width'] != b['width']) return _diff('width', a['width'], b['width']);
  if (a['height'] != b['height']) {
    return _diff('height', a['height'], b['height']);
  }

  final ac = a['cells'] as List<dynamic>;
  final bc = b['cells'] as List<dynamic>;
  if (ac.length != bc.length) {
    return _diff('cells.length', ac.length, bc.length);
  }

  for (var i = 0; i < ac.length; i++) {
    final ca = ac[i] as Map<String, dynamic>;
    final cb = bc[i] as Map<String, dynamic>;
    if (ca['ch'] != cb['ch']) return _diff('cells[$i].ch', ca['ch'], cb['ch']);
    final fga = (ca['fg'] as List).map((e) => (e as num).toDouble()).toList();
    final fgb = (cb['fg'] as List).map((e) => (e as num).toDouble()).toList();
    final bga = (ca['bg'] as List).map((e) => (e as num).toDouble()).toList();
    final bgb = (cb['bg'] as List).map((e) => (e as num).toDouble()).toList();
    for (var k = 0; k < 4; k++) {
      if (!rgbaComponentMatches('cells[$i].fg', fga, fgb, k)) return false;
      if (!rgbaComponentMatches('cells[$i].bg', bga, bgb, k)) return false;
    }
  }
  return true;
}

bool _diff(String path, Object? a, Object? b) {
  io.stderr.writeln('DIFF at $path: $a != $b');
  return false;
}

class _Args {
  _Args(this.scenes, this.width, this.height);
  final String scenes;
  final int width;
  final int height;

  static _Args parse(List<String> args) {
    var scenes = 'S1,S2,S3';
    var width = 20;
    var height = 5;
    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--scenes' && i + 1 < args.length) scenes = args[++i];
      if (a == '--width' && i + 1 < args.length) width = int.parse(args[++i]);
      if (a == '--height' && i + 1 < args.length) height = int.parse(args[++i]);
    }
    return _Args(scenes, width, height);
  }
}
