#!/usr/bin/env dart

/// Captures the static terminal frames the documentation website shows.
///
/// Every frame comes from a canonical tutorial checkpoint that ships in this
/// repository, so a published frame and the code beside it always describe the
/// same program. The capture runs through Noir's headless drive mode. It
/// proves layout, painted cells, and parsed input; it is not evidence that a
/// particular terminal emulator renders the same bytes.
///
/// Usage, from `packages/noir`:
///
///     dart run tool/capture_doc_frames.dart
///     dart run tool/capture_doc_frames.dart --check
///
/// `--check` recaptures every scene and fails when the committed artifact is
/// out of date, without replacing it.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:noir_driver/noir_driver.dart';
import 'package:path/path.dart' as p;

const _manifestPath = 'tool/recordings/doc_frames.json';
const _usage =
    'Usage: dart run tool/capture_doc_frames.dart [--check] '
    '[--only <scene id>]';

/// Resolves a manifest path, which is relative to the repository root.
///
/// The website links to each entrypoint on GitHub, so the manifest names
/// repository paths. This script runs from `packages/noir`, two levels down.
String _fromRepository(String path) => p.normalize(p.join('..', '..', path));

Future<void> main(List<String> arguments) async {
  String? only;
  var check = false;
  for (var index = 0; index < arguments.length; index++) {
    switch (arguments[index]) {
      case '--check':
        check = true;
      case '--only':
        index++;
        if (index >= arguments.length) {
          stderr.writeln(_usage);
          exitCode = 64;
          return;
        }
        only = arguments[index];
      default:
        stderr.writeln(_usage);
        exitCode = 64;
        return;
    }
  }

  try {
    await _captureAll(check: check, only: only);
  } on FormatException catch (error) {
    stderr.writeln('Invalid frame manifest: ${error.message}');
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln('Frame capture file error: ${error.message}');
    exitCode = 66;
  }
}

Future<void> _captureAll({required bool check, String? only}) async {
  final manifest = _readManifest();
  final scenes = <_Scene>[
    for (final scene in manifest.scenes)
      if (only == null || scene.id == only) scene,
  ];
  if (scenes.isEmpty) {
    throw FormatException('No scene matches "$only" in $_manifestPath.');
  }

  final captured = <String, Map<String, Object?>>{};
  for (final scene in scenes) {
    stdout.writeln('Capturing ${scene.id} from ${scene.entrypoint}…');
    captured[scene.id] = await _captureScene(scene);
  }

  final output = File(_fromRepository(manifest.output));
  final previous = output.existsSync()
      ? (jsonDecode(output.readAsStringSync()) as Map<String, Object?>)
      : <String, Object?>{};
  final frames = <String, Object?>{
    if (previous['frames'] case final Map<String, Object?> existing)
      ...existing,
    ...captured,
  };
  final ordered = <String, Object?>{
    for (final scene in manifest.scenes)
      if (frames[scene.id] case final Object? frame when frame != null)
        scene.id: frame,
  };
  final rendered = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
    'generatedBy': 'packages/noir/tool/capture_doc_frames.dart',
    'capturedWith': 'NoirDriver (NOIR_DRIVE=1), headless',
    'frames': ordered,
  });

  if (check) {
    final current = output.existsSync() ? output.readAsStringSync() : '';
    if (current.trimRight() != rendered.trimRight()) {
      stderr.writeln(
        '${manifest.output} is stale. Run '
        '`dart run tool/capture_doc_frames.dart` from packages/noir and '
        'commit the result.',
      );
      exitCode = 1;
      return;
    }
    stdout.writeln('${manifest.output} matches the captured frames.');
    return;
  }

  await output.parent.create(recursive: true);
  await output.writeAsString('$rendered\n', flush: true);
  stdout.writeln('Wrote ${ordered.length} frames to ${manifest.output}.');
}

