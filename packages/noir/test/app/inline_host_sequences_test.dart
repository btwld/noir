/// Random event sequences against an inline host, checked against a model of
/// the terminal's line.
///
/// Every sequence comes from a fixed seed. A failure names the seed and lists
/// the events that led to it, so the sequence can be replayed, and then pinned
/// as a focused test in `inline_host_test.dart`.
library;

import 'dart:async';
import 'dart:math';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/inline_host.dart';
import 'package:test/test.dart';

const _seeds = 150;
const _eventsPerSeed = 40;
const _widths = <int>[1, 2, 3, 5, 8, 13, 21, 40, 80];
const _erase = '\r\x1b[K';
const _frame = Duration(milliseconds: 16);

void main() {
  for (final polls in const <bool>[false, true]) {
    final watcher = polls ? 'width polls' : 'resize notifications';
    test('random event sequences keep the promises, with $watcher', () {
      for (var seed = 0; seed < _seeds; seed++) {
        _Sequence(seed, polls: polls).play();
      }
    });
  }
}

/// One host, the terminal it draws on, and the events of one seed.
final class _Sequence {
  _Sequence(this.seed, {required this.polls}) : _random = Random(seed) {
    _terminal = _Terminal(_pick(_widths));
    _label = ValueNotifier<String>(_word());
    // One sequence in three meets a sink that fails on one of its writes.
    final failAt = _random.nextInt(3) == 0 ? 1 + _random.nextInt(12) : null;
    _sink = _ModelSink(_terminal, failAt: failAt);
    // The watcher's listener belongs to the zone it was started in, so that
    // is where an error met by a notification is reported.
    runZonedGuarded(() {
      final mounted = createInlineHostForTesting(
        child: _Label(_label),
        sink: _sink,
        columns: _readWidth,
        resizes: _resizes.stream,
        resizesArePolls: polls,
      );
      _host = mounted.host;
      _binding = mounted.binding;
    }, (error, stackTrace) => _reported.add(error));
  }

  final int seed;
  final bool polls;
  final Random _random;
  // Closed by play().
  // ignore: close_sinks
  final StreamController<void> _resizes = StreamController<void>(sync: true);
  late final _Terminal _terminal;
  late final ValueNotifier<String> _label;
  late final _ModelSink _sink;
  late final InlineHost _host;
  late final TuiBinding _binding;

  final List<String> _events = <String>[];

  /// Errors a notification met, which reach the zone of the watcher.
  final List<Object> _reported = <Object>[];

  /// Errors an event threw to the code that caused it.
  final List<Object> _thrown = <Object>[];

  /// The lines printed above so far, in order.
  final List<String> _printed = <String>[];

  Duration _clock = Duration.zero;

  /// What the reader does on its next read instead of reporting the width.
  String? _readerFault;

  /// Whether a read failed during the current event. The host then cannot
  /// know the terminal's width, and is not held to it.
  bool _readFailed = false;

  /// The terminal's width at the last read that reported it.
  int? _widthRead;

  /// Whether anything happened since the last frame that may change the line.
  bool _dirty = true;
  bool _ended = false;

  void play() {
    try {
      for (var index = 0; index < _eventsPerSeed && !_ended; index++) {
        _step();
      }
      if (!_ended) {
        expect(_terminal.scrollback, _printed);
        _dispose();
      }
    } on TestFailure catch (failure) {
      final watcher = polls ? 'width polls' : 'resize notifications';
      fail(
        'Seed $seed with $watcher: ${failure.message}\n'
        'Events:\n  ${_events.join('\n  ')}',
      );
    } finally {
      try {
        _host.dispose();
      } on Object {
        // The failure that led here, if any, is the one to report.
      }
      unawaited(_resizes.close());
      _label.dispose();
    }
  }

  void _step() {
    final roll = _random.nextInt(100);
    if (roll < 32) {
      _pump();
    } else if (roll < 46) {
      _relabel();
    } else if (roll < 61) {
      _printAbove();
    } else if (roll < 73) {
      _resizeTerminal(notify: true);
    } else if (roll < 81) {
      _resizeTerminal(notify: false);
    } else if (roll < 88) {
      _notify();
    } else if (roll < 97) {
      _armReaderFault();
    } else {
      _dispose();
    }
  }

