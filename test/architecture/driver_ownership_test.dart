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

  test('the hot-reload runner is packaged but remains framework-owned', () {
    final command = File('bin/run.dart');
    final implementation = File('lib/src/devtools/hot_reload_runner.dart');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final dependencies = pubspec.substring(
      pubspec.indexOf('dependencies:'),
      pubspec.indexOf('dev_dependencies:'),
    );
    final devDependencies = pubspec.substring(
      pubspec.indexOf('dev_dependencies:'),
    );

    expect(command.existsSync(), isTrue);
    expect(command.readAsStringSync(), contains('runWithHotReload'));
    expect(implementation.existsSync(), isTrue);
    expect(
      implementation.readAsStringSync(),
      contains('package:vm_service/vm_service.dart'),
    );
    expect(dependencies, contains('vm_service:'));
    expect(devDependencies, isNot(contains('vm_service:')));
    expect(File('scripts/hot_reload_driver.dart').existsSync(), isFalse);

    for (final barrel in const <String>[
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
    ]) {
      final source = File(barrel).readAsStringSync();
      expect(source, isNot(contains('hot_reload_runner.dart')), reason: barrel);
      expect(source, isNot(contains('runWithHotReload')), reason: barrel);
    }
  });
}
