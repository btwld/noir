// Verifies the Noir-owned OpenTUI header against the pinned Zig ABI and
// reports which exports remain unbound.
//
//   dart run scripts/verify_opentui_abi.dart            # verify + summary
//   dart run scripts/verify_opentui_abi.dart --missing  # also list unbound
//   dart run scripts/verify_opentui_abi.dart --emit foo # prototypes for `foo*`
//
// Exits non-zero when the header disagrees with the pinned source. The same
// check runs in `test/architecture/opentui_abi_signature_test.dart`; this entry
// point exists so the inventory can be read without running a test suite.

import 'dart:io';

import 'opentui_abi/abi_derivation.dart';

const _zigPath = 'external/opentui/packages/core/src/zig/lib.zig';
const _headerPath = 'native/opentui_v0_5_1.h';

void main(List<String> args) {
  final unmappable = <String>[];
  final zig = parseZigExports(
    File(_zigPath).readAsStringSync(),
    unmappable: unmappable,
  );
  final header = parseCHeader(File(_headerPath).readAsStringSync());
  final totalExports = RegExp(
    '^export fn ',
    multiLine: true,
  ).allMatches(File(_zigPath).readAsStringSync()).length;

  final mismatches = <String>[];
  for (final entry in header.entries) {
    final expected = zig[entry.key];
    if (expected == null) continue;
    if (expected.canonical != entry.value.canonical) {
      mismatches.add(
        '  ${entry.key}\n'
        '      zig    -> ${expected.canonical}\n'
        '      header -> ${entry.value.canonical}',
      );
    }
  }

  stdout
    ..writeln('OpenTUI v0.5.1 ABI')
    ..writeln('  exports in pinned zig : $totalExports')
    ..writeln('  bound in Noir header  : ${header.length}')
    ..writeln('  mechanically derivable: ${zig.length}')
    ..writeln('  need struct typedefs  : ${totalExports - zig.length}')
    ..writeln('  signature mismatches  : ${mismatches.length}');

  if (mismatches.isNotEmpty) {
    stdout
      ..writeln()
      ..writeln('MISMATCH — the header disagrees with the pinned zig:')
      ..writeln(mismatches.join('\n'));
    exitCode = 1;
    return;
  }

  final unbound = zig.keys.where((name) => !header.containsKey(name)).toList()
    ..sort();

  final emitIndex = args.indexOf('--emit');
  if (emitIndex >= 0 && emitIndex + 1 < args.length) {
    final prefix = args[emitIndex + 1];
    stdout
      ..writeln()
      ..writeln('Prototypes for "$prefix" (paste into $_headerPath):');
    for (final name in unbound) {
      if (!name.toLowerCase().startsWith(prefix.toLowerCase())) continue;
      stdout.writeln('  ${renderPrototype(zig[name]!)}');
    }
    return;
  }

  if (args.contains('--missing')) {
    stdout
      ..writeln()
      ..writeln('Unbound but mechanically derivable (${unbound.length}):');
    for (final name in unbound) {
      stdout.writeln('  ${renderPrototype(zig[name]!)}');
    }
    stdout
      ..writeln()
      ..writeln('Need a struct or callback typedef before binding:')
      ..writeln('  ${unmappable.length} declarations across the audio, image,')
      ..writeln('  Yoga, event-bus, and text-buffer subsystems.');
  }
}
