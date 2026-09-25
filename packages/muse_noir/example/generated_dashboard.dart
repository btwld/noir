import 'dart:async';
import 'dart:io';

import 'package:ack/ack.dart';
import 'package:dartantic_ai/dartantic_ai.dart' as dartantic;
import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';

const String generatedDashboardDefaultGoogleModel = 'gemini-3.5-flash';
const String _initialPrompt =
    'Create a release dashboard and ask how the deployment should proceed.';
const String _incrementAction = 'demo_increment';
const String _answerAction = 'demo_answer';

final ThemeData _theme = ThemeData.dark.copyWith(
  surface: Color.fromHex('#0B0F14'),
  surfaceVariant: Color.fromHex('#151B23'),
  text: Color.fromHex('#E6EDF3'),
  textMuted: Color.fromHex('#7D8996'),
  border: Color.fromHex('#34404D'),
  accent: Color.fromHex('#79C0FF'),
  accentForeground: Color.fromHex('#07111A'),
  success: Color.fromHex('#56D364'),
  warning: Color.fromHex('#E3B341'),
  danger: Color.fromHex('#FF7B72'),
  info: Color.fromHex('#79C0FF'),
);

void main(List<String> arguments) {
  try {
    final dashboard = createGeneratedDashboardSession(
      arguments: arguments,
      environment: Platform.environment,
    );
    runTuiApp(GeneratedDashboardApp(dashboard: dashboard), enableMouse: true);
  } on FormatException catch (error) {
    _reportLaunchFailure(error.message);
  } on GeneratedDashboardConfigurationException catch (error) {
    _reportLaunchFailure(error.message);
  }
}

void _reportLaunchFailure(Object message) {
  stderr.writeln('muse_noir example: $message');
  exitCode = 64;
}

/// A non-secret launch configuration failure.
final class GeneratedDashboardConfigurationException implements Exception {
  /// Creates a failure with a safe [message].
  const GeneratedDashboardConfigurationException(this.message);

  /// Human-readable safe message.
  final String message;

  @override
  String toString() => message;
}

/// Creates a live-by-default or explicitly offline dashboard owner.
GeneratedDashboardSession createGeneratedDashboardSession({
  required List<String> arguments,
  required Map<String, String> environment,
}) {
  if (arguments.length == 1 && arguments.single == '--offline') {
    return GeneratedDashboardSession.scripted();
  }
  if (arguments.isNotEmpty) {
    throw const FormatException(
      'Usage: dart run example/generated_dashboard.dart [--offline]',
    );
  }
  final apiKey = (environment['GOOGLE_AI_API_KEY'] ?? '').trim();
  if (apiKey.isEmpty) {
    throw const GeneratedDashboardConfigurationException(
      'GOOGLE_AI_API_KEY is missing or empty. Export it for live generation '
      'or pass --offline for deterministic generation.',
    );
  }
  final configured = (environment['MUSE_GOOGLE_AI_MODEL'] ?? '').trim();
  return GeneratedDashboardSession.google(
    apiKey: apiKey,
    modelName: configured.isEmpty
        ? generatedDashboardDefaultGoogleModel
        : configured,
  );
}

/// App-owned Muse navigator, facts, private state, and generator.
final class GeneratedDashboardSession {
  GeneratedDashboardSession._({
    required MuseGenerator generator,
    required this.providerLabel,
    required this.isLive,
    List<String> redactions = const <String>[],
  }) : _redactions = List<String>.unmodifiable(redactions) {
    _countMuse = MuseValueListenable<int>(count);
    _messageMuse = MuseValueListenable<String>(message);
    _progressMuse = MuseValueListenable<double>(progress);
    _answerSummaryMuse = MuseValueListenable<String>(answerSummary);
    _promptMuse = MuseValueListenable<Map<String, Object?>>(submittedPrompt);
    intent = _dashboardIntent(this);
    navigator = MuseIntentNavigator(
      generator: generator,
      routes: <MuseIntentRoute>[MuseIntentRoute(intent)],
      options: const MuseGenerationOptions(timeout: Duration(minutes: 2)),
      limits: const MuseResourceLimits(maxComponents: 32, maxDepth: 8),
    );
  }

