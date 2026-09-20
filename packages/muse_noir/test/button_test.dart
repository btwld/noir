import 'dart:async';
import 'dart:convert';

import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../noir/test/helpers/tui_test_app.dart';

void main() {
  test('Button shows failure, clears it on retry, and awaits once', () async {
    final pending = Completer<void>();
    var attempts = 0;
    final fixture = await _ButtonFixture.open(() async {
      attempts += 1;
      if (attempts == 1) throw StateError('first attempt failed');
      await pending.future;
    });
    addTearDown(fixture.dispose);
    final app = fixture.app();
    addTearDown(app.dispose);
    await _drain();

    _click(app, 'Run');
    await _drain();
    app.pumpFrame();
    expect(app.captureFrame().containsText('handler for "run" threw'), isTrue);

    _click(app, 'Run');
    _click(app, 'Run');
    await _drain();
    app.pumpFrame();
    expect(attempts, 2, reason: 'pending activation suppresses duplicates');
    expect(app.captureFrame().containsText('handler for "run" threw'), isFalse);

    pending.complete();
    await _drain();
  });

  test('late completion cannot affect a replacement Button', () async {
    final pending = Completer<void>();
    final revision = ValueNotifier<int>(0);
    final revisionAdapter = MuseValueListenable<int>(revision);
    var replacementCalls = 0;
    final intent = MuseIntent(
      id: 'replacement',
      description: 'Button replacement test.',
      instructions: 'Show one replaceable Button.',
      catalog: museNoirCatalog,
      facts: <MuseFact<Object?>>[
        MuseFact<int>(
          name: 'revision',
          description: 'Rendered Button revision.',
          watch: (_) => revisionAdapter,
        ),
      ],
      actions: <MuseAction<Object?>>[
        MuseAction<void>(
              name: 'old',
              description: 'Wait for late completion.',
              handler: (_, _) => pending.future,
            )
            as MuseAction<Object?>,
        MuseAction<void>(
              name: 'new',
              description: 'Record replacement activation.',
              handler: (_, _) => replacementCalls += 1,
            )
            as MuseAction<Object?>,
      ],
    );
    var generations = 0;
    final navigator = MuseIntentNavigator(
      generator: MuseGenerator((request) async* {
        generations += 1;
        yield jsonEncode(
          _composition(
            generations == 1 ? 'Old action' : 'New action',
            generations == 1 ? 'old' : 'new',
            create: !(request.payload['surfaceExists']! as bool),
          ),
        );
      }),
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
    );
    addTearDown(() async {
      await navigator.dispose();
      revisionAdapter.dispose();
      revision.dispose();
    });
    expect(await navigator.push(intent), isA<MuseNavigated>());
    final app = createTuiTestApp(
      MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
      width: 50,
      height: 8,
    );
    addTearDown(app.dispose);
    await _drain();

    _click(app, 'Old action');
    await _drain();
    final oldSurfaceRevision = navigator.current!.surface!.revision;
    revision.value = 1;
    await _waitFor(
      () => navigator.current!.surface!.revision > oldSurfaceRevision,
    );
    app.pumpFrame();
    expect(app.captureFrame().containsText('New action'), isTrue);

    pending.completeError(StateError('late old failure'));
    await _drain();
    app.pumpFrame();
    final frame = app.captureFrame();
    expect(frame.containsText('New action'), isTrue);
    expect(frame.containsText('handler for "old" threw'), isFalse);
    expect(replacementCalls, 0);

    _click(app, 'New action');
    await _drain();
    expect(replacementCalls, 1);
  });

  test('app confirmation gates mutation inside the declared handler', () async {
    var accepted = false;
    var confirmations = 0;
    var mutations = 0;
    final fixture = await _ButtonFixture.open(() {
      confirmations += 1;
      if (!accepted) return;
      mutations += 1;
    });
    addTearDown(fixture.dispose);
    final app = fixture.app();
    addTearDown(app.dispose);
    await _drain();

    _click(app, 'Run');
    await _drain();
    expect(confirmations, 1);
    expect(mutations, 0);

    accepted = true;
    _click(app, 'Run');
    await _drain();
    expect(confirmations, 2);
    expect(mutations, 1);
  });
}

final class _ButtonFixture {
  _ButtonFixture._(this.navigator);

  final MuseIntentNavigator navigator;

  static Future<_ButtonFixture> open(FutureOr<void> Function() handler) async {
    final intent = _intent('button', 'run', handler);
    final navigator = MuseIntentNavigator(
      generator: MuseGenerator.scripted(<Object>[_composition('Run', 'run')]),
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
    );
    expect(await navigator.push(intent), isA<MuseNavigated>());
    return _ButtonFixture._(navigator);
  }

  TuiTestApp app() => createTuiTestApp(
    MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
    width: 50,
    height: 8,
  );

  Future<void> dispose() => navigator.dispose();
}

MuseIntent _intent(
  String id,
  String action,
  FutureOr<void> Function() handler,
) => MuseIntent(
  id: id,
  description: 'Button test.',
  instructions: 'Show one Button.',
  catalog: museNoirCatalog,
  actions: <MuseAction<Object?>>[
    MuseAction<void>(
          name: action,
          description: 'Run the test action.',
          handler: (_, _) => handler(),
        )
        as MuseAction<Object?>,
  ],
);

List<Object> _composition(String label, String action, {bool create = true}) =>
    <Object>[
      if (create)
        <String, Object?>{
          'version': 'v0.9.1',
          'createSurface': <String, Object?>{
            'surfaceId': 'button',
            'catalogId': museNoirCatalogId,
          },
        },
      <String, Object?>{
        'version': 'v0.9.1',
        'updateComponents': <String, Object?>{
          'surfaceId': 'button',
          'components': <Object?>[
            <String, Object?>{
              'id': 'root',
              'component': 'Button',
              'label': label,
              'action': <String, Object?>{
                'event': <String, Object?>{
                  'name': action,
                  'context': <String, Object?>{},
                },
              },
            },
          ],
        },
      },
    ];

void _click(TuiTestApp app, String label) {
  app.pumpFrame();
  final position = app.captureFrame().findText(label).single;
  app.mockMouse.click(position.x, position.y);
}

Future<void> _drain() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
