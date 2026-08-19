import 'dart:io';

import 'package:test/test.dart';

void main() {
  final rootPubspec = File('pubspec.yaml').readAsStringSync();
  final hooksPubspec = File(
    'packages/noir_hooks/pubspec.yaml',
  ).readAsStringSync();
  final hooksBarrel = File(
    'packages/noir_hooks/lib/noir_hooks.dart',
  ).readAsStringSync();

  test('noir_hooks is an explicit Dart 3.10 workspace member', () {
    expect(rootPubspec, contains('workspace:\n  - packages/noir_hooks'));
    expect(hooksPubspec, contains('name: noir_hooks'));
    expect(hooksPubspec, contains('resolution: workspace'));
    expect(hooksPubspec, contains("sdk: '>=3.10.0 <4.0.0'"));
    expect(hooksPubspec, contains('noir: ^0.0.1-alpha.1'));
    expect(hooksPubspec, isNot(contains('path: ../..')));
    expect(hooksPubspec, isNot(contains('git:')));
    final analysisOptions = File(
      'packages/noir_hooks/analysis_options.yaml',
    ).readAsStringSync();
    expect(analysisOptions, contains('include: ../../analysis_options.yaml'));
    final packagePubignore = File(
      'packages/noir_hooks/.pubignore',
    ).readAsStringSync();
    expect(packagePubignore, contains('test/'));
    expect(packagePubignore, contains('analysis_options.yaml'));
  });

  test('root noir publication excludes companion workspace packages', () {
    final pubignore = File('.pubignore').readAsStringSync();
    expect(pubignore, contains('/packages/'));
  });

  test('noir_hooks production code uses only Noir high-level public API', () {
    final sourceFiles = Directory('packages/noir_hooks/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in sourceFiles) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:noir/src/')), reason: file.path);
      expect(
        source,
        isNot(contains('package:noir/noir_low_level.dart')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('package:noir/noir_ffi.dart')),
        reason: file.path,
      );
      final noirImports = RegExp(
        r'''import\s+['"](package:noir/[^'"]+)['"]''',
      ).allMatches(source).map((match) => match.group(1)!).toList();
      expect(
        noirImports,
        everyElement('package:noir/noir.dart'),
        reason: file.path,
      );
    }
  });

  test('noir_hooks lifecycle tests reuse the existing element host', () {
    final lifecycleTestNames = <String>{
      'controllers_animation_test.dart',
      'framework_primitives_test.dart',
      'listenable_async_test.dart',
      'replacement_lifecycle_test.dart',
    };
    final lifecycleTests = Directory('packages/noir_hooks/test')
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return lifecycleTestNames.contains(name);
        })
        .toList(growable: false);

    expect(lifecycleTests, hasLength(lifecycleTestNames.length));
    for (final file in lifecycleTests) {
      final source = file.readAsStringSync();
      expect(
        source,
        contains("import '../../../test/helpers/test_element_host.dart';"),
        reason: file.path,
      );
      expect(source, isNot(contains('HookTestHost')), reason: file.path);
      expect(source, contains('TestElementHost'), reason: file.path);
    }
    final sharedHost = File(
      'test/helpers/test_element_host.dart',
    ).readAsStringSync();
    expect(sharedHost, contains('void update(Widget widget)'));
    expect(sharedHost, contains('void pumpBuild()'));
    expect(
      File('packages/noir_hooks/test/support/hook_test_host.dart').existsSync(),
      isFalse,
    );
  });

  test('noir_hooks exports the framework and built-in hook families', () {
    for (final symbol in <String>[
      'HookWidget',
      'HookBuilder',
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
      expect(hooksBarrel, contains(symbol), reason: symbol);
    }
  });

  test('CI formats, analyzes, tests, and dry-runs noir_hooks', () {
    final workflow = File('.github/workflows/ci.yml').readAsStringSync();
    expect(workflow, contains('packages/noir_hooks/lib/'));
    expect(workflow, contains('dart analyze --fatal-infos'));
    expect(
      workflow,
      contains('dart analyze --fatal-infos packages/noir_hooks'),
    );
    expect(
      workflow,
      contains('dart test packages/noir_hooks/test --concurrency=1'),
    );
    expect(
      workflow,
      contains('dart run scripts/validate_noir_hooks_package.dart'),
    );
    final validationScript = File(
      'scripts/validate_noir_hooks_package.dart',
    ).readAsStringSync();
    expect(validationScript, contains('noir_hooks_root.pubignore'));
    expect(validationScript, contains("'publish'"));
    expect(validationScript, contains("'--dry-run'"));
  });
}
