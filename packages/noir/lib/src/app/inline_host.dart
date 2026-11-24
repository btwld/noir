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
/// are. A partly transparent color is blended before it is written: a
/// background over black, as it is on the full screen, and a text color over
/// the background behind it, or over black where none is painted. Use opaque
/// colors in a row whose backdrop is the user's terminal.
///
/// Frames run from timers on the isolate that created the host, so the row
/// animates while that isolate is idle: do long work in another isolate or in
/// asynchronous steps. Until [dispose] is called the host keeps the process
/// alive and owns the line, so write completed steps and warnings with
/// [printAbove] rather than to the sink directly.
///
/// If the sink throws, the host stops for good. It cancels its frame timer
/// and its resize watcher, does not write to that sink again, and lets the
/// error surface once: from the frame or the resize notification that met
/// it, or from the [printAbove] call. [dispose] then does nothing.
///
/// The width reader and the sink are the caller's code, and may call back
/// into the host: the reader may call [printAbove] and [dispose], and the
/// sink may call [dispose]. The host asks for the width before it does
/// anything else, so when the reader ends the host, what the host was about
/// to do does not happen. The host does not read the width again while the
/// reader is running, so a reader may itself use [printAbove]; the row is
/// then left off the line until what asked for the width is over, because
/// its width is the very thing being read.
///
/// The widgets of the row may call [printAbove] and [dispose] from an
/// animation or ticker callback. While the row is being built, laid out, or
/// painted, both methods throw a [StateError] instead, write nothing, and
/// leave the host running. That covers `build`, the `State` lifecycle
/// methods a rebuild runs (`initState`, `didUpdateWidget`, `deactivate`,
/// `dispose`), a `LayoutBuilder` builder, and the layout and paint of a
/// render object. The tree cannot be torn down under the frame that is
/// walking it, so end the host from outside that frame.
///
/// A frame in which a widget throws draws nothing: the line keeps what it
/// showed until the next frame, [printAbove] call, or resize notification.
///
/// Text a widget shows is made safe on the way out: a control character is
/// written as a space. A zero-width character that stands alone, such as a
/// zero-width space in a file name, comes out as blanks or stray characters,
/// as it does on the full screen. It never stops the row.
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
    required bool resizesArePolls,
    required bool colors,
  }) : _sink = sink,
       _readColumns = columns,
       _resizesArePolls = resizesArePolls,
       _colors = colors {
    final initialColumns = columns();
    if (initialColumns <= 0) {
      throw ArgumentError.value(
        initialColumns,
        'columns',
        'must report a positive terminal width',
      );
    }
    _columns = _capped(initialColumns);
    final rowWidth = _rowWidth(_columns);

    final renderer = Renderer.create(rowWidth, 1, testing: true)
      ..setAutoFlush(false);
    _renderer = renderer;
    TuiBinding? binding;
    try {
      binding = createInlineTuiBinding(
        width: rowWidth,
        renderer: renderer,
        beginFrame: _beginFrame,
        endFrame: _endFrame,
      );
      _binding = binding;
      binding.runApp(child);
      _resizeSubscription = _watch(resizes);
    } on Object catch (error, stackTrace) {
      _disposed = true;
      if (binding != null) {
        _quietly(binding.dispose);
      }
      _quietly(renderer.dispose);
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
  /// redirected. The host calls it again at the start of every frame, in
  /// [printAbove], and on every resize notification, so it should be cheap.
  /// A width above 65,535, the most a terminal's window size can report, is
  /// treated as 65,535.
  ///
  /// With [colors] false no color is written at all, while attributes such
  /// as bold and underline still are. That is the behavior the `NO_COLOR`
  /// convention asks for.
  ///
  /// Throws [ArgumentError] when [columns] is missing for a sink that is not
  /// a terminal stream, or when it first reports a width that is not
  /// positive. An error [columns] itself throws on that first read is not
  /// caught. A later read that fails, or reports no columns, keeps the last
  /// width instead. The one later failure that is passed on is that of a
  /// reader which had ended the host before it threw.
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
    resizesArePolls: io.Platform.isWindows,
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

  /// The widest terminal there can be: a window size holds its columns in
  /// sixteen bits. The cap keeps a reader that reports nonsense from asking
  /// the renderer for an enormous row.
  static const int _maxColumns = 0xFFFF;

  final StringSink _sink;
  final int Function() _readColumns;

  /// Whether a resize notification is only a prompt to look at the width
  /// again, as on Windows, rather than word that the terminal changed.
  final bool _resizesArePolls;
  final bool _colors;
  late final Renderer _renderer;
  late final TuiBinding _binding;
  StreamSubscription<void>? _resizeSubscription;

  /// The terminal's width as last read. The binding is always laid out for
  /// it: a new width is applied where it is read.
  late int _columns;

  /// The last painted row, already serialized, or null when no frame has
  /// painted one at the current width yet. A frame is then on its way to.
  String? _row;

  /// What the host last put on the line, or null when it cannot know:
  /// nothing is written yet, or the terminal changed size and may have
  /// re-wrapped or cleared the line.
  String? _shown;

  /// Whether the width reader is running. What it starts in the host does
  /// not read the width again.
  bool _reading = false;
  bool _disposed = false;

  /// Writes [line] above the live row, where it stays in scrollback.
  ///
  /// The row is erased, [line] and a line break are written, and the row is
  /// drawn again below, all in one write. [line] may be longer than the
  /// terminal is wide; a terminal wraps it like any other output.
  ///
  /// The one case in which the row is not drawn again at once is a terminal
  /// that has changed width since the row was painted. That row would not
  /// fit, so the line below [line] stays empty until the next frame has
  /// painted the row at the new width.
  ///
  /// [line] is written exactly as given, control characters included, so
  /// that it can carry its own styling. Unlike the text of a widget, it is
  /// not made safe: escape any part that comes from outside the program,
  /// such as a file name, before passing it here. A carriage return or an
  /// escape sequence in it reaches the terminal and can overwrite or restyle
  /// what is on screen. A style the line selects and does not reset stays
  /// selected for the row below and for whatever is written next, so end a
  /// styled line with a reset.
  ///
  /// Throws [StateError] after [dispose], including when the width reader
  /// ends the host during this call, and while the row is being built, laid
  /// out, or painted. If the sink throws, the host stops, as the class
  /// documentation describes, and that error is rethrown. So is an error the
  /// width reader throws after it has ended the host.
  void printAbove(String line) {
    _checkNotDisposed();
    _checkNotWalkingTree('printAbove');
    _run(() {
      _sync();
      // The reader is the caller's code and may have ended this host.
      _checkNotDisposed();
      final row = _live();
      _sink.write('$_eraseLine$line\n$row');
      _shown = row;
    });
  }

  /// Stops the row and releases everything the host holds.
  ///
  /// Cancels the frame timer and the resize watcher, so nothing here keeps
  /// the process alive afterwards, then erases the row and leaves the cursor
  /// at the start of that empty line. Nothing is written after this returns.
  /// A second call does nothing, and neither does a call after the sink has
  /// failed.
  ///
  /// Erasing the row is the one step that is only attempted. If the sink
  /// does not take that write, the row stays as it was and nothing is thrown
  /// for it: this usually runs in a `finally` block, where its error would
  /// replace the caller's own.
  ///
  /// An animation or ticker callback may call this: the frame it runs in
  /// ends there.
  ///
  /// The one call that is refused is one made while the row is being built,
  /// laid out, or painted, as the class documentation describes. It throws
  /// a [StateError] before anything is stopped, so the host keeps running
  /// and still has to be disposed, from outside that frame.
  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _checkNotWalkingTree('dispose');
    _disposed = true;
    final failures = FirstErrorRecorder()
      ..attempt(_cancelResizeWatch)
      ..attempt(_binding.dispose)
      ..attempt(_renderer.dispose);
    _quietly(() => _sink.write(_eraseLine));
    failures.rethrowFirst();
  }

  /// The row's width for a terminal [columns] wide: every column but the last.
  ///
  /// The buffer cannot be narrower than one cell, so one column also maps to
  /// one cell; [_live] is what keeps that cell off a one-column terminal.
  static int _rowWidth(int columns) => columns < 2 ? 1 : columns - 1;

  static int _capped(int columns) =>
      columns > _maxColumns ? _maxColumns : columns;

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('InlineHost is disposed.');
    }
  }

  /// The tree cannot be resized or torn down under the frame that is walking
  /// it, and both methods that may do either are refused there, before they
  /// have written or changed anything.
  void _checkNotWalkingTree(String method) {
    if (_binding.isWalkingTree) {
      throw StateError(
        'InlineHost.$method() cannot be called while the row is being built, '
        'laid out, or painted, which includes the build and State lifecycle '
        'methods of its widgets. Call it from a timer, an event handler, or '
        'an animation callback instead.',
      );
    }
  }

  /// Runs the host's part of one operation: a frame, a [printAbove], or a
  /// resize notification.
  ///
  /// Every operation has the same steps. It reads the width with [_sync]
  /// before it does anything else, does its work, and puts the row on the
  /// line. A frame is the one operation that is split in two: it reads the
  /// width in [_beginFrame], the binding then builds and paints the tree,
  /// and [_endFrame] puts the row on the line.
  ///
  /// Whatever fails in the host's part ends the host on the spot, without
  /// going back to the sink, and is rethrown, which leaves it the only error
  /// reported. An error a widget throws while the tree is built or painted
  /// is not the host's: the frame passes it on and the host keeps running.
  void _run(void Function() operation) {
    try {
      operation();
    } on Object {
      _stop();
      rethrow;
    }
  }

  /// Reads the terminal's width and applies a new one.
  ///
  /// The reader is the caller's code, and this is the only place it is
  /// called from. It runs first in an operation, when nothing of that
  /// operation is in flight, so check [_disposed] after this returns and
  /// simply stop: the reader may have ended the host.
  ///
  /// A read that fails, or reports no columns, teaches nothing: the terminal
  /// of the sink can go away mid-run, and the last width stays.
  void _sync() {
    if (_reading) {
      // It is the reader that called into the host.
      return;
    }
    final int read;
    _reading = true;
    try {
      read = _readColumns();
    } on Object {
      if (_disposed) {
        // The reader ended the host, or a printAbove it made failed and
        // did. Keeping the error here would stop the host without a word
        // to anyone.
        rethrow;
      }
      return;
    } finally {
      _reading = false;
    }
    if (_disposed || read <= 0) {
      return;
    }
    final columns = _capped(read);
    if (columns == _columns) {
      return;
    }
    final rowWidth = _rowWidth(columns);
    final rowWidthChanged = rowWidth != _rowWidth(_columns);
    _columns = columns;
    // The terminal may have re-wrapped or cleared the line.
    _shown = null;
    if (rowWidthChanged) {
      // The row was painted for a width the terminal has left. The resize
      // marks the tree for paint and schedules a frame. Outside a frame that
      // is the frame that paints the row. Inside one, the frame in progress
      // paints it, and the scheduled one finds nothing left to do.
      _row = null;
      _binding.handleResize(rowWidth, 1);
    }
  }

  /// The text that puts the row on the sink's line, or that clears the line
  /// when there is no row to put there: none painted at this width yet, a
  /// terminal one column wide, or a width that is being read right now.
  String _live() {
    final row = _row;
    return row == null || _columns < 2 || _reading
        ? _eraseLine
        : '\r$row$_eraseToEnd';
  }

  /// Puts the current row on the line, unless it is already there.
  ///
  /// A frame paints whenever a widget rebuilds, which for an animation is
  /// every frame, while the row it produces changes far less often. The
  /// full-screen renderer writes only the cells that changed; this is the
  /// same economy for one row.
  void _show() {
    if (_row == null) {
      // The frame that paints the row at this width shows it.
      return;
    }
    final live = _live();
    if (live == _shown) {
      return;
    }
    _sink.write(live);
    _shown = live;
  }

  /// The start of a frame, before its tickers run and before it builds.
  ///
  /// A resize notification can arrive after the terminal has already
  /// changed, so every frame reads the width it is about to be shown at.
  void _beginFrame() => _run(_sync);

  /// The end of a frame that completed. [painted] is null when nothing in
  /// the tree needed painting.
  void _endFrame(Buffer? painted) => _run(() {
    if (painted != null) {
      _row = encodeAnsiRow(readBufferRow(painted, 0), colors: _colors);
    }
    _show();
  });

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
    if (_binding.isWalkingTree) {
      // A notification is a stream event, so only a synchronous stream in a
      // test can deliver one here. The next operation reads the width.
      return;
    }
    _run(() {
      _sync();
      if (_disposed) {
        return;
      }
      if (!_resizesArePolls) {
        // The notification is itself word that the terminal changed, even
        // when it reads the width it had: it may have gone to another width
        // and back, or changed height, and re-wrapped or cleared the line.
        _shown = null;
      }
      // One and two columns share a one-cell row, so the row may still be
      // there to show when the width has changed.
      _show();
    });
  }

  void _cancelResizeWatch() {
    _resizeSubscription?.cancel().ignore();
    _resizeSubscription = null;
  }

  /// Ends the host after something in an operation threw, without going
  /// back to the sink. [_run] rethrows the failure, which stays the only one
  /// reported.
  ///
  /// The teardown is immediate because no operation runs while the tree is
  /// being walked: see [_checkNotWalkingTree].
  void _stop() {
    if (_disposed) {
      // The caller, or one of its callbacks, has already ended the host.
      return;
    }
    _disposed = true;
    _quietly(_cancelResizeWatch);
    _quietly(_binding.dispose);
    _quietly(_renderer.dispose);
  }

  /// Runs [cleanup] on a path that already has a failure to report.
  static void _quietly(void Function() cleanup) {
    try {
      cleanup();
    } on Object {
      // The failure that led here remains the one that is reported.
    }
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
  bool resizesArePolls = false,
  bool colors = true,
}) {
  final host = InlineHost._(
    child: child,
    sink: sink,
    columns: columns,
    resizes: resizes,
    resizesArePolls: resizesArePolls,
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
