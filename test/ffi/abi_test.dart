import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:noir/src/ffi/abi.dart';
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    _activeLookup = null;
  });

  test('ABI validation accepts a matching fully resolved surface', () {
    final symbols = _FakeSymbols(version: expectedOpenTuiAbiVersion);
    addTearDown(symbols.dispose);

    expect(() => OpenTuiNativeAbi(symbols).validateAbi(), returnsNormally);
    expect(symbols.resolveCount, 1);
    expect(symbols.featureInvocationCount, 0);
  });

  test('ABI mismatch reports expected, found, and build info', () {
    final symbols = _FakeSymbols(version: expectedOpenTuiAbiVersion + 1);
    addTearDown(symbols.dispose);

    expect(
      () => OpenTuiNativeAbi(symbols).validateAbi(),
      throwsA(
        isA<OpenTuiAbiMismatchException>()
            .having(
              (error) => error.expected,
              'expected',
              expectedOpenTuiAbiVersion,
            )
            .having(
              (error) => error.found,
              'found',
              expectedOpenTuiAbiVersion + 1,
            )
            .having((error) => error.buildInfo, 'buildInfo', contains('fake')),
      ),
    );
    expect(symbols.resolveCount, 0);
    expect(symbols.featureInvocationCount, 0);
  });

  test('missing ABI metadata reports a clear failure', () {
    final symbols = _ThrowingMetadataSymbols();
    addTearDown(symbols.dispose);

    expect(
      () => OpenTuiNativeAbi(symbols).validateAbi(),
      throwsA(
        isA<OpenTuiAbiMismatchException>().having(
          (error) => error.details,
          'details',
          allOf(
            contains('ABI validation symbols are missing'),
            contains('otui_dart_abi_version'),
          ),
        ),
      ),
    );
    expect(symbols.resolveCount, 0);
    expect(symbols.featureInvocationCount, 0);
  });

  for (final missingSymbol in <String>[
    'otui_dart_abi_version',
    'otui_dart_build_info',
  ]) {
    test('dynamic validation rejects missing metadata $missingSymbol', () {
      final lookup = _FakeNativeLookup(missingSymbol: missingSymbol);
      addTearDown(lookup.dispose);
      final symbols = LookupOpenTuiNativeSymbols.fromLookup(lookup.call);

      expect(
        () => OpenTuiNativeAbi(symbols).validateAbi(),
        throwsA(
          isA<OpenTuiAbiMismatchException>().having(
            (error) => error.details,
            'details',
            allOf(
              contains('ABI validation symbols are missing'),
              contains(missingSymbol),
            ),
          ),
        ),
      );
      expect(lookup.featureInvocationCount, 0);
    });
  }

  for (final missingSymbol in <String>[
    'otui_dart_last_error',
    'otui_dart_clear_error',
    'createRenderer',
    'bufferDrawText',
    'setCursorPosition',
    'createTextBuffer',
    'setupTerminal',
    'getTerminalCapabilities',
  ]) {
    test('dynamic validation eagerly rejects missing $missingSymbol', () {
      final lookup = _FakeNativeLookup(missingSymbol: missingSymbol);
      addTearDown(lookup.dispose);
      final symbols = LookupOpenTuiNativeSymbols.fromLookup(lookup.call);

      expect(
        () => OpenTuiNativeAbi(symbols).validateAbi(),
        throwsA(
          isA<OpenTuiAbiMismatchException>().having(
            (error) => error.details,
            'details',
            allOf(
              contains('Required ABI symbols are missing'),
              contains(missingSymbol),
            ),
          ),
        ),
      );
      expect(lookup.featureInvocationCount, 0);
    });
  }

  test('dynamic validation resolves every canonical symbol by address', () {
    final lookup = _FakeNativeLookup();
    addTearDown(lookup.dispose);
    final symbols = LookupOpenTuiNativeSymbols.fromLookup(lookup.call);

    expect(() => OpenTuiNativeAbi(symbols).validateAbi(), returnsNormally);
    expect(
      lookup.lookedUpNames.toSet(),
      requiredOpenTuiNativeSymbolNames.toSet(),
    );
    expect(lookup.featureInvocationCount, 0);
  });

  test('bundled validation resolves the complete native asset surface', () {
    final symbols = BundledOpenTuiNativeSymbols();

    expect(() => OpenTuiNativeAbi(symbols).validateAbi(), returnsNormally);
  });

  test('canonical inventory exactly matches guarded binding operations', () {
    final source = File('lib/src/ffi/bindings.dart').readAsStringSync();
    final guardedOperations = RegExp(
      r'_generated\s*\.\s*([A-Za-z_]\w*)',
    ).allMatches(source).map((match) => match.group(1)!).toSet();
    final requiredOperations = requiredOpenTuiNativeSymbolNames
        .where((name) => !name.startsWith('otui_dart_'))
        .toSet();

    expect(requiredOpenTuiNativeSymbolNames, hasLength(60));
    expect(requiredOpenTuiNativeSymbolNames.toSet(), hasLength(60));
    expect(guardedOperations, hasLength(56));
    expect(requiredOperations, guardedOperations);
  });
}

class _FakeSymbols implements OpenTuiNativeSymbols {
  _FakeSymbols({required this.version})
    : _buildInfo = 'fake-build'.toNativeUtf8().cast<Char>();

  final int version;
  final Pointer<Char> _buildInfo;
  int resolveCount = 0;
  int featureInvocationCount = 0;

  @override
  int otuiDartAbiVersion() => version;

  @override
  Pointer<Char> otuiDartBuildInfo() => _buildInfo;

  @override
  void resolveRequiredSymbols() {
    resolveCount++;
  }

  void dispose() {
    calloc.free(_buildInfo);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    featureInvocationCount++;
    return super.noSuchMethod(invocation);
  }
}

final class _ThrowingMetadataSymbols extends _FakeSymbols {
  _ThrowingMetadataSymbols() : super(version: expectedOpenTuiAbiVersion);

  @override
  int otuiDartAbiVersion() {
    throw StateError('missing otui_dart_abi_version');
  }
}

final class _FakeNativeLookup {
  _FakeNativeLookup({this.missingSymbol})
    : _buildInfo = 'fake-lookup-build'.toNativeUtf8().cast<Char>() {
    _activeLookup = this;
  }

  final String? missingSymbol;
  final Pointer<Char> _buildInfo;
  final List<String> lookedUpNames = <String>[];
  int featureInvocationCount = 0;

  Pointer<T> call<T extends NativeType>(String symbolName) {
    lookedUpNames.add(symbolName);
    if (symbolName == missingSymbol) {
      throw ArgumentError('missing $symbolName');
    }
    return switch (symbolName) {
      'otui_dart_abi_version' => Pointer.fromFunction<Uint32 Function()>(
        _fakeAbiVersion,
        0,
      ).cast<T>(),
      'otui_dart_build_info' => Pointer.fromFunction<Pointer<Char> Function()>(
        _fakeBuildInfo,
      ).cast<T>(),
      _ => Pointer.fromFunction<Void Function()>(
        _recordFeatureInvocation,
      ).cast<T>(),
    };
  }

  void dispose() {
    if (identical(_activeLookup, this)) {
      _activeLookup = null;
    }
    calloc.free(_buildInfo);
  }
}

_FakeNativeLookup? _activeLookup;

int _fakeAbiVersion() => expectedOpenTuiAbiVersion;

Pointer<Char> _fakeBuildInfo() => _activeLookup!._buildInfo;

void _recordFeatureInvocation() {
  _activeLookup!.featureInvocationCount++;
}
