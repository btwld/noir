@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';

/// The locator diagnostics are the reason these locators are usable.
///
/// A strict miss that only says "0 matches" sends a reader back to `tree 10`
/// to guess. These phrases are the ones that answer the question instead, so
/// they are pinned here rather than left to drift out of the source.
void main() {
  test('strict locator misses teach exact types and source-only text', () {
    final source = File('lib/src/driver_tree.dart').readAsStringSync();

    expect(source, contains('runtimeType exactly'));
    expect(source, contains('Text and RichText source, not painted cells'));
    expect(source, contains('Keys in this tree:'));
    expect(source, contains('Types in this tree:'));
    expect(source, contains('No node in this tree has primary focus.'));
    expect(source, contains('Intentionally not an ancestor walk'));
  });

  test('a narrowed locator names the stage that emptied it', () {
    final source = File('lib/src/driver_tree.dart').readAsStringSync();

    expect(source, contains('No node matches the ancestor'));
    expect(source, contains('is itself ambiguous'));
    expect(source, contains('none is inside'));
    expect(source, contains('is out '));
  });

  test('the client stays off Noir private and low-level surfaces', () {
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      expect(source, isNot(contains('package:noir/src/')), reason: path);
      expect(
        source,
        isNot(contains('package:noir/noir_low_level.dart')),
        reason: path,
      );
      expect(
        source,
        isNot(contains('package:noir/noir_ffi.dart')),
        reason: path,
      );
    }
  });
}
