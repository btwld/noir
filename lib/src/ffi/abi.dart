import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'abi_contract.dart';
import 'native_symbols.dart';

export 'abi_contract.dart';

/// Thrown when the loaded OpenTUI native library does not match Dart's ABI.
final class OpenTuiAbiMismatchException implements Exception {
  /// Creates an ABI mismatch exception.
  OpenTuiAbiMismatchException({
    required this.expected,
    required this.found,
    required this.buildInfo,
    this.details,
  });

  /// ABI version required by this Dart package.
  final int expected;

  /// ABI version reported by the native library, or null if unavailable.
  final int? found;

  /// Native build metadata reported by the library.
  final String buildInfo;

  /// Lower-level failure details.
  final String? details;

  @override
  String toString() {
    final foundText = found == null ? 'unavailable' : '$found';
    final detailText = details == null ? '' : '\nDetails: $details';
    return 'OpenTUI native ABI mismatch: expected $expected, '
        'found $foundText. Native build: $buildInfo.$detailText\n'
        'Run a Dart command that invokes hook/build.dart to bundle a matching '
        'libopentui, or set OPENTUI_LIBRARY_PATH to a matching development '
        'build.';
  }
}

/// Validates the native ABI symbols exposed by libopentui.
final class OpenTuiNativeAbi {
  /// Creates an ABI validator for [symbols].
  const OpenTuiNativeAbi(this.symbols);

  /// Native symbols to validate.
  final OpenTuiNativeSymbols symbols;

  /// Throws [OpenTuiAbiMismatchException] if the native ABI is incompatible.
  void validateAbi({int expected = expectedOpenTuiAbiVersion}) {
    int? found;
    var buildInfo = 'unknown';
    try {
      found = symbols.otuiDartAbiVersion();
      buildInfo = _readCString(symbols.otuiDartBuildInfo());
    } catch (error) {
      throw OpenTuiAbiMismatchException(
        expected: expected,
        found: found,
        buildInfo: buildInfo,
        details: 'ABI validation symbols are missing or failed: $error',
      );
    }

    if (found != expected) {
      throw OpenTuiAbiMismatchException(
        expected: expected,
        found: found,
        buildInfo: buildInfo,
      );
    }

    try {
      symbols.resolveRequiredSymbols();
    } catch (error) {
      throw OpenTuiAbiMismatchException(
        expected: expected,
        found: found,
        buildInfo: buildInfo,
        details: 'Required ABI symbols are missing or failed: $error',
      );
    }
  }

  static String _readCString(Pointer<Char> pointer) {
    if (pointer == nullptr) {
      return 'unknown';
    }
    return pointer.cast<Utf8>().toDartString();
  }
}
