import 'dart:io';

import 'package:noir/noir.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

import 'buffer_capture.dart';

/// Golden file testing framework for terminal UI widgets.
///
/// Inspired by Flutter's golden tests, this framework captures widget output
/// and compares it against saved "golden" files for visual regression testing.
class GoldenTester {
  /// Creates a GoldenTester with specified buffer dimensions.
  GoldenTester({int width = 80, int height = 24})
    : _buffer = BufferCapture(width: width, height: height);
  static const String _goldenDir = 'test/goldens';
  static const String _failureDir = 'test/failures';

  final BufferCapture _buffer;

  /// Tests a widget against its golden file.
  ///
  /// This method:
  /// 1. Renders the widget to capture its output
  /// 2. Loads the expected golden file
  /// 3. Compares the actual vs expected output
  /// 4. Saves failure artifacts if they don't match
  ///
  /// [testName] should be a unique identifier for this test case.
  /// Use UPDATE_GOLDENS=1 in the calling test to opt into regeneration.
  ///
  /// Style + cursor sidecars (`<name>.styles.txt`, `<name>.cursor.txt`) are
  /// validated by default — pass `captureStyles: false` / `captureCursor:
  /// false` only when the widget under test is genuinely style-/cursor-
  /// agnostic. When sidecars are missing they are created automatically with
  /// `UPDATE_GOLDENS=1`; without that flag a missing sidecar is a hard
  /// failure with instructions to run the updater.
  Future<void> expectGolden(
    Widget widget,
    String testName, {
    bool updateGoldens = false,
    bool captureStyles = true,
    bool captureCursor = true,
  }) => expectCapturedGolden(
    _buffer.capture(widget),
    testName,
    updateGoldens: updateGoldens,
    captureStyles: captureStyles,
    captureCursor: captureCursor,
  );

  /// Compares a pre-captured buffer against golden + style/cursor sidecars.
  ///
  /// Use this when the scene must be driven through focus or multi-step setup
  /// before capture (for example focused editors after autofocus settles).
  Future<void> expectCapturedGolden(
    CapturedBuffer captured,
    String testName, {
    bool updateGoldens = false,
    bool captureStyles = true,
    bool captureCursor = true,
  }) async {
    await _ensureDirectories();

    final actualBuffer = captured.toText();
    final bufferPath = path.join(_goldenDir, '$testName.buffer.txt');

    if (updateGoldens) {
      await _saveBufferGolden(bufferPath, actualBuffer);
      if (captureStyles || captureCursor) {
        await _saveSidecarGoldens(
          testName,
          serializeStyles: () => _serializeStyles(captured),
          serializeCursor: () => captured.cursor.toGolden(),
          writeStyles: captureStyles,
          writeCursor: captureCursor,
        );
      }
      print('Updated golden files for $testName');
      return;
    }

    await _compareBufferGolden(testName, bufferPath, actualBuffer);
    if (captureStyles || captureCursor) {
      await _compareSidecarGoldens(
        testName,
        serializeStyles: () => _serializeStyles(captured),
        serializeCursor: () => captured.cursor.toGolden(),
        checkStyles: captureStyles,
        checkCursor: captureCursor,
      );
    }
  }

  /// Compares visual buffer output only.
  Future<void> expectGoldenBuffer(
    Widget widget,
    String testName, {
    bool updateGoldens = false,
  }) async {
    await _ensureDirectories();

    final captured = _buffer.capture(widget);
    final actualBuffer = captured.toText();
    final bufferPath = path.join(_goldenDir, '$testName.buffer.txt');

    if (updateGoldens) {
      await _saveBufferGolden(bufferPath, actualBuffer);
      print('Updated golden buffer for $testName');
      return;
    }

    await _compareBufferGolden(testName, bufferPath, actualBuffer);
  }

