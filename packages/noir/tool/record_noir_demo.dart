#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:noir/noir.dart' show Attr;

import 'driver/ansi_keys.dart';
import 'driver/noir_driver.dart';

const _usage =
    'Usage: dart run tool/record_noir_demo.dart '
    '--recipe <recipe.json> [--force]';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  try {
    final source = await File(options.recipePath).readAsString();
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('The recipe root must be a JSON object.');
    }
    final recipe = RecordingRecipe.fromJson(decoded);
    await recordNoirDemo(recipe, force: options.force);
    stdout.writeln(
      'Recorded ${recipe.title} to ${recipe.output} '
      '(${recipe.width}x${recipe.height}, '
      '${recipe.duration.inMilliseconds}ms at ${recipe.fps}fps).',
    );
  } on FormatException catch (error) {
    stderr.writeln('Invalid recording recipe: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Recording file error: ${error.message}');
    exitCode = 66;
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('Could not record the Noir demo: $error')
      ..writeln(stackTrace);
    exitCode = 70;
  }
}

/// A versioned recipe for one bounded documentation recording.
class RecordingRecipe {
  RecordingRecipe._({
    required this.entrypoint,
    required this.output,
    required this.title,
    required this.width,
    required this.height,
    required this.duration,
    required this.fps,
    required this.actions,
  });

  factory RecordingRecipe.fromJson(Map<String, dynamic> json) {
    final version = _requiredInt(json, 'version');
    if (version != 1) {
      throw FormatException('version must be 1, received $version.');
    }

    final entrypoint = _requiredString(json, 'entrypoint');
    if (!entrypoint.endsWith('.dart')) {
      throw const FormatException('entrypoint must name a .dart file.');
    }

    final output = _requiredString(json, 'output');
    if (!output.endsWith('.cast')) {
      throw const FormatException('output must use the .cast extension.');
    }

    final title = _requiredString(json, 'title');
    final width = _requiredInt(json, 'width');
    final height = _requiredInt(json, 'height');
    if (width <= 0 || height <= 0 || width > 300 || height > 120) {
      throw const FormatException(
        'width and height must be positive and no larger than 300x120.',
      );
    }

    final durationMs = _requiredInt(json, 'durationMs');
    if (durationMs < 100 || durationMs > 60000) {
      throw const FormatException('durationMs must be between 100 and 60000.');
    }

    final fps = _requiredInt(json, 'fps');
    if (fps < 1 || fps > 60) {
      throw const FormatException('fps must be between 1 and 60.');
    }

    final duration = Duration(milliseconds: durationMs);
    final rawActions = json['actions'] ?? const <Object?>[];
    if (rawActions is! List<Object?>) {
      throw const FormatException('actions must be a JSON array.');
    }
    final actions = <RecordingAction>[
      for (final (index, rawAction) in rawActions.indexed)
        RecordingAction.fromJson(_actionMap(rawAction, index)),
    ]..sort((left, right) => left.at.compareTo(right.at));
    for (final action in actions) {
      if (action.at > duration) {
        throw FormatException(
          'action at ${action.at.inMilliseconds}ms exceeds '
          'durationMs $durationMs.',
        );
      }
    }

    return RecordingRecipe._(
      entrypoint: entrypoint,
      output: output,
      title: title,
      width: width,
      height: height,
      duration: duration,
      fps: fps,
      actions: List.unmodifiable(actions),
    );
  }

  final String entrypoint;
  final String output;
  final String title;
  final int width;
  final int height;
  final Duration duration;
  final int fps;
  final List<RecordingAction> actions;
}

enum RecordingActionKind { key, type, clickKey }

/// One input action scheduled relative to the recording start.
class RecordingAction {
  const RecordingAction({
    required this.at,
    required this.kind,
    required this.value,
  });

