// Inline progress: one live row on stderr while the report goes to stdout.
//
//   dart run example/inline_progress.dart
//   dart run example/inline_progress.dart > report.txt
//   dart run example/inline_progress.dart 2> progress.log
//
// With stdout redirected the row still animates on the terminal. With stderr
// redirected there is no terminal to draw on, so each step is one plain line
// that is never redrawn.
//
// The simulated scan runs in a second isolate and reports over a port. The
// main isolate stays idle, which is what lets the spinner keep turning. Pass
// a number to set how long each simulated step takes, in milliseconds.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:noir/noir.dart';

/// The steps of the simulated scan, in order.
const scanSteps = <String>[
  'Line counts',
  'Function complexity and duplicated code',
  'Dependency graph',
  'Unused declarations',
  'Report',
];

/// Below this row width, [ScanRow] shows only the spinner and the counter.
const compactRowWidth = 24;

Future<void> main(List<String> arguments) async {
  final stepDuration = Duration(
    milliseconds: arguments.isEmpty ? 900 : int.parse(arguments.single),
  );
  final progress = InlineHost.canDrawOn(stderr)
      ? LiveProgress(
          stderr,
          colors: (Platform.environment['NO_COLOR'] ?? '').isEmpty,
        )
      : PlainProgress(stderr);

  final events = ReceivePort();
  await Isolate.spawn(_scan, (
    events: events.sendPort,
    stepDuration: stepDuration,
  ));

  final watch = Stopwatch();
  int? running;
  try {
    await for (final event in events) {
      if (running != null) {
        progress.finished(running, watch.elapsed);
      }
      if (event is! int) {
        break;
      }
      running = event;
      watch
        ..reset()
        ..start();
      progress.started(event);
    }
  } finally {
    events.close();
    progress.close();
  }

  stdout.writeln('Scan complete: ${scanSteps.length} steps.');
}

/// The simulated work. It only waits, where a real scan would compute.
Future<void> _scan(({SendPort events, Duration stepDuration}) job) async {
  for (var index = 0; index < scanSteps.length; index++) {
    job.events.send(index);
    await Future<void>.delayed(job.stepDuration);
  }
  job.events.send(null);
}

/// Where the scan reports each step.
abstract interface class ScanProgress {
  /// Step [index] has begun.
  void started(int index);

  /// Step [index] ended after [took].
  void finished(int index, Duration took);

  /// Releases whatever the reporter holds.
  void close();
}

/// Draws the running step as one live row and prints finished steps above it.
final class LiveProgress implements ScanProgress {
  /// Starts the row on [sink], which must be a terminal the host can draw on.
  LiveProgress(StringSink sink, {required bool colors}) {
    _host = InlineHost.start(
      sink: sink,
      colors: colors,
      child: ScanRow(step: _step),
    );
  }

  final ValueNotifier<int> _step = ValueNotifier<int>(0);
  late final InlineHost _host;

  @override
  void started(int index) {
    _step.value = index;
  }

  @override
  void finished(int index, Duration took) {
    _host.printAbove('  ✓ ${describeFinishedStep(index, took)}');
  }

  @override
  void close() {
    _host.dispose();
    _step.dispose();
  }
}

/// Writes one line per step, for a stream that is not a terminal.
final class PlainProgress implements ScanProgress {
  /// Reports on [sink] without any control sequence.
  PlainProgress(this._sink);

  final StringSink _sink;

  @override
  void started(int index) {
    _sink.writeln('${index + 1}/${scanSteps.length} ${scanSteps[index]}...');
  }

  @override
  void finished(int index, Duration took) {
    _sink.writeln(describeFinishedStep(index, took));
  }

  @override
  void close() {}
}

/// The line for a finished step, such as `1/5 Line counts  0.9 s`.
String describeFinishedStep(int index, Duration took) =>
    '${index + 1}/${scanSteps.length} ${scanSteps[index]}  '
    '${formatElapsed(took, tenths: true)}';

/// Formats [elapsed] as `12 s` or `3 min 5 s`.
///
/// With [tenths], a time under ten seconds keeps one decimal: `0.9 s`.
String formatElapsed(Duration elapsed, {bool tenths = false}) {
  if (elapsed.inMinutes > 0) {
    return '${elapsed.inMinutes} min ${elapsed.inSeconds % 60} s';
  }
  if (tenths && elapsed.inSeconds < 10) {
    return '${(elapsed.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
  return '${elapsed.inSeconds} s';
}

/// The live row: spinner, counter, step name, and time on the step so far.
///
/// The name takes the space the other parts leave and is cut with an
/// ellipsis. Below [compactRowWidth] the name and the time are dropped.
class ScanRow extends StatefulWidget {
  /// Shows the step whose index [step] holds.
  const ScanRow({required this.step, super.key});

  /// Index into [scanSteps] of the running step.
  final ValueListenable<int> step;

  @override
  State<ScanRow> createState() => _ScanRowState();
}

class _ScanRowState extends State<ScanRow> {
  @override
  void initState() {
    super.initState();
    widget.step.addListener(_handleStepChange);
  }

  @override
  void didUpdateWidget(ScanRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.step, widget.step)) {
      oldWidget.step.removeListener(_handleStepChange);
      widget.step.addListener(_handleStepChange);
    }
  }

  @override
  void dispose() {
    widget.step.removeListener(_handleStepChange);
    super.dispose();
  }

  void _handleStepChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final index = widget.step.value;
    final counter = Text(' ${index + 1}/${scanSteps.length} ');
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width != null && width < compactRowWidth) {
          return Row(children: <Widget>[const Spinner(), counter]);
        }
        return Row(
          children: <Widget>[
            const Spinner(),
            counter,
            Expanded(
              child: Text(
                scanSteps[index],
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // A new key per step starts the clock again from zero.
            ElapsedText(key: ValueKey<int>(index)),
          ],
        );
      },
    );
  }
}

/// Time since this widget was mounted, repainted once a second.
///
/// It reads frame time from a [Ticker] rather than a wall clock, so it costs
/// no timer of its own and a test can advance it by pumping frames.
class ElapsedText extends StatefulWidget {
  /// Starts counting when the widget is mounted.
  const ElapsedText({super.key});

  @override
  State<ElapsedText> createState() => _ElapsedTextState();
}

class _ElapsedTextState extends State<ElapsedText>
    with SingleTickerProviderStateMixin<ElapsedText> {
  late final Ticker _ticker;
  var _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_handleTick)..start();
  }

  void _handleTick(Duration elapsed) {
    if (elapsed.inSeconds != _elapsed.inSeconds) {
      setState(() => _elapsed = elapsed);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
    ' ${formatElapsed(_elapsed)}',
    style: TextStyle(color: Theme.of(context).textMuted),
  );
}
