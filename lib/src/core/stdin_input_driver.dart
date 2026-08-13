import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import '../foundation/first_error.dart';
import 'input.dart';

/// Narrow stdin boundary used to acquire and release one terminal-input lease.
@visibleForTesting
abstract interface class StdinInputSource {
  /// Whether stdin is attached to a terminal.
  bool get hasTerminal;

  /// Whether stdin currently buffers input by line.
  bool get lineMode;

  /// Sets whether stdin buffers input by line.
  set lineMode(bool value);

  /// Whether stdin currently echoes input bytes.
  bool get echoMode;

  /// Sets whether stdin echoes input bytes.
  set echoMode(bool value);

  /// Subscribes [onData] to raw stdin bytes.
  StreamSubscription<List<int>> listen(void Function(List<int>) onData);
}

final class _StdinModeLease {
  _StdinModeLease._(this._source, this._savedLineMode, this._savedEchoMode);

  factory _StdinModeLease.acquire(StdinInputSource source) {
    final lease = _StdinModeLease._(source, source.lineMode, source.echoMode);
    try {
      source.echoMode = false;
      source.lineMode = false;
    } on Object catch (error, stackTrace) {
      try {
        lease.restore();
      } on Object {
        // The acquisition failure remains primary after rollback is attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return lease;
  }

  final StdinInputSource _source;
  final bool _savedLineMode;
  final bool _savedEchoMode;
  bool _restored = false;

  void restore() {
    if (_restored) return;

    final failures = FirstErrorRecorder();
    try {
      failures
        ..attempt(() => _source.lineMode = _savedLineMode)
        ..attempt(() => _source.echoMode = _savedEchoMode);
    } finally {
      _restored = true;
    }
    failures.rethrowFirst();
  }
}

final class _IoStdinInputSource implements StdinInputSource {
  const _IoStdinInputSource();

  @override
  bool get hasTerminal {
    try {
      return stdin.hasTerminal;
    } on FileSystemException {
      return false;
    }
  }

  @override
  bool get lineMode => stdin.lineMode;

  @override
  set lineMode(bool value) => stdin.lineMode = value;

  @override
  bool get echoMode => stdin.echoMode;

  @override
  set echoMode(bool value) => stdin.echoMode = value;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int>) onData) =>
      stdin.listen(onData);
}

/// Connects raw stdin bytes to the app input pipeline by parsing ANSI escape
/// sequences into key, mouse, paste, and terminal capability inputs.
///
/// Without this driver, `TuiBinding` paints to the screen but never receives
/// keystrokes from the terminal. Widget tests can inject through
/// `InputManager`; a real interactive app needs this driver to read stdin.
///
/// Recognised inputs:
/// - Printable ASCII and UTF-8 multi-byte characters
/// - Backspace (DEL `0x7f`, BS `0x08`), Tab `0x09`, Enter `0x0a`/`0x0d`
/// - Escape `0x1b` alone
/// - Ctrl+letter (1..26) — emitted as a letter [LogicalKeyboardKey] with the
///   `KeyModifiers.ctrl` bit set and no printable character
/// - CSI cursor keys: `ESC[A/B/C/D` → logical arrow keys
/// - CSI Home/End: `ESC[H` / `ESC[F`
/// - CSI tilde keys: `ESC[3~`/`ESC[5~`/`ESC[6~` → logical Delete/Page keys
/// - xterm modifyOtherKeys: `ESC[27;modifier;code~`
/// - Function keys F1–F12 via `ESC O P/Q/R/S` and `ESC[N~`
/// - SGR mouse: `ESC[<Cb;Cx;CyM/m` for press/release, drag, and wheel
/// - Bracketed paste: `ESC[200~...ESC[201~` accumulated into a single event
/// - Kitty keyboard CSI-u:
///   `ESC[keycode[:alternate];modifiers[:event-type];text u`
/// - Kitty functional and tilde keys with press/repeat/release event types
class StdinInputDriver {
  /// Routes parsed stdin events to [_inputDispatcher] when input is started.
  StdinInputDriver(
    this._inputDispatcher, {
    @visibleForTesting StdinInputSource? source,
  }) : _source = source ?? const _IoStdinInputSource();

  final InputDispatcher _inputDispatcher;
  final StdinInputSource _source;
  // Ownership moves to a local snapshot before stop invokes cancellation.
  // ignore: cancel_subscriptions
  StreamSubscription<List<int>>? _sub;
  _StdinModeLease? _modeLease;
  // Buffer for incomplete escape sequences split across reads.
  final List<int> _pending = <int>[];
  _DiscardedAnsiFrame? _discardedFrame;
  Timer? _escapeTimer;
  static const Duration _escapeFlushDelay = Duration(milliseconds: 25);

