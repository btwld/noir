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