  factory RecordingAction.fromJson(Map<String, dynamic> json) {
    final atMs = _requiredInt(json, 'atMs');
    if (atMs < 0) {
      throw const FormatException('action atMs must be non-negative.');
    }

    const fields = <String, RecordingActionKind>{
      'key': RecordingActionKind.key,
      'type': RecordingActionKind.type,
      'clickKey': RecordingActionKind.clickKey,
    };
    final present = fields.entries
        .where((entry) => json[entry.key] != null)
        .toList(growable: false);
    if (present.length != 1) {
      throw const FormatException(
        'each action must contain exactly one of key, type, or clickKey.',
      );
    }
    final field = present.single;
    final value = json[field.key];
    if (value is! String || value.isEmpty) {
      throw FormatException('${field.key} must be a non-empty string.');
    }
    if (field.value == RecordingActionKind.key &&
        value.trim().toLowerCase() == 'ctrl-c') {
      throw const FormatException(
        'ctrl-c is reserved for recorder cleanup; omit it from actions.',
      );
    }
    if (field.value == RecordingActionKind.key) {
      encodeKey(value);
    }

    return RecordingAction(
      at: Duration(milliseconds: atMs),
      kind: field.value,
      value: value,
    );
  }

  final Duration at;
  final RecordingActionKind kind;
  final String value;
}

/// Encodes colored drive-mode frames as a self-contained asciicast v2 stream.
class AsciicastEncoder {
  AsciicastEncoder({
    required this.width,
    required this.height,
    required this.title,
    required this.command,
    required this.duration,
  });

  final int width;
  final int height;
  final String title;
  final String command;
  final Duration duration;
  final List<List<Object?>> _events = [];
  DriverFrame? _previousFrame;

  void addFrame(Duration at, DriverFrame frame) {
    if (frame.width != width || frame.height != height) {
      throw StateError(
        'Captured ${frame.width}x${frame.height}; expected ${width}x$height.',
      );
    }
    if (frame.rows.length != height ||
        frame.rows.any((row) => row.length != width)) {
      throw StateError('The capture did not include a complete cell matrix.');
    }
    if (_previousFrame case final previous? when _sameFrame(previous, frame)) {
      return;
    }
    _events.add([
      _seconds(at),
      'o',
      _paintFrame(frame, clear: _previousFrame == null),
    ]);
    _previousFrame = frame;
  }

  void addInput(Duration at, String input) {
    if (input.isEmpty) return;
    _events.add([_seconds(at), 'i', input]);
  }

  /// Records the SGR mouse bytes sent for a click at [point].
  void addClick(Duration at, DriverPoint point) {
    addInput(at, utf8.decode(encodeClick(point.x, point.y)));
  }

  String encode() {
    final durationSeconds = _seconds(duration);
    final events = <List<Object?>>[..._events];
    if (events.isEmpty ||
        (events.last[0]! as num).toDouble() < durationSeconds) {
      // Asciinema Player derives a v2 recording's playback length from its
      // final event, not the optional header duration. Resetting SGR at the
      // recipe boundary leaves the rendered cells unchanged while holding the
      // final frame for the intended amount of time.
      events.add([durationSeconds, 'o', '\x1b[0m']);
    }
    final header = <String, Object?>{
      'version': 2,
      'width': width,
      'height': height,
      'duration': durationSeconds,
      'idle_time_limit': 2.0,
      'command': command,
      'title': title,
      'env': const {'TERM': 'xterm-256color'},
    };
    return <String>[
      jsonEncode(header),
      for (final event in events) jsonEncode(event),
      '',
    ].join('\n');
  }
}

/// Runs [recipe] through Noir's existing non-terminal driver and writes it.
Future<void> recordNoirDemo(
  RecordingRecipe recipe, {
  bool force = false,
}) async {
  final entrypoint = File(recipe.entrypoint);
  if (!entrypoint.existsSync()) {
    throw FileSystemException('Entrypoint does not exist', entrypoint.path);
  }

  final output = File(recipe.output);
  if (output.existsSync() && !force) {
    throw FileSystemException(
      'Output already exists; pass --force to replace it',
      output.path,
    );
  }
  await output.parent.create(recursive: true);

  final encoder = AsciicastEncoder(
    width: recipe.width,
    height: recipe.height,
    title: recipe.title,
    command: 'NoirDriver (NOIR_DRIVE=1): ${recipe.entrypoint}',
    duration: recipe.duration,
  );
  final driver = await NoirDriver.launch(
    recipe.entrypoint,
    width: recipe.width,
    height: recipe.height,
  );

  var appExitCode = -1;
  try {
    final stopwatch = Stopwatch()..start();
    final frameCount =
        (recipe.duration.inMicroseconds *
                recipe.fps /
                Duration.microsecondsPerSecond)
            .ceil();
    var actionIndex = 0;
    for (var frameIndex = 0; frameIndex <= frameCount; frameIndex++) {
      final targetMicros = frameIndex == frameCount
          ? recipe.duration.inMicroseconds
          : (frameIndex * Duration.microsecondsPerSecond / recipe.fps).round();
      final target = Duration(microseconds: targetMicros);
      final remaining = target - stopwatch.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }

      while (actionIndex < recipe.actions.length &&
          recipe.actions[actionIndex].at <= target) {
        final action = recipe.actions[actionIndex++];
        await _performAction(driver, encoder, action);
      }
      encoder.addFrame(target, await driver.captureCells());
    }
  } finally {
    appExitCode = await driver.quit();
  }
  requireSuccessfulAppExit(appExitCode, recipe.entrypoint);

  await writeRecordingArtifact(output, encoder.encode(), force: force);
}