Future<Map<String, Object?>> _captureScene(_Scene scene) async {
  final entrypointPath = _fromRepository(scene.entrypoint);
  final entrypoint = File(entrypointPath);
  if (!entrypoint.existsSync()) {
    throw FileSystemException('Entrypoint does not exist', scene.entrypoint);
  }
  final source = entrypoint.readAsStringSync();

  final driver = await NoirDriver.launch(
    entrypointPath,
    width: scene.width,
    height: scene.height,
  );
  DriverFrame frame;
  var appExitCode = -1;
  try {
    for (final action in scene.actions) {
      await _perform(driver, action);
    }
    frame = await driver.captureCells();
  } finally {
    appExitCode = await driver.quit();
  }
  if (appExitCode != 0) {
    throw ProcessException(
      Platform.resolvedExecutable,
      <String>['run', entrypointPath],
      'The driven application exited with a non-zero status.',
      appExitCode,
    );
  }
  if (frame.width != scene.width || frame.height != scene.height) {
    throw StateError(
      'Captured ${frame.width}x${frame.height} for ${scene.id}; expected '
      '${scene.width}x${scene.height}.',
    );
  }

  final lines = [...frame.lines];
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  if (lines.isEmpty) {
    throw StateError('Scene ${scene.id} painted an empty frame.');
  }
  final text = lines.join('\n');
  for (final expected in scene.expected) {
    if (!text.contains(expected)) {
      throw StateError(
        'Scene ${scene.id} does not show "$expected". The documented result '
        'and the checkpoint disagree.\n$text',
      );
    }
  }

  return <String, Object?>{
    'title': scene.title,
    'command': scene.command,
    'entrypoint': scene.entrypoint,
    'width': scene.width,
    'height': scene.height,
    'interaction': scene.interaction,
    if (scene.image != null) 'image': ?scene.image,
    'sourceSha256': sha256.convert(utf8.encode(source)).toString(),
    // JPEG provenance includes styling and cursor state, not just text. Keep
    // the bulky cell data out of the website bundle; only its digest is needed.
    'visualSha256': sha256
        .convert(
          utf8.encode(
            jsonEncode([
              frame.width,
              frame.height,
              for (final row in frame.rows)
                [
                  for (final cell in row)
                    [
                      cell.char,
                      cell.foreground.toAnsiHex(),
                      cell.background.toAnsiHex(),
                      cell.attributes,
                    ],
                ],
              [
                frame.cursor.visible,
                frame.cursor.x,
                frame.cursor.y,
                frame.cursor.style,
                frame.cursor.color.toAnsiHex(),
                frame.cursor.blinking,
              ],
            ]),
          ),
        )
        .toString(),
    'lines': lines,
    'runs': [for (final row in frame.rows) _styledRuns(row)],
  };
}

/// The colors the headless renderer resolves for a cell the app never styled.
const _defaultForeground = '#ffffff';
const _defaultBackground = '#000000';

/// Groups one captured row into runs of identically styled cells.
///
/// A run names only what differs from an unstyled cell, so plain text stays
/// plain and the website can draw it in its own terminal palette. Trailing
/// unstyled blanks are dropped; a styled blank, such as the padding of a
/// focused button, is kept because it is visible.
List<Map<String, Object?>> _styledRuns(List<DriverCell> row) {
  var end = row.length;
  while (end > 0 && _isUnstyledBlank(row[end - 1])) {
    end--;
  }
  final runs = <Map<String, Object?>>[];
  for (final cell in row.take(end)) {
    final foreground = cell.foreground.toAnsiHex();
    final background = cell.background.toAnsiHex();
    final style = <String, Object?>{
      if (foreground != _defaultForeground) 'fg': foreground,
      if (background != _defaultBackground) 'bg': background,
      if (cell.attributes != 0) 'attrs': cell.attributes,
    };
    final previous = runs.lastOrNull;
    if (previous != null &&
        previous['fg'] == style['fg'] &&
        previous['bg'] == style['bg'] &&
        previous['attrs'] == style['attrs']) {
      previous['text'] = '${previous['text']}${cell.char}';
    } else {
      runs.add(<String, Object?>{'text': cell.char, ...style});
    }
  }
  return runs;
}

bool _isUnstyledBlank(DriverCell cell) =>
    cell.char.trim().isEmpty &&
    cell.background.toAnsiHex() == _defaultBackground &&
    cell.attributes == 0;