  /// Begins consuming stdin and returns whether terminal input was acquired.
  ///
  /// Returns `false` without mutating stdin when it is headless or piped.
  /// Acquisition failures restore the inherited modes before escaping.
  bool start() {
    if (_modeLease != null) return true;
    if (!_source.hasTerminal) return false;

    final lease = _StdinModeLease.acquire(_source);
    _modeLease = lease;
    try {
      _sub = _source.listen(_onBytes);
    } on Object catch (error, stackTrace) {
      _modeLease = null;
      try {
        lease.restore();
      } on Object {
        // The listen failure remains primary after rollback is attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return true;
  }

  /// Restores the acquired terminal modes, then stops consuming stdin.
  void stop() {
    final escapeTimer = _escapeTimer;
    final subscription = _sub;
    final lease = _modeLease;
    _escapeTimer = null;
    _sub = null;
    _modeLease = null;
    _pending.clear();
    _discardedFrame = null;
    escapeTimer?.cancel();

    final failures = FirstErrorRecorder();
    if (lease != null) {
      failures.attempt(lease.restore);
    }
    if (subscription != null) {
      failures.attempt(() {
        final cancellation = subscription.cancel();
        cancellation.ignore();
      });
    }
    failures.rethrowFirst();
  }

  void _onBytes(List<int> bytes) {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    final input = _pending.isEmpty ? bytes : <int>[..._pending, ...bytes];
    _pending.clear();

    var parseBytes = input;
    final discardedFrame = _discardedFrame;
    if (discardedFrame != null) {
      final recovery = _recoverDiscardedFrame(discardedFrame, input);
      if (!recovery.complete) {
        _pending.addAll(recovery.retainedPrefix);
        return;
      }
      _discardedFrame = null;
      if (recovery.nextIndex >= input.length) {
        return;
      }
      parseBytes = input.sublist(recovery.nextIndex);
    }

    final result = _parseBoundedAnsiInput(parseBytes, holdTrailingEscape: true);
    _pending
      ..clear()
      ..addAll(result.leftover);
    _discardedFrame = result._discardedFrame;
    for (final ev in result.events) {
      ev.dispatchTo(_inputDispatcher);
    }
    if (_discardedFrame == null &&
        _pending.length == 1 &&
        _pending.single == 0x1b) {
      _escapeTimer = Timer(_escapeFlushDelay, _flushPendingEscape);
    }
  }

  /// Feed raw bytes through the production parser path in integration tests.
  @visibleForTesting
  void debugFeedBytes(List<int> bytes) {
    _onBytes(bytes);
  }

  void _flushPendingEscape() {
    if (_discardedFrame != null ||
        _pending.length != 1 ||
        _pending.single != 0x1b) {
      return;
    }
    _pending.clear();
    KeyInput(
      _key(LogicalKeyboardKey.escape, keyCode: 27),
    ).dispatchTo(_inputDispatcher);
  }

  /// Flush a pending bare Escape immediately in integration tests.
  @visibleForTesting
  void debugFlushPendingEscape() {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    _flushPendingEscape();
  }
}

/// A single parsed input event from the ANSI byte stream.
abstract class ParsedInput {
  /// Initializes a typed parsed event that dispatches through its event lane.
  const ParsedInput();

  /// Forwards this parsed event to the matching dispatcher method.
  void dispatchTo(InputDispatcher dispatcher);
}

/// A parsed key event from the ANSI byte stream.
class KeyInput extends ParsedInput {
  /// Wraps [event] for dispatch through the key-input lane.
  const KeyInput(this.event);

  /// The parsed key event to dispatch.
  final KeyEvent event;
  @override
  void dispatchTo(InputDispatcher dispatcher) =>
      dispatcher.dispatchKeyEvent(event);
}

/// A parsed mouse event from the ANSI byte stream.
class MouseInput extends ParsedInput {
  /// Wraps [event] for dispatch through the mouse-input lane.
  const MouseInput(this.event);

  /// The parsed mouse event to dispatch.
  final MouseEvent event;
  @override
  void dispatchTo(InputDispatcher dispatcher) =>
      dispatcher.dispatchMouseEvent(event);
}

/// A complete bracketed-paste block. Delivered as a single [PasteEvent] —
/// subscribers see one event per paste, not one
/// synthetic key event per character.
class PasteInput extends ParsedInput {
  /// Wraps one decoded bracketed-paste block for paste dispatch.
  const PasteInput(this.text);

  /// The decoded text of the bracketed-paste block.
  final String text;
  @override
  void dispatchTo(InputDispatcher dispatcher) =>
      dispatcher.dispatchPasteEvent(PasteEvent(text));
}

/// A terminal capability/query response parsed from stdin.
class CapabilityInput extends ParsedInput {
  /// Wraps [event] for terminal-capability response dispatch.
  const CapabilityInput(this.event);

  /// The parsed terminal capability response to dispatch.
  final TerminalCapabilityEvent event;

  @override
  void dispatchTo(InputDispatcher dispatcher) =>
      dispatcher.dispatchCapabilityResponse(event);
}

/// Result of a parse pass. [leftover] holds bytes that form the start of
/// an incomplete escape sequence and need more input to decode; the caller
/// should feed them back in front of the next chunk.
class ParseResult {
  /// Records decoded [events] and incomplete [leftover] bytes for the next pass.
  const ParseResult(this.events, this.leftover) : _discardedFrame = null;

  const ParseResult._discarding(
    this.events,
    this.leftover,
    this._discardedFrame,
  );

  /// Fully decoded input events from this parse pass.
  final List<ParsedInput> events;

  /// Trailing bytes of an incomplete sequence to prepend to the next chunk.
  final List<int> leftover;

  final _DiscardedAnsiFrame? _discardedFrame;
}

const int _maxBracketedPastePayloadBytes = 1024 * 1024;
const int _maxControlSequenceBodyBytes = 4096;
const List<int> _bracketedPasteEnd = <int>[0x1b, 0x5b, 0x32, 0x30, 0x31, 0x7e];

enum _DiscardedAnsiFrame { bracketedPaste, stringCapability, csi }

final class _ParseContext {
  _ParseContext({required this.enforceLimits});

  final bool enforceLimits;
  _DiscardedAnsiFrame? discardedFrame;
  List<int> retainedPrefix = const <int>[];

  void discard(_DiscardedAnsiFrame frame, List<int> prefix) {
    discardedFrame = frame;
    retainedPrefix = prefix;
  }
}

({bool complete, int nextIndex, List<int> retainedPrefix})
_recoverDiscardedFrame(_DiscardedAnsiFrame frame, List<int> bytes) {
  switch (frame) {
    case _DiscardedAnsiFrame.bracketedPaste:
      final end = _indexOfSequence(bytes, _bracketedPasteEnd);
      if (end >= 0) {
        return (
          complete: true,
          nextIndex: end + _bracketedPasteEnd.length,
          retainedPrefix: const <int>[],
        );
      }
      return (
        complete: false,
        nextIndex: bytes.length,
        retainedPrefix: _trailingSequencePrefix(bytes, _bracketedPasteEnd),
      );
    case _DiscardedAnsiFrame.stringCapability:
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] == 0x07) {
          return (
            complete: true,
            nextIndex: i + 1,
            retainedPrefix: const <int>[],
          );
        }
        if (bytes[i] == 0x1b && i + 1 < bytes.length && bytes[i + 1] == 0x5c) {
          return (
            complete: true,
            nextIndex: i + 2,
            retainedPrefix: const <int>[],
          );
        }
      }
      return (
        complete: false,
        nextIndex: bytes.length,
        retainedPrefix: bytes.isNotEmpty && bytes.last == 0x1b
            ? const <int>[0x1b]
            : const <int>[],
      );
    case _DiscardedAnsiFrame.csi:
      for (var i = 0; i < bytes.length; i++) {
        if (!_isCsiBodyByte(bytes[i])) {
          return (
            complete: true,
            nextIndex: i + 1,
            retainedPrefix: const <int>[],
          );
        }
      }
      return (
        complete: false,
        nextIndex: bytes.length,
        retainedPrefix: const <int>[],
      );
  }
}

