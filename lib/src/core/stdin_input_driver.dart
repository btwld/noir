import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';

import 'input.dart';

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
/// - Function keys F1–F12 via `ESC O P/Q/R/S` and `ESC[N~`
/// - SGR mouse: `ESC[<Cb;Cx;CyM/m` for press/release, drag, and wheel
/// - Bracketed paste: `ESC[200~...ESC[201~` accumulated into a single event
/// - Kitty keyboard CSI-u:
///   `ESC[keycode[:alternate];modifiers[:event-type];text u`
class StdinInputDriver {
  /// Routes parsed stdin events to [_inputDispatcher] when input is started.
  StdinInputDriver(this._inputDispatcher);

  final InputDispatcher _inputDispatcher;
  StreamSubscription<List<int>>? _sub;
  bool? _previousLineMode;
  bool? _previousEchoMode;
  // Buffer for incomplete escape sequences split across reads.
  final List<int> _pending = <int>[];
  Timer? _escapeTimer;
  static const Duration _escapeFlushDelay = Duration(milliseconds: 25);

  /// Begin consuming stdin. No-op if stdin is not a TTY (headless / piped).
  void start() {
    if (!_stdinHasTerminal()) return;
    try {
      _previousLineMode = stdin.lineMode;
      _previousEchoMode = stdin.echoMode;
      stdin.lineMode = false;
      stdin.echoMode = false;
    } on StdinException {
      // Some platforms refuse mode changes; carry on best-effort.
    }
    _sub = stdin.listen(_onBytes);
  }

  /// Stop consuming stdin and restore terminal modes if we changed them.
  void stop() {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    _sub?.cancel();
    _sub = null;
    if (!_stdinHasTerminal()) return;
    try {
      if (_previousEchoMode != null) stdin.echoMode = _previousEchoMode!;
      if (_previousLineMode != null) stdin.lineMode = _previousLineMode!;
    } on StdinException {
      // Best-effort restore.
    }
  }

  bool _stdinHasTerminal() {
    try {
      return stdin.hasTerminal;
    } on FileSystemException {
      return false;
    }
  }

  void _onBytes(List<int> bytes) {
    _escapeTimer?.cancel();
    _escapeTimer = null;
    _pending.addAll(bytes);
    final result = parseAnsiInput(_pending, holdTrailingEscape: true);
    _pending
      ..clear()
      ..addAll(result.leftover);
    for (final ev in result.events) {
      ev.dispatchTo(_inputDispatcher);
    }
    if (_pending.length == 1 && _pending.single == 0x1b) {
      _escapeTimer = Timer(_escapeFlushDelay, _flushPendingEscape);
    }
  }

  /// Feed raw bytes through the production parser path in integration tests.
  @visibleForTesting
  void debugFeedBytes(List<int> bytes) {
    _onBytes(bytes);
  }

