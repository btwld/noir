@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory sourceRoot;
  late Directory sandbox;

  setUpAll(() async {
    sourceRoot = Directory.current.absolute;
    final fixture = Directory(
      path.join(sourceRoot.path, 'test', 'fixtures', 'source_package_consumer'),
    );
    expect(fixture.existsSync(), isTrue);

    sandbox = Directory.systemTemp.createTempSync('noir_source_consumer.');
    _copyDirectory(fixture, sandbox);

    final pubspec = File(path.join(sandbox.path, 'pubspec.yaml'));
    final fixtureManifest = pubspec.readAsStringSync();
    expect(fixtureManifest, contains('path: ../../..'));
    pubspec.writeAsStringSync(
      fixtureManifest.replaceFirst(
        'path: ../../..',
        'path: ${jsonEncode(sourceRoot.path)}',
      ),
    );

    final resolution = await Process.run(Platform.resolvedExecutable, <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: sandbox.path);
    expect(
      resolution.exitCode,
      0,
      reason:
          'source consumer dependency resolution failed\n'
          'stdout:\n${resolution.stdout}\n'
          'stderr:\n${resolution.stderr}',
    );
  });

  tearDownAll(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  test('retained fixture and package resolution are exact', () {
    final retainedFiles =
        Directory(
              path.join(
                sourceRoot.path,
                'test',
                'fixtures',
                'source_package_consumer',
              ),
            )
            .listSync(recursive: true)
            .whereType<File>()
            .map(
              (file) => path
                  .relative(
                    file.path,
                    from: path.join(
                      sourceRoot.path,
                      'test',
                      'fixtures',
                      'source_package_consumer',
                    ),
                  )
                  .replaceAll(Platform.pathSeparator, '/'),
            )
            .toSet();
    expect(retainedFiles, _retainedFixtureFiles);

    final packageConfigFile = File(
      path.join(sandbox.path, '.dart_tool', 'package_config.json'),
    );
    final packageConfig =
        jsonDecode(packageConfigFile.readAsStringSync())
            as Map<String, Object?>;
    final packages = (packageConfig['packages']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final noirPackages = packages
        .where((package) => package['name'] == 'noir')
        .toList();
    expect(noirPackages, hasLength(1));
    final resolvedNoirRoot = Directory.fromUri(
      packageConfigFile.uri.resolve(noirPackages.single['rootUri']! as String),
    ).resolveSymbolicLinksSync();
    expect(
      path.equals(resolvedNoirRoot, sourceRoot.resolveSymbolicLinksSync()),
      isTrue,
      reason: 'consumer must resolve noir to the current source repository',
    );

    // A Noir-only application never resolves the optional companion or the
    // Signals engine behind it.
    final resolvedNames = packages
        .map((package) => package['name']! as String)
        .toSet();
    for (final absent in const <String>[
      'noir_signals',
      'signals_core',
      'preact_signals',
    ]) {
      expect(resolvedNames, isNot(contains(absent)), reason: absent);
    }
  });

  test('positive high, high+low, and FFI-only consumers analyze', () async {
    final analysis = await _analyze(sandbox, 'bin');
    expect(
      analysis.exitCode,
      0,
      reason:
          'source consumer analysis failed\n'
          'stdout:\n${analysis.stdout}\n'
          'stderr:\n${analysis.stderr}',
    );
  });

  test(
    'consumer renders and captures a frame from its own directory',
    () async {
      final render = await Process.run(Platform.resolvedExecutable, <String>[
        'run',
        'bin/render.dart',
      ], workingDirectory: sandbox.path);
      expect(
        render.exitCode,
        0,
        reason:
            'source consumer render failed\n'
            'stdout:\n${render.stdout}\n'
            'stderr:\n${render.stderr}',
      );
    },
  );

  test('consumer CLI bundle runs after relocation', () async {
    final officialHashesBefore = _officialNativeHashes(sourceRoot);
    final buildDirectory = Directory(
      path.join(sandbox.path, 'relocatable_build'),
    );
    final build = await Process.run(Platform.resolvedExecutable, <String>[
      'build',
      'cli',
      '-t',
      'bin/render.dart',
      '--output',
      buildDirectory.path,
    ], workingDirectory: sandbox.path);
    expect(
      build.exitCode,
      0,
      reason:
          'source consumer CLI build failed\n'
          'stdout:\n${build.stdout}\n'
          'stderr:\n${build.stderr}',
    );
    expect(_officialNativeHashes(sourceRoot), officialHashesBefore);

    final builtBundle = Directory(path.join(buildDirectory.path, 'bundle'));
    expect(builtBundle.existsSync(), isTrue);
    final bundledLibraries = builtBundle
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              path.basename(file.path).contains('libopentui') ||
              path.basename(file.path) == 'opentui.dll',
        )
        .toList();
    expect(bundledLibraries, isNotEmpty);

    final relocated = Directory.systemTemp.createTempSync(
      'noir_relocated_consumer.',
    );
    try {
      _copyDirectory(builtBundle, relocated);
      final executable = File(
        path.join(
          relocated.path,
          'bin',
          Platform.isWindows ? 'render.exe' : 'render',
        ),
      );
      expect(executable.existsSync(), isTrue);
      if (!Platform.isWindows) {
        final chmod = await Process.run('chmod', <String>[
          'u+x',
          executable.path,
        ]);
        expect(chmod.exitCode, 0, reason: chmod.stderr.toString());
      }

      if (Platform.isMacOS) {
        final installName = await Process.run('otool', <String>[
          '-D',
          path.join(
            relocated.path,
            path.relative(bundledLibraries.single.path, from: builtBundle.path),
          ),
        ]);
        expect(installName.exitCode, 0, reason: installName.stderr.toString());
        expect(installName.stdout, contains('@rpath/lib/'));
        expect(installName.stdout, isNot(contains(sourceRoot.path)));

        final loadCommands = await Process.run('otool', <String>[
          '-l',
          executable.path,
        ]);
        expect(
          loadCommands.exitCode,
          0,
          reason: loadCommands.stderr.toString(),
        );
        expect(loadCommands.stdout, contains('@executable_path/..'));
      }

      final run = await Process.run(
        executable.path,
        const <String>[],
        workingDirectory: relocated.path,
      );
      expect(
        run.exitCode,
        0,
        reason:
            'relocated source consumer bundle failed\n'
            'stdout:\n${run.stdout}\n'
            'stderr:\n${run.stderr}',
      );
    } finally {
      relocated.deleteSync(recursive: true);
    }
    expect(_officialNativeHashes(sourceRoot), officialHashesBefore);
  });

  test('removed names are unreachable one identifier per probe', () async {
    final negativeDirectory = Directory(
      path.join(sandbox.path, 'generated_negative_probes'),
    )..createSync();
    final expectedMarkers = <String, int>{};

    for (final tier in _negativeTiers.entries) {
      for (final identifier in tier.value.identifiers) {
        final fileName = '${tier.key}_$identifier.dart';
        final file = File(path.join(negativeDirectory.path, fileName));
        final source = StringBuffer()
          ..writeln(tier.value.imports)
          ..writeln()
          ..writeln('void main() {')
          ..writeln('  final Object? value = $identifier; // deny:$identifier')
          ..writeln('  value.toString();')
          ..writeln('}');
        final contents = source.toString();
        file.writeAsStringSync(contents);
        expectedMarkers[fileName] =
            contents.split('\n').indexWhere((line) => line.contains('deny:')) +
            1;
      }
    }

    final analysis = await _analyze(sandbox, 'generated_negative_probes');
    expect(analysis.exitCode, isNonZero);
    final output = '${analysis.stdout}\n${analysis.stderr}';
    for (final marker in expectedMarkers.entries) {
      expect(
        RegExp(
          r'\|UNDEFINED_IDENTIFIER\|[^|\n]*' +
              RegExp.escape(marker.key) +
              r'\|' +
              marker.value.toString() +
              r'\|',
        ).hasMatch(output),
        isTrue,
        reason:
            '${marker.key}:${marker.value} must fail with '
            'UNDEFINED_IDENTIFIER.\n$output',
      );
    }
  });

  test('retained-owner package seams fail as internal-use warnings', () async {
    final relativeProbe = path.join('probes', 'internal_seams.dart');
    final probe = File(path.join(sandbox.path, relativeProbe));
    final markers = <String, int>{};
    final lines = probe.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final markerIndex = lines[index].indexOf('// seam:');
      if (markerIndex < 0) continue;
      final marker = lines[index]
          .substring(markerIndex + '// seam:'.length)
          .trim();
      expect(markers.containsKey(marker), isFalse, reason: marker);
      final standaloneMarker = lines[index].trimLeft().startsWith('// seam:');
      markers[marker] = standaloneMarker ? index : index + 1;
    }
    expect(markers.keys, _internalSeamMarkers);

    final analysis = await _analyze(sandbox, relativeProbe);
    expect(analysis.exitCode, isNonZero);
    final output = '${analysis.stdout}\n${analysis.stderr}';
    for (final marker in markers.entries) {
      expect(
        RegExp(
          r'\|INVALID_USE_OF_INTERNAL_MEMBER\|[^|\n]*internal_seams\.dart\|' +
              marker.value.toString() +
              r'\|',
        ).hasMatch(output),
        isTrue,
        reason:
            '${marker.key} at line ${marker.value} must report '
            'INVALID_USE_OF_INTERNAL_MEMBER.\n$output',
      );
    }
  });
}

