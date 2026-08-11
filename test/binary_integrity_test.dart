import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:noir/src/ffi/abi_contract.dart';
import 'package:test/test.dart';

/// Tests to ensure all required platform binaries are present and valid.
///
/// These tests verify that the package includes all necessary OpenTUI
/// native libraries for cross-platform distribution.
void main() {
  group('Binary Integrity', () {
    /// All supported platform targets that should have binaries
    final expectedTargets = [
      ('macos', 'x64', 'libopentui.dylib'),
      ('macos', 'arm64', 'libopentui.dylib'),
      ('linux', 'x64', 'libopentui.so'),
      ('linux', 'arm64', 'libopentui.so'),
      ('windows', 'x64', 'libopentui.dll'),
      ('windows', 'arm64', 'libopentui.dll'),
    ];

    test('all platform binaries exist', () {
      final missingBinaries = <String>[];

      for (final (platform, arch, filename) in expectedTargets) {
        final path = 'native/$platform/$arch/$filename';
        final file = File(path);

        if (!file.existsSync()) {
          missingBinaries.add(path);
        }
      }

      if (missingBinaries.isNotEmpty) {
        fail(
          'Missing required binaries:\n${missingBinaries.join('\n')}\n\n'
          'Run the Phase 8 source build or restore the files recorded in '
          'native_manifest.json.',
        );
      }
    });

    test('all binaries have reasonable sizes', () {
      final problematicBinaries = <String>[];

      for (final (platform, arch, filename) in expectedTargets) {
        final path = 'native/$platform/$arch/$filename';
        final file = File(path);

        if (file.existsSync()) {
          final sizeKB = file.lengthSync() / 1024;

          // Reasonable size bounds (adjust based on actual OpenTUI sizes)
          // - Minimum: 100KB (sanity check for non-empty files)
          // - Maximum: 5MB (detect bloated debug builds)
          if (sizeKB < 100 || sizeKB > 5 * 1024) {
            problematicBinaries.add('$path: ${sizeKB.toStringAsFixed(1)}KB');
          }
        }
      }

      if (problematicBinaries.isNotEmpty) {
        fail(
          'Binaries with unexpected sizes:\n${problematicBinaries.join('\n')}',
        );
      }
    });

    test('native manifest records every bundled binary', () {
      final manifestFile = File('native_manifest.json');
      expect(manifestFile.existsSync(), isTrue);

      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
      expect(manifest['abiVersion'], expectedOpenTuiAbiVersion);
      final assetsObject = manifest['assets'];
      if (assetsObject is! Map<String, Object?>) {
        fail('native_manifest.json assets must be a map');
      }

      for (final (platform, arch, filename) in expectedTargets) {
        final key = '$platform-$arch';
        final entry = assetsObject[key] as Map<String, Object?>?;
        expect(entry, isNotNull, reason: 'Missing manifest entry $key');
        expect(entry!['path'], 'native/$platform/$arch/$filename');
        expect(entry['sha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(entry['url'], startsWith('https://'));
      }
    });

    test('manifest hashes match bundled binaries', () {
      final manifest =
          jsonDecode(File('native_manifest.json').readAsStringSync())
              as Map<String, Object?>;
      final assets = manifest['assets'];
      if (assets is! Map<String, Object?>) {
        fail('native_manifest.json assets must be a map');
      }
      final mismatches = <String>[];

      for (final (platform, arch, _) in expectedTargets) {
        final key = '$platform-$arch';
        final entry = assets[key];
        if (entry is! Map<String, Object?>) {
          fail('Missing manifest entry $key');
        }
        final path = entry['path'];
        final expectedHash = entry['sha256'];
        if (path is! String || expectedHash is! String) {
          fail('Manifest entry $key must contain path and sha256');
        }
        final file = File(path);

        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          final actualHash = sha256.convert(bytes).toString();

          if (actualHash != expectedHash) {
            mismatches.add('$path: expected $expectedHash, got $actualHash');
          }
        }
      }

      if (mismatches.isNotEmpty) {
        fail(
          'Checksum mismatches detected:\n${mismatches.join('\n')}\n\n'
          'Update native_manifest.json after rebuilding native assets.',
        );
      }
    });

    test('manifest binary exists for current platform', () {
      final manifest =
          jsonDecode(File('native_manifest.json').readAsStringSync())
              as Map<String, Object?>;
      final assets = manifest['assets'];
      if (assets is! Map<String, Object?>) {
        fail('native_manifest.json assets must be a map');
      }
      final key = '${_currentPlatform()}-${_currentArch()}';
      final entry = assets[key];
      if (entry is! Map<String, Object?>) {
        fail('Missing manifest entry $key');
      }

      final path = entry['path'];
      if (path is! String) {
        fail('Manifest entry $key must contain a path');
      }
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Manifest library file does not exist: ${file.path}',
      );
    });

    test('current platform binary exports required Dart ABI symbols', () {
      if (Platform.isWindows) {
        markTestSkipped('nm symbol checks are not available on Windows');
        return;
      }

      final binary = File(_currentBinaryPath());
      expect(binary.existsSync(), isTrue);
      final result = Process.runSync(
        'nm',
        Platform.isMacOS
            ? <String>['-gU', binary.path]
            : <String>['-D', '--defined-only', binary.path],
      );
      if (result.exitCode != 0) {
        fail('nm failed for ${binary.path}:\n${result.stderr}');
      }

      final exportedSymbols = _parseExportedSymbolNames(
        '${result.stdout}\n${result.stderr}',
        stripLeadingUnderscore: Platform.isMacOS,
      );
      for (final symbol in requiredOpenTuiNativeSymbolNames) {
        expect(
          exportedSymbols,
          contains(symbol),
          reason: 'Missing exact native export $symbol',
        );
      }
    });

    test('native export parsing uses exact symbol tokens', () {
      final symbols = _parseExportedSymbolNames(
        '00000000 T _createRenderer\n00000010 T _render\n',
        stripLeadingUnderscore: true,
      );

      expect(symbols, containsAll(<String>{'createRenderer', 'render'}));
      expect(symbols, isNot(contains('Renderer')));
      expect(symbols, isNot(contains('create')));
    });

    test('package size is within reasonable bounds', () {
      // Calculate total size of all binaries
      var totalSizeBytes = 0;

      for (final (platform, arch, filename) in expectedTargets) {
        final file = File('native/$platform/$arch/$filename');
        if (file.existsSync()) {
          totalSizeBytes += file.lengthSync();
        }
      }

      final totalSizeMB = totalSizeBytes / (1024 * 1024);

      // Should be under 10MB uncompressed (pub.dev has 100MB limit)
      expect(
        totalSizeMB,
        lessThan(10),
        reason:
            'Total binary size too large: ${totalSizeMB.toStringAsFixed(1)}MB. '
            'Consider stripping debug symbols.',
      );

      // Should be at least 1MB (sanity check)
      expect(
        totalSizeMB,
        greaterThan(1),
        reason:
            'Total binary size suspiciously small: ${totalSizeMB.toStringAsFixed(1)}MB',
      );

      print(
        '✅ Total binary size: ${totalSizeMB.toStringAsFixed(1)}MB '
        '(~${(totalSizeMB * 0.3).toStringAsFixed(1)}MB gzipped)',
      );
    });
  });
}

String _currentPlatform() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

String _currentArch() => switch (Abi.current()) {
  Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
  Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
  final abi => throw UnsupportedError('Unsupported ABI: $abi'),
};

String _currentBinaryPath() {
  final platform = _currentPlatform();
  final arch = _currentArch();
  final filename = switch (platform) {
    'macos' => 'libopentui.dylib',
    'linux' => 'libopentui.so',
    'windows' => 'libopentui.dll',
    _ => throw UnsupportedError('Unsupported platform: $platform'),
  };
  return 'native/$platform/$arch/$filename';
}

Set<String> _parseExportedSymbolNames(
  String output, {
  required bool stripLeadingUnderscore,
}) => output
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .map((line) => line.split(RegExp(r'\s+')).last)
    .map(
      (name) => stripLeadingUnderscore && name.startsWith('_')
          ? name.substring(1)
          : name,
    )
    .toSet();
