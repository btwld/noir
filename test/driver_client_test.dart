import 'dart:convert';

import 'package:noir/noir.dart';
import 'package:noir/src/app/driver.dart';
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';

import '../scripts/driver/ansi_keys.dart';
import '../scripts/driver/noir_driver.dart';

/// The driver encodes names to escape bytes on the client side so the app
/// stays byte-only. That split is only correct while the bytes it produces
/// decode back to the intended event through the production parser, which is
/// what every round trip below asserts.
void main() {
  group('encodeKey', () {
    const expectedKeys = <String, LogicalKeyboardKey>{
      'up': LogicalKeyboardKey.arrowUp,
      'down': LogicalKeyboardKey.arrowDown,
      'left': LogicalKeyboardKey.arrowLeft,
      'right': LogicalKeyboardKey.arrowRight,
      'enter': LogicalKeyboardKey.enter,
      'tab': LogicalKeyboardKey.tab,
      'esc': LogicalKeyboardKey.escape,
      'backspace': LogicalKeyboardKey.backspace,
      'pgup': LogicalKeyboardKey.pageUp,
      'pgdn': LogicalKeyboardKey.pageDown,
    };

    test('documents exactly the named keys the CLI grammar offers', () {
      expect(namedKeys, unorderedEquals(expectedKeys.keys));
    });

    test('every named key parses back to its logical key', () {
      for (final entry in expectedKeys.entries) {
        expect(
          _singleKey(encodeKey(entry.key)).logicalKey,
          entry.value,
          reason: entry.key,
        );
      }
    });

    test('ctrl-<a-z> parses back to the letter with the control modifier', () {
      final event = _singleKey(encodeKey('ctrl-c'));

      expect(event.logicalKey, LogicalKeyboardKey.keyC);
      expect(event.isControlPressed, isTrue);
    });

    test('names are case-insensitive and trimmed', () {
      expect(encodeKey('  UP  '), encodeKey('up'));
      expect(encodeKey('Ctrl-C'), encodeKey('ctrl-c'));
    });

    test('an unknown name fails loudly instead of sending nothing', () {
      expect(() => encodeKey('nope'), throwsArgumentError);
      expect(() => encodeKey('ctrl-1'), throwsArgumentError);
      expect(() => encodeKey('ctrl-'), throwsArgumentError);
      expect(() => encodeKey(''), throwsArgumentError);
    });
  });

  test('encodeText parses back as one key event per character', () {
    final events = parseAnsiInput(encodeText('hi ✓')).events;

    expect(events.map((event) => (event as KeyInput).event.character), <String>[
      'h',
      'i',
      ' ',
      '✓',
    ]);
  });

  test('encodeClick parses back as a press and release at the same cell', () {
    final events = parseAnsiInput(
      encodeClick(3, 4),
    ).events.cast<MouseInput>().map((input) => input.event).toList();

    expect(events.map((event) => event.type), <MouseEventType>[
      MouseEventType.down,
      MouseEventType.up,
    ]);
    for (final event in events) {
      expect(event.button, MouseButton.left);
      expect(event.x, 3);
      expect(event.y, 4);
    }
  });

  test('encodeClick honours the requested button', () {
    final event =
        (parseAnsiInput(
                  encodeClick(0, 0, button: DriverMouseButton.right),
                ).events.first
                as MouseInput)
            .event;

    expect(event.button, MouseButton.right);
  });

  test('encodeScroll parses back as a wheel event in each direction', () {
    const expectedDirections = <DriverScrollDirection, MouseScrollDirection>{
      DriverScrollDirection.up: MouseScrollDirection.up,
      DriverScrollDirection.down: MouseScrollDirection.down,
      DriverScrollDirection.left: MouseScrollDirection.left,
      DriverScrollDirection.right: MouseScrollDirection.right,
    };

    for (final entry in expectedDirections.entries) {
      final event =
          (parseAnsiInput(encodeScroll(2, 1, entry.key)).events.single
                  as MouseInput)
              .event;

      expect(event.type, MouseEventType.scroll, reason: entry.key.name);
      expect(event.scroll?.direction, entry.value, reason: entry.key.name);
      expect(event.x, 2);
      expect(event.y, 1);
    }
  });

  test('negative mouse coordinates are rejected before encoding', () {
    expect(() => encodeClick(-1, 0), throwsArgumentError);
    expect(
      () => encodeScroll(0, -1, DriverScrollDirection.up),
      throwsArgumentError,
    );
  });

  test('DriverFrame reads a real cells capture off the wire', () {
    final host = DriverHost.create(width: 6, height: 2);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const _Scene())
      ..debugFlushFrame();

    final captured = host.capture(format: DriverCaptureFormat.cells);
    // Round-trip through JSON: this is the exact encoding the VM service
    // inlines, so it is the contract the two sides have to agree on.
    final frame = DriverFrame.fromJson(
      jsonDecode(jsonEncode(captured)) as Map<String, dynamic>,
    );

    expect(frame.width, 6);
    expect(frame.height, 2);
    expect(frame.lines, captured['lines']);
    expect(frame.contains('ok'), isTrue);
    expect(frame.rows, hasLength(2));
    expect(frame.rows.first, hasLength(6));
    expect(frame.rows.first.first.char, 'o');
    expect(frame.rows.first.first.foreground.toAnsiHex(), '#ffff00');
    expect(frame.rows.first.first.background.toAnsiHex(), '#0000ff');
    expect(frame.cursor.visible, isFalse);
  });

  test('DriverFrame reads a text capture with no per-cell rows', () {
    final host = DriverHost.create(width: 6, height: 2);
    addTearDown(host.dispose);
    host.binding
      ..runApp(const _Scene())
      ..debugFlushFrame();

    final frame = DriverFrame.fromJson(
      jsonDecode(jsonEncode(host.capture())) as Map<String, dynamic>,
    );

    expect(frame.rows, isEmpty);
    expect(frame.contains('ok'), isTrue);
  });

  test('DriverColor parses both the opaque and alpha hex forms', () {
    expect(DriverColor.parse('#0a141e').toAnsiHex(), '#0a141e');
    expect(DriverColor.parse('#0a141e80').alpha, 0x80);
    expect(DriverColor.parse('0a141e').red, 0x0a);
    expect(() => DriverColor.parse('#abc'), throwsFormatException);
  });
}

KeyEvent _singleKey(List<int> bytes) {
  final events = parseAnsiInput(bytes).events;
  expect(events, hasLength(1), reason: '$bytes');
  return (events.single as KeyInput).event;
}

class _Scene extends StatelessWidget {
  const _Scene();

  @override
  Widget build(BuildContext context) => Container(
    color: Color.blue,
    child: const Text('ok', style: TextStyle(color: Color.yellow)),
  );
}
