import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('low-level barrel symbol surface matches final audited baseline', () {
    final baseline = File(
      'test/architecture/baselines/noir_low_level_symbols.txt',
    );
    expect(
      baseline.existsSync(),
      isTrue,
      reason: 'The low-level barrel needs a checked-in phase baseline.',
    );

    final baselineSymbols = baseline
        .readAsLinesSync()
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toSet();
    final currentSymbols = _parseExportedSymbols(
      File('lib/noir_low_level.dart').readAsStringSync(),
    );

    expect(
      currentSymbols.difference(baselineSymbols),
      isEmpty,
      reason:
          'noir_low_level.dart must not grow beyond the final audited '
          'advanced API surface.',
    );
    expect(
      baselineSymbols.difference(currentSymbols),
      isEmpty,
      reason:
          'Update the final audited baseline whenever the advanced API surface '
          'is intentionally reduced.',
    );
  });
}

Set<String> _parseExportedSymbols(String source) {
  final exportPattern = RegExp(
    r"export\s+'([^']+)'\s+show\s*([^;]+);",
    multiLine: true,
    dotAll: true,
  );
  return exportPattern
      .allMatches(source)
      .expand(
        (match) => match
            .group(2)!
            .split(',')
            .map((symbol) => symbol.trim())
            .where((symbol) => symbol.isNotEmpty),
      )
      .toSet();
}
