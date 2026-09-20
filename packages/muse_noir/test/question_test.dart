import 'dart:async';

import 'package:ack/ack.dart';
import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../noir/test/helpers/buffer_capture.dart';
import '../../noir/test/helpers/key_driver.dart';
import '../../noir/test/helpers/tui_test_app.dart';

void main() {
  test('single choice edits and submits immediately', () async {
    final fixture = await _QuestionFixture.open(mode: 'single');
    addTearDown(fixture.dispose);
    final driver = fixture.driver();
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await _drain();
    expect(fixture.answers, <Map<String, Object?>>[
      <String, Object?>{
        'questionId': 'deployment',
        'answer': <String, Object?>{
          'selectedValues': <String>['tomorrow'],
          'freeText': '',
        },
      },
    ]);
  });

  test('multiple choice uses explicit submission', () async {
    final fixture = await _QuestionFixture.open(mode: 'multiple');
    addTearDown(fixture.dispose);
    final driver = fixture.driver();
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
    expect(fixture.answers, isEmpty);
    await driver.sendLogicalKey(LogicalKeyboardKey.tab, code: 9);
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await _drain();
    expect(fixture.answers.single['answer'], <String, Object?>{
      'selectedValues': <String>['today'],
      'freeText': '',
    });
  });

  test('free text is trimmed and submitted from its local draft', () async {
    final fixture = await _QuestionFixture.open(
      mode: 'single',
      options: const <Object?>[],
      allowFreeText: true,
    );
    addTearDown(fixture.dispose);
    final driver = fixture.driver();
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendPaste('  next week  ');
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await _drain();
    expect(fixture.answers.single['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'next week',
    });
  });

  test('choices plus free text submit the typed answer', () async {
    final fixture = await _QuestionFixture.open(
      mode: 'single',
      allowFreeText: true,
    );
    addTearDown(fixture.dispose);
    final driver = fixture.driver();
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.tab, code: 9);
    await driver.sendPaste('next week');
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await _drain();
    expect(fixture.answers.single['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'next week',
    });
  });

  test('disabled free text cannot diverge from the Muse draft', () async {
    final fixture = await _QuestionFixture.open(
      mode: 'single',
      options: const <Object?>[],
      allowFreeText: true,
      enabled: false,
    );
    addTearDown(fixture.dispose);
    final app = createTuiTestApp(
      MuseNoirView(navigator: fixture.navigator, renderer: museNoirRenderer),
      width: 60,
      height: 18,
    );
    addTearDown(app.dispose);
    await _drain();

    app.mockInput
      ..typeText('x')
      ..paste('locked')
      ..pressBackspace();
    app.pumpFrame();
    expect(app.captureFrame().containsText('xlocke'), isFalse);
    fixture.enabled!.value = true;
    await _drain();
    app.pumpFrame();

    app.mockInput
      ..paste('ready')
      ..pressEnter();
    await _drain();
    expect(fixture.answers.single['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'ready',
    });
  });

  test(
    'a failing check permits editing and shows rejected-action feedback',
    () async {
      final fixture = await _QuestionFixture.open(
        mode: 'single',
        options: const <Object?>[],
        allowFreeText: true,
        checks: const <Object?>[
          <String, Object?>{
            'condition': false,
            'message': 'Answers are temporarily unavailable.',
          },
        ],
      );
      addTearDown(fixture.dispose);
      final app = createTuiTestApp(
        MuseNoirView(navigator: fixture.navigator, renderer: museNoirRenderer),
        width: 60,
        height: 18,
      );
      addTearDown(app.dispose);
      await _drain();
      app.mockInput.paste('ready');
      app.mockInput.pressEnter();
      await _drain();
      expect(fixture.answers, isEmpty);
      app.pumpFrame();
      final frame = app.captureFrame();
      expect(frame.containsText('ready'), isTrue);
      expect(frame.containsText('failing'), isTrue, reason: frame.toText());
    },
  );

  test('in-flight submission suppresses duplicate activation', () async {
    final completion = Completer<void>();
    final fixture = await _QuestionFixture.open(
      mode: 'multiple',
      onAnswer: (_) => completion.future,
    );
    addTearDown(fixture.dispose);
    final driver = fixture.driver();
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.space, code: 32);
    await driver.sendLogicalKey(LogicalKeyboardKey.tab, code: 9);
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    expect(fixture.answers, hasLength(1));
    completion.complete();
    await _drain();
  });

  test('busy free text stays aligned with the submitted Muse draft', () async {
    final completion = Completer<void>();
    final fixture = await _QuestionFixture.open(
      mode: 'single',
      options: const <Object?>[],
      allowFreeText: true,
      onAnswer: (_) => completion.future,
    );
    addTearDown(fixture.dispose);
    final app = createTuiTestApp(
      MuseNoirView(navigator: fixture.navigator, renderer: museNoirRenderer),
      width: 60,
      height: 18,
    );
    addTearDown(app.dispose);
    await _drain();
    app.mockInput
      ..paste('ready')
      ..pressEnter()
      ..pressArrow(ArrowDirection.left)
      ..typeText('x')
      ..paste('blocked')
      ..pressBackspace()
      ..pressEnter();
    expect(fixture.answers, hasLength(1));

    completion.complete();
    await _drainMicrotasks();
    app.mockInput
      ..typeText('!')
      ..pressEnter();
    await _drain();
    expect(fixture.answers, hasLength(2));
    expect(fixture.answers.first['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'ready',
    });
    expect(fixture.answers.last['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'read!y',
    });
  });

  test(
    'long options stay bounded and keep visible interaction guidance',
    () async {
      final options = <Object?>[
        for (var index = 1; index <= 12; index += 1)
          <String, Object?>{'value': 'option-$index', 'label': 'Option $index'},
      ];
      final fixture = await _QuestionFixture.open(
        mode: 'multiple',
        options: options,
      );
      addTearDown(fixture.dispose);
      final capture = BufferCapture(width: 60, height: 18);
      addTearDown(capture.dispose);
      final frame = capture.capture(
        MuseNoirView(navigator: fixture.navigator, renderer: museNoirRenderer),
      );
      expect(frame.containsText('Option 1'), isTrue);
      expect(frame.containsText('Option 8'), isTrue);
      expect(frame.toText(), contains(Icons.triangleDown));
      expect(frame.containsText('Multiple choice'), isTrue);
      expect(frame.containsText('Answer'), isTrue);
    },
  );

  test('two questions retain separate draft paths', () async {
    final received = <Map<String, Object?>>[];
    final intent = _questionIntent(received, (_) {});
    final navigator = MuseIntentNavigator(
      generator: MuseGenerator.scripted(<Object>[
        <Object>[
          _create(),
          _update(<Object?>[
            <String, Object?>{
              'id': 'root',
              'component': 'Column',
              'children': <String>['q1', 'q2'],
            },
            _question('q1', 'first', 'single'),
            _question('q2', 'second', 'single', autofocus: false),
          ]),
        ],
      ]),
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
    );
    addTearDown(navigator.dispose);
    final result = await navigator.push(intent);
    expect(result, isA<MuseNavigated>());
    final driver = KeyDriver(
      MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
      width: 60,
    );
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await driver.sendLogicalKey(LogicalKeyboardKey.tab, code: 9);
    await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);
    await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
    await _drain();
    expect(received.map((answer) => answer['questionId']), <String>[
      'first',
      'second',
    ]);
    expect(received.map((answer) => answer['answer']), <Map<String, Object?>>[
      <String, Object?>{
        'selectedValues': <String>['today'],
        'freeText': '',
      },
      <String, Object?>{
        'selectedValues': <String>['tomorrow'],
        'freeText': '',
      },
    ]);
  });

  test('push and pop retain the Muse-owned Question draft', () async {
    final answers = <Map<String, Object?>>[];
    final firstIntent = _questionIntent(answers, (_) {});
    final secondIntent = MuseIntent(
      id: 'second',
      description: 'Second route.',
      instructions: 'Show a label.',
      catalog: museNoirCatalog,
    );
    final navigator = MuseIntentNavigator(
      generator: MuseGenerator.scripted(<Object>[
        <Object>[
          _create(),
          _update(<Object?>[
            _question(
              'root',
              'deployment',
              'single',
              options: const <Object?>[],
              allowFreeText: true,
            ),
          ]),
        ],
        <Object>[
          _create(),
          _update(<Object?>[
            <String, Object?>{
              'id': 'root',
              'component': 'Text',
              'text': 'Second route',
            },
          ]),
        ],
      ]),
      routes: <MuseIntentRoute>[
        MuseIntentRoute(firstIntent),
        MuseIntentRoute(secondIntent),
      ],
    );
    addTearDown(navigator.dispose);
    expect(await navigator.push(firstIntent), isA<MuseNavigated>());
    final app = createTuiTestApp(
      MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
      width: 60,
      height: 18,
    );
    addTearDown(app.dispose);
    await _drain();
    app.mockInput.paste('retained draft');
    await _drain();

    expect(await navigator.push(secondIntent), isA<MuseNavigated>());
    app.pumpFrame();
    expect(app.captureFrame().containsText('Second route'), isTrue);
    await navigator.pop();
    await _drain();
    app.pumpFrame();
    final draft = app.captureFrame().findText('retained draft').single;
    app.mockMouse.click(draft.x, draft.y);

    app.mockInput.pressEnter();
    await _drain();
    expect(answers.single['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'retained draft',
    });
  });

  test('host updates preserve an unchanged free-text selection', () async {
    final fixture = await _QuestionFixture.open(
      mode: 'single',
      options: const <Object?>[],
      allowFreeText: true,
      enabled: true,
    );
    addTearDown(fixture.dispose);
    final app = createTuiTestApp(
      MuseNoirView(navigator: fixture.navigator, renderer: museNoirRenderer),
      width: 60,
      height: 18,
    );
    addTearDown(app.dispose);
    await _drain();
    app.mockInput
      ..paste('abcd')
      ..pressArrow(ArrowDirection.left)
      ..pressArrow(ArrowDirection.left);

    fixture.enabled!.value = false;
    await _drain();
    app.pumpFrame();
    fixture.enabled!.value = true;
    await _drain();
    app.pumpFrame();
    app.mockInput
      ..typeText('X')
      ..pressEnter();
    await _drain();

    expect(fixture.answers.single['answer'], <String, Object?>{
      'selectedValues': <String>[],
      'freeText': 'abXcd',
    });
  });
}