  /// Tests multiple widgets against consolidated golden files.
  ///
  /// This method:
  /// 1. Renders all widgets and captures their output
  /// 2. Combines all outputs into single golden files with separators
  /// 3. Compares against expected consolidated golden files
  ///
  /// [testCases] is a map of testName -> widget
  /// [suiteName] is used as the base filename (e.g., 'text_widgets')
  Future<void> expectGoldenMulti(
    Map<String, Widget> testCases,
    String suiteName, {
    bool updateGoldens = false,
    bool captureStyles = true,
    bool captureCursor = true,
  }) async {
    await _ensureDirectories();

    final combinedBufferOutput = StringBuffer();
    final captures = <String, CapturedBuffer>{};

    // Capture all test cases
    for (final entry in testCases.entries) {
      final testName = entry.key;
      final widget = entry.value;

      // Capture widget output
      final captured = _buffer.capture(widget);
      final bufferOutput = captured.toText();

      // Add separator and test output
      if (combinedBufferOutput.isNotEmpty) {
        combinedBufferOutput.writeln();
      }
      combinedBufferOutput
        ..writeln('=== TEST: $testName ===')
        ..write(bufferOutput);

      captures[testName] = captured;
    }

    final bufferPath = path.join(_goldenDir, '$suiteName.buffer.txt');

    if (updateGoldens) {
      await _saveBufferGolden(bufferPath, combinedBufferOutput.toString());
      if (captureStyles || captureCursor) {
        await _saveSidecarGoldens(
          suiteName,
          serializeStyles: () =>
              _serializeCapturedSuite(captures, _serializeStyles),
          serializeCursor: () => _serializeCapturedSuite(
            captures,
            (captured) => captured.cursor.toGolden(),
          ),
          writeStyles: captureStyles,
          writeCursor: captureCursor,
        );
      }
      print(
        'Updated consolidated golden files for $suiteName (${testCases.length} test cases)',
      );
      return;
    }

    // Compare mode
    await _compareBufferGolden(
      suiteName,
      bufferPath,
      combinedBufferOutput.toString(),
    );
    if (captureStyles || captureCursor) {
      await _compareSidecarGoldens(
        suiteName,
        serializeStyles: () =>
            _serializeCapturedSuite(captures, _serializeStyles),
        serializeCursor: () => _serializeCapturedSuite(
          captures,
          (captured) => captured.cursor.toGolden(),
        ),
        checkStyles: captureStyles,
        checkCursor: captureCursor,
      );
    }
  }

  /// Cleans up failure artifacts from previous test runs.
  Future<void> cleanFailures() async {
    final failureDir = Directory(_failureDir);
    if (failureDir.existsSync()) {
      await failureDir.delete(recursive: true);
      print('Cleaned failure artifacts');
    }
  }

  /// Disposes of resources.
  void dispose() {
    _buffer.dispose();
  }

  /// Normalizes buffer by stripping trailing whitespace from each line but preserving leading spaces.
  /// This catches leading-space alignment bugs that trim() would hide.
  String _normalizeBuffer(String buffer) => buffer
      .split('\n')
      .map((line) => line.trimRight())
      .join('\n')
      .trimRight(); // Remove trailing empty lines

  // Private helper methods

  Future<void> _ensureDirectories() async {
    final goldenDir = Directory(_goldenDir);

    if (!goldenDir.existsSync()) {
      await goldenDir.create(recursive: true);
    }
  }

  /// Serialise per-cell foreground/background/attribute state into a compact
  /// run-length encoded string. Format: `<x>,<y>:<fgHex>|<bgHex>|<attr> [* run]`
  /// per non-default cell, one per line. Cells with the default style
  /// (transparent fg & bg, no attrs) are omitted to keep the file readable.
  String _serializeStyles(CapturedBuffer captured) {
    final out = StringBuffer();
    for (var y = 0; y < captured.height; y++) {
      CapturedCell? runCell;
      var runStartX = 0;
      var runLength = 0;

      void flushRun() {
        final cell = runCell;
        if (cell == null) return;
        final fg = cell.foreground;
        final bg = cell.background;
        final attr = _visualAttributes(cell);
        out.write('$runStartX,$y:${fg.toHex()}|${bg.toHex()}|$attr');
        if (runLength > 1) {
          out.write(' * $runLength');
        }
        out.writeln();
        runCell = null;
        runLength = 0;
      }

      for (var x = 0; x < captured.width; x++) {
        final cell = captured.cells[y][x];
        if (_isDefaultStyle(cell)) {
          flushRun();
          continue;
        }
        if (runCell != null && _sameStyle(runCell!, cell)) {
          runLength++;
          continue;
        }
        flushRun();
        runCell = cell;
        runStartX = x;
        runLength = 1;
      }
      flushRun();
    }
    return out.toString();
  }

