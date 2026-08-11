import 'dart:io';

import 'package:noir/src/ffi/abi_contract.dart';
import 'package:test/test.dart';

void main() {
  test('native assets own bundled runtime loading', () {
    expect(File('hook/build.dart').existsSync(), isTrue);
    expect(File('native_manifest.json').existsSync(), isTrue);
    expect(
      File('lib/src/ffi/native_library_locator.dart').existsSync(),
      isFalse,
    );

    final library = File('lib/src/ffi/library.dart').readAsStringSync();
    expect(library, contains('OPENTUI_LIBRARY_PATH'));
    expect(library, contains('BundledOpenTuiNativeSymbols'));
    expect(library, isNot(contains('NativeLibraryLocator')));
    expect(library, isNot(contains('resolvePackageUriSync')));
    expect(library, isNot(contains('node_modules')));
    expect(library, isNot(contains('.dart_tool')));
    expect(library, isNot(contains('DynamicLibrary.open(libName)')));
  });

  test('runtime bindings use Dart native assets', () {
    final source = File(
      'lib/src/ffi/native_asset_bindings.dart',
    ).readAsStringSync();

    expect(source, contains('@ffi.DefaultAsset'));
    expect(source, contains('package:noir/src/ffi/native_asset_bindings.dart'));
    expect(source, contains('@ffi.Native'));
    expect(source, isNot(contains('DynamicLibrary')));
    expect(source, isNot(contains('_lookup')));
  });

  test('old locator surface is not exported', () {
    final ffiBarrel = File('lib/noir_ffi.dart').readAsStringSync();
    final internals = File(
      'test/architecture/internals_barrel_split_test.dart',
    ).readAsStringSync();

    expect(ffiBarrel, isNot(contains('NativeLibraryLocator')));
    expect(ffiBarrel, isNot(contains('OpenTuiLibraryLoader')));
    expect(internals, isNot(contains('native_library_locator.dart')));
    expect(internals, isNot(contains('NativeLibraryLocator')));
    expect(internals, isNot(contains('OpenTuiLibraryLoader')));
  });

  test('ABI validation runs before renderer creation', () {
    final library = File('lib/src/ffi/library.dart').readAsStringSync();
    final createIndex = library.indexOf('BundledOpenTuiNativeSymbols');
    final validateIndex = library.indexOf('validateAbi');
    expect(createIndex, isNonNegative);
    expect(validateIndex, isNonNegative);
    expect(validateIndex, greaterThan(createIndex));

    final renderer = File('lib/src/core/renderer.dart').readAsStringSync();
    expect(renderer, contains('OpenTuiBindings()'));
    expect(library, contains('OpenTuiNativeAbi(symbols).validateAbi()'));
  });

  test('native symbols are ABI-validated once and cached process-wide', () {
    final library = File('lib/src/ffi/library.dart').readAsStringSync();
    final bindings = File('lib/src/ffi/bindings.dart').readAsStringSync();

    expect(library, contains('static final OpenTuiNativeSymbols'));
    expect(library, contains('_openValidatedForProcess'));
    expect(library, contains('static OpenTuiNativeSymbols open() =>'));
    expect(library, contains('OpenTuiNativeAbi(symbols).validateAbi()'));
    expect(bindings, contains('OpenTuiNativeLibrary.open()'));
  });

  test('renderer dimensions are validated at every Dart boundary', () {
    final renderer = File('lib/src/core/renderer.dart').readAsStringSync();
    final bindings = File('lib/src/ffi/bindings.dart').readAsStringSync();

    final validator = _declarationBody(
      bindings,
      'void validateRendererDimensions(int width, int height)',
    );
    expect(
      RegExp(
        r'@internal\s+void validateRendererDimensions\('
        r'int width, int height\)',
      ).allMatches(bindings),
      hasLength(1),
    );
    expect(validator, contains('if (width <= 0)'));
    expect(validator, contains("ArgumentError.value(width, 'width'"));
    expect(validator, contains('if (height <= 0)'));
    expect(validator, contains("ArgumentError.value(height, 'height'"));
    expect(validator, isNot(contains('_generated')));
    expect(validator, isNot(contains('OpenTuiBindings')));
    expect(validator, isNot(contains('FFIException')));

    _expectTokensInOrder(
      _declarationBody(renderer, 'factory Renderer.create('),
      <String>[
        'validateRendererDimensions(width, height);',
        'final bindings = OpenTuiBindings();',
        'bindings.createRenderer(',
      ],
    );
    _expectTokensInOrder(
      _declarationBody(renderer, 'void resize(int width, int height)'),
      <String>[
        '_checkNotDisposed();',
        'validateRendererDimensions(width, height);',
        '_bindings.resizeRenderer(',
      ],
    );
    _expectTokensInOrder(
      _declarationBody(bindings, 'Pointer<RendererHandle> createRenderer('),
      <String>[
        'validateRendererDimensions(width, height);',
        '_generated.createRenderer(',
      ],
    );
    _expectTokensInOrder(
      _declarationBody(
        bindings,
        'void resizeRenderer(Pointer<RendererHandle> renderer, int width, int height)',
      ),
      <String>[
        'validateRendererDimensions(width, height);',
        '_generated.resizeRenderer(',
      ],
    );
  });

  test('renderer dimension validator stays out of supported barrels', () {
    for (final barrel in <String>[
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
    ]) {
      expect(
        File(barrel).readAsStringSync(),
        isNot(contains('validateRendererDimensions')),
        reason: barrel,
      );
    }
  });

  test('missing native TextBuffer symbols are not exposed by wrappers', () {
    final bindings = File('lib/src/ffi/bindings.dart').readAsStringSync();
    final nativeSymbols = File(
      'lib/src/ffi/native_symbols.dart',
    ).readAsStringSync();

    expect(bindings, isNot(contains('textBufferConcat(')));
    expect(bindings, isNot(contains('textBufferResize(')));
    expect(bindings, isNot(contains('textBufferGetCapacity(')));
    expect(nativeSymbols, isNot(contains('textBufferConcat(')));
    expect(nativeSymbols, isNot(contains('textBufferResize(')));
    expect(nativeSymbols, isNot(contains('textBufferGetCapacity(')));
  });

  test('bundled address table exactly follows the canonical ABI inventory', () {
    final nativeSymbols = File(
      'lib/src/ffi/native_symbols.dart',
    ).readAsStringSync();
    final bundledTargets = RegExp(
      r'Native\.addressOf<.*?>\(\s*bundled\.([A-Za-z_]\w*)\s*,?\s*\)',
      dotAll: true,
    ).allMatches(nativeSymbols).map((match) => match.group(1)!).toList();

    expect(bundledTargets, requiredOpenTuiNativeSymbolNames);
    expect(bundledTargets.toSet(), hasLength(bundledTargets.length));
  });

  test('canonical ABI inventory keeps exactly the guarded exclusions out', () {
    const excludedTextBufferSymbols = <String>{
      'textBufferConcat',
      'textBufferResize',
      'textBufferGetCapacity',
    };

    expect(requiredOpenTuiNativeSymbolNames, hasLength(60));
    expect(requiredOpenTuiNativeSymbolNames.toSet(), hasLength(60));
    for (final symbol in excludedTextBufferSymbols) {
      expect(requiredOpenTuiNativeSymbolNames, isNot(contains(symbol)));
    }
  });

  test(
    'ABI validation resolves addresses without a feature behavior probe',
    () {
      final abi = File('lib/src/ffi/abi.dart').readAsStringSync();

      expect(abi, contains('symbols.resolveRequiredSymbols()'));
      expect(abi, isNot(contains('createTextBuffer(')));
      expect(abi, isNot(contains('calloc')));
      expect(abi, isNot(contains('otuiDartLastError()')));
      expect(abi, isNot(contains('otuiDartClearError()')));
    },
  );

  group('source-level package landing and durable native docs', () {
    test('package landing source stays inside the declared pub boundary', () {
      final readme = File('README.md').readAsStringSync();
      final readmeLower = readme.toLowerCase();
      final quickStart = _exactMarkerSlice(
        readme,
        '## Quick Start',
        '## Example Apps',
      );
      final nativeLibraries = _exactMarkerSlice(
        readme,
        '## Native Libraries',
        '## Known Limitations',
      );
      final quickStartLower = quickStart.toLowerCase();
      final nativeLibrariesLower = nativeLibraries
          .replaceAll(RegExp(r'\s+'), ' ')
          .toLowerCase();
      final headingOffsets = <int>[
        readme.indexOf('## Quick Start'),
        readme.indexOf('## Example Apps'),
        readme.indexOf('## Native Libraries'),
        readme.indexOf('## Known Limitations'),
      ];

      for (var index = 1; index < headingOffsets.length; index += 1) {
        expect(headingOffsets[index], greaterThan(headingOffsets[index - 1]));
      }

      const quickStartClauses = <String>{
        'dart pub add noir',
        'package:noir/noir.dart',
        'runtuiapp',
        'class helloapp extends statelesswidget',
        'class counterapp extends statefulwidget',
        'setstate(() => _count++)',
        '](example/hello.dart)',
        '](example/counter.dart)',
      };
      for (final clause in quickStartClauses) {
        expect(quickStartLower, contains(clause), reason: clause);
      }
      final installIndex = quickStartLower.indexOf('dart pub add noir');
      expect(installIndex, isNonNegative);
      expect(quickStartLower, isNot(contains('example/readme.md')));

      const nativeClauses = <String>{
        'ships bundled native libraries',
        'selects and sha-256 verifies the bundled target',
        'missing',
        'checksum mismatches',
        'incomplete or corrupt package',
        'build fails',
        'immutable provenance for the currently bundled artifacts',
        'not an update instruction',
        'opentui_library_path',
        'exact development override',
        'compatible custom library',
        'not a search path',
        'not a remedy',
      };
      for (final clause in nativeClauses) {
        expect(nativeLibrariesLower, contains(clause), reason: clause);
      }
      expect(nativeLibrariesLower, isNot(contains('download')));
      expect(
        nativeLibrariesLower,
        isNot(contains('refresh the checked-in assets')),
      );

      const rejectedReadmeTokens = <String>{
        'falls back',
        'source build',
        'source-build',
        'scripts/',
        'tasks/',
        'test/',
        'external/',
        'ffigen.md',
        'bin/parity_compare.dart',
        'bin/patch_manager.dart',
        'bin/snapshot_scenes.dart',
        'dart pub get',
        'dart run example/',
        'dart analyze',
        'dart test',
        'update_goldens',
        'go_snapshot_cmd',
        'git submodule update',
        'dart build cli',
        'clone the repo',
        'not yet published',
        'core-framework 1.0',
        'phase 9',
        'p9-',
        'pr closeout',
        'does not claim',
        '## basic framework usage',
        '## testing and goldens',
        '## local go parity',
        '## repo references',
      };
      for (final token in rejectedReadmeTokens) {
        expect(readmeLower, isNot(contains(token)), reason: token);
      }
      expect(
        RegExp(r'^```dart$', multiLine: true).allMatches(readme),
        hasLength(2),
      );

      const developmentRepositoryUrl = 'https://github.com/leoafarias/noir';
      const allowedDevelopmentRepositoryLink =
          '[Development repository](https://github.com/leoafarias/noir)';
      final repositoryUrlCount =
          readme.split(developmentRepositoryUrl).length - 1;
      final allowedRepositoryLinkCount =
          readme.split(allowedDevelopmentRepositoryLink).length - 1;
      expect(allowedRepositoryLinkCount, lessThanOrEqualTo(1));
      expect(repositoryUrlCount, allowedRepositoryLinkCount);

      final pubignoreRules = File('.pubignore')
          .readAsLinesSync()
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty && !line.startsWith('#'))
          .toSet();
      const requiredExcludedRules = <String>{
        '/scripts/',
        'tasks/',
        'test/',
        '/tools/',
        '/external/',
        '/lib/src/tools/',
        'FFIGEN.md',
        'bin/parity_compare.dart',
        'bin/patch_manager.dart',
        'bin/snapshot_scenes.dart',
      };
      const requiredLandingRules = <String>{
        'README.md',
        'CHANGELOG.md',
        'example/main.dart',
        'example/README.md',
      };
      for (final rule in requiredExcludedRules) {
        expect(pubignoreRules, contains(rule), reason: rule);
      }
      for (final rule in requiredLandingRules) {
        expect(pubignoreRules, isNot(contains(rule)), reason: rule);
      }
    });

    test(
      'durable native docs distinguish superseded history from current truth',
      () {
        final phase8 = File(
          'tasks/phase-8-native-assets.md',
        ).readAsStringSync();
        final phase8Goal = _exactMarkerSlice(
          phase8,
          '## Goal',
          '## References',
        ).toLowerCase();
        final phase8Tasks = _exactMarkerSlice(
          phase8,
          '## Tasks (to be decomposed at architect time)',
          '## Hard-rule application',
        ).toLowerCase();
        final phase8Audit = _exactMarkerSlice(
          phase8,
          '## Audit gate',
          '## What landed',
        ).toLowerCase();
        final phase8Landed = _exactMarkerSlice(
          phase8,
          '## What landed',
        ).toLowerCase();
        final phase8HeadingOffsets = <int>[
          phase8.indexOf('## Goal'),
          phase8.indexOf('## References'),
          phase8.indexOf('## Tasks (to be decomposed at architect time)'),
          phase8.indexOf('## Hard-rule application'),
          phase8.indexOf('## Audit gate'),
          phase8.indexOf('## What landed'),
        ];

        for (var index = 1; index < phase8HeadingOffsets.length; index += 1) {
          expect(
            phase8HeadingOffsets[index],
            greaterThan(phase8HeadingOffsets[index - 1]),
          );
        }

        const goalClauses = <String>{
          'bundled-only',
          'codeasset selection',
          'sha-256 verification',
          'exact development override',
          'missing',
          'checksum mismatch',
          'fails loudly',
        };
        for (final clause in goalClauses) {
          expect(phase8Goal, contains(clause), reason: clause);
        }
        expect(phase8Goal, isNot(contains('fallback')));

        final historicalTaskLines = <String>[
          phase8Tasks.split('\n').singleWhere((line) => line.contains('8.4 —')),
          phase8Tasks.split('\n').singleWhere((line) => line.contains('8.5 —')),
        ];
        for (final line in historicalTaskLines) {
          expect(line, contains('historical'));
          expect(line, contains('superseded'));
          expect(line, contains('72657aa'));
        }

        const auditClauses = <String>{
          'bundled codeasset selection',
          'missing',
          'tampered',
          'checksum mismatch',
          'fails loudly',
        };
        for (final clause in auditClauses) {
          expect(phase8Audit, contains(clause), reason: clause);
        }
        expect(
          phase8Audit,
          isNot(
            contains(
              'source-build fallback is exercised when no manifest binary '
              'exists',
            ),
          ),
        );

        const landedClauses = <String>{
          'bundled-only',
          'selects',
          'sha-256',
          'missing',
          'checksum mismatch',
          'fails',
          'provenance-only',
          'maintainers',
          'refresh',
          'opentui_library_path',
          'exact development override',
          '72657aa',
          'superseded',
          'removed',
          'download',
          'source-build fallback',
        };
        for (final clause in landedClauses) {
          expect(phase8Landed, contains(clause), reason: clause);
        }
        final normalizedPhase8Landed = phase8Landed
            .split(RegExp(r'\s+'))
            .join(' ');
        expect(
          normalizedPhase8Landed,
          contains(
            'commit `72657aa` superseded and removed the historical manifest '
            'download and source-build fallback.',
          ),
        );
        for (final historicalToken in <String>{'download', 'source-build'}) {
          expect(
            normalizedPhase8Landed.split(historicalToken),
            hasLength(2),
            reason: historicalToken,
          );
        }

        final deepPlan = File(
          'tasks/reference-implementation-plan.md',
        ).readAsStringSync();
        final nativeReview = _exactMarkerSlice(
          deepPlan,
          '12. Native distribution review',
          '\n---\n\n13. Dart best-practice review',
        ).toLowerCase();
        final phase8Plan = _exactMarkerSlice(
          deepPlan,
          'Phase 8 — Native assets',
          '\n---\n\nPhase 9 — Post-v1 whole-repository review',
        ).toLowerCase();
        expect(nativeReview, isNot(contains('\n---\n')));
        expect(phase8Plan, isNot(contains('\n---\n')));

        const nativeReviewClauses = <String>{
          'bundled-only',
          'sha-256',
          'exact development override',
          'provenance-only',
          'maintainers',
          '72657aa',
          'superseded',
          'removed',
          'download',
          'source-build fallback',
        };
        for (final clause in nativeReviewClauses) {
          expect(nativeReview, contains(clause), reason: clause);
        }
        const rejectedNativeReviewTokens = <String>{
          'current loader searches:',
          'packaged `native/<platform>/<arch>`',
          '- project root',
          '- `node_modules`',
          '- system path',
          'can compile or download native assets',
        };
        for (final token in rejectedNativeReviewTokens) {
          expect(nativeReview, isNot(contains(token)), reason: token);
        }
        expect(
          nativeReview.split('\n').map((line) => line.trim()),
          isNot(contains('- source-build fallback')),
        );

        const phase8PlanClauses = <String>{
          'bundled-only',
          'sha-256',
          'exact development override',
          'missing',
          'checksum mismatch',
          '72657aa',
          'superseded',
          'removed',
          'download',
          'source-build fallback',
        };
        for (final clause in phase8PlanClauses) {
          expect(phase8Plan, contains(clause), reason: clause);
        }
        final phase8PlanLines = phase8Plan
            .split('\n')
            .map((line) => line.trim());
        expect(phase8PlanLines, isNot(contains('- source-build fallback')));
        expect(
          phase8PlanLines,
          isNot(
            contains(
              '- source-build fallback and missing-toolchain failure are '
              'tested.',
            ),
          ),
        );
      },
    );
  });
}

