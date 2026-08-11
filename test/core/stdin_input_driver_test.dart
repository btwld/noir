import 'dart:io';

import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';

void main() {
  group('parseAnsiInput key events', () {
    test('printable ASCII becomes 1-char KeyEvent', () {
      final events = _keyEventsFor('abc'.codeUnits);
      expect(events.map((e) => e.character).toList(), ['a', 'b', 'c']);
      expect(events.map((e) => e.logicalKey).toList(), [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyC,
      ]);
      expect(events.every((e) => e.isPress), isTrue);
    });

    test('Enter (CR or LF) maps to "Enter"', () {
      expect(_keyEventsFor([0x0a]).single.logicalKey, LogicalKeyboardKey.enter);
      expect(_keyEventsFor([0x0d]).single.logicalKey, LogicalKeyboardKey.enter);
    });

    test('Tab and Backspace map by name', () {
      expect(_keyEventsFor([0x09]).single.logicalKey, LogicalKeyboardKey.tab);
      expect(
        _keyEventsFor([0x7f]).single.logicalKey,
        LogicalKeyboardKey.backspace,
      );
      expect(
        _keyEventsFor([0x08]).single.logicalKey,
        LogicalKeyboardKey.backspace,
      );
    });

    test('bare ESC byte emits Escape', () {
      expect(
        _keyEventsFor([0x1b]).single.logicalKey,
        LogicalKeyboardKey.escape,
      );
    });

    test('CSI cursor keys map to Arrow*/Home/End', () {
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x41]).single.logicalKey,
        LogicalKeyboardKey.arrowUp,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x42]).single.logicalKey,
        LogicalKeyboardKey.arrowDown,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x43]).single.logicalKey,
        LogicalKeyboardKey.arrowRight,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x44]).single.logicalKey,
        LogicalKeyboardKey.arrowLeft,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x48]).single.logicalKey,
        LogicalKeyboardKey.home,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x46]).single.logicalKey,
        LogicalKeyboardKey.end,
      );
    });

    test('CSI tilde keys map to Delete/PageUp/PageDown', () {
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x33, 0x7e]).single.logicalKey,
        LogicalKeyboardKey.delete,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x35, 0x7e]).single.logicalKey,
        LogicalKeyboardKey.pageUp,
      );
      expect(
        _keyEventsFor([0x1b, 0x5b, 0x36, 0x7e]).single.logicalKey,
        LogicalKeyboardKey.pageDown,
      );
    });

    test('Ctrl+letter sets ctrl modifier and lowercase key', () {
      // 0x03 = Ctrl+C, 0x1a = Ctrl+Z
      final ctrlC = _keyEventsFor([0x03]).single;
      expect(ctrlC.logicalKey, LogicalKeyboardKey.keyC);
      expect(ctrlC.character, isNull);
      expect(ctrlC.isControlPressed, isTrue);
      final ctrlZ = _keyEventsFor([0x1a]).single;
      expect(ctrlZ.logicalKey, LogicalKeyboardKey.keyZ);
      expect(ctrlZ.character, isNull);
      expect(ctrlZ.isControlPressed, isTrue);
    });

    test('mixed printable + Enter + CSI in one chunk', () {
      // "hi" + Enter + ArrowUp
      final bytes = <int>[0x68, 0x69, 0x0a, 0x1b, 0x5b, 0x41];
      expect(_keyEventsFor(bytes).map(_keyLabel).toList(), [
        'h',
        'i',
        'Enter',
        'ArrowUp',
      ]);
    });

    test('UTF-8 multibyte rune produces a single multi-char key', () {
      // 'ñ' = U+00F1 = 0xc3 0xb1
      expect(_keyEventsFor([0xc3, 0xb1]).single.character, 'ñ');
    });

    test('Shift+Tab and CSI modifiers are semantic', () {
      final shiftTab = _keyEventsFor('\x1b[Z'.codeUnits).single;
      expect(shiftTab.logicalKey, LogicalKeyboardKey.tab);
      expect(shiftTab.isShiftPressed, isTrue);

      final ctrlUp = _keyEventsFor('\x1b[1;5A'.codeUnits).single;
      expect(ctrlUp.logicalKey, LogicalKeyboardKey.arrowUp);
      expect(ctrlUp.isControlPressed, isTrue);
    });

    test('unknown CSI final byte is dropped safely', () {
      // ESC [ 1 ; 2 R  (cursor position report — not handled in v1)
      final events = _keyEventsFor([0x1b, 0x5b, 0x31, 0x3b, 0x32, 0x52]);
      expect(events, isEmpty);
    });
  });

  group('parseAnsiInput — terminal capability responses', () {
    List<ParsedInput> parse(List<int> bytes) => parseAnsiInput(bytes).events;

    test('DA1 CSI response (CSI ? … c) produces CapabilityInput', () {
      // ESC [ ? 6 2 ; 4 c  — xterm DA1 response
      final event = _capabilityEventsFor('\x1b[?62;4c'.codeUnits).single;
      expect(event.kind, TerminalCapabilityKind.primaryDeviceAttributes);
      expect(event.payload, '?62;4');
    });

    test('DA2 CSI response (CSI > … c) produces CapabilityInput', () {
      // ESC [ > 4 1 ; 3 4 5 ; 0 c
      final event = _capabilityEventsFor('\x1b[>41;345;0c'.codeUnits).single;
      expect(event.kind, TerminalCapabilityKind.secondaryDeviceAttributes);
      expect(event.payload, '>41;345;0');
    });

    test('DA3 CSI response (CSI = … c) produces CapabilityInput', () {
      // ESC [ = 0 c
      final event = _capabilityEventsFor('\x1b[=0c'.codeUnits).single;
      expect(event.kind, TerminalCapabilityKind.tertiaryDeviceAttributes);
      expect(event.payload, '=0');
    });

    test('DCS sequence (ESC P … ST) produces CapabilityInput', () {
      // ESC P > | iTerm2 3.5.0 ESC \
      final event = _capabilityEventsFor(
        '\x1bP>|iTerm2 3.5.0\x1b\\'.codeUnits,
      ).single;
      expect(event.kind, TerminalCapabilityKind.deviceControlString);
      expect(event.payload, '>|iTerm2 3.5.0');
    });

    test('OSC sequence terminated by BEL produces CapabilityInput', () {
      // ESC ] 0 ; title BEL
      final event = _capabilityEventsFor(
        '\x1b]0;My Title\x07'.codeUnits,
      ).single;
      expect(event.kind, TerminalCapabilityKind.operatingSystemCommand);
      expect(event.payload, '0;My Title');
    });

    test('OSC sequence terminated by ST produces CapabilityInput', () {
      final event = _capabilityEventsFor(
        '\x1b]10;rgb:ff/ff/ff\x1b\\'.codeUnits,
      ).single;
      expect(event.kind, TerminalCapabilityKind.operatingSystemCommand);
      expect(event.payload, '10;rgb:ff/ff/ff');
    });

    test('APC sequence (ESC _ … ST) produces CapabilityInput', () {
      // Kitty graphics APC: ESC _ G i = 1 ; payload ST
      final event = _capabilityEventsFor(
        '\x1b_Gi=1;payload\x1b\\'.codeUnits,
      ).single;
      expect(event.kind, TerminalCapabilityKind.applicationProgramCommand);
      expect(event.payload, 'Gi=1;payload');
    });

    test('iTerm2 DCS + APC combo produces only capability responses', () {
      // Sequence that was auto-typing into the Name field before fix.
      final bytes =
          '\x1bP>|iTerm2 3.6.10\x1b\\\x1b_Gi=1;invalid payload\x1b\\'.codeUnits;
      final events = parse(bytes);
      expect(events.whereType<KeyInput>(), isEmpty);
      expect(events.whereType<MouseInput>(), isEmpty);
      expect(events.whereType<PasteInput>(), isEmpty);
      expect(events.whereType<CapabilityInput>(), hasLength(2));
    });

    test('DCS response followed by printable text separates correctly', () {
      // ESC P…ST then 'a'
      final bytes = '\x1bP>|term\x1b\\a'.codeUnits;
      final events = parse(bytes);
      expect(events.whereType<KeyInput>().map((k) => k.event.character), ['a']);
      expect(events.whereType<CapabilityInput>(), hasLength(1));
    });

    test('incomplete DCS at end of chunk is held as leftover', () {
      final bytes = '\x1bP>|iTerm'.codeUnits;
      final result = parseAnsiInput(bytes);
      expect(result.events, isEmpty);
      expect(result.leftover, bytes);
    });

    test('ParsedInput dispatches to InputDispatcher', () {
      final source = File(
        'lib/src/core/stdin_input_driver.dart',
      ).readAsStringSync();

      expect(source, contains('void dispatchTo(InputDispatcher'));
      expect(source, isNot(contains('void dispatchTo(InputManager')));
    });
  });

  group('parseAnsiInput — mouse SGR', () {
    List<MouseEvent> mouseFor(List<int> bytes) => parseAnsiInput(
      bytes,
    ).events.whereType<MouseInput>().map((m) => m.event).toList();

    test('left-click press at (10,5)', () {
      // ESC [ < 0 ; 11 ; 6 M  (1-indexed → 0-indexed coords)
      final bytes = '\x1b[<0;11;6M'.codeUnits;
      final m = mouseFor(bytes).single;
      expect(m.type, MouseEventType.down);
      expect(m.button, MouseButton.left);
      expect(m.x, 10);
      expect(m.y, 5);
      expect(m.modifiers, 0);
    });

    test('left-click release uses lowercase m', () {
      final bytes = '\x1b[<0;11;6m'.codeUnits;
      expect(mouseFor(bytes).single.type, MouseEventType.up);
    });

    test('right-click press maps to MouseButton.right', () {
      // Cb=2 → right
      final bytes = '\x1b[<2;3;3M'.codeUnits;
      expect(mouseFor(bytes).single.button, MouseButton.right);
    });

    test('drag (motion bit set) emits move event', () {
      // Cb=32 (bit 5) + button 0 = 32 = motion with left held
      final bytes = '\x1b[<32;5;5M'.codeUnits;
      expect(mouseFor(bytes).single.type, MouseEventType.move);
    });

    test('wheel reports preserve four directions, buttons, and position', () {
      const cases = <(String, MouseScrollDirection, MouseButton)>[
        ('\x1b[<64;11;6M', MouseScrollDirection.up, MouseButton.left),
        ('\x1b[<65;11;6M', MouseScrollDirection.down, MouseButton.middle),
        ('\x1b[<66;11;6M', MouseScrollDirection.left, MouseButton.right),
        ('\x1b[<67;11;6M', MouseScrollDirection.right, MouseButton.left),
      ];

      for (final (sequence, direction, button) in cases) {
        final event = mouseFor(sequence.codeUnits).single;
        expect(event.type, MouseEventType.scroll);
        expect(event.scroll?.direction, direction);
        expect(event.scroll?.magnitude, 1);
        expect(event.button, button);
        expect(event.x, 10);
        expect(event.y, 5);
      }
    });

    test('wheel reports preserve modifiers without remapping direction', () {
      const cases = <(int, MouseScrollDirection, int, int)>[
        (
          70,
          MouseScrollDirection.left,
          KeyModifiers.shift,
          KeyModifiers.alt | KeyModifiers.ctrl,
        ),
        (
          91,
          MouseScrollDirection.right,
          KeyModifiers.alt | KeyModifiers.ctrl,
          KeyModifiers.shift,
        ),
        (
          94,
          MouseScrollDirection.left,
          KeyModifiers.shift | KeyModifiers.alt | KeyModifiers.ctrl,
          0,
        ),
      ];

      for (final (cb, direction, present, absent) in cases) {
        final event = mouseFor('\x1b[<$cb;1;1M'.codeUnits).single;
        expect(event.scroll?.direction, direction);
        expect(event.modifiers & present, present);
        expect(event.modifiers & absent, 0);
      }
    });

    test('wheel, motion, and release branches preserve precedence', () {
      final release = mouseFor('\x1b[<64;1;1m'.codeUnits).single;
      expect(release.type, MouseEventType.up);
      expect(release.button, MouseButton.left);
      expect(release.scroll, isNull);

      final motion = mouseFor('\x1b[<96;1;1m'.codeUnits).single;
      expect(motion.type, MouseEventType.move);
      expect(motion.button, MouseButton.left);
      expect(motion.scroll, isNull);

      final uppercaseWheel = mouseFor('\x1b[<96;1;1M'.codeUnits).single;
      expect(uppercaseWheel.type, MouseEventType.scroll);
      expect(uppercaseWheel.scroll?.direction, MouseScrollDirection.up);
      expect(uppercaseWheel.scroll?.magnitude, 1);
    });

    test('malformed and unsupported SGR mouse input fabricates no event', () {
      expect(mouseFor('\x1b[<64;1;1;2M'.codeUnits), isEmpty);
      expect(mouseFor('\x1b[<left;1;1M'.codeUnits), isEmpty);
      expect(mouseFor('\x1b[<64;1;1X'.codeUnits), isEmpty);
    });

    test('Ctrl+left-click sets ctrl modifier', () {
      // Cb=16 (ctrl) + 0 (left) = 16
      final bytes = '\x1b[<16;1;1M'.codeUnits;
      expect(mouseFor(bytes).single.modifiers & KeyModifiers.ctrl, isNonZero);
    });
  });

  group('parseAnsiInput — function keys', () {
    test('SS3 sequence ESC O P emits F1', () {
      final events = _keyEventsFor([0x1b, 0x4f, 0x50]);
      expect(events.single.logicalKey, LogicalKeyboardKey.f1);
    });

    test('CSI 11~ also emits F1; CSI 24~ emits F12', () {
      expect(
        _keyEventsFor('\x1b[11~'.codeUnits).single.logicalKey,
        LogicalKeyboardKey.f1,
      );
      expect(
        _keyEventsFor('\x1b[24~'.codeUnits).single.logicalKey,
        LogicalKeyboardKey.f12,
      );
    });

    test('CSI 15~ emits F5 and CSI 17~ emits F6', () {
      expect(
        _keyEventsFor('\x1b[15~'.codeUnits).single.logicalKey,
        LogicalKeyboardKey.f5,
      );
      expect(
        _keyEventsFor('\x1b[17~'.codeUnits).single.logicalKey,
        LogicalKeyboardKey.f6,
      );
    });
  });

  group('parseAnsiInput — bracketed paste', () {
    test('paste block becomes a single PasteInput event', () {
      final bytes = '\x1b[200~hello world\x1b[201~'.codeUnits;
      final events = parseAnsiInput(bytes).events;
      final paste = events.whereType<PasteInput>().single;
      expect(paste.text, 'hello world');
    });

    test('text outside the paste markers parses normally', () {
      final bytes = 'a\x1b[200~paste\x1b[201~b'.codeUnits;
      final events = parseAnsiInput(bytes).events;
      expect(events.whereType<KeyInput>().map((k) => k.event.character), [
        'a',
        'b',
      ]);
      expect(events.whereType<PasteInput>().single.text, 'paste');
    });

    test('split paste keeps the start marker in leftover', () {
      final firstChunk = '\x1b[200~hel'.codeUnits;
      final first = parseAnsiInput(firstChunk);

      expect(first.events, isEmpty);
      expect(first.leftover, firstChunk);

      final second = parseAnsiInput(<int>[
        ...first.leftover,
        ...'lo\x1b[201~'.codeUnits,
      ]);
      expect(second.leftover, isEmpty);
      expect(second.events.whereType<PasteInput>().single.text, 'hello');
    });

    test('split paste can end immediately after the start marker', () {
      final firstChunk = '\x1b[200~'.codeUnits;
      final first = parseAnsiInput(firstChunk);

      expect(first.events, isEmpty);
      expect(first.leftover, firstChunk);

      final second = parseAnsiInput(<int>[
        ...first.leftover,
        ...'hello\x1b[201~'.codeUnits,
      ]);
      expect(second.leftover, isEmpty);
      expect(second.events.whereType<PasteInput>().single.text, 'hello');
    });

    test('escape sequences inside split paste stay paste text', () {
      final firstChunk = '\x1b[200~\x1b[A'.codeUnits;
      final first = parseAnsiInput(firstChunk);
      final second = parseAnsiInput(<int>[
        ...first.leftover,
        ...'\x1b[201~'.codeUnits,
      ]);

      expect(second.events.whereType<KeyInput>(), isEmpty);
      expect(second.events.whereType<PasteInput>().single.text, '\x1b[A');
    });
  });

  group('parseAnsiInput — Kitty CSI-u', () {
    test('printable codepoint with no modifiers', () {
      // ESC [ 97 ; 1 u   ('a' with no modifiers; modField=1)
      final events = _keyEventsFor('\x1b[97;1u'.codeUnits);
      expect(events.single.logicalKey, LogicalKeyboardKey.keyA);
      expect(events.single.character, 'a');
      expect(events.single.modifiers, 0);
    });

    test('Ctrl+a via CSI-u (modField=5 → ctrl)', () {
      // 1-based modifiers: 5 - 1 = 4 = ctrl bit
      final events = _keyEventsFor('\x1b[97;5u'.codeUnits);
      expect(events.single.logicalKey, LogicalKeyboardKey.keyA);
      expect(events.single.character, 'a');
      expect(events.single.modifiers & KeyModifiers.ctrl, isNonZero);
    });

    test('named key (Tab via codepoint 9)', () {
      final events = _keyEventsFor('\x1b[9;1u'.codeUnits);
      expect(events.single.logicalKey, LogicalKeyboardKey.tab);
    });

    test('Kitty F1 via 57364', () {
      final events = _keyEventsFor('\x1b[57364;1u'.codeUnits);
      expect(events.single.logicalKey, LogicalKeyboardKey.f1);
    });

    test('Kitty named arrows follow OpenTUI key map', () {
      final up = _keyEventsFor('\x1b[57352u'.codeUnits).single;
      final down = _keyEventsFor('\x1b[57353u'.codeUnits).single;

      expect(up.logicalKey, LogicalKeyboardKey.arrowUp);
      expect(down.logicalKey, LogicalKeyboardKey.arrowDown);
    });

    test('Kitty event types set press and repeat state', () {
      final repeat = _keyEventsFor('\x1b[97;1:2u'.codeUnits).single;
      expect(repeat.logicalKey, LogicalKeyboardKey.keyA);
      expect(repeat.isPress, isTrue);
      expect(repeat.isRepeat, isTrue);

      final release = _keyEventsFor('\x1b[97;1:3u'.codeUnits).single;
      expect(release.logicalKey, LogicalKeyboardKey.keyA);
      expect(release.isPress, isFalse);
      expect(release.isRepeat, isFalse);
    });

    test('Kitty named key repeat preserves modifiers', () {
      final event = _keyEventsFor('\x1b[57352;5:2u'.codeUnits).single;

      expect(event.logicalKey, LogicalKeyboardKey.arrowUp);
      expect(event.isControlPressed, isTrue);
      expect(event.isRepeat, isTrue);
    });

    test('Kitty associated text is used as printable character', () {
      final event = _keyEventsFor('\x1b[97;1;233u'.codeUnits).single;

      expect(event.logicalKey, LogicalKeyboardKey.keyA);
      expect(event.character, 'é');
    });

    test('Kitty shifted printable keeps base logical key', () {
      final event = _keyEventsFor('\x1b[49:33;2u'.codeUnits).single;

      expect(event.logicalKey, LogicalKeyboardKey.digit1);
      expect(event.character, '!');
      expect(event.isShiftPressed, isTrue);
    });
  });

  group('parseAnsiInput — incomplete sequences', () {
    test('streaming parser can hold a trailing ESC for the next chunk', () {
      final first = parseAnsiInput([0x1b], holdTrailingEscape: true);
      expect(first.events, isEmpty);
      expect(first.leftover, [0x1b]);

      final second = parseAnsiInput(<int>[
        ...first.leftover,
        0x5b,
        0x41,
      ], holdTrailingEscape: true);
      expect(second.leftover, isEmpty);
      expect(
        second.events.whereType<KeyInput>().single.event.logicalKey,
        LogicalKeyboardKey.arrowUp,
      );
    });

    test('lone ESC [ at end of buffer is held as leftover', () {
      final r = parseAnsiInput([0x1b, 0x5b]);
      expect(r.events, isEmpty);
      expect(r.leftover, [0x1b, 0x5b]);
    });

    test('truncated UTF-8 multibyte is held as leftover', () {
      // Start of 'ñ' (0xc3 0xb1), only first byte present.
      final r = parseAnsiInput([0xc3]);
      expect(r.events, isEmpty);
      expect(r.leftover, [0xc3]);
    });
  });
}

List<KeyEvent> _keyEventsFor(List<int> bytes) => parseAnsiInput(
  bytes,
).events.whereType<KeyInput>().map((i) => i.event).toList();

String _keyLabel(KeyEvent event) =>
    event.character ?? event.logicalKey.keyLabel;

List<TerminalCapabilityEvent> _capabilityEventsFor(List<int> bytes) =>
    parseAnsiInput(
      bytes,
    ).events.whereType<CapabilityInput>().map((input) => input.event).toList();