/// Fails a recording whose driven application did not shut down cleanly.
void requireSuccessfulAppExit(int exitCode, String entrypoint) {
  if (exitCode == 0) return;
  throw ProcessException(
    Platform.resolvedExecutable,
    <String>['run', entrypoint],
    'The driven Noir application exited with a non-zero status.',
    exitCode,
  );
}

/// Publishes [contents] without overwriting an artifact unless [force] is set.
///
/// The complete payload is flushed to a unique sibling before publication.
/// Without [force], an exclusive destination reservation closes the race
/// between the recorder's initial existence check and the final write. With
/// [force], an existing artifact moves to a recovery sibling first and is
/// restored if publishing the replacement fails.
Future<void> writeRecordingArtifact(
  File output,
  String contents, {
  required bool force,
  Future<File> Function(File source, String destination)? renameFile,
}) async {
  await output.parent.create(recursive: true);
  final rename = renameFile ?? _renameFile;
  final partial = File(
    '${output.path}.partial.$pid.${DateTime.now().microsecondsSinceEpoch}',
  );
  File? backup;
  var reservedOutput = false;
  try {
    await partial.create(exclusive: true);
    await partial.writeAsString(contents, flush: true);
    if (!force) {
      await output.create(exclusive: true);
      reservedOutput = true;
    } else if (output.existsSync()) {
      backup = File(
        '${output.path}.backup.$pid.${DateTime.now().microsecondsSinceEpoch}',
      );
      await rename(output, backup.path);
    }
    try {
      await rename(partial, output.path);
    } on Object catch (publishError, publishStackTrace) {
      final previous = backup;
      if (previous != null && previous.existsSync()) {
        try {
          await rename(previous, output.path);
          backup = null;
        } on Object catch (restoreError) {
          throw FileSystemException(
            'Could not publish the replacement or restore the previous '
            'recording. The previous recording remains at ${previous.path}. '
            'Publish error: $publishError. Restore error: $restoreError',
            output.path,
          );
        }
      }
      Error.throwWithStackTrace(publishError, publishStackTrace);
    }
    reservedOutput = false;
    final previous = backup;
    if (previous != null && previous.existsSync()) {
      await previous.delete();
      backup = null;
    }
  } on Object {
    if (partial.existsSync()) {
      await partial.delete();
    }
    if (reservedOutput && output.existsSync()) {
      await output.delete();
    }
    rethrow;
  }
}

Future<File> _renameFile(File source, String destination) =>
    source.rename(destination);

Future<void> _performAction(
  NoirDriver driver,
  AsciicastEncoder encoder,
  RecordingAction action,
) async {
  switch (action.kind) {
    case RecordingActionKind.key:
      final bytes = encodeKey(action.value);
      encoder.addInput(action.at, utf8.decode(bytes));
      await driver.sendKey(action.value);
    case RecordingActionKind.type:
      encoder.addInput(action.at, action.value);
      await driver.typeText(action.value);
    case RecordingActionKind.clickKey:
      final locator = DriverLocator.byKey(action.value);
      final node = await driver.find(locator);
      final point = node.actionPoint;
      if (point == null) {
        throw StateError(
          'Cannot click $locator: the match is offscreen, fully obscured, or '
          'has no visible pointer route. Match: $node',
        );
      }
      encoder.addClick(action.at, point);
      await driver.click(point.x, point.y);
  }
}