  /// Creates a deterministic credential-free owner.
  factory GeneratedDashboardSession.scripted() {
    final scripts = <Object>[_composition(create: true)];
    scripts.addAll(
      List<Object>.generate(31, (_) => _composition(create: false)),
    );
    return GeneratedDashboardSession._(
      generator: MuseGenerator.scripted(scripts),
      providerLabel: 'Scripted offline generator',
      isLive: false,
    );
  }

  /// Creates a test or custom-host owner around [generator].
  // ignore: unreachable_from_main
  factory GeneratedDashboardSession.forGenerator(
    MuseGenerator generator, {
    String providerLabel = 'Custom generator',
  }) => GeneratedDashboardSession._(
    generator: generator,
    providerLabel: providerLabel,
    isLive: false,
  );

  /// Creates a Google generator without starting a request.
  factory GeneratedDashboardSession.google({
    required String apiKey,
    String modelName = generatedDashboardDefaultGoogleModel,
  }) {
    final normalizedKey = apiKey.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'Must be non-empty.');
    }
    final normalizedModel = _normalizeGoogleModel(modelName);
    final agent = dartantic.Agent.forProvider(
      dartantic.GoogleProvider(apiKey: normalizedKey),
      chatModelName: normalizedModel,
      temperature: 0,
      chatModelOptions: const dartantic.GoogleChatModelOptions(
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
        thinkingLevel: dartantic.GoogleThinkingLevel.minimal,
      ),
    );
    return GeneratedDashboardSession._(
      generator: MuseGenerator((request) async* {
        final prompt = <String>[
          request.declarations,
          request.facts,
          request.protocol,
        ].join('\n\n');
        await for (final chunk in agent.sendStream(prompt)) {
          if (chunk.output.isNotEmpty) yield chunk.output;
        }
      }),
      providerLabel: 'Live Google AI · $normalizedModel',
      isLive: true,
      redactions: <String>[normalizedKey],
    );
  }

  /// Human-readable provider identity.
  final String providerLabel;

  /// Whether prompts leave the process.
  final bool isLive;

  /// Private application state. Muse exposes declarations, not these values.
  final ValueNotifier<int> count = ValueNotifier<int>(0);
  final ValueNotifier<String> message = ValueNotifier<String>(
    'Reactive state connected.',
  );
  final ValueNotifier<double> progress = ValueNotifier<double>(0);
  final ValueNotifier<String> answerSummary = ValueNotifier<String>(
    'No answer saved yet.',
  );

  /// Explicitly disclosed fact; revision makes same-text retry observable.
  final ValueNotifier<Map<String, Object?>> submittedPrompt =
      ValueNotifier<Map<String, Object?>>(const <String, Object?>{
        'text': '',
        'revision': 0,
      });

  late final MuseValueListenable<int> _countMuse;
  late final MuseValueListenable<String> _messageMuse;
  late final MuseValueListenable<double> _progressMuse;
  late final MuseValueListenable<String> _answerSummaryMuse;
  late final MuseValueListenable<Map<String, Object?>> _promptMuse;

  /// Screen declaration.
  late final MuseIntent intent;

  /// App-owned navigator borrowed by the view.
  late final MuseIntentNavigator navigator;

  final List<String> _redactions;
  Future<void>? _disposeFuture;

  MuseListenable<int> get countListenable => _countMuse;
  MuseListenable<String> get messageListenable => _messageMuse;
  MuseListenable<double> get progressListenable => _progressMuse;
  MuseListenable<String> get answerSummaryListenable => _answerSummaryMuse;
  MuseListenable<Map<String, Object?>> get promptListenable => _promptMuse;

  /// Starts the first activation or notifies its watched fact to regenerate.
  Future<void> submit(String prompt) async {
    final normalized = prompt.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'Must not be empty.');
    }
    final revision = submittedPrompt.value['revision']! as int;
    submittedPrompt.value = <String, Object?>{
      'text': normalized,
      'revision': revision + 1,
    };
    if (navigator.current == null) {
      await navigator.push(intent);
    }
  }

  /// Returns a safe failure description with configured secrets redacted.
  String describeFailure(MuseFailure? failure) {
    var description = failure?.message ?? 'No accepted surface.';
    for (final secret in _redactions) {
      description = description.replaceAll(secret, '[REDACTED]');
    }
    return description;
  }

  /// Disposes the navigator, adapters, and app-owned notifiers once.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await navigator.dispose();
    _countMuse.dispose();
    _messageMuse.dispose();
    _progressMuse.dispose();
    _answerSummaryMuse.dispose();
    _promptMuse.dispose();
    count.dispose();
    message.dispose();
    progress.dispose();
    answerSummary.dispose();
    submittedPrompt.dispose();
  }
}

