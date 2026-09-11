// Verifies every selected export's prototype against the pinned Zig ABI.
//
// `upstream_opentui_v051_migration_test.dart` checks that each selected symbol
// *exists* in both the pinned Zig source and the Noir header, plus a short
// hand-maintained list of full signatures. Name agreement is not ABI agreement:
// a `u32` transcribed as `i32`, or a dropped pointer `const`, passes a name
// check and corrupts the call. The Dart guards cannot catch it either, since
// they assert the domain the header claims rather than the one Zig declares.
//
// This test derives the expected prototype for every selected symbol from the
// pinned source and compares the ABI-relevant shape.

import 'dart:io';

import 'package:test/test.dart';

import '../../tool/opentui_abi/abi_derivation.dart';
import '../helpers/opentui_v051_contract.dart';

void main() {
  late Map<String, AbiSignature> zigExports;
  late Map<String, AbiSignature> headerPrototypes;

  setUpAll(() {
    zigExports = parseZigExports(
      File('../../external/opentui/packages/core/src/zig/lib.zig').readAsStringSync(),
    );
    headerPrototypes = parseCHeader(
      File('native/opentui_v0_5_1.h').readAsStringSync(),
    );
  });

  test('the derivation covers the pinned Zig source', () {
    // A parser that silently matched nothing would make every assertion below
    // vacuous, so pin that it still reads the bulk of the pinned exports.
    expect(
      zigExports.length,
      greaterThan(250),
      reason: 'expected most of the 315 pinned exports to be derivable',
    );
  });

  test('the header declares exactly the selected symbols', () {
    expect(
      headerPrototypes.keys.toSet(),
      selectedOpenTuiV051Symbols.toSet(),
      reason: 'the header is the gate: it must declare the selection exactly',
    );
  });

  test('every selected prototype matches the pinned Zig ABI', () {
    final mismatches = <String>[];

    for (final symbol in selectedOpenTuiV051Symbols) {
      final expected = zigExports[symbol];
      final actual = headerPrototypes[symbol];

      expect(
        actual,
        isNotNull,
        reason: 'selected symbol $symbol is missing from the header',
      );
      expect(
        expected,
        isNotNull,
        reason:
            'selected symbol $symbol could not be derived from the pinned Zig '
            'source; if it legitimately needs a struct typedef, extend '
            'zigToCTypes rather than dropping the check',
      );

      if (expected!.canonical != actual!.canonical) {
        mismatches.add(
          '$symbol\n'
          '    zig    -> ${expected.canonical}\n'
          '    header -> ${actual.canonical}',
        );
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason:
          'the Noir header disagrees with the pinned Zig ABI. Each entry is a '
          'live calling-convention bug:\n${mismatches.join('\n')}',
    );
  });
}