Future<ProcessResult> _analyze(Directory sandbox, String target) =>
    Process.run(Platform.resolvedExecutable, <String>[
      'analyze',
      '--fatal-infos',
      '--fatal-warnings',
      '--format=machine',
      target,
    ], workingDirectory: sandbox.path);

void _copyDirectory(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = path.relative(entity.path, from: source.path);
    final target = path.join(destination.path, relative);
    switch (entity) {
      case final Directory _:
        Directory(target).createSync(recursive: true);
      case final File file:
        File(target)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(file.readAsBytesSync());
      case final Link _:
        throw StateError('Source consumer fixture cannot contain links');
    }
  }
}

Map<String, String> _officialNativeHashes(Directory sourceRoot) {
  final nativeRoot = Directory(path.join(sourceRoot.path, 'native'));
  return <String, String>{
    for (final file
        in nativeRoot
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => path.basename(file.path).startsWith('libopentui')))
      path.relative(file.path, from: sourceRoot.path): sha256
          .convert(file.readAsBytesSync())
          .toString(),
  };
}

const Set<String> _retainedFixtureFiles = <String>{
  'bin/ffi.dart',
  'bin/high_level.dart',
  'bin/low_level_multi_child.dart',
  'bin/low_level_single_child.dart',
  'bin/render.dart',
  'probes/internal_seams.dart',
  'pubspec.yaml',
};

