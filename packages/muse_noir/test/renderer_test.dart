import 'package:ack/ack.dart';
import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

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
