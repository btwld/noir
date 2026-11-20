/// Inline hosting: one live row on a sink the application chooses.
library;

import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';

import '../core/ansi_row.dart';
import '../core/buffer.dart';
import '../core/renderer.dart';
import '../foundation/disposable.dart';
import '../foundation/first_error.dart';
import '../framework/widget.dart';
import 'tui_binding.dart';

/// Hosts a widget as one live row, redrawn in place on a sink.
///
/// A command-line program that reports progress on stderr while its result
/// goes to stdout cannot use [runTuiApp]: that takes over the screen and reads
/// the keyboard. An inline host mounts the same widgets — `Row`, `Text`,
/// `Spinner`, anything that fits one row — and repaints them on the line the
/// cursor is on, leaving the rest of the terminal to the program.
///
/// ```dart
/// final host = InlineHost.start(
///   sink: stderr,
///   child: const Row(children: [Spinner(), Text(' Scanning')]),
/// );
/// host.printAbove('Line counts done');
/// host.dispose();
/// ```
///
/// The host writes only to the sink it was given. It never writes to stdout,
/// never reads stdin or changes its mode, never enters the alternate screen,
/// clears the screen or hides the cursor, and installs no handler for an
/// interrupt or termination signal. Each frame is a single write: a carriage
/// return, the row, and an erase to the end of the line.
///
/// The row is laid out one column narrower than the terminal. A row that
/// reached the last column would wrap, and a wrapped row cannot be redrawn in
/// place. Content that does not fit is cut off by its own layout, as it is in
/// any Noir tree: use `Expanded` for the part that may shrink, a `Text`
/// overflow for how it shrinks, and `LayoutBuilder` to swap in a shorter row
/// below some width. In a terminal one column wide nothing is drawn.
///
/// A cell no widget painted behind keeps the terminal's own background, and
/// text in the framework's default color over such a cell keeps the
/// terminal's own text color, so a row stays readable on a light terminal as
/// well as a dark one. Opaque colors a widget chooses are written as they
/// are. A partly transparent color is blended over black before it is
/// written, as it is on the full screen, so use opaque colors in a row whose
/// backdrop is the user's terminal.
///
/// Frames run from timers on the isolate that created the host, so the row
/// animates while that isolate is idle: do long work in another isolate or in
/// asynchronous steps. Until [dispose] is called the host keeps the process
/// alive and owns the line, so write completed steps and warnings with
/// [printAbove] rather than to the sink directly.
///
/// When a terminal is made narrower, it may re-wrap the row already on
/// screen before the host draws the next one. The host cannot see that, so a
/// fragment of the old row can stay on the line above.
final class InlineHost implements Disposable {
  InlineHost._({
    required Widget child,
    required StringSink sink,
    required int Function() columns,
    required Stream<void> resizes,
    required bool colors,
  }) : _sink = sink,
       _readColumns = columns,
       _colors = colors {
    final initialColumns = columns();
    if (initialColumns <= 0) {
      throw ArgumentError.value(
        initialColumns,
        'columns',
        'must report a positive terminal width',
      );
    }
    _columns = initialColumns;

    final renderer = Renderer.create(
      _rowWidth(initialColumns),
      1,
      testing: true,
    )..setAutoFlush(false);
    _renderer = renderer;
    TuiBinding? binding;
    try {
      binding = createInlineTuiBinding(
        width: _rowWidth(initialColumns),
        renderer: renderer,
        presentFrame: _presentFrame,
      );
      _binding = binding;
      binding.runApp(child);
      _resizeSubscription = _watch(resizes);
    } on Object catch (error, stackTrace) {
      _disposed = true;
      void rollback(void Function() action) {
        try {
          action();
        } on Object {
          // The start failure remains primary after rollback is attempted.
        }
      }

      if (binding != null) {
        rollback(binding.dispose);
      }
      rollback(renderer.dispose);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Mounts [child] as a live row on [sink] and schedules its first frame.
  ///
  /// [columns] reads the width of the terminal [sink] writes to. It defaults
  /// to the terminal width of [sink] itself when that is a terminal stream
  /// such as `stderr`. It is required for any other sink; [canDrawOn] tells
  /// the two apart. Pass a reader for the stream the row is really shown on:
  /// the width of stdout says nothing about a row on stderr once either is
  /// redirected. The host calls it again before every row it writes and on
  /// every resize notification, so it should be cheap.
  ///
  /// With [colors] false no color is written at all, while attributes such
  /// as bold and underline still are. That is the behavior the `NO_COLOR`
  /// convention asks for.
  ///
  /// Throws [ArgumentError] when [columns] is missing for a sink that is not
  /// a terminal stream, or when it first reports a width that is not
  /// positive. An error [columns] itself throws on that first read is not
  /// caught. A later read that fails keeps the last width instead.
  factory InlineHost.start({
    required StringSink sink,
    required Widget child,
    int Function()? columns,
    bool colors = true,
  }) => InlineHost._(
    child: child,
    sink: sink,
    columns: columns ?? _terminalColumnsOf(sink),
    resizes: _terminalResizes(),
    colors: colors,
  );

  /// Whether [sink] is a terminal an inline host can draw on.
  ///
  /// True for `stdout` or `stderr` attached to a terminal that understands
  /// escape sequences and reports a width. False for a redirected stream, a
  /// `dumb` terminal, a terminal with no window size, or any other
  /// [StringSink]. A program normally keeps its own plain output for the
  /// false case and starts a host only when this is true.
  ///
  /// `Stdout.supportsAnsiEscapes` is documented as a best-effort check that
  /// does not recognize every terminal, so outside Windows the answer comes
  /// from the `TERM` environment variable instead.
  static bool canDrawOn(StringSink sink) =>
      sink is io.Stdout &&
      inlineHostSupportsTerminal(
        hasTerminal: sink.hasTerminal,
        isWindows: io.Platform.isWindows,
        supportsAnsiEscapes: sink.supportsAnsiEscapes,
        term: io.Platform.environment['TERM'],
        columns: _terminalColumnsOrNull(sink),
      );

  static const String _eraseToEnd = '\x1b[K';
  static const String _eraseLine = '\r$_eraseToEnd';

  final StringSink _sink;
  final int Function() _readColumns;
  final bool _colors;
  late final Renderer _renderer;
  late final TuiBinding _binding;
  StreamSubscription<void>? _resizeSubscription;
  late int _columns;

  /// The last painted row, already serialized for the current width.
  String _row = '';
  bool _disposed = false;

  /// Writes [line] above the live row, where it stays in scrollback.
  ///
  /// The row is erased, [line] and a line break are written, and the row is
  /// drawn again below, all in one write. [line] is written exactly as given
  /// and may be longer than the terminal is wide; a terminal wraps it like
  /// any other output.
  ///
  /// Throws [StateError] after [dispose].
  void printAbove(String line) {
    if (_disposed) {
      throw StateError('InlineHost is disposed.');
    }
    // The row is redrawn below, so it must fit the terminal as it is now.
    _syncWidth();
    _sink.write('$_eraseLine$line\n${_liveRow()}');
  }

  /// Stops the row and releases everything the host holds.
  ///
  /// Cancels the frame timer and the resize watcher, so nothing here keeps
  /// the process alive afterwards, then erases the row and leaves the cursor
  /// at the start of that empty line. Nothing is written after this returns.
  /// A second call does nothing.
  ///
  /// An animation or ticker callback may call this: the frame it runs in
  /// ends there. Do not call it from a `build` method.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    FirstErrorRecorder()
      ..attempt(() => _resizeSubscription?.cancel().ignore())
      ..attempt(_binding.dispose)
      ..attempt(_renderer.dispose)
      ..attempt(() => _sink.write(_eraseLine))
      ..rethrowFirst();
  }

  /// The row's width for a terminal [columns] wide: every column but the last.
  ///
  /// The buffer cannot be narrower than one cell, so one column also maps to
  /// one cell; [_liveRow] is what keeps that cell off a one-column terminal.
  static int _rowWidth(int columns) => columns < 2 ? 1 : columns - 1;

  /// The text that puts the current row on the sink's line.
  String _liveRow() => _columns < 2 ? _eraseLine : '\r$_row$_eraseToEnd';

  void _presentFrame(Buffer frame) {
    if (_disposed) {
      return;
    }
    // A resize notification can arrive after the terminal has already
    // changed, so every frame checks the width it is about to be shown at.
    if (_syncWidth()) {
      // This frame was laid out for a width the terminal no longer has, and
      // the frame that replaces it is already scheduled.
      return;
    }
    _row = encodeAnsiRow(readBufferRow(frame, 0), colors: _colors);
    _sink.write(_liveRow());
  }

  StreamSubscription<void>? _watch(Stream<void> resizes) {
    try {
      return resizes.listen(
        (_) => _handleResize(),
        // A watcher that fails leaves the row at its last width.
        onError: (Object _) {},
      );
    } on Object {
      // Some runtimes cannot watch terminal resize notifications.
      return null;
    }
  }

  void _handleResize() {
    if (_disposed) {
      return;
    }
    final previousColumns = _columns;
    if (!_syncWidth() && _columns != previousColumns) {
      // One and two columns share a one-cell row, so no new frame follows.
      // Only whether that cell may be shown has changed.
      _sink.write(_liveRow());
    }
  }

  /// Reads the terminal width again and adopts it.
  ///
  /// Returns true when the row has to be laid out again. The row laid out
  /// for the old width is then forgotten rather than redrawn, and the frame
  /// that replaces it is scheduled.
  bool _syncWidth() {
    final int columns;
    try {
      columns = _readColumns();
    } on Object {
      // The sink's terminal can go away mid-run; keep the last known width.
      return false;
    }
    if (columns <= 0 || columns == _columns) {
      return false;
    }
    final previousWidth = _rowWidth(_columns);
    _columns = columns;
    final width = _rowWidth(columns);
    if (width == previousWidth) {
      return false;
    }
    _row = '';
    _binding.handleResize(width, 1);
    return true;
  }
}

/// Decides [InlineHost.canDrawOn] from the facts about a terminal stream.
@internal
@visibleForTesting
bool inlineHostSupportsTerminal({
  required bool hasTerminal,
  required bool isWindows,
  required bool supportsAnsiEscapes,
  required String? term,
  required int? columns,
}) {
  // A terminal that reports no width could not start a host.
  if (!hasTerminal || columns == null || columns <= 0) {
    return false;
  }
  if (isWindows) {
    return supportsAnsiEscapes;
  }
  return term != null && term.isNotEmpty && term != 'dumb';
}

/// Starts a host with an injected width reader and resize notifications.
///
/// Returns the binding beside the host so a test can flush frames at
/// timestamps it chooses instead of waiting for the frame timer.
@internal
@visibleForTesting
({InlineHost host, TuiBinding binding}) createInlineHostForTesting({
  required Widget child,
  required StringSink sink,
  required int Function() columns,
  required Stream<void> resizes,
  bool colors = true,
}) {
  final host = InlineHost._(
    child: child,
    sink: sink,
    columns: columns,
    resizes: resizes,
    colors: colors,
  );
  return (host: host, binding: host._binding);
}

int Function() _terminalColumnsOf(StringSink sink) {
  if (sink is io.Stdout && sink.hasTerminal) {
    return () => sink.terminalColumns;
  }
  throw ArgumentError.value(
    null,
    'columns',
    'is required when the sink is not a terminal stream. Check '
        'InlineHost.canDrawOn(sink) first, or pass a width reader',
  );
}

/// The terminal width of [sink], or null when it cannot be read.
int? _terminalColumnsOrNull(io.Stdout sink) {
  try {
    return sink.terminalColumns;
  } on Object {
    return null;
  }
}

/// Notifies when the terminal may have changed size.
///
/// Watching the window-change signal does not alter how the process reacts
/// to it, since its default action is to ignore it. Windows has no such
/// signal, so the width is polled there, as the full-screen session does.
Stream<void> _terminalResizes() => io.Platform.isWindows
    ? Stream<void>.periodic(const Duration(milliseconds: 100))
    : io.ProcessSignal.sigwinch.watch().map((_) {});