const Map<String, _NegativeTier> _negativeTiers = <String, _NegativeTier>{
  'high': _NegativeTier(
    imports: "import 'package:noir/noir.dart';",
    identifiers: <String>{
      'TuiBinding',
      'Renderer',
      'Buffer',
      'BuildOwner',
      'Element',
      'FocusAttachment',
      'InputManager',
      'InputPriority',
      'InputSubscription',
      'PaintingContext',
      'PersistentUtf8Text',
      'TextLayoutEngine',
      'TickerScheduler',
      'WidthMethod',
      'TextBuffer',
      'DirectTextAccess',
      'RenderObject',
      'PipelineOwner',
      'OpenTuiBindings',
      'RendererHandle',
      'TextAlignment',
      'TuiDisplayList',
      'OpenTuiCompositor',
    },
  ),
  'high_low': _NegativeTier(
    imports: """
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
""",
    identifiers: <String>{
      'Element',
      'ElementVisitor',
      'FocusAttachment',
      'StatefulElement',
      'StatelessElement',
      'RenderObjectElement',
      'PipelineOwner',
      'PersistentUtf8Text',
      'OpenTuiBindings',
      'RendererHandle',
      'OptimizedBufferHandle',
      'TextBufferHandle',
      'CapabilitiesHandle',
      'TextBuffer',
      'DirectTextAccess',
      'WidthMethod',
      'TextAlignment',
      'TuiDisplayList',
      'TuiDrawCommand',
      'DisplayListEncoder',
      'OpenTuiCompositor',
    },
  ),
  'ffi': _NegativeTier(
    imports: """
import 'dart:ffi';
import 'package:noir/noir_ffi.dart';
""",
    identifiers: <String>{
      'Widget',
      'StatelessWidget',
      'TuiApp',
      'runTuiApp',
      'Renderer',
      'Buffer',
      'RenderObject',
      'PaintingContext',
      'TuiCanvas',
      'BuildOwner',
      'InputManager',
      'TextAlignment',
    },
  ),
};

const Set<String> _internalSeamMarkers = <String>{
  'BuildContext.element',
  'BuildContext.owner',
  'BuildContext.getElementForInheritedWidgetOfExactType',
  'BuildContext.findRenderObject',
  'BuildContext.findAncestorRenderObjectOfType',
  'BuildContext.visitAncestorElements',
  'BuildContext.visitChildElements',
  'Widget.createElement',
  'FocusNode.attach',
  'FocusNode.detach',
  'BuildOwner.pipelineOwner',
  'BuildOwner.scheduleBuild',
  'BuildOwner.test',
  'RenderObject.pipelineOwner',
  'RenderObject.attach',
  'WidgetInspectorService.rootElement',
  'WidgetInspectorService.registerRoot',
  'WidgetInspectorService.unregisterRoot',
  'FocusManager.nodeForElement',
  'Buffer.invalidate',
  'Buffer.handle',
  'Renderer.debugCurrentBuffer',
  'Renderer.handle',
  'Renderer.bindings',
};

final class _NegativeTier {
  const _NegativeTier({required this.imports, required this.identifiers});

  final String imports;
  final Set<String> identifiers;
}