  void _flushPendingEscape() {
    if (_pending.length != 1 || _pending.single != 0x1b) return;
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
  const ParseResult(this.events, this.leftover);

  /// Fully decoded input events from this parse pass.
  final List<ParsedInput> events;

  /// Trailing bytes of an incomplete sequence to prepend to the next chunk.
  final List<int> leftover;
}

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

int _decodeModifierField(int modField) {
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

/// Parse a chunk of raw bytes into key, mouse, paste, and terminal capability
/// inputs. Pure function, side-effect free — exposed for unit testing without
/// a real stdin. Bytes that don't match a recognised pattern are dropped.
ParseResult parseAnsiInput(List<int> bytes, {bool holdTrailingEscape = false}) {
  final events = <ParsedInput>[];
  var i = 0;
  // _PasteState tracks whether we're inside a bracketed-paste block.
  final paste = _PasteState();
  while (i < bytes.length) {
    if (paste.active) {
      final consumed = paste.advance(bytes, i, events);
      if (consumed < 0) {
        // End sequence not found yet — keep everything from paste.startIndex
        // onward as leftover for the next chunk.
        return ParseResult(events, bytes.sublist(paste.startIndex));
      }
      i += consumed;
      continue;
    }
    final consumed = _parseOne(bytes, i, events, paste, holdTrailingEscape);
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
  int advance(List<int> bytes, int start, List<ParsedInput> out) {
    // Look for ESC [ 2 0 1 ~.
    final end = _indexOfEnd(bytes, start);
    if (end < 0) {
      return -1;
    }
    out.add(
      PasteInput(utf8.decode(bytes.sublist(start, end), allowMalformed: true)),
    );
    active = false;
    return (end - start) + 6; // length of "ESC [ 2 0 1 ~"
  }

  int _indexOfEnd(List<int> bytes, int from) {
    // ESC [ 2 0 1 ~  =  0x1b 0x5b 0x32 0x30 0x31 0x7e
    for (var i = from; i + 5 < bytes.length; i++) {
      if (bytes[i] == 0x1b &&
          bytes[i + 1] == 0x5b &&
          bytes[i + 2] == 0x32 &&
          bytes[i + 3] == 0x30 &&
          bytes[i + 4] == 0x31 &&
          bytes[i + 5] == 0x7e) {
        return i;
      }
    }
    return -1;
  }
}

/// Returns the number of bytes consumed. Returns 0 to signal "incomplete
/// sequence at end of buffer — preserve and wait for more".
int _parseOne(
  List<int> bytes,
  int start,
  List<ParsedInput> out,
  _PasteState paste,
  bool holdTrailingEscape,
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
      return _parseCsi(bytes, start, out, paste);
    }
    if (next == 0x4f /* 'O' */ ) {
      return _parseSs3(bytes, start, out);
    }
    // DCS ESC P, OSC ESC ], APC ESC _, PM ESC ^ — terminated by BEL or ST.
    if (next == 0x50 || next == 0x5d || next == 0x5f || next == 0x5e) {
      return _parseStringCapability(bytes, start, out);
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

int _parseStringCapability(List<int> bytes, int start, List<ParsedInput> out) {
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
      return i + 1 - start;
    }
    if (bytes[i] == 0x1b && i + 1 < bytes.length && bytes[i + 1] == 0x5c) {
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
      return i + 2 - start;
    }
    i++;
  }
  return 0; // incomplete
}

int _parseCsi(
  List<int> bytes,
  int start,
  List<ParsedInput> out,
  _PasteState paste,
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
  while (i < bytes.length && bytes[i] >= 0x20 && bytes[i] <= 0x2f) {
    i++;
  }
  if (i >= bytes.length) {
    // Incomplete sequence: signal "preserve and wait".
    return 0;
  }
  final finalByte = bytes[i];
  final params = String.fromCharCodes(bytes.sublist(paramsStart, i));

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
  final modifiers = _csiModifiers(params);
  switch (finalByte) {
    case 0x41: // 'A'
      evt = _key(LogicalKeyboardKey.arrowUp, keyCode: 0, modifiers: modifiers);
    case 0x42: // 'B'
      evt = _key(
        LogicalKeyboardKey.arrowDown,
        keyCode: 0,
        modifiers: modifiers,
      );
    case 0x43: // 'C'
      evt = _key(
        LogicalKeyboardKey.arrowRight,
        keyCode: 0,
        modifiers: modifiers,
      );
    case 0x44: // 'D'
      evt = _key(
        LogicalKeyboardKey.arrowLeft,
        keyCode: 0,
        modifiers: modifiers,
      );
    case 0x48: // 'H'
      evt = _key(LogicalKeyboardKey.home, keyCode: 0, modifiers: modifiers);
    case 0x46: // 'F'
      evt = _key(LogicalKeyboardKey.end, keyCode: 0, modifiers: modifiers);
    case 0x5a: // 'Z' — Shift+Tab
      evt = _key(
        LogicalKeyboardKey.tab,
        keyCode: 9,
        modifiers: KeyModifiers.shift,
      );
    case 0x75: // 'u' — Kitty CSI-u keyboard report
      evt = _parseKittyCsiU(params);
    case 0x7e: // '~' — extended keys parameterised by leading number
      evt = _tildeKey(params, modifiers);
    // Other final bytes: not handled; drop.
  }
  if (evt != null) out.add(KeyInput(evt));
  return i + 1 - start;
}

int _csiModifiers(String params) {
  final parts = params.split(';');
  if (parts.length < 2) return 0;
  final modField = int.tryParse(parts[1]);
  return modField == null ? 0 : _decodeModifierField(modField);
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

KeyEvent? _tildeKey(String params, int modifiers) {
  // params can be "N" or "N;M" where M encodes modifiers (xterm-style);
  // the caller has already decoded M via _csiModifiers.
  final n = int.tryParse(params.split(';').first);
  if (n == null) return null;
  switch (n) {
    case 3:
      return _key(LogicalKeyboardKey.delete, keyCode: 0, modifiers: modifiers);
    case 5:
      return _key(LogicalKeyboardKey.pageUp, keyCode: 0, modifiers: modifiers);
    case 6:
      return _key(
        LogicalKeyboardKey.pageDown,
        keyCode: 0,
        modifiers: modifiers,
      );
    case 11:
    case 1: // some terminals send ESC[1~ for F1
      return _key(LogicalKeyboardKey.f1, keyCode: 0, modifiers: modifiers);
    case 12:
    case 2: // ESC[2~ for F2 (rare)
      return _key(LogicalKeyboardKey.f2, keyCode: 0, modifiers: modifiers);
    case 13:
      return _key(LogicalKeyboardKey.f3, keyCode: 0, modifiers: modifiers);
    case 14:
      return _key(LogicalKeyboardKey.f4, keyCode: 0, modifiers: modifiers);
    case 15:
      return _key(LogicalKeyboardKey.f5, keyCode: 0, modifiers: modifiers);
    case 17:
      return _key(LogicalKeyboardKey.f6, keyCode: 0, modifiers: modifiers);
    case 18:
      return _key(LogicalKeyboardKey.f7, keyCode: 0, modifiers: modifiers);
    case 19:
      return _key(LogicalKeyboardKey.f8, keyCode: 0, modifiers: modifiers);
    case 20:
      return _key(LogicalKeyboardKey.f9, keyCode: 0, modifiers: modifiers);
    case 21:
      return _key(LogicalKeyboardKey.f10, keyCode: 0, modifiers: modifiers);
    case 23:
      return _key(LogicalKeyboardKey.f11, keyCode: 0, modifiers: modifiers);
    case 24:
      return _key(LogicalKeyboardKey.f12, keyCode: 0, modifiers: modifiers);
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
  if (code >= 0x20 && code <= 0x10ffff) {
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
      shiftedCodepoint <= 0x10ffff) {
    return String.fromCharCode(shiftedCodepoint);
  }
  return String.fromCharCode(codepoint);
}

String? _parseKittyAssociatedText(String field) {
  final codepoints = <int>[];
  for (final part in field.split(':')) {
    final codepoint = int.tryParse(part);
    if (codepoint == null || codepoint <= 0 || codepoint > 0x10ffff) {
      continue;
    }
    codepoints.add(codepoint);
  }
  if (codepoints.isEmpty) return null;
  return String.fromCharCodes(codepoints);
}

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
