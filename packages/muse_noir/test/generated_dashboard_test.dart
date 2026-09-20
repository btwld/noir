import 'dart:convert';

import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../../noir/test/helpers/buffer_capture.dart';
import '../example/generated_dashboard.dart';

void main() {
  test(
    'offline launch is explicit and construction performs no generation',
    () {
      final dashboard = createGeneratedDashboardSession(
        arguments: const <String>['--offline'],
        environment: const <String, String>{},
      );
      addTearDown(dashboard.dispose);
      expect(dashboard.isLive, isFalse);
      expect(dashboard.navigator.current, isNull);
      expect(dashboard.submittedPrompt.value['revision'], 0);
    },
  );

  test('live launch requires a key and normalizes model names', () async {
    expect(
      () => createGeneratedDashboardSession(
        arguments: const <String>[],
        environment: const <String, String>{},
      ),
      throwsA(isA<GeneratedDashboardConfigurationException>()),
    );
    final dashboard = createGeneratedDashboardSession(
      arguments: const <String>[],
      environment: const <String, String>{
        'GOOGLE_AI_API_KEY': 'secret',
        'MUSE_GOOGLE_AI_MODEL': 'models/gemini-test',
      },
    );
    expect(dashboard.providerLabel, contains('gemini-test'));
    expect(
      dashboard.describeFailure(
        MuseFailure(code: 'x', message: 'secret must not leak'),
      ),
      isNot(contains('secret')),
    );
    await dashboard.dispose();
  });

  test('request discloses prompt fact but not private state values', () async {
    final requests = <MuseGenerationRequest>[];
    final dashboard = GeneratedDashboardSession.forGenerator(
      MuseGenerator((request) async* {
        requests.add(request);
        yield jsonEncode(
          generatedDashboardScriptedComposition(
            surfaceExists: request.payload['surfaceExists']! as bool,
          ),
        );
      }),
    );
    addTearDown(dashboard.dispose);
    dashboard.answerSummary.value = 'PRIVATE ANSWER';
    dashboard.message.value = 'PRIVATE MESSAGE';

    expect(requests, isEmpty);
    await dashboard.submit('release dashboard');
    expect(requests, hasLength(1));
    expect(requests.single.facts, contains('release dashboard'));
    expect(requests.single.facts, isNot(contains('PRIVATE ANSWER')));
    expect(requests.single.facts, isNot(contains('PRIVATE MESSAGE')));
    expect(requests.single.payload['surfaceExists'], isFalse);
  });

  test(
    'same-text retry notifies a watched fact and updates existing surface',
    () async {
      final requests = <MuseGenerationRequest>[];
      final dashboard = GeneratedDashboardSession.forGenerator(
        MuseGenerator((request) async* {
          requests.add(request);
          yield jsonEncode(
            generatedDashboardScriptedComposition(
              surfaceExists: request.payload['surfaceExists']! as bool,
            ),
          );
        }),
      );
      addTearDown(dashboard.dispose);
      await dashboard.submit('same prompt');
      await dashboard.submit('same prompt');
      await _waitFor(() => requests.length == 2);
      expect(requests[0].payload['surfaceExists'], isFalse);
      expect(requests[1].payload['surfaceExists'], isTrue);
      expect(dashboard.submittedPrompt.value['revision'], 2);
    },
  );

  test('offline surface renders all eleven types and fifteen nodes', () async {
    final dashboard = GeneratedDashboardSession.scripted();
    addTearDown(dashboard.dispose);
    await dashboard.submit('release dashboard');
    expect(dashboard.navigator.current!.failure, isNull);
    final app = runTuiApp(
      MuseNoirView(navigator: dashboard.navigator, renderer: museNoirRenderer),
      headless: true,
    );
    addTearDown(app.dispose);
    final tree = WidgetInspectorService.instance
        .describeTree(maxDepth: 120)
        .join('\n');
    expect(tree, contains('Badge'));
    expect(tree, contains('ProgressBar'));
    expect(tree, contains('Spinner'));
    expect(tree, contains('Button'));
    expect(tree, contains('_MuseNoirQuestion'));
    expect(
      RegExp('_MuseNoirComponentHost.*key:').allMatches(tree),
      hasLength(15),
    );
  });

  test('private state action rebinds without another generation', () async {
    var calls = 0;
    final dashboard = GeneratedDashboardSession.forGenerator(
      MuseGenerator((request) async* {
        calls += 1;
        yield jsonEncode(
          generatedDashboardScriptedComposition(
            surfaceExists: request.payload['surfaceExists']! as bool,
          ),
        );
      }),
    );
    addTearDown(dashboard.dispose);
    await dashboard.submit('release dashboard');
    final result = await dashboard.navigator.current!.perform('demo_increment');
    expect(result.isCompleted, isTrue);
    expect(dashboard.count.value, 1);
    expect(dashboard.progress.value, 0.25);
    expect(calls, 1);
  });

  test('dashboard fits and remains interactive at 80x24', () async {
    final dashboard = GeneratedDashboardSession.scripted();
    await dashboard.submit('release dashboard');
    final capture = BufferCapture();
    addTearDown(capture.dispose);
    addTearDown(dashboard.dispose);
    final frame = capture.capture(GeneratedDashboardApp(dashboard: dashboard));
    expect(frame.width, 80);
    expect(frame.height, 24);
    expect(frame.containsText('MUSE / NOIR'), isTrue);
    expect(frame.containsText('Regenerate'), isTrue);
    expect(frame.containsText('Release readiness'), isTrue);
  });

  test('invalid fifteen-node contract is rejected', () async {
    final dashboard = GeneratedDashboardSession.forGenerator(
      MuseGenerator.scripted(<Object>[
        <Object>[
          <String, Object?>{
            'version': 'v0.9.1',
            'createSurface': <String, Object?>{
              'surfaceId': 'generated-dashboard',
              'catalogId': museNoirCatalogId,
            },
          },
          <String, Object?>{
            'version': 'v0.9.1',
            'updateComponents': <String, Object?>{
              'surfaceId': 'generated-dashboard',
              'components': <Object?>[
                <String, Object?>{
                  'id': 'root',
                  'component': 'Text',
                  'text': 'too small',
                },
              ],
            },
          },
        ],
      ]),
    );
    addTearDown(dashboard.dispose);
    await dashboard.submit('invalid');
    expect(dashboard.navigator.current!.surface, isNull);
    expect(dashboard.navigator.current!.failure, isNotNull);
  });
}

Future<void> _waitFor(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('Condition did not become true.');
}
