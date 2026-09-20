import 'dart:convert';

import 'package:ack/ack.dart';
import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../noir/test/helpers/buffer_capture.dart';
import '../../noir/test/helpers/tui_test_app.dart';

void main() {
  test(
    'binding builds its declaration once and renderer rejects duplicates',
    () {
      final binding = _leafBinding();
      expect(binding.component.name, 'Leaf');
      expect(
        () => MuseNoirRenderer(<MuseNoirComponentBinding>[binding, binding]),
        throwsA(
          isA<MuseDeclarationError>().having(
            (error) => error.code,
            'code',
            'duplicate_name',
          ),
        ),
      );
    },
  );

  test(
    'render node copies public maps/lists and inert edits fail in release',
    () {
      final properties = <String, Object?>{'value': 'a'};
      final children = <Widget>[const Text('child')];
      final node = MuseNoirRenderNode(
        type: 'Leaf',
        properties: properties,
        children: children,
      );
      properties['value'] = 'changed';
      children.clear();
      expect(node.properties, <String, Object?>{'value': 'a'});
      expect(node.children, hasLength(1));
      expect(() => node.properties['x'] = 1, throwsUnsupportedError);
      expect(() => node.edit('value', 'b'), throwsStateError);
      expect(() => node.edit('', 'b'), throwsArgumentError);
    },
  );

  for (final mismatch in <String>['missing', 'identity']) {
    test('$mismatch component fails before any builder runs', () async {
      var builds = 0;
      final declared = MuseNoirRenderer(<MuseNoirComponentBinding>[
        _leafBinding(
          builder: (_, node) {
            builds += 1;
            return const Text('leaf');
          },
        ),
      ]);
      final intent = _intent(declared.catalog(id: 'renderer/v1'));
      final navigator = await _open(intent, <Object>[
        _create('renderer/v1'),
        _update(<Object?>[_component('root', 'Leaf')]),
      ]);
      addTearDown(navigator.dispose);
      final supplied = MuseNoirRenderer(<MuseNoirComponentBinding>[
        if (mismatch == 'identity')
          MuseNoirComponentBinding(
            name: 'Leaf',
            description: 'Wrong shape.',
            children: MuseChildren.single,
            builder: (_, node) {
              builds += 1;
              return const Text('wrong');
            },
          )
        else
          MuseNoirComponentBinding(
            name: 'Other',
            description: 'Other.',
            builder: (_, node) {
              builds += 1;
              return const Text('other');
            },
          ),
      ]);
      MuseFailure? failure;
      final app = runTuiApp(
        MuseNoirView(
          navigator: navigator,
          renderer: supplied,
          errorBuilder: (_, value) {
            failure = value;
            return Text('error:${value.code}');
          },
        ),
        headless: true,
      );
      addTearDown(app.dispose);
      expect(failure?.code, 'renderer_missing_components');
      expect(builds, 0);
    });
  }

  test(
    'unused catalog entries and extra renderer entries are accepted',
    () async {
      var leafBuilds = 0;
      final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
        _leafBinding(
          builder: (_, node) {
            leafBuilds += 1;
            return const Text('leaf');
          },
        ),
        MuseNoirComponentBinding(
          name: 'Unused',
          description: 'Unused.',
          builder: (_, node) => const Text('unused'),
        ),
        MuseNoirComponentBinding(
          name: 'Extra',
          description: 'Renderer-only extra.',
          builder: (_, node) => const Text('extra'),
        ),
      ]);
      final catalog = renderer.catalog(id: 'renderer/v1').without(<String>{
        'Extra',
      });
      final navigator = await _open(_intent(catalog), <Object>[
        _create(catalog.id),
        _update(<Object?>[_component('root', 'Leaf')]),
      ]);
      addTearDown(navigator.dispose);
      final app = runTuiApp(
        MuseNoirView(navigator: navigator, renderer: renderer),
        headless: true,
      );
      addTearDown(app.dispose);
      expect(leafBuilds, 1);
    },
  );

  test('callouts use a clipped-safe marker and neutral body copy', () async {
    final intent = _intent(museNoirCatalog);
    final navigator = await _open(intent, <Object>[
      _create(museNoirCatalogId),
      _update(<Object?>[
        _component('root', 'Callout', <String, Object?>{
          'title': 'Context',
          'text': 'Plain body copy',
          'tone': 'info',
        }),
      ]),
    ]);
    addTearDown(navigator.dispose);
    final theme = ThemeData.dark.copyWith(text: Color.white, info: Color.blue);
    final capture = BufferCapture(width: 32, height: 4);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      Theme(
        data: theme,
        child: MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
      ),
    );
    final body = frame.findText('Plain body copy').single;

    expect(frame.getForegroundColor(body.x, body.y), theme.text);
    expect(frame.containsText('› Context'), isTrue);
    expect(frame.toText(), isNot(contains('│')));
    expect(frame.toText(), isNot(contains('┌')));
    expect(frame.toText(), isNot(contains('└')));
  });

  test('panels group content without closed borders', () async {
    final intent = _intent(museNoirCatalog);
    final navigator = await _open(intent, <Object>[
      _create(museNoirCatalogId),
      _update(<Object?>[
        _component('root', 'Panel', <String, Object?>{
          'title': 'Status',
          'children': <String>['body'],
        }),
        _component('body', 'Text', <String, Object?>{'text': 'Ready'}),
      ]),
    ]);
    addTearDown(navigator.dispose);
    final capture = BufferCapture(width: 24, height: 4);
    addTearDown(capture.dispose);

    final frame = capture.capture(
      MuseNoirView(navigator: navigator, renderer: museNoirRenderer),
    );
    final body = frame.findText('Ready').single;

    expect(body.x, 1);
    expect(frame.toText(), isNot(contains('┌')));
    expect(frame.toText(), isNot(contains('┐')));
    expect(frame.toText(), isNot(contains('└')));
    expect(frame.toText(), isNot(contains('┘')));
    expect(frame.toText(), isNot(contains('│')));
  });

  test('hidden component is omitted and cannot expose an action', () async {
    MuseNoirRenderNode? captured;
    final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
      _leafBinding(
        builder: (_, node) {
          captured = node;
          return const Text('hidden');
        },
      ),
    ]);
    final catalog = renderer.catalog(id: 'renderer/v1');
    final intent = _intent(catalog);
    final navigator = await _open(intent, <Object>[
      _create(catalog.id),
      _update(<Object?>[
        _component('root', 'Leaf', <String, Object?>{'visible': false}),
      ]),
    ]);
    addTearDown(navigator.dispose);
    final app = runTuiApp(
      MuseNoirView(navigator: navigator, renderer: renderer),
      headless: true,
    );
    addTearDown(app.dispose);
    expect(captured, isNull);
  });

  test(
    'draft edit is read by validated dispatch before the next frame',
    () async {
      late MuseNoirRenderNode captured;
      final received = <String>[];
      final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
        MuseNoirComponentBinding(
          name: 'Input',
          description: 'Editable input.',
          properties: <String, MuseProperty>{
            'value': MuseProperty.bindable(Ack.string(), 'Editable value.'),
          },
          builder: (_, node) {
            captured = node;
            return Text(node.properties['value']! as String);
          },
        ),
      ]);
      final catalog = renderer.catalog(id: 'edit/v1');
      final intent = MuseIntent(
        id: 'edit',
        description: 'Edit and submit.',
        instructions: 'Show one editable input.',
        catalog: catalog,
        actions: <MuseAction<Object?>>[
          MuseAction<Map<String, Object?>>(
                name: 'save',
                description: 'Save the value.',
                parameters: Ack.object(<String, AckSchema<Object, Object>>{
                  'value': Ack.string(),
                }),
                handler: (_, parameters) =>
                    received.add(parameters['value']! as String),
              )
              as MuseAction<Object?>,
        ],
      );
      final navigator = await _open(intent, <Object>[
        _create(catalog.id),
        _update(<Object?>[
          _component('root', 'Input', <String, Object?>{
            'value': 'initial',
            'action': _action('save', <String, Object?>{
              'value': <String, Object?>{'path': '/draft/root/value'},
            }),
          }),
        ]),
      ]);
      addTearDown(navigator.dispose);
      final app = runTuiApp(
        MuseNoirView(navigator: navigator, renderer: renderer),
        headless: true,
      );
      addTearDown(app.dispose);
      final activate = captured.activate!;
      captured.edit('value', 'edited');
      final result = await activate();
      expect(result.isCompleted, isTrue);
      expect(received, <String>['edited']);

      app.dispose();
      final stale = await activate();
      expect(stale.isCompleted, isFalse);
      expect(received, <String>['edited']);
    },
  );

  test(
    'stale callbacks fail closed after replacement, hiding, and disposal',
    () async {
      final visible = ValueNotifier<bool>(true);
      final revision = ValueNotifier<int>(0);
      final visibleAdapter = MuseValueListenable<bool>(visible);
      final revisionAdapter = MuseValueListenable<int>(revision);
      final nodes = <MuseNoirRenderNode>[];
      var handled = 0;
      final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
        MuseNoirComponentBinding(
          name: 'Leaf',
          description: 'Action leaf.',
          checkable: true,
          builder: (_, node) {
            nodes.add(node);
            return const Text('leaf');
          },
        ),
      ]);
      final catalog = renderer.catalog(id: 'stale/v1');
      final intent = MuseIntent(
        id: 'stale',
        description: 'Stale action test.',
        instructions: 'Show one action leaf.',
        catalog: catalog,
        states: <MuseState<Object>>[
          MuseState<bool>(
            name: 'visible',
            description: 'Whether the leaf is visible.',
            schema: Ack.boolean(),
            watch: (_) => visibleAdapter,
          ),
        ],
        facts: <MuseFact<Object?>>[
          MuseFact<int>(
            name: 'revision',
            description: 'Surface replacement revision.',
            watch: (_) => revisionAdapter,
          ),
        ],
        actions: <MuseAction<Object?>>[
          MuseAction<void>(
                name: 'run',
                description: 'Record an invocation.',
                handler: (_, _) => handled += 1,
              )
              as MuseAction<Object?>,
        ],
      );
      final navigator = MuseIntentNavigator(
        generator: MuseGenerator((request) async* {
          yield jsonEncode(<Object>[
            if (!(request.payload['surfaceExists']! as bool))
              _create(catalog.id),
            _update(<Object?>[
              _component('root', 'Leaf', <String, Object?>{
                'visible': _stateBinding('/visible'),
                'action': _action('run', const <String, Object?>{}),
              }),
            ]),
          ]);
        }),
        routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
      );
      addTearDown(() async {
        await navigator.dispose();
        visibleAdapter.dispose();
        revisionAdapter.dispose();
        visible.dispose();
        revision.dispose();
      });
      expect(await navigator.push(intent), isA<MuseNavigated>());
      final app = createTuiTestApp(
        MuseNoirView(navigator: navigator, renderer: renderer),
      );
      final replaced = nodes.single.activate!;

      final beforeReplacementRevision = navigator.current!.surface!.revision;
      revision.value = 1;
      await _waitFor(
        () => navigator.current!.surface!.revision > beforeReplacementRevision,
      );
      app.pumpFrame();
      expect(nodes, hasLength(greaterThanOrEqualTo(2)));
      final hidden = nodes.last.activate!;
      expect(await replaced(), isA<MuseActionResult>());
      expect(handled, 0);

      final beforeHideRevision = navigator.current!.surface!.revision;
      visible.value = false;
      await _waitFor(
        () => navigator.current!.surface!.revision > beforeHideRevision,
      );
      app.pumpFrame();
      expect(await hidden(), isA<MuseActionResult>());
      expect(handled, 0);

      visible.value = true;
      await _waitFor(
        () => navigator.current!.surface!.revision > beforeHideRevision + 1,
      );
      app.pumpFrame();
      expect(nodes, hasLength(greaterThanOrEqualTo(3)));
      final disposed = nodes.last.activate!;
      app.dispose();
      expect(await disposed(), isA<MuseActionResult>());
      expect(handled, 0);
    },
  );

  test(
    'forged literal action parameters are rejected during assurance',
    () async {
      final renderer = MuseNoirRenderer(<MuseNoirComponentBinding>[
        _leafBinding(),
      ]);
      final catalog = renderer.catalog(id: 'renderer/v1');
      final intent = MuseIntent(
        id: 'forged',
        description: 'Reject forged values.',
        instructions: 'Show a leaf.',
        catalog: catalog,
        actions: <MuseAction<Object?>>[
          MuseAction<Map<String, Object?>>(
                name: 'save',
                description: 'Save an integer.',
                parameters: Ack.object(<String, AckSchema<Object, Object>>{
                  'value': Ack.integer(),
                }),
                handler: (_, _) {},
              )
              as MuseAction<Object?>,
        ],
      );
      final navigator = MuseIntentNavigator(
        generator: MuseGenerator.scripted(<Object>[
          <Object>[
            _create(catalog.id),
            _update(<Object?>[
              _component('root', 'Leaf', <String, Object?>{
                'action': _action('save', <String, Object?>{
                  'value': 'not-int',
                }),
              }),
            ]),
          ],
        ]),
        routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
      );
      addTearDown(navigator.dispose);
      final result = await navigator.push(intent);
      expect(result, isA<MuseNavigationFailed>());
    },
  );
}

