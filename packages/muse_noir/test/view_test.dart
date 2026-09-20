import 'dart:async';
import 'dart:convert';

import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../noir/test/helpers/tui_test_app.dart';

void main() {
  test('mounting shows loading but never starts generation', () async {
    var calls = 0;
    final fixture = _Fixture(
      MuseGenerator((request) async* {
        calls += 1;
        yield _encodedComposition();
      }),
    );
    addTearDown(fixture.dispose);
    final app = runTuiApp(fixture.view(), headless: true);
    addTearDown(app.dispose);

    await _drain();
    expect(calls, 0);
    expect(fixture.loadingBuilds, greaterThan(0));
    final result = await fixture.navigator.push(fixture.intent);
    expect(
      result,
      isA<MuseNavigated>(),
      reason: result is MuseNavigationFailed
          ? '${result.failure} ${result.failure.issues}'
          : '$result',
    );
    await _drain();
    expect(calls, 1);
    expect(fixture.builds, greaterThan(0));
  });

  test('first generation failure reaches typed error builder', () async {
    final fixture = _Fixture(MuseGenerator.scripted(<Object>[<Object>[]]));
    addTearDown(fixture.dispose);
    await fixture.navigator.push(fixture.intent);
    final app = runTuiApp(fixture.view(), headless: true);
    addTearDown(app.dispose);
    expect(fixture.lastFailure, isNotNull);
  });

  test(
    'unmount detaches but does not dispose the borrowed navigator',
    () async {
      final fixture = _Fixture(
        MuseGenerator.scripted(<Object>[_composition()]),
      );
      addTearDown(fixture.dispose);
      await fixture.navigator.push(fixture.intent);
      final app = runTuiApp(fixture.view(), headless: true);
      app.dispose();
      expect(
        fixture.navigator.current!.status.value,
        MuseActivationStatus.ready,
      );
      expect(fixture.navigator.current!.surface, isNotNull);
    },
  );

  test('navigator replacement detaches old presentation listeners', () async {
    final revision = ValueNotifier<int>(0);
    final revisionAdapter = MuseValueListenable<int>(revision);
    var builds = 0;
    final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
      MuseNoirComponentBinding(
        name: 'Leaf',
        description: 'Leaf.',
        builder: (_, node) {
          builds += 1;
          return const Text('ready');
        },
      ),
    ]);
    final catalog = renderer.catalog(id: 'view/v1');
    final oldIntent = MuseIntent(
      id: 'old',
      description: 'Old view.',
      instructions: 'Show a leaf.',
      catalog: catalog,
      facts: <MuseFact<Object?>>[
        MuseFact<int>(
          name: 'revision',
          description: 'Old regeneration revision.',
          watch: (_) => revisionAdapter,
        ),
      ],
    );
    final newIntent = MuseIntent(
      id: 'new',
      description: 'New view.',
      instructions: 'Show a leaf.',
      catalog: catalog,
    );
    final oldNavigator = MuseIntentNavigator(
      generator: MuseGenerator((request) async* {
        final composition = _composition();
        yield jsonEncode(<Object>[
          if (!(request.payload['surfaceExists']! as bool)) composition.first,
          composition.last,
        ]);
      }),
      routes: <MuseIntentRoute>[MuseIntentRoute(oldIntent)],
    );
    final newNavigator = MuseIntentNavigator(
      generator: MuseGenerator.scripted(<Object>[_composition()]),
      routes: <MuseIntentRoute>[MuseIntentRoute(newIntent)],
    );
    addTearDown(() async {
      await oldNavigator.dispose();
      await newNavigator.dispose();
      revisionAdapter.dispose();
      revision.dispose();
    });
    expect(await oldNavigator.push(oldIntent), isA<MuseNavigated>());
    expect(await newNavigator.push(newIntent), isA<MuseNavigated>());
    final key = GlobalKey<_NavigatorHostState>();
    final app = createTuiTestApp(
      _NavigatorHost(key: key, navigator: oldNavigator, renderer: renderer),
    );
    addTearDown(app.dispose);
    expect(builds, 1);

    key.currentState!.replace(newNavigator);
    app.pumpFrame();
    expect(builds, 2);
    final afterReplacement = builds;

    final oldSurfaceRevision = oldNavigator.current!.surface!.revision;
    revision.value = 1;
    await _waitFor(
      () => oldNavigator.current!.surface!.revision > oldSurfaceRevision,
    );
    await oldNavigator.pop();
    app.pumpFrame();
    expect(builds, afterReplacement);
  });

  test('not-found changes render and recover through navigation', () async {
    final fixture = _Fixture(MuseGenerator.scripted(<Object>[_composition()]));
    addTearDown(fixture.dispose);
    final app = runTuiApp(fixture.view(), headless: true);
    addTearDown(app.dispose);
    await fixture.navigator.go('/missing');
    await _drain();
    expect(fixture.lastNotFound, '/missing');
    final result = await fixture.navigator.push(fixture.intent);
    expect(
      result,
      isA<MuseNavigated>(),
      reason: result is MuseNavigationFailed
          ? '${result.failure} ${result.failure.issues}'
          : '$result',
    );
    await _waitFor(() => fixture.builds > 0);
    expect(fixture.navigator.current!.surface, isNotNull);
  });

  test('changed renderer rechecks compatibility before building', () async {
    final fixture = _Fixture(MuseGenerator.scripted(<Object>[_composition()]));
    addTearDown(fixture.dispose);
    await fixture.navigator.push(fixture.intent);
    final renderer = ValueNotifier<MuseNoirRenderer>(fixture.renderer);
    addTearDown(renderer.dispose);
    MuseFailure? rendererFailure;
    final app = runTuiApp(
      _RendererHost(
        renderer: renderer,
        navigator: fixture.navigator,
        onFailure: (failure) => rendererFailure = failure,
      ),
      headless: true,
    );
    addTearDown(app.dispose);
    expect(fixture.builds, greaterThan(0));
    renderer.value = MuseNoirRenderer(<MuseNoirComponentBinding>[
      MuseNoirComponentBinding(
        name: 'Other',
        description: 'Other.',
        builder: (_, node) => const Text('other'),
      ),
    ]);
    await _drain();
    expect(rendererFailure?.code, 'renderer_missing_components');
  });

  test(
    'changed renderer rechecks a retained surface during generation',
    () async {
      final secondStarted = Completer<void>();
      final releaseSecond = Completer<void>();
      addTearDown(() {
        if (!releaseSecond.isCompleted) releaseSecond.complete();
      });
      var calls = 0;
      final fixture = _Fixture(
        MuseGenerator((request) async* {
          calls += 1;
          if (calls == 2) {
            secondStarted.complete();
            await releaseSecond.future;
          }
          yield _encodedComposition();
        }),
      );
      final secondIntent = MuseIntent(
        id: 'view-second',
        description: 'Second view test.',
        instructions: 'Show another leaf.',
        catalog: fixture.intent.catalog,
      );
      await fixture.navigator.dispose();
      final navigator = MuseIntentNavigator(
        generator: fixture.generator,
        routes: <MuseIntentRoute>[
          MuseIntentRoute(fixture.intent),
          MuseIntentRoute(secondIntent),
        ],
      );
      addTearDown(navigator.dispose);
      await navigator.push(fixture.intent);
      final renderer = ValueNotifier<MuseNoirRenderer>(fixture.renderer);
      addTearDown(renderer.dispose);
      MuseFailure? rendererFailure;
      final app = runTuiApp(
        _RendererHost(
          renderer: renderer,
          navigator: navigator,
          onFailure: (failure) => rendererFailure = failure,
        ),
        headless: true,
      );
      addTearDown(app.dispose);

      final secondPush = navigator.push(secondIntent);
      await secondStarted.future;
      renderer.value = MuseNoirRenderer(<MuseNoirComponentBinding>[
        MuseNoirComponentBinding(
          name: 'Other',
          description: 'Other.',
          builder: (_, node) => const Text('other'),
        ),
      ]);
      await _drain();
      expect(rendererFailure?.code, 'renderer_missing_components');
      releaseSecond.complete();
      await secondPush;
    },
  );

  test(
    'failed same-activation regeneration retains accepted surface',
    () async {
      final revision = ValueNotifier<int>(0);
      final adapter = MuseValueListenable<int>(revision);
      var calls = 0;
      final fixture = _Fixture(
        MuseGenerator((request) async* {
          calls += 1;
          if (calls == 1) {
            yield _encodedComposition();
          } else {
            yield '{}';
          }
        }),
        revision: adapter,
      );
      addTearDown(() async {
        await fixture.dispose();
        adapter.dispose();
        revision.dispose();
      });
      await fixture.navigator.push(fixture.intent);
      final app = runTuiApp(fixture.view(), headless: true);
      addTearDown(app.dispose);
      expect(fixture.navigator.current!.surface, isNotNull);
      revision.value = 1;
      await _waitFor(() => calls == 2);
      await _waitFor(
        () =>
            fixture.navigator.current!.status.value ==
            MuseActivationStatus.ready,
      );
      expect(fixture.navigator.current!.failure, isNotNull);
      expect(fixture.navigator.current!.surface, isNotNull);
    },
  );
}

