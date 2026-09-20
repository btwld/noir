import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:test/test.dart';

const _companionRoot = '../noir_signals';

void main() {
  final rootPubspec = File('pubspec.yaml').readAsStringSync();
  final companionPubspec = File(
    '$_companionRoot/pubspec.yaml',
  ).readAsStringSync();
  final companionBarrel = File(
    '$_companionRoot/lib/noir_signals.dart',
  ).readAsStringSync();

  test('hooks live in the companion package, not in Noir', () {
    expect(File('lib/hooks.dart').existsSync(), isFalse);
    expect(Directory('lib/src/hooks').existsSync(), isFalse);
    expect(Directory('test/hooks').existsSync(), isFalse);
    expect(Directory('packages/noir_hooks').existsSync(), isFalse);
    expect(Directory('$_companionRoot/lib/src/hooks').existsSync(), isTrue);

    final mainBarrel = File('lib/noir.dart').readAsStringSync();
    expect(mainBarrel, isNot(contains("export 'hooks.dart'")));
    expect(mainBarrel, isNot(contains('src/hooks/')));
    expect(
      File('lib/noir_low_level.dart').readAsStringSync(),
      isNot(contains('src/hooks/')),
    );
  });

  test('the repository is one Pub workspace with an explicit member', () {
    final workspace = File('../../pubspec.yaml').readAsStringSync();
    expect(workspace, contains('publish_to: none'));
    expect(
      workspace,
      contains(
        'workspace:\n'
        '  - packages/noir\n'
        '  - packages/noir_driver\n'
        '  - packages/muse_noir\n'
        '  - packages/noir_signals',
      ),
    );
    expect(rootPubspec, contains('resolution: workspace'));
    expect(companionPubspec, contains('resolution: workspace'));
    expect(companionPubspec, contains('name: noir_signals'));
    expect(companionPubspec, contains('noir: ^0.0.2'));
    expect(companionPubspec, contains('signals_core: ^7.0.0'));
  });

  test('Noir carries no dependency on the companion or on Signals', () {
    expect(rootPubspec, isNot(contains('noir_signals:')));
    expect(rootPubspec, isNot(contains('signals_core')));
    expect(rootPubspec, isNot(contains('preact_signals')));

    for (final file in _dartFilesUnder('lib')) {
      final source = File(file).readAsStringSync();
      expect(source, isNot(contains('package:signals_core/')), reason: file);
      expect(source, isNot(contains('package:noir_signals/')), reason: file);
    }
  });

  test('companion production code uses only supported public API', () {
    final sourceFiles = _dartFilesUnder('$_companionRoot/lib');
    expect(sourceFiles, isNotEmpty);

    for (final file in sourceFiles) {
      final source = File(file).readAsStringSync();
      expect(source, isNot(contains('package:noir/src/')), reason: file);
      expect(
        source,
        isNot(contains('package:noir/noir_low_level.dart')),
        reason: file,
      );
      expect(
        source,
        isNot(contains('package:noir/noir_ffi.dart')),
        reason: file,
      );
      expect(
        source,
        isNot(contains('package:signals_core/src/')),
        reason: file,
      );
      expect(source, isNot(contains('package:preact_signals/')), reason: file);
      expect(source, isNot(contains('dart:ffi')), reason: file);

      final noirImports = RegExp(
        r'''import\s+['"](package:noir/[^'"]+)['"]''',
      ).allMatches(source).map((match) => match.group(1)!).toList();
      expect(noirImports, everyElement('package:noir/noir.dart'), reason: file);
    }
  });

  test('the companion barrel exports the hook families', () {
    // Exact membership, not a substring search: `contains('useSignal')` is
    // satisfied by `useSignalValue`, and `contains('SignalWidget')` by a
    // mention in the library doc comment.
    final exported = _shownSymbols(companionBarrel);
    for (final symbol in <String>[
      'SignalWidget',
      'SignalBuilder',
      'HookState',
      'useState',
      'useEffect',
      'useListenableSelector',
      'useFuture',
      'useStream',
      'useAnimationController',
      'useTextEditingController',
      'useFocusNode',
      'useScrollController',
      'useViewportController',
    ]) {
      expect(exported, contains(symbol), reason: symbol);
    }
  });

  test('the companion barrel exports the signal families', () {
    final exported = _shownSymbols(companionBarrel);
    for (final symbol in <String>[
      'useSignal',
      'useComputed',
      'useSignalValue',
      'useSignalEffect',
      'SignalValueBuilder',
      'SignalValueWidgetBuilder',
    ]) {
      expect(exported, contains(symbol), reason: symbol);
    }
  });

  test('the companion barrel exports nothing but the approved surface', () {
    // `_shownSymbols` can only read a `show` clause, so a bare `export`
    // would slip past the frozen set entirely. Require the clause first,
    // then freeze what it names.
    final exports = RegExp(
      r'^export\s+[^;]*;',
      multiLine: true,
      dotAll: true,
    ).allMatches(companionBarrel).map((match) => match.group(0)!).toList();
    expect(exports, isNotEmpty);
    for (final directive in exports) {
      expect(
        directive,
        matches(RegExp(r'\bshow\b')),
        reason: 'every export must name its symbols: $directive',
      );
    }

    // The whole export set is frozen, so a new public name has to be an
    // intentional edit here rather than an accidental re-export.
    expect(_shownSymbols(companionBarrel), _companionSurface);
  });

  test('the Signals contract has one guide and one website page', () {
    final guide = File('$_companionRoot/doc/signals.md').readAsStringSync();
    final page = File(
      '../../website/src/content/docs/signals.mdx',
    ).readAsStringSync();
    final navigation = File(
      '../../website/src/content/docs/_meta.ts',
    ).readAsStringSync();

    // The navigation label is editorial; the route and its owner are not.
    expect(navigation, contains('  signals:'));
    for (final contract in <String>[
      'useSignal',
      'useComputed',
      'useSignalValue',
      'SignalValueBuilder',
      'autoDispose',
    ]) {
      expect(guide, contains(contract), reason: 'guide: $contract');
      expect(page, contains(contract), reason: 'page: $contract');
    }
    // Automatic whole-build tracking is a separate feature; neither document
    // may promise it.
    for (final source in <String>[guide, page]) {
      expect(source, contains('no automatic whole-build tracking'));
      expect(source, contains('SignalWidget'));
      expect(source, isNot(contains('HookWidget')));
    }
    expect(
      File('$_companionRoot/README.md').readAsStringSync(),
      contains('doc/signals.md'),
    );
  });

  test('the companion barrel keeps the hook Effect typedef', () {
    // `signals_core` also declares `Effect`. The hook typedef wins, so the
    // upstream class must stay out of the export list.
    expect(companionBarrel, contains("export 'src/hooks/primitives.dart'"));
    final upstreamExport = RegExp(
      r"export 'package:signals_core/signals_core\.dart'\s+show([^;]+);",
    ).firstMatch(companionBarrel);
    expect(upstreamExport, isNotNull);
    final shown = upstreamExport!
        .group(1)!
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toSet();
    expect(shown, isNot(contains('Effect')));
    for (final symbol in <String>[
      'Signal',
      'ReadonlySignal',
      'Computed',
      'SignalOptions',
      'ComputedOptions',
      'EffectOptions',
      'signal',
      'computed',
      'effect',
      'batch',
      'untracked',
    ]) {
      expect(shown, contains(symbol), reason: symbol);
    }
  });

  test('companion tests reuse the repository harnesses, not a copy', () {
    final bridge = File(
      '$_companionRoot/test/helpers/noir_test_helpers.dart',
    ).readAsStringSync();
    for (final helper in <String>[
      'buffer_capture.dart',
      'test_element_host.dart',
      'tui_test_app.dart',
    ]) {
      expect(bridge, contains("export '../../../noir/test/helpers/$helper';"));
      expect(File('test/helpers/$helper').existsSync(), isTrue);
    }
    final helperFiles = Directory(
      '$_companionRoot/test/helpers',
    ).listSync().whereType<File>().toList(growable: false);
    expect(
      helperFiles.map((file) => file.uri.pathSegments.last),
      unorderedEquals(<String>['noir_test_helpers.dart', 'package_paths.dart']),
    );
    // No helper may redeclare a harness the bridge already re-exports.
    for (final file in helperFiles) {
      final source = file.readAsStringSync();
      for (final owned in <String>[
        'class TestElementHost',
        'class BufferCapture',
        'TuiTestApp createTuiTestApp',
      ]) {
        expect(source, isNot(contains(owned)), reason: '${file.path}: $owned');
      }
    }

    const lifecycleTestNames = <String>{
      'controllers_animation_test.dart',
      'framework_integration_test.dart',
      'framework_primitives_test.dart',
      'listenable_async_test.dart',
      'replacement_lifecycle_test.dart',
    };
    final tests = Directory('$_companionRoot/test/hooks')
        .listSync()
        .whereType<File>()
        .where(
          (file) => lifecycleTestNames.contains(file.uri.pathSegments.last),
        )
        .toList(growable: false);

    expect(tests, hasLength(lifecycleTestNames.length));
    for (final file in tests) {
      final source = file.readAsStringSync();
      expect(
        source,
        contains("import '../helpers/noir_test_helpers.dart';"),
        reason: file.path,
      );
      expect(source, contains('TestElementHost'), reason: file.path);
    }
  });

  test('distribution keeps each package archive to its own tree', () {
    final rootPubignore = File('.pubignore').readAsStringSync();
    final companionPubignore = File(
      '$_companionRoot/.pubignore',
    ).readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(rootPubignore, isNot(contains('/packages/')));
    expect(companionPubignore, contains('test/'));
    // The packages are siblings, so each archives its own directory in place.
    // One script stages the standalone copy that the consumer check resolves.
    final stagingScript = File(
      'tool/stage_companion_package.dart',
    ).readAsStringSync();
    expect(stagingScript, contains("const _companionPath = '$_companionRoot'"));
    expect(stagingScript, contains("'resolution: workspace'"));
    expect(stagingScript, contains('pubspec_overrides.yaml'));
    expect(
      File('../../AGENTS.md').readAsStringSync(),
      contains('dart run tool/stage_companion_package.dart --verify'),
    );
    expect(
      File('../../.gitignore').readAsStringSync(),
      contains('pubspec_overrides.yaml'),
    );
    expect(File('$_companionRoot/LICENSE').existsSync(), isTrue);
    expect(File('$_companionRoot/README.md').existsSync(), isTrue);
    expect(File('$_companionRoot/CHANGELOG.md').existsSync(), isTrue);
    expect(
      File('$_companionRoot/analysis_options.yaml').readAsStringSync(),
      isNot(contains('../')),
      reason: 'companion analysis settings must be self-contained',
    );

    // One consumer check per package, each resolving from outside its tree.
    final companionConsumer = File(
      '$_companionRoot/test/package_consumer_test.dart',
    ).readAsStringSync();
    expect(companionConsumer, contains('stage_companion_package.dart'));
    expect(companionConsumer, contains('noir_only'));
    expect(
      File('test/source_package_consumer_test.dart').readAsStringSync(),
      contains("'noir_signals',"),
      reason: 'the Noir consumer must assert the companion stays absent',
    );

    expect(changelog, contains('Removed `package:noir/hooks.dart`'));
    expect(readme, contains('package:noir_signals'));
    expect(readme, isNot(contains('package:noir/hooks.dart')));
  });

  test('companion install guidance matches its own manifest', () {
    final version = RegExp(
      r'^version: (.+)$',
      multiLine: true,
    ).firstMatch(companionPubspec)!.group(1)!.trim();
    final noirConstraint = RegExp(
      r'^  noir: (.+)$',
      multiLine: true,
    ).firstMatch(companionPubspec)!.group(1)!.trim();
    final companionConstraint = '^${version.split('+').first}';

    // One website destination owns dependency instructions. Ordinary guides
    // must not repeat a hosted block that cannot resolve yet.
    for (final path in <String>[
      '$_companionRoot/README.md',
      '$_companionRoot/doc/hooks.md',
      '$_companionRoot/doc/signals.md',
      '../../website/src/content/docs/installation.mdx',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('noir: $noirConstraint'), reason: path);
      expect(
        source,
        contains('noir_signals: $companionConstraint'),
        reason: path,
      );
    }
    for (final path in <String>[
      '../../website/src/content/docs/hooks.mdx',
      '../../website/src/content/docs/signals.mdx',
      '../../website/src/content/api.mdx',
    ]) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('noir_signals: $companionConstraint')),
        reason: '$path must link the installation page instead',
      );
    }

    final changelogVersions = RegExp(r'^##\s+([^\s]+)\s*$', multiLine: true)
        .allMatches(File('$_companionRoot/CHANGELOG.md').readAsStringSync())
        .map((match) => match.group(1))
        .toList();
    expect(changelogVersions.first, version);
  });

  test('the Noir skill routes hook guidance to the companion guide', () {
    final skillDirectory = Directory('../../skills/noir').absolute.uri;
    final canonicalHooksGuide = File.fromUri(
      skillDirectory.resolve('../../packages/noir_signals/doc/hooks.md'),
    );
    final hooksReference = File.fromUri(
      skillDirectory.resolve('references/hooks.md'),
    );
    final skill = File.fromUri(
      skillDirectory.resolve('SKILL.md'),
    ).readAsStringSync();

    expect(canonicalHooksGuide.existsSync(), isTrue);
    expect(hooksReference.existsSync(), isTrue);
    expect(File('doc/hooks.md').existsSync(), isFalse);
    expect(skill, contains('`references/hooks.md`'));
    expect(skill, contains('`../../packages/noir_signals/doc/hooks.md`'));
    expect(skill, isNot(contains('noir-hooks')));

    final hooks = hooksReference.readAsStringSync();
    final referenceDirectory = Directory(
      '../../skills/noir/references',
    ).absolute.uri;
    for (final path in <String>[
      '../../../packages/noir_signals/doc/hooks.md',
      'design.md',
      'inputs-and-focus.md',
      'testing.md',
      '../SKILL.md#see-and-drive-a-running-app-drive-mode',
    ]) {
      final filePath = path.split('#').first;
      expect(
        File.fromUri(referenceDirectory.resolve(filePath)).existsSync(),
        isTrue,
        reason: path,
      );
      expect(hooks, contains('`$path`'), reason: path);
    }
    expect(hooks, contains('package:noir_signals/noir_signals.dart'));
    expect(
      hooks,
      contains('`../../../packages/noir_signals/doc/signals.md`'),
      reason: 'the skill must route reactive-state questions too',
    );
    expect(hooks, contains('Call hooks unconditionally'));
    expect(hooks, contains('input callbacks'));
    expect(hooks, contains('effect'));
    expect(hooks, contains('retained hook state'));
  });

  test('agent skills live only in the repository skills directory', () {
    expect(File('../../skills/noir/SKILL.md').existsSync(), isTrue);
    expect(Directory('../../skills/noir-hooks').existsSync(), isFalse);
    final tracked = Process.runSync('git', <String>[
      'ls-files',
      '--',
      '../../.agents',
      '../../.claude',
    ]);
    expect(tracked.exitCode, 0, reason: tracked.stderr as String);
    expect(
      (tracked.stdout as String).trim(),
      isEmpty,
      reason: 'agent skills are shared from skills/, not per-tool folders',
    );
  });
}