String _normalizeGoogleModel(String modelName) {
  final configured = modelName.trim();
  final normalized = configured.startsWith('models/')
      ? configured.substring('models/'.length)
      : configured;
  if (normalized.isEmpty) {
    throw const GeneratedDashboardConfigurationException(
      'MUSE_GOOGLE_AI_MODEL must name a model after the optional models/ prefix.',
    );
  }
  return normalized;
}

/// Prompt-driven gallery for every Muse Noir catalog component.
final class GeneratedDashboardApp extends StatefulWidget {
  /// Creates the app for [dashboard].
  const GeneratedDashboardApp({required this.dashboard, super.key});

  /// Owner borrowed by this widget and disposed at unmount.
  final GeneratedDashboardSession dashboard;

  @override
  State<GeneratedDashboardApp> createState() => _GeneratedDashboardAppState();
}

final class _GeneratedDashboardAppState extends State<GeneratedDashboardApp> {
  late final TextEditingController _promptController;
  MuseActivation? _activation;
  VoidCallback? _stopActivation;
  String? _promptError;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(text: _initialPrompt);
    widget.dashboard.navigator.currentListenable.addListener(
      _navigationChanged,
    );
    _navigationChanged();
  }

  void _navigationChanged() {
    _stopActivation?.call();
    _activation = widget.dashboard.navigator.current;
    final activation = _activation;
    _stopActivation = activation == null
        ? null
        : () {
            activation.status.removeListener(_activationChanged);
          };
    activation?.status.addListener(_activationChanged);
    if (mounted) setState(() {});
  }

  void _activationChanged() {
    if (mounted) setState(() {});
  }

  void _clearPrompt() {
    _promptController.clear();
    if (_promptError != null) setState(() => _promptError = null);
  }

  void _generate() {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() => _promptError = 'Enter a prompt before generating.');
      return;
    }
    setState(() => _promptError = null);
    unawaited(
      widget.dashboard.submit(prompt).catchError((Object _) {
        if (mounted) {
          setState(() => _promptError = 'Generation ended unexpectedly.');
        }
      }),
    );
  }

  @override
  void dispose() {
    widget.dashboard.navigator.currentListenable.removeListener(
      _navigationChanged,
    );
    _stopActivation?.call();
    _promptController.dispose();
    unawaited(widget.dashboard.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: _theme.textMuted,
      fontWeight: FontWeight.dim,
    );
    return Theme(
      data: _theme,
      child: Container(
        color: _theme.surface,
        padding: const EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(child: Text('MUSE / NOIR', style: TextStyles.bold)),
                Text(_providerHeaderLabel(widget.dashboard), style: muted),
              ],
            ),
            Text('AI drafts. Muse assures. Noir renders.', style: muted),
            const SizedBox(height: 1),
            const Text('Describe the dashboard', style: TextStyles.bold),
            Container(
              color: _theme.surfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TextInput(
                key: const ValueKey<String>('demo_prompt'),
                controller: _promptController,
                backgroundColor: _theme.surfaceVariant,
                maxLength: 512,
                autofocus: true,
                onChanged: (_) {
                  if (_promptError != null) setState(() => _promptError = null);
                },
                onSubmit: _generate,
              ),
            ),
            const SizedBox(height: 1),
            Row(
              spacing: 1,
              children: <Widget>[
                Button(
                  key: const ValueKey<String>('demo_generate'),
                  label: _activation == null ? 'Generate' : 'Regenerate',
                  onPressed: _generate,
                ),
                Button(
                  key: const ValueKey<String>('demo_clear'),
                  label: 'Clear',
                  color: _theme.surfaceVariant,
                  textColor: _theme.textMuted,
                  onPressed: _clearPrompt,
                ),
                Expanded(
                  child: Text(
                    _statusLabel(_activation),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: _statusColor(_activation, _theme),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (_promptError case final error?)
              Text(error, style: TextStyles.error),
            const SizedBox(height: 1),
            const Text('Output', style: TextStyles.bold),
            Expanded(
              child: ScrollBox(
                canRequestFocus: false,
                child: _activation == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Nothing generated yet.',
                            style: TextStyles.bold,
                          ),
                          Text(
                            'Use Generate to create and assure a dashboard.',
                            style: muted,
                          ),
                        ],
                      )
                    : MuseNoirView(
                        key: const ValueKey<String>('generated_surface'),
                        navigator: widget.dashboard.navigator,
                        renderer: museNoirRenderer,
                        loadingBuilder: (_) => const Row(
                          spacing: 1,
                          children: <Widget>[
                            Spinner(),
                            Text('Generating dashboard…'),
                          ],
                        ),
                        errorBuilder: (context, failure) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text(
                              'No dashboard was accepted.',
                              style: TextStyles.error,
                            ),
                            Text(
                              widget.dashboard.describeFailure(failure),
                              style: muted,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Text(
              'Enter activate · Tab next · Wheel scroll · Ctrl+C quit',
              style: muted,
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(MuseActivation? activation) =>
    switch (activation?.status.value) {
      null => 'Ready for a prompt',
      MuseActivationStatus.generating =>
        'Generating · previous output stays visible',
      MuseActivationStatus.ready => 'Ready · assured by Muse',
      MuseActivationStatus.failed => 'Generation failed',
      MuseActivationStatus.disposed => 'Closed',
    };

Color _statusColor(MuseActivation? activation, ThemeData theme) =>
    switch (activation?.status.value) {
      null => theme.textMuted,
      MuseActivationStatus.generating => theme.info,
      MuseActivationStatus.ready => theme.success,
      MuseActivationStatus.failed => theme.danger,
      MuseActivationStatus.disposed => theme.textMuted,
    };

String _providerHeaderLabel(GeneratedDashboardSession dashboard) {
  if (!dashboard.isLive) return 'OFFLINE · scripted';
  const prefix = 'Live Google AI · ';
  return dashboard.providerLabel.startsWith(prefix)
      ? 'LIVE · ${dashboard.providerLabel.substring(prefix.length)}'
      : 'LIVE · Google AI';
}

MuseIntent _dashboardIntent(GeneratedDashboardSession owner) => MuseIntent(
  id: 'example.generated-dashboard',
  description: 'A complete terminal-native Muse and Noir component gallery.',
  instructions:
      'Create a compact release dashboard using exactly fifteen components '
      'and all eleven catalog types. Ask the four declared release questions.',
  catalog: museNoirCatalog,
  states: <MuseState<Object>>[
    MuseState<int>(
      name: 'count',
      description: 'Private completed demo action count.',
      schema: Ack.integer().min(0),
      watch: (_) => owner.countListenable,
    ),
    MuseState<String>(
      name: 'message',
      description: 'Private reactive status message.',
      schema: Ack.string().maxLength(2048),
      watch: (_) => owner.messageListenable,
    ),
    MuseState<double>(
      name: 'progress',
      description: 'Private normalized progress.',
      schema: Ack.double().min(0).max(1),
      watch: (_) => owner.progressListenable,
    ),
    MuseState<String>(
      name: 'answerSummary',
      description: 'Private summary of the latest submitted answer.',
      schema: Ack.string().maxLength(2048),
      watch: (_) => owner.answerSummaryListenable,
    ),
  ],
  facts: <MuseFact<Object?>>[
    MuseFact<Map<String, Object?>>(
      name: 'submittedPrompt',
      description: 'The user-submitted dashboard request and retry revision.',
      watch: (_) => owner.promptListenable,
    ),
  ],
  actions: <MuseAction<Object?>>[
    MuseAction<void>(
          name: _incrementAction,
          description: 'Advance the demo progress.',
          handler: (_, _) {
            final count = owner.count.value + 1;
            owner.count.value = count;
            owner.message.value = 'Demo action completed · $count';
            owner.progress.value = (count % 5) / 4;
          },
        )
        as MuseAction<Object?>,
    MuseAction<Map<String, Object?>>(
          name: _answerAction,
          description: 'Record one bounded Question answer.',
          parameters: Ack.object(<String, AckSchema<Object, Object>>{
            'questionId': Ack.string().notEmpty().maxLength(128),
            'answer': Ack.object(<String, AckSchema<Object, Object>>{
              'selectedValues': Ack.list(
                Ack.string().notEmpty().maxLength(128),
              ).maxLength(12),
              'freeText': Ack.string().maxLength(2048),
            }).strict(),
          }).strict(),
          handler: (_, parameters) {
            final answer = parameters['answer']! as Map<String, Object?>;
            final selected = answer['selectedValues']! as List<Object?>;
            final freeText = answer['freeText']! as String;
            final values = <String>[
              if (selected.isNotEmpty) selected.join(', '),
              if (freeText.isNotEmpty) freeText,
            ];
            owner.answerSummary.value =
                '${parameters['questionId']} · ${values.join(' / ')}';
          },
        )
        as MuseAction<Object?>,
  ],
  constraints: _dashboardConstraints,
);

final List<MuseConstraint> _dashboardConstraints = <MuseConstraint>[
  ...museNoirConstraints,
  MuseConstraint.root(allowedComponentTypes: <String>{'Column'}),
  MuseConstraint.count(
    componentTypes: <String>{'Column'},
    minimum: 1,
    maximum: 1,
  ),
  MuseConstraint.count(componentTypes: <String>{'Row'}, minimum: 1, maximum: 1),
  MuseConstraint.count(
    componentTypes: <String>{'Panel'},
    minimum: 1,
    maximum: 1,
  ),
  MuseConstraint.count(
    componentTypes: <String>{'Text'},
    minimum: 2,
    maximum: 2,
  ),
  for (final type in <String>[
    'Badge',
    'Callout',
    'Divider',
    'Progress',
    'Spinner',
    'Button',
  ])
    MuseConstraint.count(
      componentTypes: <String>{type},
      minimum: 1,
      maximum: 1,
    ),
  MuseConstraint.count(
    componentTypes: <String>{'Question'},
    minimum: 4,
    maximum: 4,
  ),
  MuseConstraint.componentAction(
    componentTypes: <String>{'Button'},
    action: _incrementAction,
  ),
  MuseConstraint.componentAction(
    componentTypes: <String>{'Question'},
    action: _answerAction,
    parameterEqualsComponentProperty: const <String, String>{
      'questionId': 'questionId',
    },
  ),
  MuseConstraint.stateBinding(
    componentTypes: <String>{'Progress'},
    property: 'value',
    statePath: '/progress',
  ),
  MuseConstraint.stateBinding(
    componentTypes: <String>{'Callout'},
    property: 'text',
    statePath: '/answerSummary',
  ),
];

/// Deterministic offline composition used by the example and its tests.
// ignore: unreachable_from_main
Object generatedDashboardScriptedComposition({required bool surfaceExists}) =>
    _composition(create: !surfaceExists);

List<Object> _composition({required bool create}) => <Object>[
  if (create)
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
        _component('root', 'Column', <String, Object?>{
          'align': 'start',
          'spacing': 'none',
          'children': <String>[
            'title',
            'summary',
            'statusPanel',
            'progress',
            'callout',
            'increment',
            'divider',
            'questionWindow',
            'questionChecks',
            'questionNote',
            'questionOwner',
          ],
        }),
        _component('title', 'Text', <String, Object?>{
          'text': 'Release readiness',
          'variant': 'title',
        }),
        _component('summary', 'Text', <String, Object?>{
          'text': 'Review status, then complete four setup questions.',
          'variant': 'caption',
        }),
        _component('statusPanel', 'Panel', <String, Object?>{
          'title': 'Assured surface',
          'children': <String>['statusRow'],
        }),
        _component('statusRow', 'Row', <String, Object?>{
          'spacing': 'sm',
          'children': <String>['badge', 'spinner'],
        }),
        _component('badge', 'Badge', <String, Object?>{
          'label': 'ASSURED',
          'variant': 'success',
        }),
        _component('spinner', 'Spinner', <String, Object?>{
          'label': _state('/message'),
        }),
        _component('progress', 'Progress', <String, Object?>{
          'label': 'Demo progress',
          'value': _state('/progress'),
          'width': 24,
        }),
        _component('callout', 'Callout', <String, Object?>{
          'title': 'Latest saved answer',
          'text': _state('/answerSummary'),
          'tone': 'info',
        }),
        _component('increment', 'Button', <String, Object?>{
          'label': 'Advance demo progress',
          'variant': 'primary',
          'action': _action(_incrementAction, const <String, Object?>{}),
        }),
        _component('divider', 'Divider'),
        _question(
          'questionWindow',
          'window',
          '1. Deployment window',
          'single',
          const <Object?>[
            <String, Object?>{'value': 'now', 'label': 'Now'},
            <String, Object?>{'value': 'tonight', 'label': 'Tonight'},
          ],
        ),
        _question(
          'questionChecks',
          'checks',
          '2. Required checks',
          'multiple',
          const <Object?>[
            <String, Object?>{'value': 'tests', 'label': 'Tests'},
            <String, Object?>{'value': 'review', 'label': 'Review'},
          ],
        ),
        _question(
          'questionNote',
          'note',
          '3. Release note',
          'single',
          const <Object?>[],
          allowFreeText: true,
        ),
        _question(
          'questionOwner',
          'owner',
          '4. Release owner',
          'single',
          const <Object?>[
            <String, Object?>{'value': 'platform', 'label': 'Platform team'},
            <String, Object?>{'value': 'release', 'label': 'Release manager'},
          ],
          allowFreeText: true,
        ),
      ],
    },
  },
];

Map<String, Object?> _component(
  String id,
  String component, [
  Map<String, Object?> values = const <String, Object?>{},
]) => <String, Object?>{'id': id, 'component': component, ...values};

Map<String, Object?> _question(
  String id,
  String questionId,
  String prompt,
  String mode,
  List<Object?> options, {
  bool allowFreeText = false,
}) => _component(id, 'Question', <String, Object?>{
  'questionId': questionId,
  'prompt': prompt,
  'mode': mode,
  'options': options,
  'allowFreeText': allowFreeText,
  'autofocus': false,
  'answer': <String, Object?>{'selectedValues': <String>[], 'freeText': ''},
  'action': _action(_answerAction, <String, Object?>{
    'questionId': questionId,
    'answer': <String, Object?>{'path': '/draft/$id/answer'},
  }),
});

Map<String, Object?> _action(String name, Map<String, Object?> context) =>
    <String, Object?>{
      'event': <String, Object?>{'name': name, 'context': context},
    };

Map<String, Object?> _state(String path) => <String, Object?>{
  r'$muse': <String, Object?>{
    'state': <String, Object?>{'path': path},
  },
};