final class _Fixture {
  _Fixture(this.generator, {MuseListenable<int>? revision}) {
    renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
      MuseNoirComponentBinding(
        name: 'Leaf',
        description: 'Leaf.',
        builder: (_, node) {
          builds += 1;
          return const Text('ready');
        },
      ),
    ]);
    intent = MuseIntent(
      id: 'view',
      description: 'View test.',
      instructions: 'Show a leaf.',
      catalog: renderer.catalog(id: 'view/v1'),
      facts: <MuseFact<Object?>>[
        if (revision != null)
          MuseFact<int>(
            name: 'revision',
            description: 'Regeneration revision.',
            watch: (_) => revision,
          ),
      ],
    );
    navigator = MuseIntentNavigator(
      generator: generator,
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
    );
  }

  final MuseGenerator generator;
  late final MuseNoirRenderer renderer;
  late final MuseIntent intent;
  late final MuseIntentNavigator navigator;
  int builds = 0;
  int loadingBuilds = 0;
  MuseFailure? lastFailure;
  String? lastNotFound;

  Widget view() => MuseNoirView(
    navigator: navigator,
    renderer: renderer,
    loadingBuilder: (_) {
      loadingBuilds += 1;
      return const Text('loading');
    },
    errorBuilder: (_, failure) {
      lastFailure = failure;
      return Text('error:${failure.code}');
    },
    notFoundBuilder: (_, path) {
      lastNotFound = path;
      return Text('missing:$path');
    },
  );

  Future<void> dispose() => navigator.dispose();
}

