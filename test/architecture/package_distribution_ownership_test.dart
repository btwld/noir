import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final readme = File('README.md').readAsStringSync();
  final skill = _read('skills/noir/SKILL.md');
  final testingGuide = _read('skills/noir/references/testing.md');
  final widgetsGuide = _read('skills/noir/references/widgets.md');
  final inputsGuide = _read('skills/noir/references/inputs-and-focus.md');
  final stateGuide = _read('skills/noir/references/state-and-animation.md');
  final exampleGuide = _read('example/README.md');
  final pubspec = _read('pubspec.yaml');
  final packageVersion = _packageVersion(pubspec);
  final releaseTodo = _read('TODO.md');
  final contributorGuide = _read('AGENTS.md');
  final appSource = _read('lib/src/app/app.dart');
  final highLevelBarrel = _read('lib/noir.dart');
  final lowLevelBarrel = _read('lib/noir_low_level.dart');
  final ffiBarrel = _read('lib/noir_ffi.dart');
  final chatDemo = _read('example/chat_demo.dart');

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

  test('public changelog leads with the current alpha package version', () {
    final changelog = _read('CHANGELOG.md');
    final changelogVersions = RegExp(
      r'^##\s+([^\s]+)\s*$',
      multiLine: true,
    ).allMatches(changelog).map((match) => match.group(1)).toList();

    expect(packageVersion, matches(RegExp(r'^\d+\.\d+\.\d+-[0-9A-Za-z.-]+$')));
    expect(changelogVersions, isNotEmpty);
    expect(changelogVersions.first, packageVersion);
    expect(changelogVersions.toSet(), hasLength(changelogVersions.length));
    expect(changelog, contains('invalidate cached hook output'));
    expect(changelog, contains('Like Reactor'));
    expect(changelog, contains('First public alpha'));
    expect(changelog, isNot(contains('Initial public release')));
    expect(changelog.toLowerCase(), isNot(contains('muse')));
    expect(changelog.toLowerCase(), isNot(contains('pixel')));
  });

  test('live release records derive the package version in one place', () {
    expect(releaseTodo, startsWith('# Release TODO — `$packageVersion`'));
    expect(
      contributorGuide,
      contains('The target is the current core-framework prerelease candidate'),
    );
    expect(contributorGuide, isNot(contains(packageVersion)));
  });

  test(
    'pinned OpenTUI notice accompanies bundled native libraries',
    () {
      final noticeFile = File('THIRD_PARTY_NOTICES.md');
      expect(noticeFile.existsSync(), isTrue);
      final notice = _normalizeLineEndings(noticeFile.readAsStringSync());
      final upstreamLicense = _normalizeLineEndings(
        File('external/opentui/LICENSE').readAsStringSync(),
      );
      final packagedLicense = _normalizeLineEndings(
        File('third_party/opentui-v0.5.1/LICENSE').readAsStringSync(),
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
      ]) {
        expect(notice, contains('third_party/opentui-v0.5.1/$fileName'));
      }
    },
    skip: File('external/opentui/LICENSE').existsSync()
        ? false
        : 'OpenTUI submodule is not materialized in this checkout.',
  );

  test('README gives truthful prerelease install and runnable samples', () {
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
    expect(readme, contains('Noir is currently a prerelease.'));
    expect(
      RegExp(r'^```dart$', multiLine: true).allMatches(readme),
      hasLength(2),
    );
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
      'escape a clipped viewport',
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
    expect(appSource, contains('return TuiApp._(binding);'));
    expect(appSource, contains('TuiApp._(this._binding);'));
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

    final currentAppGuidance = '$readme\n$skill\n$exampleGuide';
    expect(currentAppGuidance, isNot(contains('await runTuiApp')));
    expect(currentAppGuidance, isNot(contains('TuiBinding.instance')));
    expect(currentAppGuidance, isNot(contains('binding.inputManager')));
    expect(
      currentAppGuidance.toLowerCase(),
      isNot(contains('dispose the binding')),
    );
    expect(chatDemo, isNot(contains('detaches State.context before dispose')));
    expect(chatDemo, isNot(contains('..stop();')));
  });

  test('shipped guidance describes the final three API tiers', () {
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
      'advanced hosting, renderer/buffer access, and supported custom render-object protocols',
      'Concrete Element implementations and the recorder/display-list/compositor backend stay framework-owned',
    ]) {
      expect(skillFlat, contains(evidence), reason: evidence);
    }
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
        '--exclude-from=.pubignore',
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

  test('development guidance is excluded while examples stay publishable', () {
    final repositorySkillDocs =
        'skills/noir/SKILL.md skills/noir/references/testing.md skills/noir/references/widgets.md skills/noir/references/inputs-and-focus.md skills/noir/references/state-and-animation.md'
            .split(' ');
    const exampleGuidePath = 'example/README.md';
    final ignored = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--ignored',
      '--exclude-from=.pubignore',
      '--',
      ...repositorySkillDocs,
    ]);
    expect(ignored.exitCode, 0, reason: ignored.stderr as String);
    expect(
      (ignored.stdout as String).trim().split('\n'),
      unorderedEquals(repositorySkillDocs),
    );
    final exampleIgnored = Process.runSync('git', [
      'ls-files',
      '--cached',
      '--others',
      '--ignored',
      '--exclude-from=.pubignore',
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
      'AGENTS.md',
      'CLAUDE.md',
      'GOALS.md',
      'CONTRIBUTING.md',
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
