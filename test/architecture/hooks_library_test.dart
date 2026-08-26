import 'dart:io';

import 'package:path/path.dart' as path;
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

    expect(readme, contains('package:noir/hooks.dart'));
    expect(changelog, contains('package:noir/hooks.dart'));
    expect(pubignore, isNot(contains('/lib/hooks.dart')));
    expect(pubignore, isNot(contains('/lib/src/hooks/')));
  });

  test('the Noir skill owns hook guidance as a routed reference', () {
    final skillDirectory = Directory('skills/noir').absolute.uri;
    final canonicalHooksGuide = File.fromUri(
      skillDirectory.resolve('../../doc/hooks.md'),
    );
    final hooksReference = File.fromUri(
      skillDirectory.resolve('references/hooks.md'),
    );
    final skill = File.fromUri(
      skillDirectory.resolve('SKILL.md'),
    ).readAsStringSync();

    expect(canonicalHooksGuide.existsSync(), isTrue);
    expect(hooksReference.existsSync(), isTrue);
    expect(skill, contains('`references/hooks.md`'));
    expect(skill, contains('`../../doc/hooks.md`'));
    expect(skill, isNot(contains('noir-hooks')));

    if (!hooksReference.existsSync()) return;
    final hooks = hooksReference.readAsStringSync();
    final referenceDirectory = Directory('skills/noir/references').absolute.uri;
    for (final path in <String>[
      '../../../doc/hooks.md',
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
    expect(hooks, contains('package:noir/hooks.dart'));
    expect(hooks, contains('Call hooks unconditionally'));
    expect(hooks, contains('input callbacks'));
    expect(hooks, contains('effect'));
    expect(hooks, contains('retained hook state'));
  });

  test('hook guidance uses the existing Noir discovery entry points', () {
    for (final linkPath in <String>[
      '.agents/skills/noir',
      '.claude/skills/noir',
    ]) {
      final link = Link(linkPath);
      expect(link.existsSync(), isTrue, reason: linkPath);
      expect(
        link.targetSync(),
        path.join('..', '..', 'skills', 'noir'),
        reason: linkPath,
      );
    }
    expect(Directory('skills/noir-hooks').existsSync(), isFalse);
    expect(Link('.agents/skills/noir-hooks').existsSync(), isFalse);
    expect(Link('.claude/skills/noir-hooks').existsSync(), isFalse);
  });
}