  bool _isDefaultStyle(CapturedCell cell) =>
      cell.foreground.r == 0 &&
      cell.foreground.g == 0 &&
      cell.foreground.b == 0 &&
      cell.foreground.a == 0 &&
      cell.background.r == 0 &&
      cell.background.g == 0 &&
      cell.background.b == 0 &&
      cell.background.a == 0 &&
      _visualAttributes(cell) == 0;

  bool _sameStyle(CapturedCell a, CapturedCell b) =>
      a.foreground == b.foreground &&
      a.background == b.background &&
      _visualAttributes(a) == _visualAttributes(b);

  // OpenTUI stores native hyperlink allocation IDs in bits 8–31. Those IDs
  // are non-visual and vary between runs; semantic URLs are asserted through
  // buffer/driver tests instead of style goldens.
  int _visualAttributes(CapturedCell cell) => cell.attributes & 0xff;

  /// Writes the style/cursor sidecars produced by the given serializers.
  /// Single- and multi-capture flows differ only in the serializer thunks.
  Future<void> _saveSidecarGoldens(
    String testName, {
    required String Function() serializeStyles,
    required String Function() serializeCursor,
    required bool writeStyles,
    required bool writeCursor,
  }) async {
    if (writeStyles) {
      final stylesPath = path.join(_goldenDir, '$testName.styles.txt');
      await File(stylesPath).writeAsString(serializeStyles());
    }
    if (writeCursor) {
      final cursorPath = path.join(_goldenDir, '$testName.cursor.txt');
      await File(cursorPath).writeAsString(serializeCursor());
    }
  }

  /// Compares the serialized style/cursor sidecars against their goldens,
  /// saving failure artifacts on mismatch.
  Future<void> _compareSidecarGoldens(
    String testName, {
    required String Function() serializeStyles,
    required String Function() serializeCursor,
    required bool checkStyles,
    required bool checkCursor,
  }) async {
    final stylesPath = path.join(_goldenDir, '$testName.styles.txt');
    final cursorPath = path.join(_goldenDir, '$testName.cursor.txt');

    final missing = <String>[];
    if (checkStyles && !File(stylesPath).existsSync()) {
      missing.add(stylesPath);
    }
    if (checkCursor && !File(cursorPath).existsSync()) {
      missing.add(cursorPath);
    }
    if (missing.isNotEmpty) {
      fail(
        'Sidecar missing for $testName: ${missing.join(', ')}\n'
        'Run `UPDATE_GOLDENS=1 dart test ...` to generate.',
      );
    }

    final actualStyles = checkStyles ? serializeStyles() : null;
    final actualCursor = checkCursor ? serializeCursor() : null;
    final expectedStyles = checkStyles
        ? await File(stylesPath).readAsString()
        : null;
    final expectedCursor = checkCursor
        ? await File(cursorPath).readAsString()
        : null;

    // `actualStyles` / `expectedStyles` are non-null whenever `checkStyles`
    // is true; same pairing for the cursor variant. We compare the trimmed
    // form to ignore trailing whitespace in golden files.
    final stylesMatch =
        !checkStyles || (actualStyles?.trim() == expectedStyles?.trim());
    final cursorMatch =
        !checkCursor || (actualCursor?.trim() == expectedCursor?.trim());

    if (stylesMatch && cursorMatch) return;

    if (!stylesMatch) {
      await _saveFailureArtifacts(
        testName,
        actualStyles ?? '',
        expectedStyles ?? '',
        'styles',
      );
    }
    if (!cursorMatch) {
      await _saveFailureArtifacts(
        testName,
        actualCursor ?? '',
        expectedCursor ?? '',
        'cursor',
      );
    }
    final failures = <String>[];
    if (!stylesMatch) failures.add('per-cell styles');
    if (!cursorMatch) failures.add('cursor state');
    fail(
      'Golden style sidecar failed for $testName\n'
      'Mismatched: ${failures.join(' and ')}\n'
      'Check failure artifacts in $_failureDir/\n'
      'Re-run the relevant test with UPDATE_GOLDENS=1 to update them.',
    );
  }