final class _RendererHost extends StatefulWidget {
  const _RendererHost({
    required this.renderer,
    required this.navigator,
    required this.onFailure,
  });

  final ValueNotifier<MuseNoirRenderer> renderer;
  final MuseIntentNavigator navigator;
  final void Function(MuseFailure failure) onFailure;

  @override
  State<_RendererHost> createState() => _RendererHostState();
}

final class _RendererHostState extends State<_RendererHost> {
  @override
  void initState() {
    super.initState();
    widget.renderer.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.renderer.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MuseNoirView(
    navigator: widget.navigator,
    renderer: widget.renderer.value,
    errorBuilder: (_, failure) {
      widget.onFailure(failure);
      return Text('error:${failure.code}');
    },
  );
}

final class _NavigatorHost extends StatefulWidget {
  const _NavigatorHost({
    required this.navigator,
    required this.renderer,
    super.key,
  });

  final MuseIntentNavigator navigator;
  final MuseNoirRenderer renderer;

  @override
  State<_NavigatorHost> createState() => _NavigatorHostState();
}

final class _NavigatorHostState extends State<_NavigatorHost> {
  late MuseIntentNavigator _navigator = widget.navigator;

  void replace(MuseIntentNavigator navigator) {
    setState(() => _navigator = navigator);
  }

  @override
  Widget build(BuildContext context) =>
      MuseNoirView(navigator: _navigator, renderer: widget.renderer);
}

List<Object> _composition() => <Object>[
  <String, Object?>{
    'version': 'v0.9.1',
    'createSurface': <String, Object?>{
      'surfaceId': 's',
      'catalogId': 'view/v1',
    },
  },
  <String, Object?>{
    'version': 'v0.9.1',
    'updateComponents': <String, Object?>{
      'surfaceId': 's',
      'components': <Object?>[
        <String, Object?>{'id': 'root', 'component': 'Leaf'},
      ],
    },
  },
];

String _encodedComposition() => jsonEncode(_composition());

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
