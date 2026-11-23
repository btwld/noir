@Tags(['safe-process-spawning'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/inline_host.dart';
import 'package:test/test.dart';

import '../../example/inline_progress.dart';

void main() {
  group('ScanRow', () {
    test('shows the spinner, counter, name, and time on the step', () {
      final row = _Row.start(columns: 60);
      addTearDown(row.dispose);

      row.start();
      expect(
        row.text,
        startsWith('${SpinnerFrames.dots.first} 1/5 Line counts'),
      );
      expect(row.text, endsWith(' 0 s'));
      expect(terminalStringWidth(row.text), 59);

      row.pump(const Duration(seconds: 12));
      expect(row.text, endsWith(' 12 s'));

      row.pump(const Duration(minutes: 3, seconds: 5));
      expect(row.text, endsWith(' 3 min 5 s'));
    });

    test('a new step shows its name and starts the clock again', () {
      final row = _Row.start(columns: 60);
      addTearDown(row.dispose);
      row
        ..start()
        ..pump(const Duration(seconds: 12));
      expect(row.text, endsWith(' 12 s'));

      row.step.value = 1;
      row.pump(const Duration(seconds: 12));

      expect(
        row.text,
        contains(' 2/5 Function complexity and duplicated code'),
      );
      expect(row.text, endsWith(' 0 s'));

      row.pump(const Duration(seconds: 15));
      expect(row.text, endsWith(' 3 s'));
    });

    test('cuts a long name with an ellipsis and keeps the time', () {
      final row = _Row.start(columns: 30, step: 1);
      addTearDown(row.dispose);

      row.start();

      expect(
        row.text,
        '${SpinnerFrames.dots.first} 2/5 Function complex... 0 s',
      );
      expect(terminalStringWidth(row.text), 29);
    });

    test('keeps the time on the step while the row is compact', () {
      final row = _Row.start(columns: 60);
      addTearDown(row.dispose);
      row
        ..start()
        ..pump(const Duration(seconds: 12));
      expect(row.text, endsWith(' 12 s'));

      row
        ..resizeTo(compactRowWidth)
        ..pump(const Duration(seconds: 13));
      expect(row.text, endsWith(' 1/5'));

      // Wide again, in the middle of the same step: the clock kept running.
      row
        ..resizeTo(60)
        ..pump(const Duration(seconds: 15));
      expect(row.text, contains(' 1/5 Line counts'));
      expect(row.text, endsWith(' 15 s'));
    });

    test('below the compact width keeps only the spinner and counter', () {
      final row = _Row.start(columns: compactRowWidth);
      addTearDown(row.dispose);

      row.start();

      expect(row.text, '${SpinnerFrames.dots.first} 1/5');
    });
  });

  test(
    'LiveProgress draws the row, prints finished steps above, and clears',
    () async {
      final output = StringBuffer();
      final progress = LiveProgress(output, colors: false, columns: () => 60)
        ..started(0);
      // The first frame runs from a zero-delay timer that the host created.
      await Future<void>.delayed(Duration.zero);
      progress
        ..finished(0, const Duration(milliseconds: 900))
        ..started(1)
        ..close();

      final written = output.toString();
      expect(
        written,
        startsWith('\r${SpinnerFrames.dots.first} 1/5 Line counts'),
      );
      expect(written, contains('\r\x1b[K  ✓ 1/5 Line counts  0.9 s\n'));
      expect(written, endsWith('\r\x1b[K'));
    },
  );

  test('formatElapsed switches units as the time grows', () {
    expect(formatElapsed(const Duration(milliseconds: 940)), '0 s');
    expect(
      formatElapsed(const Duration(milliseconds: 940), tenths: true),
      '0.9 s',
    );
    expect(formatElapsed(const Duration(seconds: 12), tenths: true), '12 s');
    expect(formatElapsed(const Duration(minutes: 3, seconds: 5)), '3 min 5 s');
    expect(
      formatElapsed(const Duration(minutes: 1234, seconds: 5)),
      '1234 min 5 s',
    );
  });

  test(
    'outside a terminal, reports plain lines and keeps stdout for the report',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>['run', 'example/inline_progress.dart', '5'],
        workingDirectory: Directory.current.path,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      // `dart run` reports build-hook progress itself, on stdout or on
      // stderr depending on the SDK, and with no line break after it.
      final hookProgress = RegExp(r'Running (build|link) hooks\.\.\.');
      final stdoutText = (result.stdout as String).replaceAll(hookProgress, '');
      final stderrText = (result.stderr as String).replaceAll(hookProgress, '');
      expect(result.exitCode, 0, reason: '$stdoutText\n$stderrText');

      expect(stdoutText, contains('Scan complete: 5 steps.'));
      expect(stdoutText, isNot(contains('Line counts')));

      expect(stderrText, isNot(contains('\x1b')));
      expect(stderrText, isNot(contains('\r')));
      final lines = const LineSplitter().convert(stderrText);
      expect(
        lines,
        containsAllInOrder(<Matcher>[
          equals('1/5 Line counts...'),
          matches(RegExp(r'^1/5 Line counts  \d+\.\d s$')),
          equals('5/5 Report...'),
          matches(RegExp(r'^5/5 Report  \d+\.\d s$')),
        ]),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// [ScanRow] mounted in an inline host that the test paces frame by frame.
final class _Row {
  _Row._(
    this.step,
    this._host,
    this._binding,
    this._output,
    this._resizes,
    this._columns,
  );

  factory _Row.start({required int columns, int step = 0}) {
    final notifier = ValueNotifier<int>(step);
    final output = StringBuffer();
    final width = <int>[columns];
    // Closed by dispose().
    // ignore: close_sinks
    final resizes = StreamController<void>(sync: true);
    final mounted = createInlineHostForTesting(
      child: ScanRow(step: notifier),
      sink: output,
      columns: () => width[0],
      resizes: resizes.stream,
    );
    return _Row._(
      notifier,
      mounted.host,
      mounted.binding,
      output,
      resizes,
      width,
    );
  }

  final ValueNotifier<int> step;
  final InlineHost _host;
  final TuiBinding _binding;
  final StringBuffer _output;
  final StreamController<void> _resizes;
  final List<int> _columns;

  /// The row as last drawn, without control sequences.
  String get text => _output
      .toString()
      .split('\r')
      .last
      .replaceAll(RegExp(r'\x1b\[[0-9;?]*[A-Za-z]'), '');

  /// Mounts the row and starts its clocks at frame time zero.
  ///
  /// `LayoutBuilder` builds its subtree during the first layout, which is
  /// after that frame ticked, so the spinner takes its start from the frame
  /// that follows.
  void start() {
    pump();
    pump();
  }

  void pump([Duration timestamp = Duration.zero]) {
    _binding.debugFlushFrame(timestamp);
  }

  /// Reports a new terminal width, as a resize notification would.
  void resizeTo(int columns) {
    _columns[0] = columns;
    _resizes.add(null);
  }

  void dispose() {
    _host.dispose();
    step.dispose();
    unawaited(_resizes.close());
  }
}