Future<void> _perform(NoirDriver driver, _Action action) async {
  switch (action.kind) {
    case _ActionKind.key:
      await driver.sendKey(action.value);
    case _ActionKind.type:
      await driver.typeText(action.value);
    case _ActionKind.clickKey:
      final node = await driver.find(DriverLocator.byKey(action.value));
      final point = node.actionPoint;
      if (point == null) {
        throw StateError(
          'Cannot click ${action.value}: the match is offscreen, fully '
          'obscured, or has no visible pointer route. Match: $node',
        );
      }
      await driver.click(point.x, point.y);
  }
  // One idle turn lets the driven app finish the frame the action requested.
  await driver.capture();
}

_Manifest _readManifest() {
  final file = File(_manifestPath);
  if (!file.existsSync()) {
    throw FileSystemException('Missing frame manifest', _manifestPath);
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('The manifest root must be a JSON object.');
  }
  final output = decoded['output'];
  if (output is! String || !output.endsWith('.json')) {
    throw const FormatException('output must name a .json file.');
  }
  final rawScenes = decoded['scenes'];
  if (rawScenes is! List<Object?> || rawScenes.isEmpty) {
    throw const FormatException('scenes must be a non-empty JSON array.');
  }
  final scenes = <_Scene>[
    for (final scene in rawScenes) _Scene.fromJson(scene),
  ];
  final ids = scenes.map((scene) => scene.id).toSet();
  if (ids.length != scenes.length) {
    throw const FormatException('every scene id must be unique.');
  }
  return _Manifest(output: output, scenes: scenes);
}

class _Manifest {
  const _Manifest({required this.output, required this.scenes});

  final String output;
  final List<_Scene> scenes;
}

class _Scene {
  const _Scene({
    required this.id,
    required this.entrypoint,
    required this.title,
    required this.command,
    required this.interaction,
    required this.width,
    required this.height,
    required this.actions,
    required this.expected,
    this.image,
  });

  factory _Scene.fromJson(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('every scene must be a JSON object.');
    }
    final width = _requiredInt(value, 'width');
    final height = _requiredInt(value, 'height');
    if (width <= 0 || height <= 0 || width > 300 || height > 120) {
      throw const FormatException(
        'width and height must be positive and no larger than 300x120.',
      );
    }
    final entrypoint = _requiredString(value, 'entrypoint');
    if (!entrypoint.endsWith('.dart')) {
      throw const FormatException('entrypoint must name a .dart file.');
    }
    final rawActions = value['actions'] ?? const <Object?>[];
    if (rawActions is! List<Object?>) {
      throw const FormatException('actions must be a JSON array.');
    }
    final rawExpected = value['expect'] ?? const <Object?>[];
    if (rawExpected is! List<Object?>) {
      throw const FormatException('expect must be a JSON array.');
    }
    final image = value['image'];
    if (image != null && (image is! String || !image.endsWith('.jpg'))) {
      throw const FormatException('image must name a .jpg file.');
    }
    return _Scene(
      id: _requiredString(value, 'id'),
      entrypoint: entrypoint,
      title: _requiredString(value, 'title'),
      command: _requiredString(value, 'command'),
      interaction: _requiredString(value, 'interaction'),
      width: width,
      height: height,
      actions: <_Action>[for (final action in rawActions) _Action.from(action)],
      expected: <String>[
        for (final text in rawExpected)
          if (text is String && text.isNotEmpty)
            text
          else
            throw const FormatException('expect entries must be strings.'),
      ],
      image: image as String?,
    );
  }

  final String id;
  final String entrypoint;
  final String title;
  final String command;
  final String interaction;
  final int width;
  final int height;
  final List<_Action> actions;

  /// Text the documented result promises this frame contains.
  final List<String> expected;

  /// The screenshot in `packages/noir_signals/doc/images/` this scene backs.
  final String? image;
}

enum _ActionKind { key, type, clickKey }

class _Action {
  const _Action(this.kind, this.value);

  factory _Action.from(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('every action must be a JSON object.');
    }
    for (final kind in _ActionKind.values) {
      final raw = value[kind.name];
      if (raw == null) continue;
      if (raw is! String || raw.isEmpty) {
        throw FormatException('${kind.name} must be a non-empty string.');
      }
      return _Action(kind, raw);
    }
    throw const FormatException('an action needs key, type, or clickKey.');
  }

  final _ActionKind kind;
  final String value;
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw FormatException('$field must be an integer.');
  }
  return value;
}