final class _QuestionFixture {
  _QuestionFixture._(
    this.navigator,
    this.answers, {
    this.enabled,
    MuseValueListenable<bool>? enabledAdapter,
  }) : _enabledAdapter = enabledAdapter;

  final MuseIntentNavigator navigator;
  final List<Map<String, Object?>> answers;
  final ValueNotifier<bool>? enabled;
  final MuseValueListenable<bool>? _enabledAdapter;

  static Future<_QuestionFixture> open({
    required String mode,
    List<Object?> options = const <Object?>[
      <String, Object?>{'value': 'today', 'label': 'Today'},
      <String, Object?>{'value': 'tomorrow', 'label': 'Tomorrow'},
    ],
    bool allowFreeText = false,
    bool? enabled,
    List<Object?>? checks,
    FutureOr<void> Function(Map<String, Object?> answer)? onAnswer,
  }) async {
    final answers = <Map<String, Object?>>[];
    final enabledNotifier = enabled == null
        ? null
        : ValueNotifier<bool>(enabled);
    final enabledAdapter = enabledNotifier == null
        ? null
        : MuseValueListenable<bool>(enabledNotifier);
    final intent = _questionIntent(
      answers,
      onAnswer ?? (_) {},
      enabled: enabledAdapter,
    );
    final navigator = MuseIntentNavigator(
      generator: MuseGenerator.scripted(<Object>[
        <Object>[
          _create(),
          _update(<Object?>[
            _question(
              'root',
              'deployment',
              mode,
              options: options,
              allowFreeText: allowFreeText,
              enabled: enabledAdapter == null
                  ? true
                  : _stateBinding('/enabled'),
              checks: checks,
            ),
          ]),
        ],
      ]),
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
    );
    final result = await navigator.push(intent);
    expect(
      result,
      isA<MuseNavigated>(),
      reason: result is MuseNavigationFailed
          ? '${result.failure} ${result.failure.issues}'
          : '$result',
    );
    return _QuestionFixture._(
      navigator,
      answers,
      enabled: enabledNotifier,
      enabledAdapter: enabledAdapter,
    );
  }

