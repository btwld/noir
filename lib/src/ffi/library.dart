import 'dart:ffi';
import 'dart:io' show File, Platform;

import 'native_symbols.dart';

/// Opens the OpenTUI native symbols.
final class OpenTuiNativeLibrary {
  OpenTuiNativeLibrary._();

  static final OpenTuiNativeSymbols _symbols = _openValidatedForProcess();

  /// Returns ABI-validated native symbols for the bundled asset or dev override.
  static OpenTuiNativeSymbols open() => _symbols;

  static OpenTuiNativeSymbols _openValidatedForProcess() {
    final envPath = Platform.environment['OPENTUI_LIBRARY_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      return _openOverride(envPath);
    }

    return BundledOpenTuiNativeSymbols();
  }

  static OpenTuiNativeSymbols _openOverride(String path) {
    if (!File(path).existsSync()) {
      throw OpenTuiLibraryLoadException(
        'OPENTUI_LIBRARY_PATH points to a file that does not exist: $path',
      );
    }

    try {
      return LookupOpenTuiNativeSymbols(DynamicLibrary.open(path));
    } catch (error) {
      throw OpenTuiLibraryLoadException(
        'Failed to load OPENTUI_LIBRARY_PATH=$path: $error',
      );
    }
  }
}

/// Thrown when the explicit development native-library override cannot load.
final class OpenTuiLibraryLoadException implements Exception {
  /// Creates a library load exception.
  const OpenTuiLibraryLoadException(this.message);

  /// Failure details.
  final String message;

  @override
  String toString() =>
      'Could not load OpenTUI native library.\n'
      '$message\n'
      'Run dart pub get so hook/build.dart can resolve the verified package '
      'asset, or set OPENTUI_LIBRARY_PATH to a matching development build.';
}