  void _pump() {
    final writes = _during('frame', () {
      _binding.debugFlushFrame(_clock += _frame);
    });
    if (_ended) {
      return;
    }
    expect(writes.length, lessThan(2), reason: 'more than one write a frame');
    for (final write in writes) {
      expect(write, isNot(contains('\n')), reason: 'a frame wrote a line');
    }
    if (_readFailed) {
      return;
    }
    if (!_dirty) {
      expect(writes, isEmpty, reason: 'a frame rewrote an unchanged row');
    }
    final width = _terminal.width;
    final expected = width < 2
        ? ''
        : _label.value.substring(0, min(_label.value.length, width - 1));
    expect(_terminal.line, expected, reason: 'the line after a frame');
    _dirty = false;
  }

  void _relabel() {
    final next = _word();
    _events.add('label "$next"');
    if (next != _label.value) {
      _label.value = next;
      _dirty = true;
    }
  }

  void _printAbove() {
    final line = 'L${_printed.length}';
    final writes = _during('printAbove $line', () => _host.printAbove(line));
    if (_ended) {
      return;
    }
    expect(writes, hasLength(1), reason: 'printAbove is one write');
    expect(writes.single, startsWith('$_erase$line\n'));
    _printed.add(line);
  }

  void _resizeTerminal({required bool notify}) {
    final width = _pick(_widths);
    final how = notify ? 'with a notification' : 'silently';
    if (!notify) {
      _events.add('terminal $width wide, $how');
      _terminal.width = width;
      _dirty = true;
      return;
    }
    final writes = _during('terminal $width wide, $how', () {
      _terminal.width = width;
      _resizes.add(null);
    });
    _dirty = true;
    if (_ended) {
      return;
    }
    expect(writes.length, lessThan(2), reason: 'two writes a notification');
  }

  void _notify() {
    final unchanged = _widthRead == _terminal.width;
    final writes = _during('notification', () => _resizes.add(null));
    if (_ended) {
      return;
    }
    expect(writes.length, lessThan(2), reason: 'two writes a notification');
    if (polls) {
      if (unchanged && !_readFailed) {
        expect(writes, isEmpty, reason: 'a poll at the same width wrote');
      }
    } else {
      _dirty = true;
    }
  }

  void _armReaderFault() {
    final fault = _random.nextBool() ? 'throws' : 'reports no columns';
    _events.add('the next width read $fault');
    _readerFault = fault;
    _dirty = true;
  }

  void _dispose() {
    final writes = _during('dispose', _host.dispose);
    expect(_thrown, isEmpty, reason: 'dispose threw');
    expect(_reported, isEmpty, reason: 'dispose reported an error');
    if (!_sink.failed) {
      expect(writes, <String>[_erase], reason: 'dispose erases the row');
    }
    _expectStopped();
  }

  /// Runs one event and returns what the sink took during it.
  ///
  /// When the sink failed in it, checks that the host stopped and that the
  /// failure surfaced once, and ends the sequence.
  List<String> _during(String event, void Function() body) {
    _events.add(event);
    _readFailed = false;
    final written = _sink.writes.length;
    final failedBefore = _sink.failed;
    try {
      body();
    } on Object catch (error) {
      _thrown.add(error);
    }
    final writes = _sink.writes.sublist(written);
    if (!_readFailed) {
      for (final write in writes) {
        _expectRowFits(write);
      }
    }
    if (_sink.failed && !failedBefore && event != 'dispose') {
      expect(
        <Object>[..._thrown, ..._reported],
        <Object>[same(_sink.failure)],
        reason: 'a sink failure surfaces exactly once',
      );
      _expectStopped();
    } else if (event != 'dispose') {
      expect(_thrown, isEmpty, reason: 'the event threw');
      expect(_reported, isEmpty, reason: 'an error reached the zone');
    }
    return writes;
  }

