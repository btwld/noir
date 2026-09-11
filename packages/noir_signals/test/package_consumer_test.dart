@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'helpers/package_paths.dart';

/// Checks that an application outside this Pub workspace can depend on the
/// staged companion artifact and use both public libraries.
///
/// The companion is staged outside the checkout by
/// `packages/noir/tool/stage_companion_package.dart`, so the consumer resolves
/// the same files an application outside this Pub workspace would.
void main() {
  late Directory noir;
  late Directory staged;
  late Directory sandbox;
  late ProcessResult resolution;

  setUpAll(() async {
    noir = noirRoot;

    final workspace = Directory.systemTemp.createTempSync(
      'noir_signals_consumer.',
    );
    addTearDown(() {
      if (workspace.existsSync()) workspace.deleteSync(recursive: true);
    });
    staged = Directory('${workspace.path}/noir_signals');
    sandbox = Directory('${workspace.path}/consumer')
      ..createSync(recursive: true);

    final stage = await Process.run(Platform.resolvedExecutable, <String>[
      'run',
      'tool/stage_companion_package.dart',
      '--output',
      staged.path,
    ], workingDirectory: noir.path);
    expect(
      stage.exitCode,
      0,
      reason:
          'staging failed\n'
          'stdout:\n${stage.stdout}\n'
          'stderr:\n${stage.stderr}',
    );

    final fixture = Directory(
      '${companionRoot.path}/test/fixtures/package_consumer',
    );
    expect(fixture.existsSync(), isTrue);
    _copyDirectory(fixture, sandbox);

    final pubspec = File('${sandbox.path}/pubspec.yaml');
    final template = pubspec.readAsStringSync();
    expect(template, contains('path: NOIR_PATH'));
    expect(template, contains('path: NOIR_SIGNALS_PATH'));
    pubspec.writeAsStringSync(
      template
          .replaceAll('path: NOIR_PATH', 'path: ${noir.path}')
          .replaceFirst('path: NOIR_SIGNALS_PATH', 'path: ${staged.path}'),
    );

    resolution = await Process.run(Platform.resolvedExecutable, <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: sandbox.path);
  });

  test('an outside consumer resolves the staged companion artifact', () {
    expect(
      resolution.exitCode,
      0,
      reason:
          'companion consumer resolution failed\n'
          'stdout:\n${resolution.stdout}\n'
          'stderr:\n${resolution.stderr}',
    );

    final resolved = _resolvedPackages(sandbox);
    expect(resolved, contains('noir'));
    expect(resolved, contains('noir_signals'));
    expect(resolved, contains('signals_core'));

    // The staged artifact carries no workspace resolution and no test tree.
    final stagedPubspec = File(
      '${staged.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(stagedPubspec, isNot(contains('resolution: workspace')));
    expect(stagedPubspec, contains('noir: ^'));
    expect(File('${staged.path}/lib/noir_signals.dart').existsSync(), isTrue);
    expect(File('${staged.path}/LICENSE').existsSync(), isTrue);
  });

  test('both public libraries analyze in an outside consumer', () async {
    final analysis = await Process.run(Platform.resolvedExecutable, <String>[
      'analyze',
      '--fatal-infos',
      '--fatal-warnings',
      '--format=machine',
      'bin',
    ], workingDirectory: sandbox.path);

    expect(
      analysis.exitCode,
      0,
      reason:
          'companion consumer analysis failed\n'
          'stdout:\n${analysis.stdout}\n'
          'stderr:\n${analysis.stderr}',
    );
  });

  test('a Noir-only consumer resolves no Signals package', () async {
    final noirOnly = Directory('${sandbox.parent.path}/noir_only')
      ..createSync(recursive: true);
    File('${noirOnly.path}/pubspec.yaml').writeAsStringSync(
      'name: noir_only_consumer\n'
      'publish_to: none\n'
      '\n'
      'environment:\n'
      "  sdk: '>=3.10.0 <4.0.0'\n"
      '\n'
      'dependencies:\n'
      '  noir:\n'
      '    path: ${noir.path}\n',
    );

    final result = await Process.run(Platform.resolvedExecutable, <String>[
      'pub',
      'get',
      '--offline',
    ], workingDirectory: noirOnly.path);
    expect(
      result.exitCode,
      0,
      reason:
          'Noir-only consumer resolution failed\n'
          'stdout:\n${result.stdout}\n'
          'stderr:\n${result.stderr}',
    );

    final resolved = _resolvedPackages(noirOnly);
    expect(resolved, contains('noir'));
    for (final absent in <String>[
      'noir_signals',
      'signals_core',
      'preact_signals',
    ]) {
      expect(resolved, isNot(contains(absent)), reason: absent);
    }
  });
}

Set<String> _resolvedPackages(Directory sandbox) {
  final packageConfig =
      jsonDecode(
            File(
              '${sandbox.path}/.dart_tool/package_config.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  return <String>{
    for (final package
        in (packageConfig['packages']! as List<Object?>)
            .cast<Map<String, Object?>>())
      package['name']! as String,
  };
}

void _copyDirectory(Directory source, Directory destination) {
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = entity.path.substring(source.path.length + 1);
    final target = '${destination.path}${Platform.pathSeparator}$relative';
    switch (entity) {
      case final Directory _:
        Directory(target).createSync(recursive: true);
      case final File file:
        File(target)
          ..parent.createSync(recursive: true)
          ..writeAsBytesSync(file.readAsBytesSync());
      case final Link _:
        throw StateError('The consumer fixture cannot contain links');
    }
  }
}
