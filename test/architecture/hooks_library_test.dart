import 'dart:io';

import 'package:test/test.dart';

void main() {
  final hooksBarrel = File('lib/hooks.dart').readAsStringSync();
  final mainBarrel = File('lib/noir.dart').readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  test('hooks are an opt-in library in the root package', () {
    expect(File('lib/hooks.dart').existsSync(), isTrue);
    expect(Directory('lib/src/hooks').existsSync(), isTrue);
    expect(Directory('packages/noir_hooks').existsSync(), isFalse);
    expect(pubspec, isNot(contains('packages/noir_hooks')));
    expect(mainBarrel, isNot(contains("export 'hooks.dart'")));
  });

  test('hook production code uses only Noir high-level public API', () {
    final sourceFiles = Directory('lib/src/hooks')
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

  test('hooks library exports the framework and built-in hook families', () {
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

  test('hook lifecycle tests reuse the existing element host', () {
    const lifecycleTestNames = <String>{
      'controllers_animation_test.dart',
      'framework_integration_test.dart',
      'framework_primitives_test.dart',
      'listenable_async_test.dart',
      'replacement_lifecycle_test.dart',
    };
    final tests = Directory('test/hooks')
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
        contains("import '../helpers/test_element_host.dart';"),
        reason: file.path,
      );
      expect(source, contains('TestElementHost'), reason: file.path);
    }
  });

  test('root package documentation and publication include hooks', () {
    final readme = File('README.md').readAsStringSync();
    final changelog = File('CHANGELOG.md').readAsStringSync();
    final pubignore = File('.pubignore').readAsStringSync();

    expect(readme, contains("import 'package:noir/hooks.dart';"));
    expect(changelog, contains('package:noir/hooks.dart'));
    expect(pubignore, isNot(contains('/lib/hooks.dart')));
    expect(pubignore, isNot(contains('/lib/src/hooks/')));
  });
}
