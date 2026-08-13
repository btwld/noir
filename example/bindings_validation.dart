#!/usr/bin/env dart
// ignore_for_file: cascade_invocations

import 'dart:io';
import 'dart:math' as math;

import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';

/// Owns Enter-only input for one bindings-validation terminal session.
abstract interface class BindingsValidationInput {
  /// Discards bytes through the platform's Enter byte.
  Future<void> waitForEnter();

  /// Restores the input modes captured during acquisition.
  void restore();
}

/// Narrow synchronous stdin boundary used by [BindingsValidationInputLease].
abstract interface class BindingsValidationStdin {
  /// Whether stdin is attached to a terminal.
  bool get hasTerminal;

  /// Whether the host uses carriage return as the raw Enter byte.
  bool get isWindows;

  /// Whether stdin currently buffers input by line.
  bool get lineMode;

  set lineMode(bool value);

  /// Whether stdin currently echoes input bytes.
  bool get echoMode;

  set echoMode(bool value);

  /// Reads one raw byte, returning `-1` at end of input.
  int readByteSync();
}

/// A raw Enter-only stdin lease for the interactive validation scenes.
final class BindingsValidationInputLease implements BindingsValidationInput {
  BindingsValidationInputLease._(
    this._stdin,
    this._savedLineMode,
    this._savedEchoMode,
    this._enterByte,
  );

  /// Acquires stdin by disabling echo first and line buffering second.
  factory BindingsValidationInputLease.acquire(BindingsValidationStdin stdin) {
    if (!stdin.hasTerminal) {
      throw StateError('Bindings validation requires terminal stdin');
    }

    final savedLineMode = stdin.lineMode;
    final savedEchoMode = stdin.echoMode;
    final enterByte = stdin.isWindows ? 0x0d : 0x0a;
    final lease = BindingsValidationInputLease._(
      stdin,
      savedLineMode,
      savedEchoMode,
      enterByte,
    );

    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
    } catch (error, stackTrace) {
      try {
        lease.restore();
      } catch (_) {
        // Acquisition remains the primary failure after rollback is attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }

    return lease;
  }

  final BindingsValidationStdin _stdin;
  final bool _savedLineMode;
  final bool _savedEchoMode;
  final int _enterByte;
  bool _restored = false;

  @override
  Future<void> waitForEnter() async {
    if (_restored) {
      throw StateError('Bindings validation input has been restored');
    }

    while (true) {
      final byte = _stdin.readByteSync();
      if (byte == -1) {
        throw StateError('stdin closed before Enter');
      }
      if (byte == _enterByte) return;
    }
  }

  @override
  void restore() {
    if (_restored) return;

    Object? failure;
    StackTrace? failureStackTrace;
    try {
      try {
        _stdin.lineMode = _savedLineMode;
      } catch (error, stackTrace) {
        failure = error;
        failureStackTrace = stackTrace;
      }
      try {
        _stdin.echoMode = _savedEchoMode;
      } catch (error, stackTrace) {
        failure ??= error;
        failureStackTrace ??= stackTrace;
      }
    } finally {
      _restored = true;
    }

    if (failure != null) {
      Error.throwWithStackTrace(failure, failureStackTrace!);
    }
  }
}

/// Owns renderer and input acquisition for one validation run.
abstract interface class BindingsValidationRuntime {
  /// Creates the renderer used by all scenes.
  Renderer createRenderer(int width, int height);

  /// Acquires the input lease before terminal setup.
  BindingsValidationInput acquireInput();

  /// Enters the renderer's terminal session.
  void setupTerminal(Renderer renderer);

  /// Hides the renderer-owned cursor for validation frames.
  void hideCursor(Renderer renderer);

  /// Releases the renderer after input restoration.
  void disposeRenderer(Renderer renderer);
}

final class _IoBindingsValidationStdin implements BindingsValidationStdin {
  const _IoBindingsValidationStdin();

  @override
  bool get hasTerminal => stdin.hasTerminal;

  @override
  bool get isWindows => Platform.isWindows;

  @override
  bool get lineMode => stdin.lineMode;

  @override
  set lineMode(bool value) => stdin.lineMode = value;

