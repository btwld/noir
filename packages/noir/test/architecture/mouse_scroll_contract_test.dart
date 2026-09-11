import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('wheel API has one direction/magnitude payload without scalar shim', () {
    final shippedSources = <String>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.path),
      'README.md',
      '../../skills/noir/references/inputs-and-focus.md',
    ];
    final combined = shippedSources
        .map((path) => File(path).readAsStringSync())
        .join('\n');

    expect(combined, isNot(contains('scrollDelta')));
    expect(combined, isNot(contains('MouseScrollAxis')));

    final inputSource = File('lib/src/core/input.dart').readAsStringSync();
    expect(inputSource, isNot(contains('get axis')));
  });
}