  KeyDriver driver() => KeyDriver(
    MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
    width: 60,
    height: 18,
  );

  Future<void> dispose() async {
    await navigator.dispose();
    _enabledAdapter?.dispose();
    enabled?.dispose();
  }
}

MuseIntent _questionIntent(
  List<Map<String, Object?>> answers,
  FutureOr<void> Function(Map<String, Object?> answer) onAnswer, {
  MuseListenable<bool>? enabled,
}) => MuseIntent(
  id: 'question',
  description: 'Question test.',
  instructions: 'Ask bounded questions.',
  catalog: museNoirCatalog,
  constraints: museNoirConstraints,
  states: <MuseState<Object>>[
    if (enabled != null)
      MuseState<bool>(
            name: 'enabled',
            description: 'Whether the question accepts input.',
            schema: Ack.boolean(),
            watch: (_) => enabled,
          )
          as MuseState<Object>,
  ],
  actions: <MuseAction<Object?>>[
    MuseAction<Map<String, Object?>>(
          name: 'answer',
          description: 'Record one answer.',
          parameters: Ack.object(<String, AckSchema<Object, Object>>{
            'questionId': Ack.string(),
            'answer': Ack.object(<String, AckSchema<Object, Object>>{
              'selectedValues': Ack.list(Ack.string()),
              'freeText': Ack.string(),
            }),
          }),
          handler: (_, parameters) {
            answers.add(parameters);
            return onAnswer(parameters);
          },
        )
        as MuseAction<Object?>,
  ],
);