String _paintFrame(DriverFrame frame, {required bool clear}) {
  final output = StringBuffer('\x1b[?25l');
  if (clear) {
    output.write('\x1b[2J');
  }
  for (var y = 0; y < frame.rows.length; y++) {
    output.write('\x1b[${y + 1};1H');
    DriverCell? style;
    for (final cell in frame.rows[y]) {
      if (style == null || !_sameStyle(style, cell)) {
        output.write(_sgr(cell));
        style = cell;
      }
      if (cell.char.isNotEmpty) {
        output.write(cell.char);
      }
    }
  }
  output.write('\x1b[0m');
  output
    ..write('\x1b]12;${frame.cursor.color.toAnsiHex()}\x1b\\')
    ..write('\x1b[${_cursorShapeCode(frame.cursor)} q')
    ..write('\x1b[${frame.cursor.y + 1};${frame.cursor.x + 1}H')
    ..write(frame.cursor.visible ? '\x1b[?25h' : '\x1b[?25l');
  return output.toString();
}

int _cursorShapeCode(DriverCursor cursor) => switch (cursor.style) {
  'block' => cursor.blinking ? 1 : 2,
  'underline' => cursor.blinking ? 3 : 4,
  'bar' => cursor.blinking ? 5 : 6,
  final style => throw StateError('Unsupported cursor style "$style".'),
};

String _sgr(DriverCell cell) {
  final codes = <int>[
    0,
    if (cell.attributes & Attr.bold != 0) 1,
    if (cell.attributes & Attr.dim != 0) 2,
    if (cell.attributes & Attr.italic != 0) 3,
    if (cell.attributes & Attr.underline != 0) 4,
    if (cell.attributes & Attr.blink != 0) 5,
    if (cell.attributes & Attr.reverse != 0) 7,
    if (cell.attributes & Attr.strike != 0) 9,
    38,
    2,
    cell.foreground.red,
    cell.foreground.green,
    cell.foreground.blue,
    48,
    2,
    cell.background.red,
    cell.background.green,
    cell.background.blue,
  ];
  return '\x1b[${codes.join(';')}m';
}

bool _sameFrame(DriverFrame left, DriverFrame right) {
  if (left.width != right.width ||
      left.height != right.height ||
      left.cursor.visible != right.cursor.visible ||
      left.cursor.x != right.cursor.x ||
      left.cursor.y != right.cursor.y ||
      left.cursor.style != right.cursor.style ||
      left.cursor.blinking != right.cursor.blinking ||
      !_sameColor(left.cursor.color, right.cursor.color)) {
    return false;
  }
  for (var y = 0; y < left.rows.length; y++) {
    for (var x = 0; x < left.rows[y].length; x++) {
      final leftCell = left.rows[y][x];
      final rightCell = right.rows[y][x];
      if (leftCell.char != rightCell.char || !_sameStyle(leftCell, rightCell)) {
        return false;
      }
    }
  }
  return true;
}

bool _sameStyle(DriverCell left, DriverCell right) =>
    left.attributes == right.attributes &&
    _sameColor(left.foreground, right.foreground) &&
    _sameColor(left.background, right.background);

bool _sameColor(DriverColor left, DriverColor right) =>
    left.red == right.red &&
    left.green == right.green &&
    left.blue == right.blue &&
    left.alpha == right.alpha;

double _seconds(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerSecond;

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('$key must be an integer.');
  }
  return value;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

Map<String, dynamic> _actionMap(Object? value, int index) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('actions[$index] must be a JSON object.');
  }
  return value;
}

class _Options {
  const _Options({required this.recipePath, required this.force});

  static _Options? parse(List<String> arguments) {
    String? recipePath;
    var force = false;
    for (var index = 0; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--recipe':
          if (++index >= arguments.length || arguments[index].isEmpty) {
            return null;
          }
          recipePath = arguments[index];
        case '--force':
          force = true;
        default:
          return null;
      }
    }
    if (recipePath == null) return null;
    return _Options(recipePath: recipePath, force: force);
  }

  final String recipePath;
  final bool force;
}