  @override
  bool get echoMode => stdin.echoMode;

  @override
  set echoMode(bool value) => stdin.echoMode = value;

  @override
  int readByteSync() => stdin.readByteSync();
}

final class _IoBindingsValidationRuntime implements BindingsValidationRuntime {
  const _IoBindingsValidationRuntime();

  @override
  Renderer createRenderer(int width, int height) =>
      Renderer.create(width, height);

  @override
  BindingsValidationInput acquireInput() =>
      BindingsValidationInputLease.acquire(const _IoBindingsValidationStdin());

  @override
  void setupTerminal(Renderer renderer) => renderer.setupTerminal();

  @override
  void hideCursor(Renderer renderer) => renderer.hideCursor();

  @override
  void disposeRenderer(Renderer renderer) => renderer.dispose();
}

final class _FirstFailure {
  Object? _error;
  StackTrace? _stackTrace;

  void capture(Object error, StackTrace stackTrace) {
    _error ??= error;
    _stackTrace ??= stackTrace;
  }

  void attempt(void Function() action) {
    try {
      action();
    } catch (error, stackTrace) {
      capture(error, stackTrace);
    }
  }

  void rethrowFirst() {
    final error = _error;
    if (error != null) {
      Error.throwWithStackTrace(error, _stackTrace!);
    }
  }
}

/// Runs five interactive advanced renderer/buffer and ABI-unstable FFI scenes.
///
/// This uses an alternate screen and requires a terminal at least 120x40.
Future<void> main() async {
  Object? failure;
  StackTrace? failureStackTrace;

  try {
    await runBindingsValidation();
  } catch (error, stackTrace) {
    failure = error;
    failureStackTrace = stackTrace;
  }

  if (failure != null) {
    stderr.writeln('Bindings validation failed: $failure');
    stderr.writeln(failureStackTrace);
    exitCode = 1;
    return;
  }

  stdout.writeln('Bindings validation completed successfully.');
}

/// Runs one complete validation session with input restored before renderer disposal.
Future<void> runBindingsValidation({
  BindingsValidationRuntime runtime = const _IoBindingsValidationRuntime(),
}) async {
  Renderer? renderer;
  BindingsValidationInput? input;
  final failure = _FirstFailure();

  try {
    final createdRenderer = runtime.createRenderer(80, 30);
    renderer = createdRenderer;
    final acquiredInput = runtime.acquireInput();
    input = acquiredInput;
    runtime.setupTerminal(createdRenderer);
    runtime.hideCursor(createdRenderer);
    await runBindingsValidationDemos(
      createdRenderer,
      waitForUser: acquiredInput.waitForEnter,
    );
  } catch (error, stackTrace) {
    failure.capture(error, stackTrace);
  } finally {
    final inputToRestore = input;
    if (inputToRestore != null) {
      failure.attempt(inputToRestore.restore);
    }
    final rendererToDispose = renderer;
    if (rendererToDispose != null) {
      failure.attempt(() => runtime.disposeRenderer(rendererToDispose));
    }
  }

  failure.rethrowFirst();
}

/// Renders the five validation scenes through a borrowed [renderer].
///
/// The caller owns terminal setup and disposal. [waitForUser] runs after each
/// rendered frame, which lets tests capture the same scenes without reading
/// stdin.
Future<void> runBindingsValidationDemos(
  Renderer renderer, {
  required Future<void> Function() waitForUser,
}) async {
  final demos = [
    () => _demoBasicRendering(renderer),
    () => _demoColors(renderer),
    () => _demoTextAttributes(renderer),
    () => _demoBoxDrawing(renderer),
    () => _demoLargeBuffer(renderer),
  ];

  for (var i = 0; i < demos.length; i++) {
    await demos[i]();
    await waitForUser();
  }
}

Future<void> _demoBasicRendering(Renderer renderer) async {
  renderer.setBackgroundColor(Color.rgb(0.02, 0.02, 0.05));
  renderer.clearTerminal();

  final buf = renderer.nextBuffer;
  buf.clear(Color.rgb(0.02, 0.02, 0.05));

  // Title
  buf.drawText(
    'Noir FFI Bindings Validation',
    12,
    2,
    Color.yellow,
    attributes: Attr.bold | Attr.underline,
  );

  // Basic shapes
  buf.fillRect(5, 5, 30, 3, Color.blue);
  buf.drawText('Filled Rectangle', 6, 6, Color.white, attributes: Attr.bold);

  buf.fillRect(40, 5, 25, 8, Color.red);
  buf.drawText('Large Rectangle', 42, 7, Color.white);
  buf.drawText('Multi-line text', 42, 9, Color.yellow);

  // Grid pattern
  for (var x = 5; x < 70; x += 10) {
    for (var y = 15; y < 25; y += 2) {
      buf.drawText('●', x, y, Color.green);
    }
  }

  buf.drawText('Press ENTER to continue...', 25, 27, Color.cyan);

  renderer.render(force: true);
}

Future<void> _demoColors(Renderer renderer) async {
  final buf = renderer.nextBuffer;
  buf.clear(Color.black);

  buf.drawText(
    'Color Palette Demonstration',
    20,
    2,
    Color.white,
    attributes: Attr.bold,
  );

  // Predefined colors
  final colors = [
    ('Red', Color.red),
    ('Green', Color.green),
    ('Blue', Color.blue),
    ('Yellow', Color.yellow),
    ('Cyan', Color.cyan),
    ('Magenta', Color.magenta),
    ('White', Color.white),
    ('Gray', Color.rgb(0.5, 0.5, 0.5)),
  ];

  for (var i = 0; i < colors.length; i++) {
    final (name, color) = colors[i];
    final x = 5 + (i % 4) * 18;
    final y = 5 + (i ~/ 4) * 3;

    // Colored background
    buf.fillRect(x, y, 16, 2, color);
    buf.drawText('████████', x, y, color);
    buf.drawText(name.padRight(8), x, y + 1, Color.white, bg: color);
  }

  // Gradient demonstration
  buf.drawText('RGB Gradient:', 5, 15, Color.white, attributes: Attr.bold);
  for (var x = 0; x < 60; x++) {
    final r = x / 60.0;
    final g = math.sin(x / 10.0).abs();
    final b = 1.0 - (x / 60.0);
    buf.drawText('█', 10 + x, 17, Color(r, g, b));
  }

  buf.drawText('Press ENTER to continue...', 25, 27, Color.cyan);

  renderer.render(force: true);
}

Future<void> _demoTextAttributes(Renderer renderer) async {
  final buf = renderer.nextBuffer;
  buf.clear(Color.rgb(0.05, 0.05, 0.1));

  buf.drawText(
    'Text Attributes Demonstration',
    20,
    2,
    Color.white,
    attributes: Attr.bold,
  );

  final samples = [
    ('Normal text', 0, Color.white),
    ('Bold text', Attr.bold, Color.yellow),
    ('Italic text', Attr.italic, Color.cyan),
    ('Underline text', Attr.underline, Color.green),
    ('Dim text', Attr.dim, Color.white),
    ('Reverse text', Attr.reverse, Color.white),
    ('Strikethrough', Attr.strike, Color.red),
    ('Bold + Underline', Attr.bold | Attr.underline, Color.magenta),
  ];

  for (var i = 0; i < samples.length; i++) {
    final (text, attrs, color) = samples[i];
    buf.drawText(text, 5, 5 + i * 2, color, attributes: attrs);
  }

  // Blinking text (if supported)
  buf.drawText(
    'Blinking text (if supported)',
    40,
    8,
    Color.red,
    attributes: Attr.blink,
  );

  buf.drawText('Press ENTER to continue...', 25, 27, Color.cyan);

  renderer.render(force: true);
}

Future<void> _demoBoxDrawing(Renderer renderer) async {
  final buf = renderer.nextBuffer;
  buf.clear(Color.rgb(0.02, 0.05, 0.02));

  buf.drawText(
    'Box Drawing Demonstration',
    22,
    1,
    Color.white,
    attributes: Attr.bold,
  );

  // Simple box
  final simpleBox = BoxOptions();
  buf.drawBox(5, 3, 20, 8, simpleBox, Color.white, Color.black);
  buf.drawText('Simple Box', 8, 5, Color.yellow);
  buf.drawText('Default borders', 7, 7, Color.white);

  // Titled box with fill
  final titledBox = BoxOptions(
    title: 'Information Panel',
    titleAlignment: TextAlign.center,
    fill: true,
  );
  buf.drawBox(30, 3, 25, 8, titledBox, Color.cyan, Color.rgb(0.1, 0.1, 0.3));
  buf.drawText('Filled box with', 32, 5, Color.white);
  buf.drawText('centered title', 32, 6, Color.white);
  buf.drawText('and background', 32, 7, Color.white);

  // Custom border sides
  final partialBox = BoxOptions(
    title: 'Partial',
    sides: BorderSides(left: false, right: false),
    fill: true,
  );
  buf.drawBox(
    60,
    3,
    15,
    5,
    partialBox,
    Color.green,
    Color.rgb(0.05, 0.2, 0.05),
  );
  buf.drawText('Top/Bottom', 62, 5, Color.white);

  // Complex nested layout
  final outerBox = BoxOptions(title: 'Outer Container', fill: true);
  buf.drawBox(5, 13, 70, 12, outerBox, Color.yellow, Color.rgb(0.1, 0.1, 0.05));

  final innerBox1 = BoxOptions(title: 'Panel 1');
  buf.drawBox(8, 16, 20, 6, innerBox1, Color.white, Color.black);
  buf.drawText('Content A', 12, 18, Color.green);

  final innerBox2 = BoxOptions(title: 'Panel 2');
  buf.drawBox(32, 16, 20, 6, innerBox2, Color.white, Color.black);
  buf.drawText('Content B', 36, 18, Color.red);

  final innerBox3 = BoxOptions(title: 'Panel 3');
  buf.drawBox(56, 16, 15, 6, innerBox3, Color.white, Color.black);
  buf.drawText('Content C', 58, 18, Color.blue);

  buf.drawText('Press ENTER to continue...', 25, 27, Color.cyan);

  renderer.render(force: true);
}

Future<void> _demoLargeBuffer(Renderer renderer) async {
  renderer.resize(120, 40);
  renderer.setBackgroundColor(Color.black);
  final buf = renderer.nextBuffer;
  buf.clear(Color.black);

  buf.drawText(
    'Large Buffer Performance Test (120x40)',
    30,
    1,
    Color.white,
    attributes: Attr.bold,
  );

  // Performance test - draw many elements
  final stopwatch = Stopwatch()..start();

  // Grid background
  for (var y = 3; y < 35; y += 2) {
    for (var x = 2; x < 118; x += 4) {
      buf.drawText('·', x, y, Color.rgb(0.3, 0.3, 0.3));
    }
  }

  // Moving sine wave
  for (var x = 0; x < 100; x++) {
    final y = (15 + 8 * math.sin(x / 10.0)).round();
    buf.drawText(
      '█',
      x + 10,
      y,
      Color.rgb(
        (math.sin(x / 20.0) + 1) / 2,
        (math.cos(x / 15.0) + 1) / 2,
        (math.sin(x / 25.0) + 1) / 2,
      ),
    );
  }

  // Multiple rectangles
  for (var i = 0; i < 10; i++) {
    final x = 5 + i * 11;
    final y = 25 + (i % 3) * 3;
    final w = 8;
    final h = 2;

    buf.fillRect(x, y, w, h, Color.rgb(i / 10.0, 1.0 - i / 10.0, 0.5));
    buf.drawText('$i', x + 3, y, Color.white);
  }

  // Complex text rendering
  final text = 'Performance test with complex rendering operations ';
  for (var i = 0; i < 5; i++) {
    buf.drawText(text * 2, 5, 32 + i, Color.rgb(0.8, 0.8, 0.2));
  }

  stopwatch.stop();

  buf.drawText(
    'Rendering time: ${stopwatch.elapsedMilliseconds}ms',
    30,
    37,
    Color.green,
  );
  buf.drawText('Press ENTER to continue...', 35, 38, Color.cyan);

  renderer.render(force: true);
}