Map<String, Object?> _create() => <String, Object?>{
  'version': 'v0.9.1',
  'createSurface': <String, Object?>{
    'surfaceId': 'question',
    'catalogId': museNoirCatalogId,
  },
};

Map<String, Object?> _update(List<Object?> components) => <String, Object?>{
  'version': 'v0.9.1',
  'updateComponents': <String, Object?>{
    'surfaceId': 'question',
    'components': components,
  },
};

Map<String, Object?> _question(
  String id,
  String questionId,
  String mode, {
  List<Object?> options = const <Object?>[
    <String, Object?>{'value': 'today', 'label': 'Today'},
    <String, Object?>{'value': 'tomorrow', 'label': 'Tomorrow'},
  ],
  bool allowFreeText = false,
  Object? enabled = true,
  bool autofocus = true,
  List<Object?>? checks,
}) => <String, Object?>{
  'id': id,
  'component': 'Question',
  'questionId': questionId,
  'prompt': 'Choose deployment timing',
  'mode': mode,
  'options': options,
  'allowFreeText': allowFreeText,
  'enabled': enabled,
  'autofocus': autofocus,
  'answer': <String, Object?>{'selectedValues': <String>[], 'freeText': ''},
  'checks': ?checks,
  'action': <String, Object?>{
    'event': <String, Object?>{
      'name': 'answer',
      'context': <String, Object?>{
        'questionId': questionId,
        'answer': <String, Object?>{'path': '/draft/$id/answer'},
      },
    },
  },
};

Map<String, Object?> _stateBinding(String path) => <String, Object?>{
  r'$muse': <String, Object?>{
    'state': <String, Object?>{'path': path},
  },
};

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _drainMicrotasks() async {
  for (var index = 0; index < 10; index += 1) {
    await Future<void>.microtask(() {});
  }
}