  /// The row a write leaves on the cursor's line fits the terminal as it is
  /// at that moment: it never reaches the last column.
  void _expectRowFits(String write) {
    final live = write.substring(write.lastIndexOf('\n') + 1);
    expect(
      live,
      allOf(startsWith('\r'), endsWith('\x1b[K')),
      reason: 'the row is not redrawn in place',
    );
    final row = live.substring(1, live.length - 3).replaceAll(_style, '');
    expect(
      terminalStringWidth(row),
      lessThan(max(_terminal.width, 1)),
      reason: 'a row as wide as the ${_terminal.width} column terminal',
    );
  }

  /// Nothing of the host is left running, and nothing more is written.
  void _expectStopped() {
    _ended = true;
    expect(_resizes.hasListener, isFalse, reason: 'the watcher is still on');
    expect(
      _binding.debugHasScheduledFrame,
      isFalse,
      reason: 'a frame is still scheduled',
    );
    final attempts = _sink.attempts;
    _binding.debugFlushFrame(_clock += _frame);
    expect(() => _host.printAbove('late'), throwsStateError);
    expect(_host.dispose, returnsNormally);
    expect(_sink.attempts, attempts, reason: 'a write after the host ended');
  }

  int _readWidth() {
    final fault = _readerFault;
    _readerFault = null;
    if (fault != null) {
      _readFailed = true;
      if (fault == 'throws') {
        throw StateError('no terminal');
      }
      return 0;
    }
    return _widthRead = _terminal.width;
  }

  T _pick<T>(List<T> values) => values[_random.nextInt(values.length)];

  String _word() {
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    final length = _random.nextInt(31);
    return String.fromCharCodes(<int>[
      for (var index = 0; index < length; index++)
        letters.codeUnitAt(_random.nextInt(letters.length)),
    ]);
  }
}

final _style = RegExp(r'\x1b\[[0-9;]*m');

/// The part of a terminal the host's output can reach: the line the cursor
/// is on, and the lines above it.
///
/// It does not wrap. Whether a row would have wrapped is checked where the
/// row is written, against the width the terminal has at that moment.
final class _Terminal {
  _Terminal(this.width);

  int width;
  final List<String> scrollback = <String>[];
  final List<String> _cells = <String>[];
  int _cursor = 0;

  String get line => _cells.join().trimRight();

  void receive(String text) {
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '\r') {
        _cursor = 0;
      } else if (char == '\n') {
        scrollback.add(line);
        _cells.clear();
        _cursor = 0;
      } else if (char == '\x1b') {
        final end = text.indexOf(RegExp('[A-Za-z]'), index);
        final sequence = text.substring(index, end + 1);
        if (sequence == '\x1b[K') {
          if (_cells.length > _cursor) {
            _cells.removeRange(_cursor, _cells.length);
          }
        } else if (!_style.hasMatch(sequence)) {
          fail('The host wrote an unexpected control sequence.');
        }
        index = end;
      } else {
        while (_cells.length <= _cursor) {
          _cells.add(' ');
        }
        _cells[_cursor] = char;
        _cursor++;
      }
    }
  }
}

/// Passes what the host writes on to the terminal, except for one write
/// that throws when [failAt] is set.
final class _ModelSink implements StringSink {
  _ModelSink(this._terminal, {this.failAt});

  final _Terminal _terminal;

  /// The write attempt that throws, counting from one.
  final int? failAt;
  final StateError failure = StateError('sink closed');
  final List<String> writes = <String>[];
  int attempts = 0;

  /// Whether the failing write has been attempted.
  bool get failed {
    final failAt = this.failAt;
    return failAt != null && attempts >= failAt;
  }

  @override
  void write(Object? object) {
    attempts++;
    if (attempts == failAt) {
      throw failure;
    }
    final text = '$object';
    writes.add(text);
    _terminal.receive(text);
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

/// Shows the text [label] holds.
final class _Label extends StatefulWidget {
  const _Label(this.label);

  final ValueNotifier<String> label;

  @override
  State<_Label> createState() => _LabelState();
}

final class _LabelState extends State<_Label> {
  @override
  void initState() {
    super.initState();
    widget.label.addListener(_changed);
  }

  @override
  void dispose() {
    widget.label.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  @override
  Widget build(BuildContext context) => Text(widget.label.value);
}
