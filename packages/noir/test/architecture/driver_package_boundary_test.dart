import 'dart:io';

import 'package:test/test.dart';

const _driverRoot = '../noir_driver';

/// The driver client is a separate package so an app never carries a
/// process-control channel in its production dependencies.
///
/// Noir's only tie to it is a dev-dependency, used by the two checkout-only
/// documentation tools under `tool/`, which `.pubignore` keeps out of the
/// archive. Anything stronger than that would put `vm_service`-driven process
/// control on the supported surface, which is what
/// `driver_ownership_test.dart` exists to prevent.
void main() {
  final rootPubspec = File('pubspec.yaml').readAsStringSync();
  final driverPubspec = File('$_driverRoot/pubspec.yaml').readAsStringSync();

  test('the driver client lives in its own package, not in Noir', () {
    expect(Directory('tool/driver').existsSync(), isFalse);
    expect(File('tool/noir_drive.dart').existsSync(), isFalse);
    expect(File('$_driverRoot/lib/noir_driver.dart').existsSync(), isTrue);
    expect(File('$_driverRoot/bin/drive.dart').existsSync(), isTrue);

    for (final barrel in const <String>[
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
    ]) {
      expect(
        File(barrel).readAsStringSync(),
        isNot(contains('noir_driver')),
        reason: barrel,
      );
    }
  });

  test('the repository workspace lists the driver package', () {
    final workspace = File('../../pubspec.yaml').readAsStringSync();

    expect(
      workspace,
      contains(
        'workspace:\n'
        '  - packages/noir\n'
        '  - packages/noir_driver\n'
        '  - packages/muse_noir\n'
        '  - packages/noir_signals',
      ),
    );
    expect(driverPubspec, contains('resolution: workspace'));
    expect(driverPubspec, contains('name: noir_driver'));
    expect(driverPubspec, contains('noir: ^0.0.2'));
  });

  test('Noir depends on the driver for tooling only, never at runtime', () {
    final dependencies = rootPubspec.substring(
      rootPubspec.indexOf('dependencies:'),
      rootPubspec.indexOf('dev_dependencies:'),
    );
    final devDependencies = rootPubspec.substring(
      rootPubspec.indexOf('dev_dependencies:'),
    );

    expect(dependencies, isNot(contains('noir_driver')));
    expect(devDependencies, contains('noir_driver:'));
    expect(File('.pubignore').readAsStringSync(), contains('/tool/'));
  });

  test('no shipped Noir source imports the driver client', () {
    for (final root in const <String>['lib', 'bin', 'hook']) {
      for (final file
          in Directory(root)
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('package:noir_driver')),
          reason: file.path,
        );
      }
    }
  });

  test('the driver package uses only Noir public API', () {
    final sources = Directory('$_driverRoot/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(sources, isNotEmpty);

    for (final file in sources) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:noir/src/')), reason: file.path);
    }
  });
}
