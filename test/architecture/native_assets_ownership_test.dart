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

    final library = _read('lib/src/ffi/library.dart');
    expect(library, contains('OPENTUI_LIBRARY_PATH'));
    expect(library, contains('BundledOpenTuiNativeSymbols'));
    expect(library, isNot(contains('NativeLibraryLocator')));
    expect(library, isNot(contains('resolvePackageUriSync')));
    expect(library, isNot(contains('node_modules')));
    expect(library, isNot(contains('.dart_tool')));
    expect(library, isNot(contains('DynamicLibrary.open(libName)')));
  });

  test('runtime bindings use Dart native assets', () {
    final source = _read('lib/src/ffi/native_asset_bindings.dart');

    expect(source, contains('@ffi.DefaultAsset'));
    expect(source, contains('package:noir/src/ffi/native_asset_bindings.dart'));
    expect(source, contains('@ffi.Native'));
    expect(source, isNot(contains('DynamicLibrary')));
    expect(source, isNot(contains('_lookup')));
  });

  test('obsolete locator types stay out of supported surfaces', () {
    final ffiBarrel = _read('lib/noir_ffi.dart');
    final internals = _read(
      'test/architecture/internals_barrel_split_test.dart',
    );

    for (final token in <String>[
      'NativeLibraryLocator',
      'OpenTuiLibraryLoader',
    ]) {
      expect(ffiBarrel, isNot(contains(token)), reason: token);
      expect(internals, isNot(contains(token)), reason: token);
    }
    expect(internals, isNot(contains('native_library_locator.dart')));
  });

  test('ABI validation runs once before renderer creation', () {
    final library = _read('lib/src/ffi/library.dart');
    final bindings = _read('lib/src/ffi/bindings.dart');
    final renderer = _read('lib/src/core/renderer.dart');

    expect(library, contains('static final OpenTuiNativeSymbols'));
    expect(library, contains('_openValidatedForProcess'));
    expect(library, contains('OpenTuiNativeAbi(symbols).validateAbi()'));
    expect(bindings, contains('OpenTuiNativeLibrary.open()'));
    expect(renderer, contains('OpenTuiBindings()'));
  });

  test('renderer dimensions are guarded at every Dart boundary', () {
    final renderer = _read('lib/src/core/renderer.dart');
    final bindings = _read('lib/src/ffi/bindings.dart');
    final validator = _declarationBody(
      bindings,
      'void validateRendererDimensions(int width, int height)',
    );

    expect(validator, contains('if (width <= 0)'));
    expect(validator, contains("ArgumentError.value(width, 'width'"));
    expect(validator, contains('if (height <= 0)'));
    expect(validator, contains("ArgumentError.value(height, 'height'"));
    expect(validator, isNot(contains('_generated')));
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

  test('native symbol inventory is exact and guarded', () {
    final bindings = _read('lib/src/ffi/bindings.dart');
    final nativeSymbols = _read('lib/src/ffi/native_symbols.dart');
    final bundledTargets = RegExp(
      r'Native\.addressOf<.*?>\(\s*bundled\.([A-Za-z_]\w*)\s*,?\s*\)',
      dotAll: true,
    ).allMatches(nativeSymbols).map((match) => match.group(1)!).toList();

    expect(requiredOpenTuiNativeSymbolNames, hasLength(60));
    expect(requiredOpenTuiNativeSymbolNames.toSet(), hasLength(60));
    expect(bundledTargets, requiredOpenTuiNativeSymbolNames);
    expect(bundledTargets.toSet(), hasLength(bundledTargets.length));

    for (final symbol in <String>[
      'textBufferConcat',
      'textBufferResize',
      'textBufferGetCapacity',
    ]) {
      expect(requiredOpenTuiNativeSymbolNames, isNot(contains(symbol)));
      expect(bindings, isNot(contains('$symbol(')));
      expect(nativeSymbols, isNot(contains('$symbol(')));
    }
  });

  test('ABI validation resolves symbols without behavior probes', () {
    final abi = _read('lib/src/ffi/abi.dart');

    expect(abi, contains('symbols.resolveRequiredSymbols()'));
    expect(abi, isNot(contains('createTextBuffer(')));
    expect(abi, isNot(contains('calloc')));
    expect(abi, isNot(contains('otuiDartLastError()')));
    expect(abi, isNot(contains('otuiDartClearError()')));
  });

  test('package landing stays inside the publish boundary', () {
    final readme = _read('README.md');
    final pubignoreRules = _read('.pubignore')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();

    for (final clause in <String>[
      'dart pub add noir:^1.0.0-alpha.1',
      'package:noir/noir.dart',
      'runTuiApp',
      'ships bundled native libraries',
      'SHA-256 verifies the bundled target',
      'immutable provenance',
      'not an update instruction',
      'OPENTUI_LIBRARY_PATH',
      'exact development override',
      'macOS 15.0 or later',
    ]) {
      expect(readme, contains(clause), reason: clause);
    }
    for (final stale in <String>[
      'Phase 8',
      'Phase 9',
      'P9-',
      'PR #',
      'leoafarias/cli_ui',
      'source-build fallback',
    ]) {
      expect(readme, isNot(contains(stale)), reason: stale);
    }

    for (final rule in <String>[
      '.agents/',
      '.claude/',
      '/skills/',
      '/scripts/',
      '/tools/',
      '/external/',
      '/lib/src/tools/',
      'tasks/',
      'test/',
      'FFIGEN.md',
      'ffigen_dynamic.yaml',
      'ffigen_native_assets.yaml',
      'bin/parity_compare.dart',
      'bin/patch_manager.dart',
      'bin/snapshot_scenes.dart',
    ]) {
      expect(pubignoreRules, contains(rule), reason: rule);
    }
    for (final shipped in <String>[
      'README.md',
      'CHANGELOG.md',
      'example/main.dart',
      'example/README.md',
    ]) {
      expect(pubignoreRules, isNot(contains(shipped)), reason: shipped);
    }
  });

  test('durable docs preserve the read-only native boundary', () {
    final docs = <String>[
      _read('AGENTS.md'),
      _read('GOALS.md'),
      _read('tasks/READ_HERE.md'),
      _read('tasks/release-readiness.md'),
    ].join('\n');

    for (final clause in <String>[
      'read-only',
      'external/opentui',
      'native artifacts',
      'separate explicit dependency-strategy decision',
      'exact-cursor restoration',
      'absolute build/debug paths',
    ]) {
      expect(docs, contains(clause), reason: clause);
    }
    expect(docs, isNot(contains('tasks/phase-')));
    expect(docs, isNot(contains('pull request #12')));
  });

  test('binary recovery diagnostics restore matching tracked provenance', () {
    final testSource = _read('test/binary_integrity_test.dart');

    expect(
      testSource,
      contains(
        'Restore the exact tracked binaries and native_manifest.json from ',
      ),
    );
    expect(
      testSource,
      contains('Restore the exact binary and manifest pair. A native refresh '),
    );
    expect(
      testSource,
      contains('separately authorized dependency-strategy decision'),
    );
    expect(testSource, isNot(contains('Run the Phase 8 source build')));
    expect(
      testSource,
      isNot(
        contains('Update native_manifest.json after rebuilding native assets'),
      ),
    );
  });
}

String _read(String path) => File(path).readAsStringSync();

String _declarationBody(String source, String signature) {
  final signatureStart = source.indexOf(signature);
  expect(
    signatureStart,
    isNonNegative,
    reason: 'missing signature: $signature',
  );

  final parametersStart = source.indexOf('(', signatureStart);
  var parameterDepth = 0;
  var parametersEnd = -1;
  for (var index = parametersStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '(':
        parameterDepth += 1;
      case ')':
        parameterDepth -= 1;
        if (parameterDepth == 0) parametersEnd = index;
    }
    if (parametersEnd >= 0) break;
  }

  final bodyStart = source.indexOf('{', parametersEnd + 1);
  expect(bodyStart, isNonNegative, reason: 'missing body: $signature');
  var depth = 0;
  for (var index = bodyStart; index < source.length; index += 1) {
    switch (source[index]) {
      case '{':
        depth += 1;
      case '}':
        depth -= 1;
        if (depth == 0) return source.substring(bodyStart, index + 1);
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
