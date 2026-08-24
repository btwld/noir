import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('drive mode keeps injected input on the parser path', () {
    final source = File('lib/src/app/driver.dart').readAsStringSync();

    expect(source, contains('StdinInputDriver'));
    expect(source, contains('debugFeedBytes'));
    expect(source, isNot(contains('dispatchKey(')));
    expect(source, isNot(contains('dispatchMouse(')));
    expect(source, isNot(contains('dispatchPaste(')));
    expect(source, isNot(contains('ext.noir.driver.query')));
    expect(source, isNot(contains('_queryMethod')));
    expect(
      'developer.registerExtension('.allMatches(source),
      hasLength(7),
      reason: 'the driver must retain exactly its seven existing RPC methods',
    );
  });

  test('driver text extraction stays private and widget APIs stay clean', () {
    final driver = File('lib/src/app/driver.dart').readAsStringSync();
    final widget = File('lib/src/framework/widget.dart').readAsStringSync();
    final text = File('lib/src/widgets/text.dart').readAsStringSync();
    final richText = File('lib/src/widgets/rich_text.dart').readAsStringSync();

    expect(
      File('lib/src/framework/driver_diagnostics.dart').existsSync(),
      isFalse,
    );
    expect(driver, contains('String? _driverTextForWidget(Widget widget)'));
    expect(driver, contains('Text(:final data, :final textSpan)'));
    expect(driver, contains('RichText(:final text)'));
    for (final source in <String>[widget, text, richText]) {
      expect(source, isNot(contains('DriverTextDiagnosticProvider')));
      expect(source, isNot(contains('driverDiagnosticText')));
    }
  });

  test('drive-mode internals are not exported from any barrel', () {
    for (final barrel in const <String>[
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
    ]) {
      final source = File(barrel).readAsStringSync();
      for (final symbol in const <String>[
        'app/driver.dart',
        'DriverHost',
        'DriverCaptureFormat',
        'createDriveModeHost',
      ]) {
        expect(source, isNot(contains(symbol)), reason: '$barrel: $symbol');
      }
    }
  });

  test('strict locator misses teach exact types and source-only text', () {
    final source = File('scripts/driver/driver_tree.dart').readAsStringSync();

    expect(source, contains('runtimeType exactly'));
    expect(source, contains('Text and RichText source, not painted cells'));
    expect(source, contains('Keys in this tree:'));
    expect(source, contains('Types in this tree:'));
    expect(source, contains('No node in this tree has primary focus.'));
    expect(source, contains('Intentionally not an ancestor walk'));
  });

  test('as-built driver guidance rejects leftover locator specs', () {
    const paths = <String>[
      'CONTRIBUTING.md',
      'skills/noir/SKILL.md',
      'example/README.md',
      'lib/src/app/driver.dart',
      'scripts/driver/driver_tree.dart',
      'scripts/driver/noir_driver.dart',
    ];
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('nearest ancestor point')), reason: path);
      expect(source, isNot(contains('diagnostic-provider')), reason: path);
    }

    final contributing = File('CONTRIBUTING.md').readAsStringSync();
    final skill = File('skills/noir/SKILL.md').readAsStringSync();
    final exampleGuide = File('example/README.md').readAsStringSync();
    final client = File('scripts/driver/noir_driver.dart').readAsStringSync();
    final host = File('lib/src/app/driver.dart').readAsStringSync();

    expect(contributing, contains('own visible pointer route'));
    expect(contributing, contains('does not borrow'));
    expect(contributing, contains('tree defaults to depth 2'));
    expect(contributing, contains('painted capture rows'));
    expect(skill, contains('own visible pointer route'));
    expect(skill, contains('fail instead of auto-scrolling'));
    expect(skill, contains('tree defaults to depth 2'));
    expect(skill, contains('painted capture rows'));
    expect(exampleGuide, contains('tree 10'));
    expect(exampleGuide, contains('layout box'));
    expect(client, contains('painted capture rows'));
    expect(client, contains("DriverLocator.byKey('increment')"));
    expect(host, contains('own visible pointer route'));
  });

  test('the driver control channel stays out of the shipped package', () {
    // `vm_service` is a dev dependency. A `lib/` or `bin/` import would make
    // it a runtime dependency of every consumer, which is exactly why the
    // driver client and CLI live under `scripts/`.
    for (final root in const <String>['lib', 'bin']) {
      for (final file
          in Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:vm_service')),
          reason: file.path,
        );
      }
    }
  });
}