int _indexOfSequence(List<int> bytes, List<int> sequence, {int start = 0}) {
  for (var i = start; i + sequence.length <= bytes.length; i++) {
    var matches = true;
    for (var j = 0; j < sequence.length; j++) {
      if (bytes[i + j] != sequence[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

List<int> _trailingSequencePrefix(
  List<int> bytes,
  List<int> sequence, {
  int start = 0,
}) {
  final available = bytes.length - start;
  final maximum = available < sequence.length - 1
      ? available
      : sequence.length - 1;
  for (var length = maximum; length > 0; length--) {
    final offset = bytes.length - length;
    var matches = true;
    for (var i = 0; i < length; i++) {
      if (bytes[offset + i] != sequence[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return bytes.sublist(offset);
  }
  return const <int>[];
}

bool _isCsiBodyByte(int byte) => byte >= 0x20 && byte <= 0x3f;

KeyEvent _key(
  LogicalKeyboardKey logicalKey, {
  required int keyCode,
  String? character,
  int modifiers = 0,
  bool isPress = true,
  bool isRepeat = false,
}) => KeyEvent(
  logicalKey: logicalKey,
  keyCode: keyCode,
  character: character,
  modifiers: modifiers,
  isPress: isPress,
  isRepeat: isRepeat,
);

int? _decodeModifierField(int modField) {
  if (modField < 1) return null;
  final raw = modField - 1;
  var mods = 0;
  if (raw & 1 != 0) mods |= KeyModifiers.shift;
  if (raw & 2 != 0) mods |= KeyModifiers.alt;
  if (raw & 4 != 0) mods |= KeyModifiers.ctrl;
  if (raw & 8 != 0) mods |= KeyModifiers.super_;
  if (raw & 16 != 0) mods |= KeyModifiers.hyper;
  if (raw & 32 != 0) mods |= KeyModifiers.meta;
  if (raw & 64 != 0) mods |= KeyModifiers.capsLock;
  if (raw & 128 != 0) mods |= KeyModifiers.numLock;
  return mods;
}

typedef _CsiKeyMetadata = ({int modifiers, bool isPress, bool isRepeat});

/// Parse a chunk of raw bytes into key, mouse, paste, and terminal capability
/// inputs. Pure function, side-effect free — exposed for unit testing without
/// a real stdin. Bytes that don't match a recognised pattern are dropped.
ParseResult parseAnsiInput(
  List<int> bytes, {
  bool holdTrailingEscape = false,
}) => _parseAnsiInput(
  bytes,
  holdTrailingEscape: holdTrailingEscape,
  enforceLimits: false,
);

ParseResult _parseBoundedAnsiInput(
  List<int> bytes, {
  required bool holdTrailingEscape,
}) => _parseAnsiInput(
  bytes,
  holdTrailingEscape: holdTrailingEscape,
  enforceLimits: true,
);

ParseResult _parseAnsiInput(
  List<int> bytes, {
  required bool holdTrailingEscape,
  required bool enforceLimits,
}) {
  final events = <ParsedInput>[];
  final context = _ParseContext(enforceLimits: enforceLimits);
  var i = 0;
  // _PasteState tracks whether we're inside a bracketed-paste block.
  final paste = _PasteState();
  while (i < bytes.length) {
    if (paste.active) {
      final consumed = paste.advance(bytes, i, events, context);
      if (context.discardedFrame != null) {
        return ParseResult._discarding(
          events,
          context.retainedPrefix,
          context.discardedFrame,
        );
      }
      if (consumed < 0) {
        // End sequence not found yet — keep everything from paste.startIndex
        // onward as leftover for the next chunk.
        return ParseResult(events, bytes.sublist(paste.startIndex));
      }
      i += consumed;
      continue;
    }
    final consumed = _parseOne(
      bytes,
      i,
      events,
      paste,
      holdTrailingEscape,
      context,
    );
    if (context.discardedFrame != null) {
      return ParseResult._discarding(
        events,
        context.retainedPrefix,
        context.discardedFrame,
      );
    }
    if (consumed == 0) {
      // Incomplete escape sequence at end of buffer; preserve as leftover.
      return ParseResult(events, bytes.sublist(i));
    }
    i += consumed;
  }
  if (paste.active) {
    return ParseResult(events, bytes.sublist(paste.startIndex));
  }
  return ParseResult(events, const <int>[]);
}

class _PasteState {
  bool active = false;
  int startIndex = 0;

  /// Try to consume up through (and including) the `ESC [ 201 ~` end
  /// sequence. Returns the number of input bytes consumed since [start].
  /// Returns -1 if the end sequence is not in [bytes] yet.
  int advance(
    List<int> bytes,
    int start,
    List<ParsedInput> out,
    _ParseContext context,
  ) {
    // Look for ESC [ 2 0 1 ~.
    final end = _indexOfEnd(bytes, start);
    if (end < 0) {
      if (context.enforceLimits) {
        final terminatorPrefix = _trailingSequencePrefix(
          bytes,
          _bracketedPasteEnd,
          start: start,
        );
        final definitePayloadLength =
            bytes.length - start - terminatorPrefix.length;
        if (definitePayloadLength > _maxBracketedPastePayloadBytes) {
          context.discard(_DiscardedAnsiFrame.bracketedPaste, terminatorPrefix);
        }
      }
      return -1;
    }
    if (context.enforceLimits && end - start > _maxBracketedPastePayloadBytes) {
      active = false;
      return (end - start) + _bracketedPasteEnd.length;
    }
    out.add(
      PasteInput(utf8.decode(bytes.sublist(start, end), allowMalformed: true)),
    );
    active = false;
    return (end - start) + _bracketedPasteEnd.length;
  }

  // ESC [ 2 0 1 ~  =  0x1b 0x5b 0x32 0x30 0x31 0x7e
  int _indexOfEnd(List<int> bytes, int from) =>
      _indexOfSequence(bytes, _bracketedPasteEnd, start: from);
}

/// Returns the number of bytes consumed. Returns 0 to signal "incomplete
/// sequence at end of buffer — preserve and wait for more".
int _parseOne(
  List<int> bytes,
  int start,
  List<ParsedInput> out,
  _PasteState paste,
  bool holdTrailingEscape,
  _ParseContext context,
) {
  final b = bytes[start];

  // ESC sequences
  if (b == 0x1b) {
    if (start + 1 >= bytes.length) {
      if (holdTrailingEscape) return 0;
      out.add(KeyInput(_key(LogicalKeyboardKey.escape, keyCode: 27)));
      return 1;
    }
    final next = bytes[start + 1];
    if (next == 0x5b /* '[' */ ) {
      return _parseCsi(bytes, start, out, paste, context);
    }
    if (next == 0x4f /* 'O' */ ) {
      return _parseSs3(bytes, start, out);
    }
    // DCS ESC P, OSC ESC ], APC ESC _, PM ESC ^ — terminated by BEL or ST.
    if (next == 0x50 || next == 0x5d || next == 0x5f || next == 0x5e) {
      return _parseStringCapability(bytes, start, out, context);
    }
    // ST alone (ESC \) — drop silently.
    if (next == 0x5c) {
      return 2;
    }
    // Bare ESC.
    out.add(KeyInput(_key(LogicalKeyboardKey.escape, keyCode: 27)));
    return 1;
  }

  // Named single-byte controls.
  if (b == 0x0a || b == 0x0d) {
    out.add(KeyInput(_key(LogicalKeyboardKey.enter, keyCode: 13)));
    return 1;
  }
  if (b == 0x09) {
    out.add(KeyInput(_key(LogicalKeyboardKey.tab, keyCode: 9)));
    return 1;
  }
  if (b == 0x7f || b == 0x08) {
    out.add(KeyInput(_key(LogicalKeyboardKey.backspace, keyCode: 8)));
    return 1;
  }

  // Ctrl+letter (1..26 maps to a..z).
  if (b >= 0x01 && b <= 0x1a) {
    final letter = String.fromCharCode(b + 0x60);
    out.add(
      KeyInput(
        _key(
          LogicalKeyboardKey.forLetter(letter),
          keyCode: b + 0x60,
          modifiers: KeyModifiers.ctrl,
        ),
      ),
    );
    return 1;
  }

  // Printable ASCII.
  if (b >= 0x20 && b < 0x80) {
    final character = String.fromCharCode(b);
    out.add(
      KeyInput(
        _key(
          LogicalKeyboardKey.forCharacter(character),
          keyCode: b,
          character: character,
        ),
      ),
    );
    return 1;
  }

  // UTF-8 multi-byte.
  if (b >= 0x80) {
    int n;
    if ((b & 0xe0) == 0xc0) {
      n = 2;
    } else if ((b & 0xf0) == 0xe0) {
      n = 3;
    } else if ((b & 0xf8) == 0xf0) {
      n = 4;
    } else {
      return 1; // continuation byte at start; skip
    }
    if (start + n > bytes.length) {
      // Need more bytes to decode this rune.
      return 0;
    }
    try {
      final s = utf8.decode(bytes.sublist(start, start + n));
      out.add(
        KeyInput(
          _key(LogicalKeyboardKey.forCharacter(s), keyCode: 0, character: s),
        ),
      );
    } on FormatException {
      // malformed; drop
    }
    return n;
  }

  // Other low control bytes — drop silently.
  return 1;
}

int _parseStringCapability(
  List<int> bytes,
  int start,
  List<ParsedInput> out,
  _ParseContext context,
) {
  final kind = switch (bytes[start + 1]) {
    0x50 => TerminalCapabilityKind.deviceControlString,
    0x5d => TerminalCapabilityKind.operatingSystemCommand,
    0x5f => TerminalCapabilityKind.applicationProgramCommand,
    0x5e => TerminalCapabilityKind.privacyMessage,
    _ => null,
  };
  if (kind == null) return 1;
  var i = start + 2;
  while (i < bytes.length) {
    if (bytes[i] == 0x07) {
      if (!context.enforceLimits ||
          i - (start + 2) <= _maxControlSequenceBodyBytes) {
        out.add(
          _capabilityInput(
            kind: kind,
            bytes: bytes,
            start: start,
            payloadStart: start + 2,
            payloadEnd: i,
            end: i + 1,
          ),
        );
      }
      return i + 1 - start;
    }
    if (bytes[i] == 0x1b && i + 1 < bytes.length && bytes[i + 1] == 0x5c) {
      if (!context.enforceLimits ||
          i - (start + 2) <= _maxControlSequenceBodyBytes) {
        out.add(
          _capabilityInput(
            kind: kind,
            bytes: bytes,
            start: start,
            payloadStart: start + 2,
            payloadEnd: i,
            end: i + 2,
          ),
        );
      }
      return i + 2 - start;
    }
    i++;
  }
  if (context.enforceLimits) {
    final terminatorPrefix = bytes.isNotEmpty && bytes.last == 0x1b
        ? const <int>[0x1b]
        : const <int>[];
    final definiteBodyLength =
        bytes.length - (start + 2) - terminatorPrefix.length;
    if (definiteBodyLength > _maxControlSequenceBodyBytes) {
      context.discard(_DiscardedAnsiFrame.stringCapability, terminatorPrefix);
    }
  }
  return 0; // incomplete
}

int _parseCsi(
  List<int> bytes,
  int start,
  List<ParsedInput> out,
  _PasteState paste,
  _ParseContext context,
) {
  // Layout: ESC [ <params> <intermediates> <final>
  // params:        0x30..0x3f  (digits, ; , < > ? — including SGR mouse '<')
  // intermediates: 0x20..0x2f  (space, ! "  # ...)
  // final:         0x40..0x7e
  var i = start + 2;
  final paramsStart = i;
  while (i < bytes.length && bytes[i] >= 0x30 && bytes[i] <= 0x3f) {
    i++;
  }
  final paramsEnd = i;
  while (i < bytes.length && bytes[i] >= 0x20 && bytes[i] <= 0x2f) {
    i++;
  }
  if (i >= bytes.length) {
    if (context.enforceLimits &&
        i - (start + 2) > _maxControlSequenceBodyBytes) {
      context.discard(_DiscardedAnsiFrame.csi, const <int>[]);
    }
    // Incomplete sequence: signal "preserve and wait".
    return 0;
  }
  if (context.enforceLimits && i - (start + 2) > _maxControlSequenceBodyBytes) {
    return i + 1 - start;
  }
  final finalByte = bytes[i];
  final params = String.fromCharCodes(bytes.sublist(paramsStart, paramsEnd));
  final intermediates = String.fromCharCodes(bytes.sublist(paramsEnd, i));

  if (finalByte == 0x63 /* c */ ) {
    final kind = _deviceAttributesKind(params);
    if (kind != null) {
      out.add(
        _capabilityInput(
          kind: kind,
          bytes: bytes,
          start: start,
          payloadStart: paramsStart,
          payloadEnd: i,
          end: i + 1,
        ),
      );
      return i + 1 - start;
    }
  }

  final reportKind = switch ((finalByte, intermediates, params)) {
    (0x79, r'$', final params) when _privateModeReport.hasMatch(params) =>
      TerminalCapabilityKind.privateModeReport,
    (0x52, '', final params) when _cursorPositionReport.hasMatch(params) =>
      TerminalCapabilityKind.cursorPositionReport,
    (0x75, '', final params) when _kittyKeyboardStatus.hasMatch(params) =>
      TerminalCapabilityKind.kittyKeyboardStatus,
    _ => null,
  };
  if (reportKind != null) {
    out.add(
      _capabilityInput(
        kind: reportKind,
        bytes: bytes,
        start: start,
        payloadStart: paramsStart,
        payloadEnd: i,
        end: i + 1,
      ),
    );
    return i + 1 - start;
  }

  // SGR mouse: parameters start with '<'.
  if (params.isNotEmpty && params.codeUnitAt(0) == 0x3c /* '<' */ ) {
    if (finalByte == 0x4d || finalByte == 0x6d /* M or m */ ) {
      _emitMouse(params.substring(1), finalByte == 0x4d, out);
      return i + 1 - start;
    }
    return i + 1 - start; // unknown mouse-shaped CSI; drop
  }

  // Bracketed paste start: ESC [ 200 ~
  if (finalByte == 0x7e && params == '200') {
    paste.active = true;
    paste.startIndex = start;
    return i + 1 - start;
  }

  KeyEvent? evt;
  final metadata = _csiKeyMetadata(params);
  if (metadata == null) return i + 1 - start;
  switch (finalByte) {
    case 0x41: // 'A'
      evt = _csiKey(LogicalKeyboardKey.arrowUp, metadata);
    case 0x42: // 'B'
      evt = _csiKey(LogicalKeyboardKey.arrowDown, metadata);
    case 0x43: // 'C'
      evt = _csiKey(LogicalKeyboardKey.arrowRight, metadata);
    case 0x44: // 'D'
      evt = _csiKey(LogicalKeyboardKey.arrowLeft, metadata);
    case 0x48: // 'H'
      evt = _csiKey(LogicalKeyboardKey.home, metadata);
    case 0x46: // 'F'
      evt = _csiKey(LogicalKeyboardKey.end, metadata);
    case 0x5a: // 'Z' — Shift+Tab
      evt = _key(
        LogicalKeyboardKey.tab,
        keyCode: 9,
        modifiers: KeyModifiers.shift,
      );
    case 0x75: // 'u' — Kitty CSI-u keyboard report
      evt = _parseKittyCsiU(params);
    case 0x7e: // '~' — extended keys parameterised by leading number
      evt = _modifyOtherKeysKey(params) ?? _tildeKey(params, metadata);
    // Other final bytes: not handled; drop.
  }
  if (evt != null) out.add(KeyInput(evt));
  return i + 1 - start;
}

final RegExp _privateModeReport = RegExp(r'^\?[0-9]+;[0-9]+$');
final RegExp _cursorPositionReport = RegExp(r'^[0-9]+;[0-9]+$');
final RegExp _kittyKeyboardStatus = RegExp(r'^\?[0-9]+$');

_CsiKeyMetadata? _csiKeyMetadata(String params) {
  final parts = params.split(';');
  if (parts.length < 2 || parts[1].isEmpty) {
    return (modifiers: 0, isPress: true, isRepeat: false);
  }
  final fields = parts[1].split(':');
  final modField = int.tryParse(fields.first);
  if (modField == null) return null;
  final modifiers = _decodeModifierField(modField);
  if (modifiers == null) return null;
  final eventType = fields.length > 1 ? fields[1] : null;
  return (
    modifiers: modifiers,
    isPress: eventType != '3',
    isRepeat: eventType == '2',
  );
}

TerminalCapabilityKind? _deviceAttributesKind(String params) {
  if (params.isEmpty) return null;
  return switch (params.codeUnitAt(0)) {
    0x3f => TerminalCapabilityKind.primaryDeviceAttributes, // ?
    0x3e => TerminalCapabilityKind.secondaryDeviceAttributes, // >
    0x3d => TerminalCapabilityKind.tertiaryDeviceAttributes, // =
    _ => null,
  };
}

CapabilityInput _capabilityInput({
  required TerminalCapabilityKind kind,
  required List<int> bytes,
  required int start,
  required int payloadStart,
  required int payloadEnd,
  required int end,
}) => CapabilityInput(
  TerminalCapabilityEvent(
    kind: kind,
    payload: utf8.decode(
      bytes.sublist(payloadStart, payloadEnd),
      allowMalformed: true,
    ),
    raw: utf8.decode(bytes.sublist(start, end), allowMalformed: true),
  ),
);

/// `ESC O <letter>` sequences — historically used for F1-F4 in some
/// terminals (xterm "application keypad" mode).
int _parseSs3(List<int> bytes, int start, List<ParsedInput> out) {
  if (start + 2 >= bytes.length) return 0;
  final c = bytes[start + 2];
  KeyEvent? evt;
  switch (c) {
    case 0x50:
      evt = _key(LogicalKeyboardKey.f1, keyCode: 0);
    case 0x51:
      evt = _key(LogicalKeyboardKey.f2, keyCode: 0);
    case 0x52:
      evt = _key(LogicalKeyboardKey.f3, keyCode: 0);
    case 0x53:
      evt = _key(LogicalKeyboardKey.f4, keyCode: 0);
  }
  if (evt != null) out.add(KeyInput(evt));
  return 3;
}

KeyEvent _csiKey(LogicalKeyboardKey logicalKey, _CsiKeyMetadata metadata) =>
    _key(
      logicalKey,
      keyCode: 0,
      modifiers: metadata.modifiers,
      isPress: metadata.isPress,
      isRepeat: metadata.isRepeat,
    );

KeyEvent? _tildeKey(String params, _CsiKeyMetadata metadata) {
  // params can be "N", "N;M", or Kitty's "N;M:eventType" form. The caller
  // has already decoded modifiers and event state into metadata.
  final n = int.tryParse(params.split(';').first);
  if (n == null) return null;
  switch (n) {
    case 1:
    case 7: // rxvt
      return _csiKey(LogicalKeyboardKey.home, metadata);
    case 2:
      return _csiKey(LogicalKeyboardKey.insert, metadata);
    case 3:
      return _csiKey(LogicalKeyboardKey.delete, metadata);
    case 4:
    case 8: // rxvt
      return _csiKey(LogicalKeyboardKey.end, metadata);
    case 5:
      return _csiKey(LogicalKeyboardKey.pageUp, metadata);
    case 6:
      return _csiKey(LogicalKeyboardKey.pageDown, metadata);
    case 11:
      return _csiKey(LogicalKeyboardKey.f1, metadata);
    case 12:
      return _csiKey(LogicalKeyboardKey.f2, metadata);
    case 13:
      return _csiKey(LogicalKeyboardKey.f3, metadata);
    case 14:
      return _csiKey(LogicalKeyboardKey.f4, metadata);
    case 15:
      return _csiKey(LogicalKeyboardKey.f5, metadata);
    case 17:
      return _csiKey(LogicalKeyboardKey.f6, metadata);
    case 18:
      return _csiKey(LogicalKeyboardKey.f7, metadata);
    case 19:
      return _csiKey(LogicalKeyboardKey.f8, metadata);
    case 20:
      return _csiKey(LogicalKeyboardKey.f9, metadata);
    case 21:
      return _csiKey(LogicalKeyboardKey.f10, metadata);
    case 23:
      return _csiKey(LogicalKeyboardKey.f11, metadata);
    case 24:
      return _csiKey(LogicalKeyboardKey.f12, metadata);
  }
  return null;
}

/// Decode xterm modifyOtherKeys: `ESC [ 27 ; modifiers ; code ~`.
///
/// The modifier field is 1-based, matching Kitty CSI-u. OpenTUI enables this
/// mode when Kitty keyboard reporting is unavailable, so it must preserve the
/// same logical key and modifier information.
KeyEvent? _modifyOtherKeysKey(String params) {
  final fields = params.split(';');
  if (fields.length != 3 || fields.first != '27') return null;

  final modifierField = int.tryParse(fields[1]);
  final code = int.tryParse(fields[2]);
  if (modifierField == null || code == null) return null;

  final modifiers = _decodeModifierField(modifierField);
  if (modifiers == null) return null;
  final namedKey = switch (code) {
    9 => LogicalKeyboardKey.tab,
    13 => LogicalKeyboardKey.enter,
    27 => LogicalKeyboardKey.escape,
    32 => LogicalKeyboardKey.space,
    8 || 127 => LogicalKeyboardKey.backspace,
    _ => null,
  };
  if (namedKey != null) {
    return _key(namedKey, keyCode: code, modifiers: modifiers);
  }
  if (code >= 0x20 && _isUnicodeScalarValue(code)) {
    final character = String.fromCharCode(code);
    return _key(
      LogicalKeyboardKey.forCharacter(character),
      keyCode: code,
      character: character,
      modifiers: modifiers,
    );
  }
  return null;
}

/// Decode Kitty keyboard CSI-u:
/// `ESC [ keycode[:alternate] ; modifiers[:event-type] ; text u`.
///
/// Keycode is a Unicode codepoint, or one of Kitty's named-key codes for
/// non-printable keys. Modifiers are 1-based (1=none, 2=shift, 5=ctrl...).
/// Event type is 1/default=press, 2=repeat, 3=release.
KeyEvent? _parseKittyCsiU(String params) {
  final fields = params.split(';');
  final keyFields = fields.first.split(':');
  final code = int.tryParse(keyFields.first);
  if (code == null) return null;

  final modifierFields = fields.length > 1
      ? fields[1].split(':')
      : const <String>[];
  final modField = modifierFields.isNotEmpty
      ? int.tryParse(modifierFields.first) ?? 1
      : 1;
  final mods = _decodeModifierField(modField);
  if (mods == null) return null;
  final eventType = modifierFields.length > 1 ? modifierFields[1] : null;
  final isRepeat = eventType == '2';
  final isPress = eventType != '3';

  final associatedText = fields.length > 2
      ? _parseKittyAssociatedText(fields[2])
      : null;
  final shiftedCodepoint = keyFields.length > 1
      ? int.tryParse(keyFields[1])
      : null;

  final namedKey = _kittyNamedKey(code);
  if (namedKey != null) {
    return _key(
      namedKey,
      keyCode: code,
      modifiers: mods,
      isPress: isPress,
      isRepeat: isRepeat,
    );
  }
  if (code >= 0x20 && _isUnicodeScalarValue(code)) {
    final character = _kittyPrintableCharacter(
      codepoint: code,
      modifiers: mods,
      shiftedCodepoint: shiftedCodepoint,
      associatedText: associatedText,
    );
    return _key(
      LogicalKeyboardKey.forCharacter(String.fromCharCode(code)),
      keyCode: code,
      character: character,
      modifiers: mods,
      isPress: isPress,
      isRepeat: isRepeat,
    );
  }
  return _key(
    LogicalKeyboardKey.unknown,
    keyCode: code,
    modifiers: mods,
    isPress: isPress,
    isRepeat: isRepeat,
  );
}

String _kittyPrintableCharacter({
  required int codepoint,
  required int modifiers,
  required int? shiftedCodepoint,
  required String? associatedText,
}) {
  if (associatedText != null) return associatedText;
  if (modifiers & KeyModifiers.shift != 0 &&
      shiftedCodepoint != null &&
      shiftedCodepoint > 0 &&
      _isUnicodeScalarValue(shiftedCodepoint)) {
    return String.fromCharCode(shiftedCodepoint);
  }
  return String.fromCharCode(codepoint);
}

String? _parseKittyAssociatedText(String field) {
  final codepoints = <int>[];
  for (final part in field.split(':')) {
    final codepoint = int.tryParse(part);
    if (codepoint == null ||
        codepoint <= 0 ||
        !_isUnicodeScalarValue(codepoint)) {
      continue;
    }
    codepoints.add(codepoint);
  }
  if (codepoints.isEmpty) return null;
  return String.fromCharCodes(codepoints);
}

bool _isUnicodeScalarValue(int value) =>
    value >= 0 && value <= 0x10ffff && (value < 0xd800 || value > 0xdfff);

LogicalKeyboardKey? _kittyNamedKey(int code) {
  switch (code) {
    case 9:
      return LogicalKeyboardKey.tab;
    case 13:
      return LogicalKeyboardKey.enter;
    case 27:
      return LogicalKeyboardKey.escape;
    case 127:
      return LogicalKeyboardKey.backspace;
    case 57344:
      return LogicalKeyboardKey.escape;
    case 57345:
      return LogicalKeyboardKey.enter;
    case 57346:
      return LogicalKeyboardKey.tab;
    case 57347:
      return LogicalKeyboardKey.backspace;
    case 57348:
      return LogicalKeyboardKey.insert;
    case 57349:
      return LogicalKeyboardKey.delete;
    case 57350:
      return LogicalKeyboardKey.arrowLeft;
    case 57351:
      return LogicalKeyboardKey.arrowRight;
    case 57352:
      return LogicalKeyboardKey.arrowUp;
    case 57353:
      return LogicalKeyboardKey.arrowDown;
    case 57354:
      return LogicalKeyboardKey.pageUp;
    case 57355:
      return LogicalKeyboardKey.pageDown;
    case 57356:
      return LogicalKeyboardKey.home;
    case 57357:
      return LogicalKeyboardKey.end;
    case 57364:
      return LogicalKeyboardKey.f1;
    case 57365:
      return LogicalKeyboardKey.f2;
    case 57366:
      return LogicalKeyboardKey.f3;
    case 57367:
      return LogicalKeyboardKey.f4;
    case 57368:
      return LogicalKeyboardKey.f5;
    case 57369:
      return LogicalKeyboardKey.f6;
    case 57370:
      return LogicalKeyboardKey.f7;
    case 57371:
      return LogicalKeyboardKey.f8;
    case 57372:
      return LogicalKeyboardKey.f9;
    case 57373:
      return LogicalKeyboardKey.f10;
    case 57374:
      return LogicalKeyboardKey.f11;
    case 57375:
      return LogicalKeyboardKey.f12;
  }
  return null;
}

void _emitMouse(String params, bool isPress, List<ParsedInput> out) {
  // params is "Cb;Cx;Cy" (1-indexed coords).
  final parts = params.split(';');
  if (parts.length != 3) return;
  final cb = int.tryParse(parts[0]);
  final cx = int.tryParse(parts[1]);
  final cy = int.tryParse(parts[2]);
  if (cb == null || cx == null || cy == null) return;

  final isMotion = (cb & 0x20) != 0;
  final isWheel = (cb & 0x40) != 0;
  final shift = (cb & 0x04) != 0;
  final alt = (cb & 0x08) != 0;
  final ctrl = (cb & 0x10) != 0;

  var mods = 0;
  if (shift) mods |= KeyModifiers.shift;
  if (alt) mods |= KeyModifiers.alt;
  if (ctrl) mods |= KeyModifiers.ctrl;

  final btnIndex = cb & 0x03;
  final button = switch (btnIndex) {
    0 => MouseButton.left,
    1 => MouseButton.middle,
    2 => MouseButton.right,
    _ => MouseButton.left,
  };

  // Match OpenTUI's SGR precedence: uppercase wheel, then motion, then
  // ordinary press/release. Shift remains raw event metadata.
  if (isWheel && isPress) {
    final direction = switch (btnIndex) {
      0 => MouseScrollDirection.up,
      1 => MouseScrollDirection.down,
      2 => MouseScrollDirection.left,
      _ => MouseScrollDirection.right,
    };
    out.add(
      MouseInput(
        MouseEvent(
          type: MouseEventType.scroll,
          button: button,
          x: cx - 1,
          y: cy - 1,
          modifiers: mods,
          scroll: MouseScroll(direction: direction),
        ),
      ),
    );
    return;
  }

  final type = isMotion
      ? MouseEventType.move
      : (isPress ? MouseEventType.down : MouseEventType.up);
  out.add(
    MouseInput(
      MouseEvent(
        type: type,
        button: button,
        x: cx - 1,
        y: cy - 1,
        modifiers: mods,
      ),
    ),
  );
}