String _exactMarkerSlice(
  String source,
  String startMarker, [
  String? endMarker,
]) {
  final start = source.indexOf(startMarker);
  expect(start, isNonNegative, reason: 'missing start marker: $startMarker');
  expect(
    source.indexOf(startMarker, start + startMarker.length),
    -1,
    reason: 'duplicate start marker: $startMarker',
  );

  if (endMarker == null) {
    return source.substring(start);
  }

  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(end, isNonNegative, reason: 'missing end marker: $endMarker');
  expect(end, greaterThan(start), reason: 'reversed markers: $startMarker');
  expect(
    source.indexOf(endMarker),
    end,
    reason: 'end marker occurs before start or is duplicated: $endMarker',
  );
  expect(
    source.indexOf(endMarker, end + endMarker.length),
    -1,
    reason: 'duplicate end marker after: $startMarker',
  );
  return source.substring(start, end);
}

String _declarationBody(String source, String signature) {
  final signatureStart = source.indexOf(signature);
  expect(
    signatureStart,
    isNonNegative,
    reason: 'missing signature: $signature',
  );
  expect(
    source.indexOf(signature, signatureStart + signature.length),
    -1,
    reason: 'duplicate signature: $signature',
  );

  final parametersStart = source.indexOf('(', signatureStart);
  expect(
    parametersStart,
    isNonNegative,
    reason: 'missing parameters: $signature',
  );
  var parameterDepth = 0;
  var parametersEnd = -1;
  for (var index = parametersStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '(':
        parameterDepth += 1;
      case ')':
        parameterDepth -= 1;
        if (parameterDepth == 0) {
          parametersEnd = index;
          break;
        }
    }
    if (parametersEnd >= 0) {
      break;
    }
  }
  expect(
    parametersEnd,
    isNonNegative,
    reason: 'unclosed parameters: $signature',
  );

  final bodyStart = source.indexOf('{', parametersEnd + 1);
  expect(bodyStart, isNonNegative, reason: 'missing body: $signature');

  var depth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '{':
        depth += 1;
      case '}':
        depth -= 1;
        if (depth == 0) {
          return source.substring(bodyStart, index + 1);
        }
    }
  }

  fail('unclosed body: $signature');
}

void _expectTokensInOrder(String source, List<String> tokens) {
  var previousIndex = -1;
  for (final token in tokens) {
    final index = source.indexOf(token);
    expect(index, isNonNegative, reason: 'missing token: $token');
    expect(
      index,
      greaterThan(previousIndex),
      reason: 'out-of-order token: $token',
    );
    previousIndex = index;
  }
}