  String _serializeCapturedSuite(
    Map<String, CapturedBuffer> captures,
    String Function(CapturedBuffer captured) serialize,
  ) {
    final out = StringBuffer();
    for (final entry in captures.entries) {
      if (out.isNotEmpty) out.writeln();
      out.writeln('=== TEST: ${entry.key} ===');
      final body = serialize(entry.value).trimRight();
      if (body.isNotEmpty) out.writeln(body);
    }
    return out.toString();
  }

  Future<void> _saveBufferGolden(String bufferPath, String buffer) async {
    await File(bufferPath).writeAsString(buffer);
  }

  Future<void> _compareBufferGolden(
    String testName,
    String bufferPath,
    String actualBuffer,
  ) async {
    final bufferFile = File(bufferPath);
    if (!bufferFile.existsSync()) {
      fail(
        'Golden buffer file not found: $bufferPath\n'
        'Re-run the relevant test with UPDATE_GOLDENS=1 to create it.',
      );
    }

    final expectedBuffer = await bufferFile.readAsString();

    // Compare buffers with normalized trailing whitespace per line but
    // preserve leading spaces. Using trim() alone can hide alignment bugs.
    if (_normalizeBuffer(actualBuffer) == _normalizeBuffer(expectedBuffer)) {
      return;
    }

    await _saveFailureArtifacts(
      testName,
      actualBuffer,
      expectedBuffer,
      'buffer',
    );
    fail(
      'Golden buffer mismatch for $testName\n'
      'Expected: $bufferPath\n'
      'Actual: ${path.join(_failureDir, '$testName.actual.buffer.txt')}\n'
      'Re-run the relevant test with UPDATE_GOLDENS=1 to update the golden file.',
    );
  }

  Future<void> _saveFailureArtifacts(
    String testName,
    String actual,
    String expected,
    String type,
  ) async {
    final failureDir = Directory(_failureDir);
    if (!failureDir.existsSync()) {
      await failureDir.create(recursive: true);
    }

    final actualPath = path.join(_failureDir, '$testName.actual.$type.txt');
    final expectedPath = path.join(_failureDir, '$testName.expected.$type.txt');
    final diffPath = path.join(_failureDir, '$testName.diff.$type.txt');

    await File(actualPath).writeAsString(actual);
    await File(expectedPath).writeAsString(expected);

    // Create a simple diff
    final diff = _createDiff(expected, actual);
    await File(diffPath).writeAsString(diff);
  }

  String _createDiff(String expected, String actual) {
    final expectedLines = expected.split('\n');
    final actualLines = actual.split('\n');
    final diff = StringBuffer();

    diff
      ..writeln('--- Expected')
      ..writeln('+++ Actual')
      ..writeln('@@');

    final maxLength = [
      expectedLines.length,
      actualLines.length,
    ].reduce((a, b) => a > b ? a : b);

    for (var i = 0; i < maxLength; i++) {
      final expectedLine = i < expectedLines.length ? expectedLines[i] : '';
      final actualLine = i < actualLines.length ? actualLines[i] : '';

      if (expectedLine != actualLine) {
        if (expectedLine.isNotEmpty) diff.writeln('- $expectedLine');
        if (actualLine.isNotEmpty) diff.writeln('+ $actualLine');
      } else {
        diff.writeln('  $expectedLine');
      }
    }

    return diff.toString();
  }
}
