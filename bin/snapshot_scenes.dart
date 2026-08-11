// ignore_for_file: cascade_invocations, prefer_constructors_over_static_methods
// Minimal snapshot scenes for Dart side parity checks.
// Usage:
//   dart run bin/snapshot_scenes.dart --scene S1 --width 20 --height 5
// Scenes:
//   S1: text_hello
//   S2: box_20x5 (bordered, filled)
//   S3: padded_text (12x5 region with 1-cell padding)
//   W1: Text('Hello')
//   W2: default Row with Left, Middle, Right
//   W3: default Column with Line 1, Line 2, Line 3

import 'dart:convert';
import 'dart:io' as io;

import 'package:noir/noir.dart' as ui;
import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/buffer.dart' show createBufferFromNative;

import '../test/helpers/buffer_capture.dart';

void main(List<String> args) async {
  final argz = _Args.parse(args);
  final Map<String, dynamic> jsonOut;

  switch (argz.scene) {
    case 'S1':
    case 'S2':
    case 'S3':
      jsonOut = _capturePrimitiveScene(argz);
    case 'W1':
      jsonOut = captureWidgetSceneSnapshot(
        const ui.Text('Hello'),
        width: argz.width,
        height: argz.height,
      );
    case 'W2':
      jsonOut = captureWidgetSceneSnapshot(
        const ui.Row(
          children: [ui.Text('Left'), ui.Text('Middle'), ui.Text('Right')],
        ),
        width: argz.width,
        height: argz.height,
      );
    case 'W3':
      jsonOut = captureWidgetSceneSnapshot(
        const ui.Column(
          children: [ui.Text('Line 1'), ui.Text('Line 2'), ui.Text('Line 3')],
        ),
        width: argz.width,
        height: argz.height,
      );
    default:
      io.stderr.writeln('Unknown scene: ${argz.scene}');
      io.exitCode = 2;
      return;
  }

  io.stdout.write(const JsonEncoder.withIndent('  ').convert(jsonOut));
}

/// Captures one widget scene through the repository's real test render path.
Map<String, dynamic> captureWidgetSceneSnapshot(
  ui.Widget widget, {
  required int width,
  required int height,
}) {
  final capture = BufferCapture(
    width: width,
    height: height,
    layoutConstraints: ui.BoxConstraints.tight(width: width, height: height),
  );
  try {
    return _snapshotFromCapturedBuffer(capture.capture(widget));
  } finally {
    capture.dispose();
  }
}

Map<String, dynamic> _capturePrimitiveScene(_Args argz) {
  final bindings = OpenTuiBindings();
  final renderer = bindings.createRenderer(argz.width, argz.height);
  try {
    final buffer = createBufferFromNative(
      bindings.getNextBuffer(renderer),
      bindings,
    )..clear(ui.Color.transparent);

    switch (argz.scene) {
      case 'S1':
        _sceneTextHello(buffer);
      case 'S2':
        _sceneBox(buffer);
      case 'S3':
        _scenePaddedText(buffer);
      default:
        throw StateError('Not a primitive scene: ${argz.scene}');
    }

    return _snapshotFromBuffer(buffer);
  } finally {
    bindings.destroyRenderer(renderer);
  }
}

Map<String, dynamic> _snapshotFromCapturedBuffer(CapturedBuffer captured) => {
  'version': '1',
  'width': captured.width,
  'height': captured.height,
  'cells': [
    for (var y = 0; y < captured.height; y++)
      for (var x = 0; x < captured.width; x++)
        _capturedCellSnapshot(captured, x, y),
  ],
};

Map<String, dynamic> _capturedCellSnapshot(
  CapturedBuffer captured,
  int x,
  int y,
) {
  final foreground = captured.getForegroundColor(x, y);
  final background = captured.getBackgroundColor(x, y);
  return {
    'ch': captured.getChar(x, y),
    'fg': [foreground.r, foreground.g, foreground.b, foreground.a],
    'bg': [background.r, background.g, background.b, background.a],
  };
}

Map<String, dynamic> _snapshotFromBuffer(Buffer buffer) {
  final direct = buffer.getDirectAccess();
  return {
    'version': '1',
    'width': direct.width,
    'height': direct.height,
    'cells': [
      for (var y = 0; y < direct.height; y++)
        for (var x = 0; x < direct.width; x++)
          _directCellSnapshot(direct, x, y),
    ],
  };
}

Map<String, dynamic> _directCellSnapshot(
  DirectBufferAccess direct,
  int x,
  int y,
) {
  final foreground = direct.getForeground(x, y);
  final background = direct.getBackground(x, y);
  return {
    'ch': direct.getChar(x, y),
    'fg': [foreground.r, foreground.g, foreground.b, foreground.a],
    'bg': [background.r, background.g, background.b, background.a],
  };
}

void _sceneTextHello(Buffer buffer) {
  // Draw "Hello" at 0,0 in white.
  buffer.drawText('Hello', 0, 0, ui.Color.white);
}

void _sceneBox(Buffer buffer) {
  // 20x5 bordered box, cyan border on dark background fill.
  // Positioned at 0,0 and assumes width>=20, height>=5.
  buffer.drawBox(
    0,
    0,
    20,
    5,
    const BoxOptions(fill: true),
    ui.Color.cyan, // cyan border
    const ui.Color(0.1, 0.1, 0.15), // dark fill
  );
}

void _scenePaddedText(Buffer buffer) {
  // 12x5 area with a background, 1-cell padding, text inside.
  // Top-left at 0,0 for determinism.
  buffer.fillRect(0, 0, 12, 5, const ui.Color(0.05, 0.05, 0.08));
  buffer.drawText('Inner', 1, 1, ui.Color.white);
}

class _Args {
  _Args(this.scene, this.width, this.height);
  final String scene;
  final int width;
  final int height;

  static _Args parse(List<String> args) {
    var scene = 'S1';
    var width = 20;
    var height = 5;

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      if (a == '--scene' && i + 1 < args.length) scene = args[++i];
      if (a == '--width' && i + 1 < args.length) width = int.parse(args[++i]);
      if (a == '--height' && i + 1 < args.length) height = int.parse(args[++i]);
    }
    return _Args(scene, width, height);
  }
}
