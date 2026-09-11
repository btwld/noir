import 'dart:async';

import 'dart:convert';

import 'package:noir/noir.dart';
import 'package:noir/src/app/driver.dart';
import 'package:noir/src/core/stdin_input_driver.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';

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
      'shift-tab': LogicalKeyboardKey.tab,
      'space': LogicalKeyboardKey.space,
      'esc': LogicalKeyboardKey.escape,
      'backspace': LogicalKeyboardKey.backspace,
      'home': LogicalKeyboardKey.home,
      'end': LogicalKeyboardKey.end,
      'delete': LogicalKeyboardKey.delete,
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

    test('new navigation names use their conventional terminal bytes', () {
      expect(encodeKey('shift-tab'), utf8.encode('\x1b[Z'));
      expect(encodeKey('home'), utf8.encode('\x1b[H'));
      expect(encodeKey('end'), utf8.encode('\x1b[F'));
      expect(encodeKey('delete'), utf8.encode('\x1b[3~'));
      expect(_singleKey(encodeKey('shift-tab')).isShiftPressed, isTrue);
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

  test(
    'driver readiness waits for the first painted frame after registration',
    () async {
      var polls = 0;
      var delays = 0;
      await awaitDriverReady(
        frames: () async {
          polls++;
          if (polls == 1) throw RPCError('info', -32601);
          return polls < 4 ? 0 : 1;
        },
        timeout: const Duration(seconds: 5),
        delay: (_) async => delays++,
      );
      expect(polls, 4);
      expect(delays, 3);
    },
  );

  test(
    'driver readiness times out when registered but no frame is painted',
    () async {
      await expectLater(
        awaitDriverReady(frames: () async => 0, timeout: Duration.zero),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test(
    'driver readiness bounds a pending info response by its deadline',
    () async {
      await expectLater(
        awaitDriverReady(
          frames: () => Completer<int>().future,
          timeout: Duration.zero,
        ).timeout(
          const Duration(milliseconds: 200),
          onTimeout: () => throw StateError('Readiness exceeded its deadline'),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('driver readiness propagates unexpected service errors', () async {
    final error = RPCError('info', RPCErrorKind.kServiceDisappeared.code);
    await expectLater(
      awaitDriverReady(
        frames: () async => throw error,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(same(error)),
    );
  });

  test('pollFrameAdvance returns as soon as frames increase', () async {
    var frames = 0;
    final advanced = await pollFrameAdvance(
      frames: () async => ++frames,
      before: 0,
    );

    expect(advanced, isTrue);
    expect(frames, 1);
  });

  test('isDrivenServiceGone is only the vanished-service RPC', () {
    expect(
      isDrivenServiceGone(
        RPCError('info', RPCErrorKind.kServiceDisappeared.code),
      ),
      isTrue,
    );
    // A request still in flight when the socket closes fails with the
    // generic server-error code and the disposed-connection message.
    expect(
      isDrivenServiceGone(
        RPCError(
          'info',
          RPCErrorKind.kServerError.code,
          'Service connection disposed',
        ),
      ),
      isTrue,
    );
    expect(
      isDrivenServiceGone(
        RPCError('info', RPCErrorKind.kConnectionDisposed.code),
      ),
      isTrue,
    );
    expect(
      isDrivenServiceGone(
        RPCError('info', RPCErrorKind.kServerError.code, 'another failure'),
      ),
      isFalse,
    );
    expect(isDrivenServiceGone(RPCError('info', 100)), isFalse);
    expect(isDrivenServiceGone(StateError('gone')), isFalse);
  });

  test('pollFrameAdvance returns false when frames never increase', () async {
    final advanced = await pollFrameAdvance(
      frames: () async => 0,
      before: 0,
      cap: Duration.zero,
    );

    expect(advanced, isFalse);
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

  group('DriverTree locators', () {
    test('parses structured JSON and resolves exact locator kinds', () {
      final tree = DriverTree.fromJson(_driverTreeJson());

      expect(tree.root!.type, 'Root');
      expect(tree.root!.children.single.parent, same(tree.root));
      expect(tree.findAll(DriverLocator.byKey('save')), hasLength(1));
      expect(tree.findAll(DriverLocator.byKey('SAVE')), isEmpty);
      expect(tree.findAll(DriverLocator.byType('Button')), hasLength(2));
      expect(tree.findAll(DriverLocator.byText('Save')), hasLength(1));
      expect(tree.findAll(DriverLocator.byText('save')), isEmpty);
      expect(tree.findAll(const DriverLocator.focused()), hasLength(1));
    });

    test('strict find diagnoses zero and multiple matches', () {
      final tree = DriverTree.fromJson(_driverTreeJson());

      expect(
        () => tree.find(DriverLocator.byKey('missing')),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('0 matches'),
          ),
        ),
      );
      expect(
        () => tree.find(DriverLocator.byType('Button')),
        throwsA(
          isA<StateError>()
              .having((error) => '$error', 'message', contains('2 matches'))
              .having((error) => '$error', 'matches', contains('key: save'))
              .having((error) => '$error', 'matches', contains('key: cancel')),
        ),
      );
    });

    test(
      'strict zero-match errors list nearby types, keys, and the source-text rule',
      () {
        final tree = DriverTree.fromJson(_driverTreeJson());

        expect(
          () => tree.find(DriverLocator.byType('Select')),
          throwsA(
            isA<StateError>()
                .having((error) => '$error', 'message', contains('0 matches'))
                .having((error) => '$error', 'message', contains('runtimeType'))
                .having(
                  (error) => '$error',
                  'message',
                  contains('Select<String>'),
                ),
          ),
        );
        expect(
          () => tree.find(DriverLocator.byKey('missing')),
          throwsA(
            isA<StateError>()
                .having((error) => '$error', 'message', contains('0 matches'))
                .having((error) => '$error', 'message', contains('save'))
                .having((error) => '$error', 'message', contains('panel')),
          ),
        );
        expect(
          () => tree.find(DriverLocator.byText('Apple')),
          throwsA(
            isA<StateError>()
                .having((error) => '$error', 'message', contains('0 matches'))
                .having(
                  (error) => '$error',
                  'message',
                  contains('Text and RichText source'),
                )
                .having((error) => '$error', 'message', contains('save')),
          ),
        );
        expect(
          () => DriverTree.fromJson(
            _driverTreeJson(includeSave: false),
          ).find(const DriverLocator.focused()),
          throwsA(
            isA<StateError>()
                .having((error) => '$error', 'message', contains('0 matches'))
                .having(
                  (error) => '$error',
                  'message',
                  contains('primary focus'),
                ),
          ),
        );
      },
    );

    test('actionPoint never borrows a visible ancestor for a hidden node', () {
      final tree = DriverTree.fromJson(_driverTreeJson());
      final label = tree.find(DriverLocator.byText('Save'));

      expect(label.hitPoint, isNull);
      expect(label.actionPoint, isNull);
    });

    test('click helper rejects a match with only an ancestor point', () async {
      final clicked = <DriverPoint>[];

      await expectLater(
        clickDriverLocator(
          DriverLocator.byText('Save'),
          fetchTree: () async => DriverTree.fromJson(_driverTreeJson()),
          click: clicked.add,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => '$error',
            'message',
            contains('offscreen, fully obscured'),
          ),
        ),
      );
      expect(clicked, isEmpty);
    });

    test('click helper re-resolves immediately before every action', () async {
      var fetches = 0;
      final clicked = <DriverPoint>[];
      Future<DriverTree> fetchTree() async {
        fetches++;
        final json = _driverTreeJson();
        final root = json['root']! as Map<String, Object?>;
        final panel =
            (root['children']! as List<Object?>).single!
                as Map<String, Object?>;
        final save =
            (panel['children']! as List<Object?>).first!
                as Map<String, Object?>;
        final label =
            (save['children']! as List<Object?>).single!
                as Map<String, Object?>;
        label['hitPoint'] = <String, Object?>{'x': fetches, 'y': 2};
        return DriverTree.fromJson(json);
      }

      await clickDriverLocator(
        DriverLocator.byText('Save'),
        fetchTree: fetchTree,
        click: clicked.add,
      );
      await clickDriverLocator(
        DriverLocator.byText('Save'),
        fetchTree: fetchTree,
        click: clicked.add,
      );

      expect(fetches, 2);
      expect(clicked, const <DriverPoint>[
        DriverPoint(1, 2),
        DriverPoint(2, 2),
      ]);
    });
  });

  group('locator waits', () {
    test('waitFor retries zero matches and returns a fresh match', () async {
      var calls = 0;
      final node = await waitForDriverLocator(
        DriverLocator.byKey('save'),
        fetchTree: () async {
          calls++;
          return DriverTree.fromJson(_driverTreeJson(includeSave: calls >= 2));
        },
        pollInterval: Duration.zero,
      );

      expect(calls, 2);
      expect(node.key, 'save');
    });

    test(
      'waitFor times out on zero and fails immediately on multiple',
      () async {
        await expectLater(
          waitForDriverLocator(
            DriverLocator.byKey('save'),
            fetchTree: () async =>
                DriverTree.fromJson(_driverTreeJson(includeSave: false)),
            timeout: Duration.zero,
            pollInterval: Duration.zero,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'message',
              contains('Timed out'),
            ),
          ),
        );
        await expectLater(
          waitForDriverLocator(
            DriverLocator.byType('Button'),
            fetchTree: () async => DriverTree.fromJson(_driverTreeJson()),
            timeout: const Duration(days: 1),
            pollInterval: Duration.zero,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => '$error',
              'message',
              contains('2 matches'),
            ),
          ),
        );
      },
    );

    test('waitForAbsent polls until every match is gone', () async {
      var calls = 0;
      await waitForAbsentDriverLocator(
        DriverLocator.byType('Button'),
        fetchTree: () async {
          calls++;
          return DriverTree.fromJson(
            _driverTreeJson(includeSave: calls < 2, includeCancel: calls < 3),
          );
        },
        pollInterval: Duration.zero,
      );

      expect(calls, 3);
    });
  });
}

Map<String, Object?> _driverTreeJson({
  bool includeSave = true,
  bool includeCancel = true,
}) => <String, Object?>{
  'type': 'Success',
  'root': <String, Object?>{
    'type': 'Root',
    'key': null,
    'text': null,
    'focused': false,
    'hasFocusedDescendant': true,
    'hitPoint': null,
    'children': <Object?>[
      <String, Object?>{
        'type': 'Panel',
        'key': 'panel',
        'text': null,
        'focused': false,
        'hasFocusedDescendant': true,
        'hitPoint': <String, Object?>{'x': 4, 'y': 2},
        'children': <Object?>[
          if (includeSave)
            <String, Object?>{
              'type': 'Button',
              'key': 'save',
              'text': null,
              'focused': true,
              'hasFocusedDescendant': false,
              'hitPoint': null,
              'children': <Object?>[
                <String, Object?>{
                  'type': 'Text',
                  'key': null,
                  'text': 'Save',
                  'focused': false,
                  'hasFocusedDescendant': false,
                  'hitPoint': null,
                  'children': <Object?>[],
                },
              ],
            },
          if (includeCancel)
            <String, Object?>{
              'type': 'Button',
              'key': 'cancel',
              'text': 'Cancel',
              'focused': false,
              'hasFocusedDescendant': false,
              'hitPoint': <String, Object?>{'x': 10, 'y': 2},
              'children': <Object?>[],
            },
          <String, Object?>{
            'type': 'Select<String>',
            'key': 'fruit',
            'text': null,
            'focused': false,
            'hasFocusedDescendant': false,
            'hitPoint': <String, Object?>{'x': 2, 'y': 5},
            'children': <Object?>[],
          },
        ],
      },
    ],
  },
};

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
