import 'dart:convert';

import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';

void main() {
  final named = <String, LogicalKeyboardKey>{
    '\x1bOA': LogicalKeyboardKey.arrowUp,
    '\x1bOB': LogicalKeyboardKey.arrowDown,
    '\x1bOC': LogicalKeyboardKey.arrowRight,
    '\x1bOD': LogicalKeyboardKey.arrowLeft,
    '\x1bOH': LogicalKeyboardKey.home,
    '\x1bOF': LogicalKeyboardKey.end,
    '\x1bOM': LogicalKeyboardKey.enter,
    '\x1b[P': LogicalKeyboardKey.f1,
    '\x1b[Q': LogicalKeyboardKey.f2,
    '\x1b[S': LogicalKeyboardKey.f4,
  };
  for (final MapEntry(key: sequence, value: key) in named.entries) {
    test('${jsonEncode(sequence)} maps to ${key.keyLabel} across chunks', () {
      _forEverySplit(sequence, (event) {
        expect(event.logicalKey, key);
        expect(event.character, isNull);
      });
    });
  }

  for (final (code, key) in [
    ('a', LogicalKeyboardKey.arrowUp),
    ('b', LogicalKeyboardKey.arrowDown),
    ('c', LogicalKeyboardKey.arrowRight),
    ('d', LogicalKeyboardKey.arrowLeft),
  ]) {
    test('SS3 control-arrow $code preserves its modifier across chunks', () {
      _forEverySplit('\x1bO$code', (event) {
        expect(event.logicalKey, key);
        expect(event.modifiers, KeyModifiers.ctrl);
      });
    });
  }
  for (final (code, key) in [
    ('P', LogicalKeyboardKey.f1),
    ('Q', LogicalKeyboardKey.f2),
    ('S', LogicalKeyboardKey.f4),
  ]) {
    test('CSI function key $code preserves modifiers across chunks', () {
      _forEverySplit('\x1b[1;5$code', (event) {
        expect(event.logicalKey, key);
        expect(event.modifiers, KeyModifiers.ctrl);
      });
    });
  }

  final keypad = <String, String>{
    'j': '*',
    'k': '+',
    'l': ',',
    'm': '-',
    'n': '.',
    'o': '/',
    'p': '0',
    'q': '1',
    'r': '2',
    's': '3',
    't': '4',
    'u': '5',
    'v': '6',
    'w': '7',
    'x': '8',
    'y': '9',
    'X': '=',
  };
  for (final MapEntry(key: code, value: character) in keypad.entries) {
    test('SS3 keypad $code inserts $character across chunks', () {
      _forEverySplit('\x1bO$code', (event) {
        expect(event.logicalKey, LogicalKeyboardKey.forCharacter(character));
        expect(event.character, character);
        expect(event.modifiers, 0);
      });
    });
  }

  for (final character in ['a', 'A', '1', ' ', 'é', '😀']) {
    test('legacy Alt+$character remains one modified key across chunks', () {
      _forEverySplit('\x1b$character', (event) {
        expect(event.logicalKey, LogicalKeyboardKey.forCharacter(character));
        expect(event.character, character);
        expect(event.isAltPressed, isTrue);
        expect(event.isShiftPressed, character == 'A');
      });
    });
  }
  for (final (sequence, key, modifiers) in [
    ('\x1b\x03', LogicalKeyboardKey.keyC, KeyModifiers.ctrl),
    ('\x1b\x7f', LogicalKeyboardKey.backspace, 0),
    ('\x1b\b', LogicalKeyboardKey.backspace, 0),
    ('\x1b\r', LogicalKeyboardKey.enter, 0),
  ]) {
    test('legacy Alt control ${jsonEncode(sequence)} keeps its key', () {
      _forEverySplit(sequence, (event) {
        expect(event.logicalKey, key);
        expect(event.character, isNull);
        expect(event.modifiers, modifiers | KeyModifiers.alt);
      });
    });
  }

  test('a bare Escape still flushes without an Alt modifier', () {
    final dispatcher = InputDispatcher();
    final events = <KeyEvent>[];
    dispatcher.onKey(events.add);
    final driver = StdinInputDriver(dispatcher);
    addTearDown(driver.stop);

    driver.debugFeedBytes([27]);
    expect(events, isEmpty);
    driver.debugFlushPendingEscape();

    expect(events.single.logicalKey, LogicalKeyboardKey.escape);
    expect(events.single.modifiers, 0);
  });
}

void _forEverySplit(String sequence, void Function(KeyEvent) verify) {
  final bytes = utf8.encode(sequence);
  for (var split = 0; split <= bytes.length; split++) {
    final dispatcher = InputDispatcher();
    final events = <KeyEvent>[];
    dispatcher.onKey(events.add);
    final driver = StdinInputDriver(dispatcher);
    try {
      driver.debugFeedBytes(bytes.sublist(0, split));
      driver.debugFeedBytes(bytes.sublist(split));
      driver.debugFlushPendingEscape();
      expect(events, hasLength(1), reason: 'split at byte $split');
      verify(events.single);
    } finally {
      driver.stop();
    }
  }
}