List<String> _dartFilesUnder(String directory) =>
    Directory(directory)
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path.replaceAll(Platform.pathSeparator, '/'))
        .where((file) => file.endsWith('.dart'))
        .toList(growable: false)
      ..sort();

/// Every symbol the barrel names in a `show` clause.
Set<String> _shownSymbols(String barrel) => <String>{
  for (final match in RegExp(
    r'export\s+[^;]*?\bshow\b([^;]*);',
    dotAll: true,
  ).allMatches(barrel))
    ...match
        .group(1)!
        .split(',')
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty),
};

/// The frozen public surface of `package:noir_signals/noir_signals.dart`.
const Set<String> _companionSurface = <String>{
  // Upstream Signals primitives an application needs to declare a model.
  'Computed',
  'ComputedOptions',
  'EffectCallback',
  'EffectCleanup',
  'EffectOptions',
  'ReadonlySignal',
  'ReadonlySignalOptions',
  'Signal',
  'SignalEffectException',
  'SignalOptions',
  'SignalsError',
  'SignalsReadAfterDisposeError',
  'SignalsWriteAfterDisposeError',
  'batch',
  'computed',
  'effect',
  'signal',
  'untracked',
  // Hook runtime.
  'Hook',
  'HookState',
  'SignalBuilder',
  'SignalWidget',
  'SignalWidgetBuilder',
  'use',
  'useContext',
  'useTickerProvider',
  // Built-in hooks.
  'AsyncSnapshot',
  'ConnectionState',
  'Dispose',
  'Effect',
  'ObjectRef',
  'Reducer',
  'Store',
  'ValueEquality',
  'useAnimation',
  'useAnimationController',
  'useAnimationStatus',
  'useCallback',
  'useChangeNotifier',
  'useDisposable',
  'useEffect',
  'useFocusNode',
  'useFuture',
  'useIsMounted',
  'useListenable',
  'useListenableSelector',
  'useMemoized',
  'useOnDispose',
  'useOnListenableChange',
  'usePrevious',
  'useReducer',
  'useRef',
  'useScrollController',
  'useState',
  'useStream',
  'useTextEditingController',
  'useValueChanged',
  'useValueListenable',
  'useValueNotifier',
  'useViewportController',
  // Signals integration.
  'SignalValueBuilder',
  'SignalValueWidgetBuilder',
  'useComputed',
  'useSignal',
  'useSignalEffect',
  'useSignalValue',
};
