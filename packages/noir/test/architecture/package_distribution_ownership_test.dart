import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final readme = File('README.md').readAsStringSync();
  final skill = _read('../../skills/noir/SKILL.md');
  final skillAgentMetadata = _read('../../skills/noir/agents/openai.yaml');
  final testingGuide = _read('../../skills/noir/references/testing.md');
  final widgetsGuide = _read('../../skills/noir/references/widgets.md');
  final inputsGuide = _read('../../skills/noir/references/inputs-and-focus.md');
  final stateGuide = _read(
    '../../skills/noir/references/state-and-animation.md',
  );
  final designGuide = _read('../../skills/noir/references/design.md');
  final exampleGuide = _read('example/README.md');
  final pubspec = _read('pubspec.yaml');
  final packageVersion = _packageVersion(pubspec);
  final contributorGuide = _read('../../AGENTS.md');
  final appSource = _read('lib/src/app/app.dart');
  final highLevelBarrel = _read('lib/noir.dart');
  final lowLevelBarrel = _read('lib/noir_low_level.dart');
  final ffiBarrel = _read('lib/noir_ffi.dart');
  final chatDemo = _read('example/src/chat/app.dart');
  final agentProtocol = _read('example/src/chat/protocol.dart');
  final agentController = _read('example/src/chat/session_controller.dart');
  final claudeBackend = _read('example/src/chat/claude_cli_backend.dart');

  test('retained source consumer uses only supported package barrels', () {
    final fixtureRoot = Directory('test/fixtures/source_package_consumer');
    expect(fixtureRoot.existsSync(), isTrue);

    final fixtureFiles = <String>{
      for (final file
          in fixtureRoot.listSync(recursive: true).whereType<File>())
        file.path
            .substring(fixtureRoot.path.length + 1)
            .replaceAll(Platform.pathSeparator, '/'),
    };
    expect(
      fixtureFiles,
      unorderedEquals(<String>{
        'pubspec.yaml',
        'bin/ffi.dart',
        'bin/high_level.dart',
        'bin/low_level_multi_child.dart',
        'bin/low_level_single_child.dart',
        'bin/render.dart',
        'probes/internal_seams.dart',
      }),
    );

    final pubspecSource = File(
      '${fixtureRoot.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(pubspecSource, contains('name: noir_source_consumer'));
    expect(pubspecSource, contains('publish_to: none'));
    expect(pubspecSource, contains('noir:\n    path: ../../..'));
    expect(pubspecSource, isNot(contains('hosted:')));
    expect(pubspecSource, isNot(contains('git:')));

    final expectedImports = <String, Set<String>>{
      'high_level.dart': {'package:noir/noir.dart'},
      'low_level_multi_child.dart': {
        'package:noir/noir.dart',
        'package:noir/noir_low_level.dart',
      },
      'low_level_single_child.dart': {
        'package:noir/noir.dart',
        'package:noir/noir_low_level.dart',
      },
      'ffi.dart': {'package:noir/noir_ffi.dart'},
      'render.dart': {
        'package:noir/noir.dart',
        'package:noir/noir_low_level.dart',
      },
    };
    for (final entry in expectedImports.entries) {
      final source = File(
        '${fixtureRoot.path}/bin/${entry.key}',
      ).readAsStringSync();
      final importDirectives = RegExp(
        r'^[ \t]*import\b[\s\S]*?;',
        multiLine: true,
      ).allMatches(source);
      final imports = importDirectives.map((match) {
        final directive = match.group(0)!.trim();
        final uri = RegExp(
          r'''^import\s+['"]([^'"]+)['"]\s*;$''',
          dotAll: true,
        ).firstMatch(directive);
        return uri?.group(1) ?? '<unsupported:$directive>';
      }).toList();
      expect(imports, unorderedEquals(entry.value), reason: entry.key);
    }
  });

  test('source consumer resolves offline, analyzes, and renders in place', () {
    final runner = File('test/source_package_consumer_test.dart');

    expect(runner.existsSync(), isTrue);
    final source = runner.readAsStringSync();
    expect(source, contains("@Tags(['safe-process-spawning'])"));
    expect(source, contains('Directory.systemTemp.createTemp'));
    expect(source, contains('package_config.json'));
    expect(source, contains('resolveSymbolicLinksSync'));
    final processCalls = RegExp(
      r'\bProcess\.(run|runSync|start|startSync)\s*\(',
    ).allMatches(source).toList();
    expect(processCalls, hasLength(8));
    expect(processCalls.map((match) => match.group(1)), everyElement('run'));
    expect(
      source,
      matches(RegExp(r"'pub',\s*'get',\s*'--offline'", multiLine: true)),
    );
    expect(source, contains("_analyze(sandbox, 'bin')"));
    expect(source, contains("'bin/render.dart'"));
    expect(source, contains("'build',\n      'cli'"));
    expect(source, contains('noir_relocated_consumer.'));
    expect(source, contains("'-D'"));
    expect(source, contains("'@rpath/lib/'"));
    expect(source, contains("'--fatal-infos'"));
    expect(source, contains("'--fatal-warnings'"));
    expect(source, contains("'--format=machine'"));
  });

  test('public changelog leads with the current package version', () {
    final changelog = _read('CHANGELOG.md');
    final changelogVersions = RegExp(
      r'^##\s+([^\s]+)\s*$',
      multiLine: true,
    ).allMatches(changelog).map((match) => match.group(1)).toList();

    expect(packageVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(packageVersion, '0.0.3');
    expect(changelogVersions, isNotEmpty);
    expect(changelogVersions.first, packageVersion);
    expect(changelogVersions.toSet(), hasLength(changelogVersions.length));
    expect(changelog, contains('invalidate cached hook output'));
    expect(changelog, contains('Like Reactor'));
    expect(changelog, contains('First public alpha'));
    expect(changelog, isNot(contains('Initial public release')));
    expect(changelog.toLowerCase(), isNot(contains('muse')));
  });

  test('current changelog records its release contracts', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    final currentRelease = _changelogSection(changelog, packageVersion);

    expect(currentRelease, isNotEmpty);
    expect(
      RegExp(r'^### Fixed$', multiLine: true).allMatches(currentRelease),
      hasLength(1),
    );
    for (final contract in const [
      'BuildOwner.buildScope()',
      'in its original order',
      'requests a frame',
      'TuiApp.requestExit',
      'reaches the exit sink unchanged',
      'bundled native artifacts are unchanged from 0.0.2',
    ]) {
      expect(_normalized(currentRelease), contains(contract), reason: contract);
    }
  });

  test('published 0.0.2 changelog retains its release contracts', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    final publishedRelease = _changelogSection(changelog, '0.0.2');

    expect(publishedRelease, isNotEmpty);
    expect(
      RegExp(r'^### Changed$', multiLine: true).allMatches(publishedRelease),
      hasLength(1),
    );
    for (final contract in const [
      'packages/noir',
      'The package `repository` field',
      'bundled native artifacts are unchanged from 0.0.1',
    ]) {
      expect(
        _normalized(publishedRelease),
        contains(contract),
        reason: contract,
      );
    }
  });

  test('published 0.0.1 changelog retains its release contracts', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    final currentRelease = _changelogSection(changelog, '0.0.1');

    expect(currentRelease, isNotEmpty);
    expect(
      changelog,
      isNot(matches(RegExp(r'^## 0\.0\.1-alpha\.2$', multiLine: true))),
    );
    for (final heading in const ['Added', 'Fixed', 'Removed']) {
      expect(
        RegExp('^### $heading\$', multiLine: true).allMatches(currentRelease),
        hasLength(1),
        reason: heading,
      );
    }
    for (final contract in const [
      'This initial 0.0.x release',
      'State.deferDispose',
      'HookState.deferDispose',
      'LayoutBuilder',
      'FocusManager',
      'keyed `ListView` row',
      'native ABI',
      'bundled native artifacts are unchanged',
    ]) {
      expect(_normalized(currentRelease), contains(contract), reason: contract);
    }
  });

  test('published alpha.4 changelog retains its release contracts', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    final publishedAlpha = _changelogSection(changelog, '0.0.1-alpha.4');

    expect(publishedAlpha, isNotEmpty);
    for (final heading in const ['Changed', 'Fixed']) {
      expect(
        RegExp('^### $heading\$', multiLine: true).allMatches(publishedAlpha),
        hasLength(1),
        reason: heading,
      );
    }
    for (final contract in const [
      'example/src/',
      'LICENSE-YOGA',
      'bin/patch_manager.dart',
      'already excluded from the published alpha.3 archive',
      'public API shapes and runtime behavior',
      'native ABI',
      'bundled native artifacts are unchanged',
    ]) {
      expect(_normalized(publishedAlpha), contains(contract), reason: contract);
    }
  });

  test('published alpha.3 changelog retains its release contracts', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    final publishedAlpha = _changelogSection(changelog, '0.0.1-alpha.3');

    expect(publishedAlpha, isNotEmpty);
    for (final heading in const ['Added', 'Changed', 'Fixed', 'Removed']) {
      expect(
        RegExp('^### $heading\$', multiLine: true).allMatches(publishedAlpha),
        hasLength(1),
        reason: heading,
      );
    }
    for (final contract in const [
      'Ctrl+A',
      'Ctrl+C',
      'modifyOtherKeys',
      'through tmux',
      'Forced Kitty graphics',
      'unsupported for alpha.3',
      'package:noir/noir_ffi.dart',
      'scissor-',
      'opacity-stack',
    ]) {
      expect(publishedAlpha, contains(contract), reason: contract);
    }
  });

  test('published alpha.1 and alpha.0 changelog sections stay pinned', () {
    final changelog = _normalizeLineEndings(_read('CHANGELOG.md'));
    expect(_changelogSection(changelog, '0.0.1-alpha.1'), _publishedAlpha1);
    expect(_changelogSection(changelog, '0.0.1-alpha.0'), _publishedAlpha0);
    expect(_publishedAlpha1, isNot(contains('git show')));
    expect(_publishedAlpha0, isNot(contains('git show')));
  });

  test('live release records derive the package version in one place', () {
    final changelog = _read('CHANGELOG.md');
    final publication = _read('../../publication.json');
    expect(changelog, contains('\n## $packageVersion\n'));
    expect(
      changelog.indexOf('\n## $packageVersion\n'),
      changelog.indexOf('\n## '),
      reason: 'the manifest version heads the changelog',
    );
    expect(publication, contains('"noir": '));
    expect(publication, contains('"noir_signals": '));
    expect(
      contributorGuide,
      contains('The target is the current core-framework release candidate'),
    );
    expect(contributorGuide, isNot(contains(packageVersion)));
  });

  test('live version references follow the package release', () {
    final dialog = _read('example/dialog_demo.dart');
    expect(dialog, contains(packageVersion));
    expect(
      RegExp(RegExp.escape(packageVersion)).allMatches(dialog),
      hasLength(3),
    );

    for (final path in const [
      'lib/src/core/terminal_image.dart',
      '../../skills/noir/references/widgets.md',
      '../../website/src/content/docs/platform-limitations.mdx',
    ]) {
      expect(_read(path), isNot(contains('alpha.3')), reason: path);
    }

    final historicalRecording = _read('tool/recordings/pub_search_demo.dart');
    expect(historicalRecording, contains("version: '0.0.1-alpha.3'"));
  });

  test(
    'pinned OpenTUI and Yoga notices accompany bundled native libraries',
    () {
      final noticeFile = File('THIRD_PARTY_NOTICES.md');
      expect(noticeFile.existsSync(), isTrue);
      final notice = _normalizeLineEndings(noticeFile.readAsStringSync());
      final upstreamLicense = _normalizeLineEndings(
        File('../../external/opentui/LICENSE').readAsStringSync(),
      );
      final packagedLicense = _normalizeLineEndings(
        File('third_party/opentui-v0.5.1/LICENSE').readAsStringSync(),
      );
      final packagedYogaLicense = _normalizeLineEndings(
        File('third_party/opentui-v0.5.1/LICENSE-YOGA').readAsStringSync(),
      );
      final buildDependencies = _read(
        '../../external/opentui/packages/core/src/zig/build.zig.zon',
      );
      final manifest =
          jsonDecode(File('native_manifest.json').readAsStringSync())
              as Map<String, Object?>;

      expect(notice, contains('OpenTUI'));
      expect(notice, contains('https://github.com/anomalyco/opentui'));
      expect(notice, contains(manifest['commit']! as String));
      expect(packagedLicense, upstreamLicense);
      for (final fileName in <String>[
        'LICENSE',
        'LICENSE-WUFFS',
        'LICENSE-LIBWEBP',
        'AUTHORS-LIBWEBP',
        'PATENTS-LIBWEBP',
        'LICENSE-STB',
        'LICENSE-LCMS2',
        'LICENSE-YOGA',
      ]) {
        expect(notice, contains('third_party/opentui-v0.5.1/$fileName'));
      }
      expect(
        buildDependencies,
        contains('git+https://github.com/facebook/yoga#v3.2.1'),
      );
      expect(notice, contains('https://github.com/facebook/yoga'));
      expect(notice, contains('v3.2.1'));
      expect(packagedYogaLicense, _yogaV321License);
      expect(
        _read('CHANGELOG.md'),
        contains('published `0.0.1-alpha.3` archive omitted'),
      );
    },
    skip: File('../../external/opentui/LICENSE').existsSync()
        ? false
        : 'OpenTUI submodule is not materialized in this checkout.',
  );

  test('legacy ASCII font payload is absent from package sources and docs', () {
    const forbiddenSource =
        'c'
        'fonts';
    expect(File('tool/generate_ascii_font_data.dart').existsSync(), isFalse);
    expect(Directory('third_party/$forbiddenSource').existsSync(), isFalse);

    final packageTextFiles = <File>[
      for (final root in <String>[
        'bin',
        'example',
        'hook',
        'lib',
        'tool',
        '../../skills',
        'test',
      ])
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => const <String>{
                '.dart',
                '.json',
                '.md',
                '.yaml',
                '.yml',
              }.any(file.path.endsWith),
            ),
      for (final path in <String>[
        '../../AGENTS.md',
        'README.md',
        '../../GOALS.md',
        'CHANGELOG.md',
        'THIRD_PARTY_NOTICES.md',
        'pubspec.yaml',
      ])
        File(path),
    ];
    final staleReferences = <String>[
      for (final file in packageTextFiles)
        if (file.readAsStringSync().toLowerCase().contains(forbiddenSource))
          file.path,
    ];
    expect(staleReferences, isEmpty);
  });

  test('README gives truthful install and runnable samples', () {
    final installStart = readme.indexOf('## Install');
    final quickStartIndex = readme.indexOf('## Quick Start');
    final nextSectionIndex = readme.indexOf('\n## ', quickStartIndex + 3);
    final quickStart = readme.substring(quickStartIndex, nextSectionIndex);
    final install = readme.substring(installStart, quickStartIndex);

    expect(installStart, greaterThanOrEqualTo(0));
    expect(install, contains('dart pub add noir'));
    expect(install, isNot(contains('dart pub add noir:^')));
    expect(install, contains('path: ../noir'));
    expect(
      _normalized(install),
      contains('pin an exact commit or release tag'),
    );
    expect(readme, contains('Noir is at an early 0.0.x stage.'));
    // Three complete, runnable samples: the one-line entry point plus the
    // two Quick Start apps. Fragments stay inline so every block compiles.
    expect(
      RegExp(r'^```dart$', multiLine: true).allMatches(readme),
      hasLength(3),
    );
    expect(readme, contains('void main() => runTuiApp(const MyApp('));
    expect(readme, contains('TuiApp.exit(context)'));
    expect(quickStart, contains('class HelloApp extends StatelessWidget'));
    expect(quickStart, contains('class CounterApp extends StatefulWidget'));
    expect(quickStart, contains('setState(() => _count++)'));
    for (final staleClaim in <String>[
      'Core-framework 1.0',
      'Phase 9',
      'P9-',
      'PR closeout',
      'does not claim',
    ]) {
      expect(readme, isNot(contains(staleClaim)), reason: staleClaim);
    }
  });

  test('README documents the packaged headless native health check', () {
    final readmeFlat = _normalized(readme).toLowerCase();

    expect(readme, contains('dart run noir:health_check'));
    expect(readmeFlat, contains('native testing mode'));
    expect(readmeFlat, contains('bundled native asset'));
    expect(readmeFlat, contains('headless buffer/render lifecycle'));
    expect(
      readmeFlat,
      contains('does not validate real terminal escape rendering'),
    );
  });

  test('packaged hot reload has one public command and current guidance', () {
    final changelog = _read('CHANGELOG.md');
    final guidance = '$readme\n$skill\n$changelog';

    expect(File('bin/run.dart').existsSync(), isTrue);
    expect(readme, contains('dart run noir:run example/counter.dart'));
    expect(skill, contains('dart run noir:run example/counter.dart'));
    expect(changelog, contains('`dart run noir:run`'));
    expect(guidance, contains('.dart_tool/noir/run.log'));
    expect(guidance, isNot(contains('tool/hot_reload_driver.dart')));
  });

  test('removed checkout-only hot reload driver has no stale guidance', () {
    final removedDriverPath = <String>[
      'tool',
      'hot_reload_driver.dart',
    ].join('/');
    final guidanceFiles = <File>[
      // The hooks guide moved to the companion package, so the root `doc/`
      // directory no longer exists in a clean checkout.
      for (final root in <String>[
        'bin',
        'example',
        'hook',
        'lib',
        '../noir_signals',
        'tool',
        '../../skills',
      ])
        ...Directory(root)
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) => const <String>[
                '.dart',
                '.md',
                '.yaml',
                '.yml',
              ].any(file.path.endsWith),
            ),
      for (final path in <String>[
        '../../AGENTS.md',
        'CHANGELOG.md',
        '../../CONTRIBUTING.md',
        '../../GOALS.md',
        'README.md',
        'pubspec.yaml',
      ])
        File(path),
    ];
    final staleReferences = <String>[
      for (final file in guidanceFiles)
        if (file.readAsStringSync().contains(removedDriverPath)) file.path,
    ];

    expect(File(removedDriverPath).existsSync(), isFalse);
    expect(staleReferences, isEmpty);
  });

  test('example catalog lists every shipped entrypoint exactly once', () {
    final shippedExamples = Directory('example')
        .listSync()
        .whereType<File>()
        .map((file) => file.path.split(Platform.pathSeparator).last)
        .where((name) => name.endsWith('.dart'))
        .toSet();
    final catalogEntries = RegExp(
      r'`dart run example/([^`]+\.dart)`',
    ).allMatches(exampleGuide).map((match) => match.group(1)!).toList();

    expect(catalogEntries.toSet(), hasLength(catalogEntries.length));
    expect(catalogEntries, unorderedEquals(shippedExamples));
    expect(
      readme,
      contains(
        '[example catalog](https://github.com/btwld/noir/blob/main/packages/noir/example/README.md)',
      ),
    );
    expect(
      RegExp(
        r'\[example catalog\]\(https://github\.com/btwld/noir/blob/main/packages/noir/example/README\.md\)',
      ).allMatches(readme),
      hasLength(1),
    );
    expect(
      RegExp(r'example/[^)]+\.dart').allMatches(readme).length,
      lessThan(shippedExamples.length),
      reason: 'README must link to the catalog instead of duplicating it',
    );
    for (final heading in <String>[
      '## Start here',
      '## Core concepts',
      '## Controls and data',
      '## Complete apps',
      '## Motion',
      '## Advanced and reference',
    ]) {
      expect(exampleGuide, contains(heading));
    }
  });

  test('example guide explains optional quiet build-hook status', () {
    expect(
      exampleGuide,
      contains('dart run --verbosity=error example/counter.dart'),
    );
    expect(exampleGuide, contains('still runs and verifies the native asset'));
    expect(exampleGuide, contains('Dart invalidates the\n  build-hook cache'));
  });

  test('README preserves known limitations without internal ticket IDs', () {
    final limitationsStart = readme.indexOf('## Known Limitations');
    expect(limitationsStart, greaterThanOrEqualTo(0));
    final limitations = _normalized(
      readme.substring(limitationsStart),
    ).toLowerCase();
    for (final disclosure in <String>[
      'multi-code-point graphemes',
      'selection ranges',
      'native encoded storage',
      'deployment target of 12',
      'macos 12',
      'straddles a clipped viewport edge',
      'low-level native operation failures',
      'main-screen row 1/column 1',
      'absolute build/debug paths',
    ]) {
      expect(limitations, contains(disclosure), reason: disclosure);
    }
    expect(limitations, isNot(contains('P9-')));
    expect(limitations, isNot(contains('startup ordering window')));
  });

  test('shipped lifecycle guidance matches the final TuiApp facade', () {
    expect(appSource, contains('TuiApp runTuiApp('));
    expect(appSource, contains('final handle = TuiApp._(binding, '));
    expect(appSource, contains('TuiApp._(this._binding, this._exitCodeSink);'));
    for (final method in <String>['onKey', 'onMouse', 'onPaste']) {
      expect(
        appSource,
        matches(RegExp('$method\\([\\s\\S]*?priority: InputPriority\\.app')),
        reason: method,
      );
    }
    expect(appSource, contains('if (cancelled) return;'));
    expect(appSource, contains('if (_disposed) return;'));

    final readmeFlat = _normalized(readme);
    final skillFlat = _normalized(skill);
    final exampleFlat = _normalized(exampleGuide);
    for (final evidence in <String>[
      'returns a `TuiApp` handle synchronously',
      'app-priority handlers',
      'idempotent canceler',
      '`TuiApp.dispose()` is idempotent',
      'cancels every still-owned registration before disposing the mounted app',
      '`headless: true` creates no owned terminal renderer',
    ]) {
      expect(readmeFlat, contains(evidence), reason: evidence);
    }
    for (final evidence in <String>[
      'returns the handle synchronously',
      'app-priority',
      'idempotent canceler',
      '`dispose()` is idempotent',
      'returned `TuiApp`',
    ]) {
      expect(skillFlat, contains(evidence), reason: evidence);
    }
    expect(
      exampleFlat,
      contains(
        '`runTuiApp(..., headless: true)` returns a `TuiApp` whose '
        '`isHeadless` is `true` and creates no owned terminal renderer',
      ),
    );

    final currentAppGuidance =
        '$readme\n$skill\n$exampleGuide\n$testingGuide\n$inputsGuide';
    expect(currentAppGuidance, isNot(contains('await runTuiApp')));
    expect(currentAppGuidance, isNot(contains('TuiBinding.instance')));
    expect(currentAppGuidance, isNot(contains('binding.inputManager')));
    expect(currentAppGuidance, isNot(contains('app.enableMouse();')));
    expect(currentAppGuidance, isNot(contains('tuiApp.enableMouse();')));
    expect(
      currentAppGuidance,
      isNot(contains('app.dispose() then `io.exit(0)`')),
    );
    expect(
      currentAppGuidance,
      isNot(contains('registerHotReloadExtension(app);')),
    );
    expect(
      testingGuide,
      isNot(contains(RegExp(r'runTuiApp\([^;]*width:', dotAll: true))),
      reason: 'runTuiApp no longer takes width/height',
    );
    expect(
      currentAppGuidance.toLowerCase(),
      isNot(contains('dispose the binding')),
    );
    expect(chatDemo, isNot(contains('detaches State.context before dispose')));
    expect(chatDemo, isNot(contains('..stop();')));
  });

  test('shipped guidance describes the three supported import surfaces', () {
    expect(highLevelBarrel, contains("export 'src/app/app.dart' show TuiApp"));
    expect(
      highLevelBarrel,
      contains('show Attr, BorderSides, BoxOptions, TextAlign'),
    );
    expect(
      lowLevelBarrel,
      contains("export 'src/app/tui_binding.dart' show TuiBinding"),
    );
    expect(lowLevelBarrel, isNot(contains('show Element,')));
    expect(ffiBarrel, contains('show FFIException, OpenTuiBindings'));

    final readmeFlat = _normalized(readme);
    final skillFlat = _normalized(skill);
    for (final evidence in <String>[
      '`package:noir/noir.dart` — ordinary application and widget authoring',
      '`package:noir/noir_low_level.dart` — advanced hosting, renderer/buffer access, and supported custom rendering',
      '`package:noir/noir_ffi.dart` — ABI-unstable raw FFI access',
      'Concrete Element implementations and the recorder/display-list/compositor backend remain framework-owned',
    ]) {
      expect(readmeFlat, contains(evidence), reason: evidence);
    }
    for (final evidence in <String>[
      'Widget lifecycle hooks and Signals reactive state are opt-in through the companion `package:noir_signals`',
      'advanced hosting, renderer/buffer access, and supported custom render-object protocols',
      'Concrete Element implementations and the recorder/display-list/compositor backend stay framework-owned',
    ]) {
      expect(skillFlat, contains(evidence), reason: evidence);
    }
  });

  test('agent chat keeps protocol, reducer, and presentation boundaries', () {
    final packageImports = RegExp(
      r"^import 'package:noir/([^']+)';$",
      multiLine: true,
    ).allMatches(chatDemo).map((match) => match.group(1)).toList();
    expect(packageImports, ['noir.dart']);
    expect(agentProtocol, isNot(contains('package:noir/')));
    expect(
      agentController,
      contains("import 'package:noir/noir.dart' show ChangeNotifier;"),
    );
    expect(agentController, isNot(contains('package:noir/src/')));

    final applicationSources = '$chatDemo\n$agentProtocol\n$agentController';
    expect(
      applicationSources,
      isNot(contains('package:noir/noir_low_level.dart')),
    );
    expect(applicationSources, isNot(contains('package:noir/noir_ffi.dart')));
    expect(applicationSources, isNot(contains("import 'dart:io'")));
    expect(applicationSources, isNot(contains('Process.start')));
    expect(claudeBackend, contains("import 'dart:io';"));
    expect(claudeBackend, contains('Process.start'));
    expect(claudeBackend, isNot(contains('package:noir/')));
    expect(claudeBackend, contains("'--safe-mode'"));
    expect(claudeBackend, contains("'--disable-slash-commands'"));
    expect(claudeBackend, contains("'--strict-mcp-config'"));
    // The adapter exposes no permission channel, so tools stay off and no
    // constructor parameter may turn them on.
    expect(claudeBackend, contains("'--tools',\n    '',"));
    expect(claudeBackend, isNot(contains('allowedTools')));
    expect(claudeBackend, contains("'--permission-mode',\n    'dontAsk',"));
    expect(claudeBackend, contains("'{\"mcpServers\":{}}'"));
    expect(claudeBackend, contains("'--no-session-persistence'"));
    expect(claudeBackend, contains("'--max-budget-usd'"));
    expect(claudeBackend, isNot(contains("'--continue'")));
    expect(claudeBackend, isNot(contains("'--resume'")));
    expect(claudeBackend, isNot(contains('~/.claude')));
    expect(chatDemo, contains("const prefix = '--claude=';"));
    expect(chatDemo, isNot(contains('ChatResponder')));
    expect(chatDemo, isNot(contains('jumpTo(0)')));
    expect(chatDemo, isNot(contains('newest-first')));
    expect(chatDemo, contains('ScrollController(followTail: true)'));
    expect(chatDemo, contains('MarkdownView('));
    expect(chatDemo, contains('submitOnEnter: true'));
  });

  test('desktop target metadata matches the bundled manifest matrix', () {
    final assets = _manifestAssets();
    final manifestOs = assets.map((asset) => asset['os']! as String).toSet();
    final manifestPairs = assets
        .map((asset) => '${asset['os']}/${asset['arch']}')
        .toSet();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(manifestPairs, hasLength(6));
    expect(_pubspecPlatforms(pubspec), unorderedEquals(manifestOs));
    expect(_readmeTargetPairs(readme), unorderedEquals(manifestPairs));
    expect(
      readme,
      contains('Android, iOS, and web are not supported targets.'),
    );
    expect(
      readme,
      contains(
        'The bundled macOS x64 and arm64 libraries require macOS 13.0 or later.',
      ),
    );
    expect(
      readme,
      isNot(
        matches(
          RegExp(
            r'(?:supports?[^\n.]{0,40}(?:Android|iOS|web)|'
            r'(?:Android|iOS|web)[^\n.]{0,20}(?:is|are) supported)',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test(
    'distribution-critical source inclusion follows pubignore semantics',
    () {
      final requiredPaths = <String>[
        'LICENSE',
        'THIRD_PARTY_NOTICES.md',
        'README.md',
        'CHANGELOG.md',
        'pubspec.yaml',
        'native_manifest.json',
        'bin/run.dart',
        'hook/build.dart',
        ...Directory('third_party/opentui-v0.5.1')
            .listSync()
            .whereType<File>()
            .map((file) => file.path.replaceAll(Platform.pathSeparator, '/')),
        'third_party/uucode-84ceda/LICENSE.md',
        'third_party/uucode-84ceda/LICENSE_unicode',
        ..._manifestAssets().map((asset) => asset['path']! as String),
      ];

      for (final path in requiredPaths) {
        expect(File(path).existsSync(), isTrue, reason: '$path must exist');
      }

      final result = Process.runSync('git', [
        'ls-files',
        '--cached',
        '--others',
        '--ignored',
        '--exclude-per-directory=.pubignore',
        '--',
        ...requiredPaths,
      ]);
      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(
        (result.stdout as String).trim(),
        isEmpty,
        reason: 'distribution-critical source inputs must not be ignored',
      );
    },
  );

  test('notice comparisons normalize Windows and classic line endings', () {
    expect(_normalizeLineEndings('a\r\nb\rc\n'), 'a\nb\nc\n');
  });

  test('generated API documentation stays outside the publish archive', () {
    final pubignoreLines = _read('.pubignore').split('\n');

    expect(pubignoreLines, contains('/doc/api/'));
  });

  test('muse_noir keeps one private Muse adapter door', () {
    final libraryRoot = Directory('../muse_noir/lib');
    final dartFiles = libraryRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    final internalImports = <String>[
      for (final file in dartFiles)
        if (file.readAsStringSync().contains('package:muse/src/')) file.path,
    ];

    expect(internalImports, <String>['../muse_noir/lib/src/muse_bridge.dart']);
    final barrel = _read('../muse_noir/lib/muse_noir.dart');
    expect(barrel, isNot(contains('muse_bridge.dart')));
    expect(barrel, isNot(contains('surface_view.dart')));
  });

  test('muse_noir production stays on Muse and Noir public surfaces', () {
    final sources = Directory('../muse_noir/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('muse_bridge.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(sources, isNot(contains('package:flutter/')));
    expect(sources, isNot(contains('package:noir/src/')));
    expect(sources, isNot(contains('package:noir/noir_ffi.dart')));
    expect(
      sources,
      isNot(contains('MusePreparedSurface')),
      reason: 'Prepared types stay confined to the private bridge.',
    );
  });

  test(
    'repository-only code stays in scripts and large examples share one layout',
    () {
      expect(
        Directory('bin').listSync().whereType<File>().map(
          (file) => file.path.replaceAll(Platform.pathSeparator, '/'),
        ),
        unorderedEquals(<String>['bin/health_check.dart', 'bin/run.dart']),
      );
      final misplacedToolFiles = Directory('lib/src/tools').existsSync()
          ? Directory(
              'lib/src/tools',
            ).listSync(recursive: true).whereType<File>().toList()
          : const <File>[];
      expect(misplacedToolFiles, isEmpty);

      for (final path in const <String>[
        'tool/patch_manager.dart',
        'tool/patch_manager/patch_manager.dart',
        'tool/snapshot_scenes.dart',
        'example/src/chat/app.dart',
        'example/src/chat/protocol.dart',
        'example/src/chat/session_controller.dart',
        'example/src/chat/claude_cli_backend.dart',
        'example/src/pub_search/app.dart',
        'example/src/pub_search/catalog.dart',
        'example/src/pub_search/models.dart',
        'example/src/pub_search/package_detail.dart',
        'example/src/pub_search/theme.dart',
        'example/src/shared/demo_scaffold.dart',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: path);
      }
    },
  );

  test('website records live with the website application', () {
    expect(File('PRODUCT.md').existsSync(), isFalse);
    expect(File('DESIGN.md').existsSync(), isFalse);
    expect(File('../../website/README.md').existsSync(), isTrue);
    expect(File('../../website/DESIGN.md').existsSync(), isTrue);
  });

  test(
    'website application and its design record stay outside the Dart package archive',
    () {
      // The website is a sibling of the package, so the archive cannot carry
      // it and no ignore rule is needed.
      expect(Directory('website').existsSync(), isFalse);
      expect(File('../../website/README.md').existsSync(), isTrue);
      expect(File('../../website/DESIGN.md').existsSync(), isTrue);
      final pubignoreLines = _read('.pubignore').split('\n');
      expect(pubignoreLines, isNot(contains('/PRODUCT.md')));
      expect(pubignoreLines, isNot(contains('/DESIGN.md')));
    },
  );

  test('website catalog uses the public composed components', () {
    final catalog = _read('../../website/src/content/docs/widget-catalog.mdx');
    final layout = _read('../../website/src/content/docs/widgets-layout.mdx');

    for (final widget in <String>[
      'Panel',
      'Modal',
      'Autocomplete<T>',
      'TreeView',
      'TreeViewController',
    ]) {
      expect(catalog, contains('`$widget`'), reason: widget);
    }
    // Modal instructions belong to the reference; the layout guide keeps the
    // regions and constraints a screen is composed from.
    expect(catalog, contains('Modal('));
    expect(layout, contains('Panel('));
    expect(layout, isNot(contains('Modal(')));
    expect(layout, isNot(contains('class LogPanel')));
  });

  test('every catalog widget name reaches a usable destination', () {
    final catalog = _read('../../website/src/content/docs/widget-catalog.mdx');
    final definitions = RegExp(
      r'^\[([a-z0-9]+)\]: (\S+)$',
      multiLine: true,
    ).allMatches(catalog);
    expect(definitions, isNotEmpty);

    final destinations = <String, String>{
      for (final match in definitions) match.group(1)!: match.group(2)!,
    };
    for (final destination in destinations.values) {
      expect(
        destination,
        startsWith('https://pub.dev/documentation/noir/'),
        reason: 'a catalog name must resolve to the generated reference',
      );
    }

    // Reference-style labels only work when every use has a definition.
    final uses = RegExp(r'\]\[([a-z0-9]+)\]').allMatches(catalog);
    expect(uses, isNotEmpty);
    for (final use in uses) {
      expect(
        destinations,
        contains(use.group(1)),
        reason: 'undefined catalog link label: ${use.group(1)}',
      );
    }
    // One curated page exists; the catalog must point at it.
    expect(catalog, contains('](/docs/widgets/text-input)'));
    expect(
      File(
        '../../website/src/content/docs/widgets/text-input.mdx',
      ).existsSync(),
      isTrue,
    );
  });

  test('data-selection examples retain application-owned behavior', () {
    final autocomplete = _read('example/autocomplete_demo.dart');
    final filePicker = _read('example/file_picker_demo.dart');

    expect(autocomplete, contains('Autocomplete<PackageSuggestion>'));
    expect(autocomplete, contains('class PackageAutocompleteController'));
    expect(filePicker, contains('TreeView<DemoFileNode>'));
    expect(filePicker, contains('TreeViewController<DemoFileNode>'));
    expect(filePicker, isNot(contains('class FilePickerController')));
    expect(filePicker, isNot(contains('class DemoFileEntry')));
  });

  test('development guidance is excluded while examples stay publishable', () {
    final repositorySkillDocs =
        '../../skills/noir/SKILL.md ../../skills/noir/agents/openai.yaml ../../skills/noir/references/testing.md ../../skills/noir/references/widgets.md ../../skills/noir/references/inputs-and-focus.md ../../skills/noir/references/state-and-animation.md ../../skills/noir/references/design.md ../../skills/noir/references/hooks.md'
            .split(' ');
    const exampleGuidePath = 'example/README.md';
    // Agent skills are repository guidance beside the package, never inside
    // it, so no ignore rule is needed to keep them out of the archive.
    for (final doc in repositorySkillDocs) {
      expect(File(doc).existsSync(), isTrue, reason: doc);
    }
    expect(Directory('skills').existsSync(), isFalse);
    final exampleIgnored = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--ignored',
      '--exclude-per-directory=.pubignore',
      '--',
      exampleGuidePath,
    ]);
    expect(exampleIgnored.exitCode, 0, reason: exampleIgnored.stderr as String);
    expect((exampleIgnored.stdout as String).trim(), isEmpty);

    final barrels = 'lib/noir.dart lib/noir_low_level.dart lib/noir_ffi.dart'
        .split(' ')
        .map(_read)
        .join('\n');
    expect(
      barrels,
      isNot(
        matches(
          RegExp(
            r'\b(?:WidgetTester|BufferCapture|BufferMatchers|GoldenTester|KeyDriver|createTuiTestApp|TuiTestApp)\b',
          ),
        ),
      ),
    );
    final repositorySkillText = repositorySkillDocs.map(_read).join('\n');
    expect(
      repositorySkillText,
      isNot(
        matches(
          RegExp(
            r'(?:`|\]\()(?:\.\./)*(?:test|tasks|scripts|tools|external|\.context)/',
          ),
        ),
      ),
    );
    for (final excludedFile in <String>[
      '../../AGENTS.md',
      '../../CLAUDE.md',
      '../../GOALS.md',
      '../../CONTRIBUTING.md',
    ]) {
      expect(
        repositorySkillText,
        isNot(contains(excludedFile)),
        reason: excludedFile,
      );
    }
    expect(
      testingGuide,
      contains('does not export a public widget-test harness'),
    );
  });

  test('skill signatures and comparisons match current Noir contracts', () {
    final editingSource = _read('lib/src/widgets/text_input_connection.dart');
    final stateSource = _read('lib/src/framework/widget.dart');
    final shortcutTests = _read('test/widgets/shortcuts_actions_test.dart');
    final borderSource = _read('lib/src/painting/box_border.dart');
    final driveCli = _read('../noir_driver/bin/drive.dart');

    const expectedSkillAgentMetadata =
        'interface:\n'
        '  display_name: "Noir"\n'
        '  short_description: "Build Dart terminal apps with Noir"\n'
        r'  default_prompt: "Use $noir to build or improve a Dart terminal application with Noir."'
        '\n';
    expect(skillAgentMetadata, expectedSkillAgentMetadata);

    final layoutEvidence = [
      _read('lib/src/widgets/row_column.dart'),
      _read('lib/src/widgets/flexible.dart'),
      borderSource,
      skill,
      widgetsGuide,
    ].join('\n');
    expect(
      _normalized(layoutEvidence),
      matches(
        RegExp(
          r'^(?=[\s\S]*final int spacing;)(?=[\s\S]*this\.spacing = 0)(?=[\s\S]*final int flex;)(?=[\s\S]*this\.flex = 1)(?=[\s\S]*`Flex\.spacing` is a non-negative `int`)(?=[\s\S]*int spacing = 0)(?=[\s\S]*const Flexible\(\{ required Widget child, int flex = 1, FlexFit fit = FlexFit\.loose, Key\? key \}\))(?=[\s\S]*const Expanded\(\{ required Widget child, int flex = 1, Key\? key \}\))',
        ),
      ),
    );
    for (final signature in const <String>[
      'Border.all({',
      'Border.symmetric({',
      'Border({',
      'TextDecoration? decoration',
    ]) {
      expect(widgetsGuide, contains(signature), reason: signature);
    }
    for (final staleSignature in const <String>[
      'const Border.all({',
      'const Border.symmetric({',
      'const Border({',
      'List<TextDecoration>? decoration',
    ]) {
      expect(
        widgetsGuide,
        isNot(contains(staleSignature)),
        reason: staleSignature,
      );
    }
    expect(borderSource, isNot(contains('const Border({')));
    expect(borderSource, isNot(contains('const Border.all({')));
    expect(borderSource, isNot(contains('const Border.symmetric({')));

    expect(editingSource, isNot(contains('LogicalKeyboardKey.tab')));
    expect(editingSource, contains('InsertTabIntent:'));
    expect(
      shortcutTests,
      contains('TextArea Tab and Shift+Tab route through traversal policy'),
    );
    expect(inputsGuide, contains('Physical Tab and Shift+Tab move focus'));
    expect(inputsGuide, contains('dispatching an `InsertTabIntent`'));
    expect(
      inputsGuide,
      contains('event.logicalKey == LogicalKeyboardKey.keyQ'),
    );
    expect(
      inputsGuide,
      isNot(contains('event.logicalKey == LogicalKeyboardKey.keyA`.')),
    );
    expect(inputsGuide, contains('repository-contributor implementation rule'));
    expect(inputsGuide, contains('must not import `package:noir/src/**`'));

    final comparisonDocs = '$skill\n$stateGuide';
    expect(
      comparisonDocs,
      isNot(
        matches(
          RegExp(
            '~90%|This is the Flutter pipeline, unchanged|Identical to Flutter|full Flutter lifecycle|the whole list|1:1 noir equivalent',
          ),
        ),
      ),
    );
    expect(_normalized(skill), contains('Flutter-inspired'));
    expect(_normalized(skill), contains('Noir signatures are authoritative'));
    expect(
      '$stateSource\n$skill',
      matches(
        RegExp(
          r'^(?=[\s\S]*void initState\(\))(?=[\s\S]*void didChangeDependencies\(\))(?=[\s\S]*void didUpdateWidget)(?=[\s\S]*void deactivate\(\))(?=[\s\S]*void dispose\(\))(?=[\s\S]*bool get mounted)(?=[\s\S]*`initState`)(?=[\s\S]*`didChangeDependencies`)(?=[\s\S]*`didUpdateWidget`)(?=[\s\S]*`deactivate`)(?=[\s\S]*`dispose`)(?=[\s\S]*`mounted`)',
        ),
      ),
    );
    expect(stateGuide, contains('dependOnInheritedWidgetOfExactType'));

    expect(
      skill,
      isNot(
        contains(
          'There is no `Stack`, `Wrap`, `ListView`, or `GestureDetector`',
        ),
      ),
      reason: 'ListView is shipped; the catalog must not list it as missing',
    );
    for (final name in const <String>[
      'Theme',
      'ThemeData',
      'ListView',
      'Autocomplete',
      'AutocompleteStatus',
      'TreeView',
      'TreeViewController',
      'TreeNode',
      'Checkbox',
      'Switch',
      'Button',
      'Divider',
      'ProgressBar',
      'Spinner',
      'Badge',
      'DataTable',
      'Panel',
      'Modal',
      'ModalController',
    ]) {
      expect(skill, contains('`$name`'), reason: 'SKILL.md catalog: $name');
    }
    expect(widgetsGuide, contains('const Theme({required this.data'));
    expect(widgetsGuide, contains('const ThemeData({'));
    expect(widgetsGuide, contains('const Divider({'));
    expect(widgetsGuide, contains('const Badge({'));
    expect(widgetsGuide, contains('const ProgressBar({'));
    expect(widgetsGuide, contains('const Spinner({'));
    expect(widgetsGuide, contains('const Panel({'));
    expect(widgetsGuide, contains('const Modal({'));
    expect(inputsGuide, contains('const Autocomplete<T>({'));
    expect(inputsGuide, contains('const ListView({'));
    expect(inputsGuide, contains('TreeNode<T>.leaf({'));
    expect(inputsGuide, contains('TreeViewController<T>({'));
    expect(inputsGuide, contains('const TreeView<T>({'));
    expect(inputsGuide, contains('const Checkbox({'));
    expect(inputsGuide, contains('const Switch({'));
    expect(inputsGuide, contains('const Button({'));
    expect(inputsGuide, contains('const DataTable({'));
    expect(inputsGuide, contains('const DataColumn({'));
    expect(skill, contains('Theme.of(context)'));
    expect(skill, contains('selectedIndex'));
    expect(skill, contains('`references/design.md`'));
    expect(driveCli, contains('scroll takes <up|down|left|right> <x> <y>.'));
    expect(skill, contains('scroll <up|down|left|right> <x> <y>'));
    expect(driveCli, contains('find <locator>'));
    expect(driveCli, contains('wait <locator>'));
    expect(driveCli, contains('DriverLocator.byText(value)'));
    expect(skill, contains('`ValueKey<String>`'));
    expect(skill, contains('exact and case-sensitive'));
    expect(skill, contains('fail instead of auto-scrolling'));
    expect(skill, contains('find key increment'));
    expect(skill, contains('Select<String>'));
    expect(skill, contains('own visible pointer route'));
    expect(skill, contains('painted capture rows'));
    expect(exampleGuide, contains('find key increment'));
    expect(exampleGuide, contains('Select<String>'));
    expect(exampleGuide, contains('tree 10'));
    expect(driveCli, contains("argument == '--size'"));
    expect(skill, contains('`--size 80x24`'));

    expect(designGuide, contains('0 / 1 / 2'));
    expect(
      designGuide,
      contains('EdgeInsets(left: 2, top: 1, right: 2, bottom: 1)'),
    );
    expect(
      designGuide,
      contains('per-side max of `padding` and border thickness'),
    );
    expect(designGuide, contains('Theme.of(context)'));
    expect(designGuide, contains('Use `Panel`'));
    expect(designGuide, isNot(contains('There is no public `Panel`')));
    expect(designGuide, contains('Use `Modal`'));
    expect(designGuide, isNot(contains('There is no public modal')));
    expect(designGuide, contains('80×24'));
    expect(designGuide, contains('8px grid'));
    expect(designGuide, isNot(contains('MaterialApp')));
    expect(designGuide, isNot(contains('border-radius')));

    final listViewSource = _read('lib/src/widgets/list_view.dart');
    expect(
      listViewSource,
      contains(
        'Widget Function(BuildContext context, int index, bool selected)',
      ),
    );
    expect(
      inputsGuide,
      contains(
        'Widget Function(BuildContext context, int index, bool selected)',
      ),
    );
    expect(inputsGuide, contains('itemBuilder: (context, index, selected)'));
    expect(
      inputsGuide,
      isNot(contains('itemBuilder: (context, index) =>')),
      reason: 'the builder takes selected; a 2-arg copy does not compile',
    );

    final switchSource = _read('lib/src/widgets/switch.dart');
    expect(switchSource, contains('Falls back to [ThemeData.success]'));
    expect(switchSource, contains('widget.activeColor ?? theme.success'));
    expect(
      inputsGuide,
      contains('this.activeColor,                     // ThemeData.success'),
    );
    expect(
      inputsGuide,
      isNot(
        contains('this.activeColor,                     // ThemeData.accent'),
      ),
      reason: 'Switch.on uses ThemeData.success, not accent',
    );
  });

  test('shipped example guidance uses supported package imports', () {
    final inspectorSource = _read('lib/src/framework/diagnostics.dart');
    final lowLevel = _read('lib/noir_low_level.dart');
    final inspectorEvidence = '$inspectorSource\n$lowLevel\n$exampleGuide';
    expect(
      inspectorEvidence,
      matches(
        RegExp(
          r"^(?=[\s\S]*static final WidgetInspectorService instance)(?=[\s\S]*List<String> describeTree\()(?=[\s\S]*show WidgetInspectorService, describeIdentity)(?=[\s\S]*import 'package:noir/noir_low_level\.dart';)(?=[\s\S]*WidgetInspectorService\.instance\.describeTree\(\))",
        ),
      ),
    );
    expect(
      exampleGuide,
      isNot(
        matches(
          RegExp(r'test/|scripts/|\.context/|AGENTS\.md|CLAUDE\.md|tasks/'),
        ),
      ),
    );

    final imports = <String>{};
    for (final file in Directory('example').listSync().whereType<File>().where(
      (file) => file.path.endsWith('.dart'),
    )) {
      for (final match in RegExp(
        '''^import ['"](package:noir/[^'"]+)['"];''',
        multiLine: true,
      ).allMatches(file.readAsStringSync())) {
        imports.add(match.group(1)!);
      }
    }
    expect(
      imports,
      unorderedEquals(<String>{
        'package:noir/noir.dart',
        'package:noir/noir_low_level.dart',
        'package:noir/noir_ffi.dart',
      }),
    );
  });
}

String _normalized(String source) => source.replaceAll(RegExp(r'\s+'), ' ');

String _normalizeLineEndings(String source) =>
    source.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _changelogSection(String changelog, String version) {
  final header = '## $version';
  final start = changelog.indexOf(header);
  if (start < 0) return '';
  final rest = changelog.substring(start);
  final next = RegExp(r'\n## ').firstMatch(rest);
  final section = next == null ? rest : rest.substring(0, next.start);
  return section.trimRight();
}

// Exact upstream body from Yoga's v3.2.1 tag. Inline so the packaged notice
// cannot drift from the dependency that OpenTUI compiles into its binaries.
const _yogaV321License =
    'MIT License\n'
    '\n'
    'Copyright (c) Facebook, Inc. and its affiliates.\n'
    '\n'
    'Permission is hereby granted, free of charge, to any person obtaining a copy\n'
    'of this software and associated documentation files (the "Software"), to deal\n'
    'in the Software without restriction, including without limitation the rights\n'
    'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n'
    'copies of the Software, and to permit persons to whom the Software is\n'
    'furnished to do so, subject to the following conditions:\n'
    '\n'
    'The above copyright notice and this permission notice shall be included in all\n'
    'copies or substantial portions of the Software.\n'
    '\n'
    'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n'
    'IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n'
    'FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n'
    'AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n'
    'LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n'
    'OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n'
    'SOFTWARE.\n';

// Exact published bodies from tag v0.0.1-alpha.1. Inline so CI checkouts
// that do not fetch tags cannot rewrite history undetected.
const _publishedAlpha1 = '''
## 0.0.1-alpha.1

- The native-asset build hook now declares `native_manifest.json` and the
  selected bundled library as file-system dependencies. Dart can therefore
  invalidate cached hook output, repeat SHA-256 verification, and regenerate
  the derived macOS bundle copy when either input changes.
- Added focused regression coverage for the hook dependency declarations and
  documented how to suppress routine build-hook status without skipping native
  asset verification.
- Added the Like Reactor example, demonstrating deterministic heart particles,
  animation-driven morphing, and overlapping keyboard and mouse activation.''';

const _publishedAlpha0 = '''
## 0.0.1-alpha.0

- First public alpha of Noir's Flutter-like reactive widget framework for
  terminal applications.
- Declarative stateless and stateful widgets, `setState`, layout, text styling,
  focus, keyboard and mouse input, text editing, scrolling, and animation.
- `Align` positions naturally sized children within bounded boxes while still
  filling bounded axes and shrink-wrapping unbounded axes.
- Hot reload support: `TuiApp.reassemble()` rebuilds every mounted element and
  forces a full layout and paint pass, preserving `State`, focus, scroll, and
  animation state and recreating no terminal or native resource.
- Opt-in `registerHotReloadExtension(app)` publishes the `ext.noir.reassemble`
  VM service extension so a development driver can rebuild a running app after
  `reloadSources`.
- The Flutter-inspired counter example composes a flat blue app bar, centered
  body, and solid square-style clickable action surface. Up/Down, `+`/`-`,
  Enter, Space, and left click drive its state; an unconsumed Ctrl+C key follows
  the terminal session's cleanup and interrupt exit path while higher-priority
  handlers can override it.
- Terminal shutdown restores inherited line and echo modes before cancelling
  the stdin subscription, avoiding Dart/macOS `EBADF` errors during Escape or
  other normal disposal paths.
- Terminal input preserves modifiers from xterm `modifyOtherKeys` reports,
  maps Home/Insert/End and function-key reports to pinned OpenTUI semantics,
  and retains press/repeat/release metadata from Kitty functional and tilde
  reports. The multiline examples use Ctrl+D as a portable submit key while
  `TextArea` still accepts Ctrl+Enter when the terminal reports that chord.
- Bundled, SHA-256-verified OpenTUI native libraries for macOS, Linux, and
  Windows on x64 and arm64.
- Canonical OpenTUI v0.5.1 source and unchanged official release assets.
- macOS bundles require macOS 13.0 or later.
- See
  [Known Limitations](https://github.com/conceptadev/noir#known-limitations)
  for current platform and rendering constraints.''';

String _read(String path) => File(path).readAsStringSync();

String _packageVersion(String pubspec) => RegExp(
  r'^version:\s*(\S+)\s*$',
  multiLine: true,
).firstMatch(pubspec)!.group(1)!;

List<Map<String, Object?>> _manifestAssets() {
  final manifest =
      jsonDecode(File('native_manifest.json').readAsStringSync())
          as Map<String, Object?>;
  final assets = manifest['assets']! as Map<String, Object?>;
  return assets.values.cast<Map<String, Object?>>().toList();
}

Set<String> _pubspecPlatforms(String source) {
  final lines = source.split('\n');
  final start = lines.indexOf('platforms:');
  if (start < 0) return {};
  final platforms = <String>{};
  for (final line in lines.skip(start + 1)) {
    if (line.isNotEmpty && !line.startsWith('  ')) break;
    if (line.isEmpty) continue;
    final match = RegExp(r'^  ([a-z]+):\s*$').firstMatch(line);
    if (match == null) return {'<invalid-platform-entry>'};
    platforms.add(match.group(1)!);
  }
  return platforms;
}

Set<String> _readmeTargetPairs(String source) {
  const osNames = {'macOS': 'macos', 'Linux': 'linux', 'Windows': 'windows'};
  final pairs = <String>{};
  for (final line in source.split('\n')) {
    final row = RegExp(
      r'^\| (macOS|Linux|Windows) \| (.+) \|$',
    ).firstMatch(line);
    if (row == null) continue;
    for (final arch in RegExp('`([^`]+)`').allMatches(row.group(2)!)) {
      pairs.add('${osNames[row.group(1)]}/${arch.group(1)}');
    }
  }
  return pairs;
}