MuseNoirComponentBinding _leafBinding({MuseNoirComponentBuilder? builder}) =>
    MuseNoirComponentBinding(
      name: 'Leaf',
      description: 'A terminal leaf.',
      builder: builder ?? (_, node) => const Text('leaf'),
    );

MuseIntent _intent(MuseCatalog catalog) => MuseIntent(
  id: 'renderer',
  description: 'Renderer test.',
  instructions: 'Show the supplied component.',
  catalog: catalog,
);

Future<MuseIntentNavigator> _open(
  MuseIntent intent,
  List<Object> messages,
) async {
  final navigator = MuseIntentNavigator(
    generator: MuseGenerator.scripted(<Object>[messages]),
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
  return navigator;
}

Map<String, Object?> _create(String catalogId) => <String, Object?>{
  'version': 'v0.9.1',
  'createSurface': <String, Object?>{'surfaceId': 's', 'catalogId': catalogId},
};

Map<String, Object?> _update(List<Object?> components) => <String, Object?>{
  'version': 'v0.9.1',
  'updateComponents': <String, Object?>{
    'surfaceId': 's',
    'components': components,
  },
};

Map<String, Object?> _component(
  String id,
  String component, [
  Map<String, Object?> values = const <String, Object?>{},
]) => <String, Object?>{'id': id, 'component': component, ...values};

Map<String, Object?> _action(String name, Map<String, Object?> context) =>
    <String, Object?>{
      'event': <String, Object?>{'name': name, 'context': context},
    };

Map<String, Object?> _stateBinding(String path) => <String, Object?>{
  r'$muse': <String, Object?>{
    'state': <String, Object?>{'path': path},
  },
};

Future<void> _waitFor(bool Function() condition) async {
  for (var index = 0; index < 100; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
