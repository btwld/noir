import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/inline_host.dart';
import 'package:test/test.dart';

const _eraseToEnd = '\x1b[K';
const _eraseRow = '\r\x1b[K';

void main() {
  group('InlineHost frames', () {
    test('draws the row in place and erases what follows it', () {
      final session = _Session.start(const Text('hello'), columns: 40);
      addTearDown(session.dispose);

      expect(session.sink.writes, isEmpty);
      session.pump();

      expect(session.sink.writes, <String>['\rhello$_eraseToEnd']);
    });

    test('writes nothing when a frame paints nothing new', () {
      final session = _Session.start(const Text('hello'), columns: 40);
      addTearDown(session.dispose);
      session
        ..pump()
        ..pump(const Duration(milliseconds: 16));

      expect(session.sink.writes, hasLength(1));
    });

    test('animates the spinner with the frame time the test supplies', () {
      final session = _Session.start(
        const Row(children: <Widget>[Spinner(), Text(' scanning')]),
        columns: 40,
      );
      addTearDown(session.dispose);

      for (final milliseconds in const <int>[0, 120, 200, 280]) {
        session.pump(Duration(milliseconds: milliseconds));
      }

      expect(session.sink.writes.map(_visibleText), <String>[
        '${SpinnerFrames.dots[0]} scanning',
        '${SpinnerFrames.dots[1]} scanning',
        '${SpinnerFrames.dots[2]} scanning',
        '${SpinnerFrames.dots[3]} scanning',
      ]);
      for (final write in session.sink.writes) {
        expect(write, startsWith('\r'));
        expect(write, endsWith(_eraseToEnd));
      }
    });

    test('repaints when the widget rebuilds from caller state', () {
      final step = ValueNotifier<String>('one');
      addTearDown(step.dispose);
      final session = _Session.start(_StepLabel(step), columns: 40);
      addTearDown(session.dispose);
      session.pump();

      step.value = 'two';
      session.pump(const Duration(milliseconds: 16));

      expect(session.sink.writes.map(_visibleText), <String>['one', 'two']);
    });
  });

  group('InlineHost width', () {
    test('no row reaches the last column, at any width', () {
      final contents = <String, Widget>{
        'short': const Row(
          children: <Widget>[
            Spinner(),
            Text(' 2/8 '),
            Expanded(child: Text('Lines')),
            Text('12 s'),
          ],
        ),
        'long': const Row(
          children: <Widget>[
            Spinner(),
            Text(' 2/8 '),
            Expanded(
              child: Text(
                'Function complexity and duplicated code across every '
                'package of a very large workspace, measured twice',
              ),
            ),
            Text('1234 min 5 s'),
          ],
        ),
        'wide glyphs': const Text('進捗状況を表示しています進捗状況を表示しています'),
      };

      for (final entry in contents.entries) {
        for (var columns = 1; columns <= 100; columns++) {
          final session = _Session.start(entry.value, columns: columns);
          try {
            session.pump();
            session.host.printAbove('done');
            expect(session.sink.writes, isNotEmpty);
            for (final row in session.sink.rows) {
              expect(
                terminalStringWidth(row),
                lessThan(columns),
                reason: '${entry.key} at $columns columns wrote "$row"',
              );
            }
          } finally {
            session.dispose();
          }
        }
      }
    });

    test('uses every column but the last', () {
      final session = _Session.start(
        const Text('abcdefghijklmnopqrstuvwxyz'),
        columns: 10,
      );
      addTearDown(session.dispose);
      session.pump();

      expect(session.sink.rows.single, 'abcdefghi');
    });

    test('draws nothing in a one-column terminal', () {
      final session = _Session.start(const Text('hello'), columns: 1);
      addTearDown(session.dispose);
      session.pump();
      session.host.printAbove('done');

      expect(session.sink.writes, <String>[
        _eraseRow,
        '${_eraseRow}done\n$_eraseRow',
      ]);
    });

    test('lays the next row out at the width a resize reports', () {
      final session = _Session.start(
        const Text('abcdefghijklmnopqrstuvwxyz'),
        columns: 20,
      );
      addTearDown(session.dispose);
      session.pump();
      expect(session.sink.rows.single, 'abcdefghijklmnopqrs');

      session
        ..resizeTo(8)
        ..pump(const Duration(milliseconds: 16));

      expect(session.sink.rows.last, 'abcdefg');

      session
        ..resizeTo(30)
        ..pump(const Duration(milliseconds: 32));

      expect(session.sink.rows.last, 'abcdefghijklmnopqrstuvwxyz');
    });

    test('never redraws a row laid out for the previous width', () {
      final session = _Session.start(
        const Text('abcdefghijklmnopqrstuvwxyz'),
        columns: 20,
      );
      addTearDown(session.dispose);
      session
        ..pump()
        ..resizeTo(8);
      session.host.printAbove('done');

      expect(session.sink.writes.last, '${_eraseRow}done\n$_eraseRow');
    });

    test('skips a frame laid out for a width the terminal no longer has', () {
      final label = ValueNotifier<String>('abcdefghijklmnopqrstuvwxyz');
      addTearDown(label.dispose);
      final session = _Session.start(_StepLabel(label), columns: 20);
      addTearDown(session.dispose);
      session.pump();
      final written = session.sink.writes.length;

      // The terminal shrinks and a frame is painted before any resize
      // notification has been delivered.
      session.setColumns(8);
      label.value = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
      session.pump(const Duration(milliseconds: 16));

      expect(session.sink.writes, hasLength(written));
      expect(session.binding.debugHasScheduledFrame, isTrue);

      session.pump(const Duration(milliseconds: 32));
      expect(session.sink.rows.last, 'ABCDEFG');
    });

    test('printAbove never redraws a row wider than a shrunken terminal', () {
      final session = _Session.start(
        const Text('abcdefghijklmnopqrstuvwxyz'),
        columns: 20,
      );
      addTearDown(session.dispose);
      session.pump();

      session.setColumns(8);
      session.host.printAbove('done');

      expect(session.sink.writes.last, '${_eraseRow}done\n$_eraseRow');
      session.pump(const Duration(milliseconds: 16));
      expect(session.sink.rows.last, 'abcdefg');
    });

    test('erases the row at one column and restores it at two', () {
      final session = _Session.start(const Text('hello'), columns: 2);
      addTearDown(session.dispose);
      session.pump();
      expect(session.sink.writes, <String>['\rh$_eraseToEnd']);

      session.resizeTo(1);
      expect(session.sink.writes.last, _eraseRow);

      session.resizeTo(2);
      expect(session.sink.writes.last, '\rh$_eraseToEnd');
    });

    test('ignores a resize event that reports the same width', () {
      final session = _Session.start(const Text('hello'), columns: 40);
      addTearDown(session.dispose);
      session
        ..pump()
        ..resizeTo(40);

      expect(session.binding.debugHasScheduledFrame, isFalse);
      expect(session.sink.writes, hasLength(1));
    });

    test('keeps the last width when the reader fails or reports none', () {
      var fail = false;
      var columns = 20;
      final session = _Session.startWith(
        const Text('abcdefghijklmnopqrstuvwxyz'),
        columns: () {
          if (fail) throw StateError('no terminal');
          return columns;
        },
      );
      addTearDown(session.dispose);
      session.pump();

      fail = true;
      session.resizes.add(null);
      fail = false;
      columns = 0;
      session.resizes.add(null);

      expect(session.binding.debugHasScheduledFrame, isFalse);
      expect(session.sink.rows.single, 'abcdefghijklmnopqrs');
    });
  });

  group('InlineHost colors', () {
    test('leaves the terminal background and text color alone', () {
      final session = _Session.start(const Text('plain'), columns: 40);
      addTearDown(session.dispose);
      session.pump();

      expect(session.sink.writes.single, '\rplain$_eraseToEnd');
    });

    test('writes a painted background with the text color over it', () {
      final session = _Session.start(
        const Row(
          children: <Widget>[
            Text('a', style: TextStyle(backgroundColor: Color.black)),
            Text('b'),
          ],
        ),
        columns: 40,
      );
      addTearDown(session.dispose);
      session.pump();

      expect(
        session.sink.writes.single,
        '\r\x1b[0;38;2;255;255;255;48;2;0;0;0ma\x1b[0mb$_eraseToEnd',
      );
    });

    test('writes a partly transparent background blended over black', () {
      // OpenTUI blends a translucent color against an opaque black backdrop,
      // on the full screen and here alike, so it never reaches the row as
      // a tint of the user's terminal.
      final session = _Session.start(
        const Text(
          'a',
          style: TextStyle(backgroundColor: Color.whiteTransparent),
        ),
        columns: 40,
      );
      addTearDown(session.dispose);
      session.pump();

      expect(
        session.sink.writes.single,
        '\r\x1b[0;38;2;255;255;255;48;2;128;128;128ma\x1b[0m$_eraseToEnd',
      );
    });

    test('writes a color a widget chose and resets before erasing', () {
      final session = _Session.start(
        const Text(
          'warn',
          style: TextStyle(color: Color.red, fontWeight: FontWeight.bold),
        ),
        columns: 40,
      );
      addTearDown(session.dispose);
      session.pump();

      expect(
        session.sink.writes.single,
        '\r\x1b[0;1;38;2;255;0;0mwarn\x1b[0m$_eraseToEnd',
      );
    });

    test('with colors off, keeps attributes and drops every color', () {
      final session = _Session.start(
        const Row(
          children: <Widget>[
            Spinner(),
            Text(
              ' warn',
              style: TextStyle(
                color: Color.red,
                backgroundColor: Color.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        columns: 40,
        colors: false,
      );
      addTearDown(session.dispose);
      session.pump();

      expect(
        session.sink.writes.single,
        '\r${SpinnerFrames.dots[0]}\x1b[0;1m warn\x1b[0m$_eraseToEnd',
      );
    });
  });

  test('text from a widget cannot inject a control sequence', () {
    final session = _Session.start(const Text('a\x1b[31mb\x07c'), columns: 40);
    addTearDown(session.dispose);
    session.pump();

    final written = session.sink.writes.single;
    expect(written, startsWith('\r'));
    expect(written, endsWith(_eraseToEnd));
    final row = written.substring(1, written.length - _eraseToEnd.length);
    expect(row.runes.where((rune) => rune < 0x20 || rune == 0x7f), isEmpty);
    expect(row, contains('a'));
    expect(row, contains('b'));
    expect(row, contains('c'));
  });

  group('InlineHost boundaries', () {
    test('hosts the row on a headless binding', () {
      // A headless binding acquires no input driver and no signal handler,
      // and never sets a terminal up.
      final session = _Session.start(const Text('x'), columns: 40);
      addTearDown(session.dispose);

      expect(session.binding.isHeadless, isTrue);
    });

    test('writes no control output but return, erase-to-end, and SGR', () {
      final session = _Session.start(
        const Row(
          children: <Widget>[
            Spinner(),
            Text(
              ' warn ',
              style: TextStyle(
                color: Color.red,
                backgroundColor: Color.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(child: Text('a step with a rather long name')),
          ],
        ),
        columns: 30,
      );
      session
        ..pump()
        ..pump(const Duration(milliseconds: 120));
      session.host.printAbove('done');
      session
        ..resizeTo(12)
        ..pump(const Duration(milliseconds: 200))
        ..resizeTo(1)
        ..resizeTo(40)
        ..pump(const Duration(milliseconds: 300))
        ..dispose();

      // Anything else would be a mode switch: an alternate screen, a hidden
      // cursor, a cleared screen, a cursor move, or a query.
      final allowed = RegExp(r'\x1b\[[0-9;]*m|\x1b\[K|\r|\n');
      final remainder = session.sink.writes.join().replaceAll(allowed, '');
      expect(
        remainder.runes.where((rune) => rune < 0x20 || rune == 0x7f),
        isEmpty,
        reason: 'unexpected control output in "$remainder"',
      );
    });

    test('a child that fails to mount is rethrown, with nothing left', () {
      final sink = _RecordingSink();
      final resizes = StreamController<void>(sync: true);
      // A controller nobody listened to never completes its close future.
      addTearDown(() => unawaited(resizes.close()));

      expect(
        () => createInlineHostForTesting(
          child: const _FailsToMount(),
          sink: sink,
          columns: () => 40,
          resizes: resizes.stream,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'mount failed',
          ),
        ),
      );
      expect(resizes.hasListener, isFalse);
      expect(sink.writes, isEmpty);
    });

    test('may be disposed from a callback that runs inside a frame', () {
      late final _Session session;
      session = _Session.start(
        _CallsOnTick(() => session.host.dispose()),
        columns: 40,
      );
      session.pump();

      expect(
        () => session.pump(const Duration(milliseconds: 16)),
        returnsNormally,
      );
      expect(session.sink.writes.last, _eraseRow);
    });
  });

  group('InlineHost.printAbove', () {
    test('erases the row, writes the line, then redraws the row', () {
      final session = _Session.start(const Text('live'), columns: 40);
      addTearDown(session.dispose);
      session.pump();

      session.host.printAbove('  ✓ 1/8 Line counts   0.8 s');

      expect(session.sink.writes, <String>[
        '\rlive$_eraseToEnd',
        '$_eraseRow  ✓ 1/8 Line counts   0.8 s\n\rlive$_eraseToEnd',
      ]);
    });

    test('writes only the line before the first frame', () {
      final session = _Session.start(const Text('live'), columns: 40);
      addTearDown(session.dispose);

      session.host.printAbove('starting');

      expect(session.sink.writes, <String>['${_eraseRow}starting\n$_eraseRow']);
    });

    test('keeps a line longer than the terminal intact', () {
      final session = _Session.start(const Text('live'), columns: 10);
      addTearDown(session.dispose);
      session.pump();
      const warning = 'Warning: the cache directory cannot be written';

      session.host.printAbove(warning);

      expect(
        session.sink.writes.last,
        '$_eraseRow$warning\n\rlive$_eraseToEnd',
      );
    });

    test('throws once the host is disposed', () {
      final session = _Session.start(const Text('live'), columns: 40);
      session.dispose();

      expect(() => session.host.printAbove('late'), throwsStateError);
    });
  });

  group('InlineHost.dispose', () {
    test('erases the row and leaves the cursor at the line start', () {
      final session = _Session.start(const Text('live'), columns: 40);
      session.pump();

      session.host.dispose();

      expect(session.sink.writes.last, _eraseRow);
    });

    test('stops the frame timer and the resize watcher', () {
      final session = _Session.start(const Spinner(), columns: 40);
      session.pump();
      expect(session.binding.debugHasScheduledFrame, isTrue);
      expect(session.resizes.hasListener, isTrue);

      session.host.dispose();

      expect(session.binding.debugHasScheduledFrame, isFalse);
      expect(session.resizes.hasListener, isFalse);
    });

    test('writes nothing afterwards and is safe to call twice', () {
      final session = _Session.start(const Spinner(), columns: 40);
      session.pump();
      session.host.dispose();
      final written = session.sink.writes.length;

      session.host.dispose();
      session.binding.debugFlushFrame(const Duration(milliseconds: 200));
      session.resizes.add(null);

      expect(session.sink.writes, hasLength(written));
    });
  });

  group('InlineHost.start', () {
    test('needs a width reader for a sink that is not a terminal', () {
      expect(
        () => InlineHost.start(sink: StringBuffer(), child: const Text('x')),
        throwsA(
          isA<ArgumentError>().having((error) => error.name, 'name', 'columns'),
        ),
      );
    });

    test('draws on any sink once the caller supplies the width', () async {
      final sink = _RecordingSink();
      final host = InlineHost.start(
        sink: sink,
        columns: () => 12,
        child: const Text('abcdefghijklmnopqrstuvwxyz'),
      );
      addTearDown(host.dispose);

      // The first frame runs from a zero-delay timer created by start().
      await Future<void>.delayed(Duration.zero);

      expect(sink.rows, <String>['abcdefghijk']);
    });

    test('rejects a first width that is not positive', () {
      expect(
        () => InlineHost.start(
          sink: _RecordingSink(),
          columns: () => 0,
          child: const Text('x'),
        ),
        throwsArgumentError,
      );
    });
  });

  group('InlineHost.canDrawOn', () {
    test('refuses a sink that is not a terminal stream', () {
      expect(InlineHost.canDrawOn(StringBuffer()), isFalse);
      expect(InlineHost.canDrawOn(_RecordingSink()), isFalse);
    });

    test('needs a terminal that takes escape sequences and has a width', () {
      bool supported({
        bool hasTerminal = true,
        bool isWindows = false,
        bool supportsAnsiEscapes = true,
        String? term = 'xterm-256color',
        int? columns = 80,
      }) => inlineHostSupportsTerminal(
        hasTerminal: hasTerminal,
        isWindows: isWindows,
        supportsAnsiEscapes: supportsAnsiEscapes,
        term: term,
        columns: columns,
      );

      expect(supported(), isTrue);
      expect(supported(term: 'tmux-256color'), isTrue);
      expect(supported(hasTerminal: false), isFalse);
      expect(supported(term: 'dumb'), isFalse);
      expect(supported(term: ''), isFalse);
      expect(supported(term: null), isFalse);
      // Outside Windows only TERM decides.
      expect(supported(supportsAnsiEscapes: false), isTrue);
      expect(supported(isWindows: true, term: null), isTrue);
      expect(supported(isWindows: true, supportsAnsiEscapes: false), isFalse);
      // A terminal with no window size would make start() throw.
      expect(supported(columns: 0), isFalse);
      expect(supported(columns: null), isFalse);
    });
  });
}

/// One host under test with the seams a test drives it through.
final class _Session {
  _Session._(this.host, this.binding, this.sink, this.resizes, this._columns);

  factory _Session.start(
    Widget child, {
    required int columns,
    bool colors = true,
  }) {
    final width = <int>[columns];
    return _Session.startWith(
      child,
      columns: () => width[0],
      colors: colors,
      width: width,
    );
  }

  factory _Session.startWith(
    Widget child, {
    required int Function() columns,
    bool colors = true,
    List<int>? width,
  }) {
    final sink = _RecordingSink();
    // Closed by dispose().
    // ignore: close_sinks
    final resizes = StreamController<void>(sync: true);
    final mounted = createInlineHostForTesting(
      child: child,
      sink: sink,
      columns: columns,
      resizes: resizes.stream,
      colors: colors,
    );
    return _Session._(mounted.host, mounted.binding, sink, resizes, width);
  }

  final InlineHost host;
  final TuiBinding binding;
  final _RecordingSink sink;
  final StreamController<void> resizes;
  final List<int>? _columns;

  void pump([Duration timestamp = Duration.zero]) {
    binding.debugFlushFrame(timestamp);
  }

  /// Changes the terminal width without delivering a resize notification.
  void setColumns(int columns) {
    _columns![0] = columns;
  }

  void resizeTo(int columns) {
    setColumns(columns);
    resizes.add(null);
  }

  void dispose() {
    host.dispose();
    unawaited(resizes.close());
  }
}

/// Records every write separately, so a test can assert one write per frame.
final class _RecordingSink implements StringSink {
  final List<String> writes = <String>[];

  /// The live rows written so far, without control sequences.
  ///
  /// A `printAbove` write contributes only the row it redraws: the line it
  /// prints above belongs to scrollback and may be any width.
  List<String> get rows => <String>[
    for (final write in writes) _visibleText(write.split('\n').last),
  ];

  @override
  void write(Object? object) => writes.add('$object');

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

final _controlSequence = RegExp(r'\x1b\[[0-9;?]*[A-Za-z]');

String _visibleText(String written) =>
    written.replaceAll(_controlSequence, '').replaceAll('\r', '');

final class _StepLabel extends StatefulWidget {
  const _StepLabel(this.step);

  final ValueNotifier<String> step;

  @override
  State<_StepLabel> createState() => _StepLabelState();
}

final class _StepLabelState extends State<_StepLabel> {
  @override
  void initState() {
    super.initState();
    widget.step.addListener(_handleChange);
  }

  @override
  void dispose() {
    widget.step.removeListener(_handleChange);
    super.dispose();
  }

  void _handleChange() => setState(() {});

  @override
  Widget build(BuildContext context) => Text(widget.step.value);
}

final class _FailsToMount extends StatefulWidget {
  const _FailsToMount();

  @override
  State<_FailsToMount> createState() => _FailsToMountState();
}

final class _FailsToMountState extends State<_FailsToMount> {
  @override
  void initState() {
    super.initState();
    throw StateError('mount failed');
  }

  @override
  Widget build(BuildContext context) => const Text('unreachable');
}

/// Runs [onTick] once, from a ticker, which is inside a frame.
final class _CallsOnTick extends StatefulWidget {
  const _CallsOnTick(this.onTick);

  final void Function() onTick;

  @override
  State<_CallsOnTick> createState() => _CallsOnTickState();
}

final class _CallsOnTickState extends State<_CallsOnTick>
    with SingleTickerProviderStateMixin<_CallsOnTick> {
  late final Ticker _ticker;
  var _called = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (_called) return;
      _called = true;
      widget.onTick();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ticking');
}
