import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

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
          'Restore the exact tracked binaries and native_manifest.json from '
          'the same repository revision.',
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

    test('manifest deployment metadata matches bundled macOS binaries', () {
      final manifest =
          jsonDecode(File('native_manifest.json').readAsStringSync())
              as Map<String, Object?>;
      final assets = manifest['assets']! as Map<String, Object?>;

      for (final entry in assets.values.cast<Map<String, Object?>>()) {
        if (entry['os'] == 'macos') {
          expect(entry['minimumOsVersion'], '15.0');
          final path = entry['path']! as String;
          expect(
            _readMacOsMinimumVersion(File(path).readAsBytesSync()),
            entry['minimumOsVersion'],
            reason: path,
          );
        } else {
          expect(entry, isNot(contains('minimumOsVersion')));
        }
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
          'Restore the exact binary and manifest pair. A native refresh '
          'requires a separately authorized dependency-strategy decision.',
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

String _readMacOsMinimumVersion(List<int> bytes) {
  const headerSize = 32;
  const machO64LittleEndian = 0xfeedfacf;
  const lcBuildVersion = 0x32;
  const platformMacOs = 1;

  if (bytes.length < headerSize) {
    fail('Truncated 64-bit Mach-O header.');
  }
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  if (data.getUint32(0, Endian.little) != machO64LittleEndian) {
    fail('Expected a thin 64-bit little-endian Mach-O binary.');
  }

  final commandCount = data.getUint32(16, Endian.little);
  final commandBytes = data.getUint32(20, Endian.little);
  final commandsEnd = headerSize + commandBytes;
  if (commandsEnd > bytes.length) {
    fail('Mach-O load-command table is truncated.');
  }

  var offset = headerSize;
  final versions = <int>[];
  for (var index = 0; index < commandCount; index++) {
    if (offset + 8 > commandsEnd) {
      fail('Mach-O load command $index is truncated.');
    }
    final command = data.getUint32(offset, Endian.little);
    final commandSize = data.getUint32(offset + 4, Endian.little);
    if (commandSize < 8 || offset + commandSize > commandsEnd) {
      fail('Mach-O load command $index has invalid size $commandSize.');
    }
    if (command == lcBuildVersion) {
      if (commandSize < 24) {
        fail('LC_BUILD_VERSION is truncated.');
      }
      final platform = data.getUint32(offset + 8, Endian.little);
      if (platform != platformMacOs) {
        fail('LC_BUILD_VERSION targets platform $platform, not macOS.');
      }
      versions.add(data.getUint32(offset + 12, Endian.little));
    }
    offset += commandSize;
  }
  if (offset != commandsEnd) {
    fail('Mach-O load commands do not match sizeofcmds.');
  }
  if (versions.length != 1) {
    fail('Expected exactly one LC_BUILD_VERSION, found ${versions.length}.');
  }

  final encoded = versions.single;
  final major = encoded >> 16;
  final minor = (encoded >> 8) & 0xff;
  final patch = encoded & 0xff;
  return patch == 0 ? '$major.$minor' : '$major.$minor.$patch';
}
