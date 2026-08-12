// ignore_for_file: unreachable_from_main

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:code_assets/code_assets.dart';
import 'package:crypto/crypto.dart';
import 'package:hooks/hooks.dart';

const openTuiNativeAssetName = 'src/ffi/native_asset_bindings.dart';
const _manifestPath = 'native_manifest.json';

Future<void> main(List<String> args) async {
  await build(args, buildOpenTuiNativeAsset);
}

Future<void> buildOpenTuiNativeAsset(
  BuildInput input,
  BuildOutputBuilder output, {
  NativeAssetBuildEnvironment environment = const NativeAssetBuildEnvironment(),
}) async {
  if (!input.config.buildCodeAssets) {
    return;
  }

  final manifest = NativeManifest.fromFile(
    File.fromUri(input.packageRoot.resolve(_manifestPath)),
  );
  final entry = manifest.entryFor(
    input.config.code.targetOS,
    input.config.code.targetArchitecture,
  );
  final library = await resolveNativeAsset(
    packageRoot: input.packageRoot,
    entry: entry,
    environment: environment,
  );

  final isLinkedMacOS =
      input.config.linkingEnabled && input.config.code.targetOS == OS.macOS;
  if (isLinkedMacOS) {
    final bundleReadyLibrary = input.outputDirectoryShared.resolve(
      'macos-${entry.arch}-libopentui.dylib',
    );
    await prepareMacOSBundleLibrary(library, bundleReadyLibrary);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: openTuiNativeAssetName,
        linkMode: DynamicLoadingBundled(),
        file: bundleReadyLibrary,
      ),
    );
    return;
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: openTuiNativeAssetName,
      linkMode: input.config.code.targetOS == OS.macOS
          ? DynamicLoadingSystem(library)
          : DynamicLoadingBundled(),
      file: input.config.code.targetOS == OS.macOS ? null : library,
    ),
  );
}

const _machO64LittleEndianMagic = 0xFEEDFACF;
const _machOHeaderSize = 32;
const _lcSourceVersion = 0x2A;

/// Makes room for Dart's relocatable install-name rewrite in a build copy.
///
/// Canonical OpenTUI v0.5.1 fills the Mach-O load-command area exactly. Dart
/// expands `@rpath/libopentui.dylib` to `@rpath/lib/libopentui.dylib` when it
/// bundles a CLI application, so remove the optional 16-byte source-version
/// command from a hook output copy. The tracked official library remains
/// byte-for-byte unchanged; Dart performs its normal install-name rewrite and
/// ad-hoc signing only on this derivative application asset.
Future<void> prepareMacOSBundleLibrary(Uri source, Uri destination) async {
  final bytes = await File.fromUri(source).readAsBytes();
  final data = ByteData.sublistView(bytes);
  if (bytes.length < _machOHeaderSize ||
      data.getUint32(0, Endian.little) != _machO64LittleEndianMagic) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset must be a thin little-endian Mach-O 64 '
      'library.',
    );
  }

  final commandCount = data.getUint32(16, Endian.little);
  final commandBytes = data.getUint32(20, Endian.little);
  final commandsEnd = _machOHeaderSize + commandBytes;
  if (commandsEnd > bytes.length) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset has truncated load commands.',
    );
  }

  var offset = _machOHeaderSize;
  for (var index = 0; index < commandCount; index++) {
    if (offset + 8 > commandsEnd) {
      throw const NativeAssetBuildException(
        'Official macOS OpenTUI asset has a truncated load command.',
      );
    }
    final command = data.getUint32(offset, Endian.little);
    final size = data.getUint32(offset + 4, Endian.little);
    if (size < 8 || offset + size > commandsEnd) {
      throw const NativeAssetBuildException(
        'Official macOS OpenTUI asset has an invalid load command.',
      );
    }
    if (command == _lcSourceVersion) {
      if (size != 16) {
        throw const NativeAssetBuildException(
          'Official macOS OpenTUI asset has an unexpected '
          'LC_SOURCE_VERSION size.',
        );
      }
      bytes.setRange(offset, commandsEnd - size, bytes, offset + size);
      bytes.fillRange(commandsEnd - size, commandsEnd, 0);
      data
        ..setUint32(16, commandCount - 1, Endian.little)
        ..setUint32(20, commandBytes - size, Endian.little);
      final destinationFile = File.fromUri(destination);
      await destinationFile.parent.create(recursive: true);
      await destinationFile.writeAsBytes(bytes, flush: true);
      return;
    }
    offset += size;
  }
  if (offset != commandsEnd) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset load-command sizes are inconsistent.',
    );
  }
  throw const NativeAssetBuildException(
    'Official macOS OpenTUI asset is missing LC_SOURCE_VERSION padding.',
  );
}

/// Resolves the bundled OpenTUI binary for [entry] and verifies its SHA-256.
///
/// The published package ships prebuilt, SHA-256-verified binaries for every
/// supported target, so the bundled binary is the single supported resolution
/// path. A missing file means a corrupt or unmaterialized checkout rather than
/// a recoverable condition, so it fails loudly.
Future<Uri> resolveNativeAsset({
  required Uri packageRoot,
  required NativeManifestEntry entry,
  NativeAssetBuildEnvironment environment = const NativeAssetBuildEnvironment(),
}) async {
  final bundled = packageRoot.resolve(entry.path);
  if (!environment.fileExists(bundled)) {
    throw NativeAssetBuildException(
      'No bundled OpenTUI binary for ${entry.key} at ${entry.path}. '
      'The package ships prebuilt binaries for all supported targets '
      '(macos/linux/windows on x64/arm64); a missing file indicates a corrupt '
      'or unmaterialized checkout.',
    );
  }
  await environment.verifySha256(bundled, entry.sha256);
  return bundled;
}

final class NativeManifest {
  NativeManifest._({
    required this.schemaVersion,
    required this.repository,
    required this.tag,
    required this.commit,
    required this.assets,
  });

  factory NativeManifest.fromJson(Map<String, Object?> json) {
    final schemaVersion = json['schemaVersion'];
    final repository = json['repository'];
    final tag = json['tag'];
    final commit = json['commit'];
    final assetsJson = json['assets'];
    if (schemaVersion is! int ||
        repository is! String ||
        tag is! String ||
        commit is! String ||
        assetsJson is! Map<String, Object?>) {
      throw const NativeAssetBuildException(
        'native_manifest.json must contain schemaVersion, repository, tag, '
        'commit, and assets.',
      );
    }
    if (schemaVersion != 1) {
      throw NativeAssetBuildException(
        'Unsupported native manifest schema version $schemaVersion.',
      );
    }
    if (repository != 'https://github.com/anomalyco/opentui' ||
        tag != 'v0.5.1' ||
        commit != 'ad9a818d7a9d73f3386e92a445d0feb4b395c69e') {
      throw const NativeAssetBuildException(
        'native_manifest.json must identify canonical OpenTUI v0.5.1.',
      );
    }

    return NativeManifest._(
      schemaVersion: schemaVersion,
      repository: Uri.parse(repository),
      tag: tag,
      commit: commit,
      assets: assetsJson.map((key, value) {
        if (value is! Map<String, Object?>) {
          throw NativeAssetBuildException('Manifest entry $key must be a map.');
        }
        return MapEntry(key, NativeManifestEntry.fromJson(key, value));
      }),
    );
  }

  factory NativeManifest.fromFile(File file) {
    if (!file.existsSync()) {
      throw NativeAssetBuildException('Missing native manifest: ${file.path}');
    }
    return NativeManifest.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  final int schemaVersion;
  final Uri repository;
  final String tag;
  final String commit;
  final Map<String, NativeManifestEntry> assets;

  NativeManifestEntry entryFor(OS os, Architecture architecture) {
    final key = '${_manifestOs(os)}-${_manifestArch(architecture)}';
    final entry = assets[key];
    if (entry == null) {
      throw NativeAssetBuildException(
        'No OpenTUI native asset manifest entry for $key.',
      );
    }
    return entry;
  }
}

final class NativeManifestEntry {
  const NativeManifestEntry({
    required this.key,
    required this.os,
    required this.arch,
    required this.path,
    required this.archiveUrl,
    required this.archiveSha256,
    required this.archiveMember,
    required this.minimumOsVersion,
    required this.minimumGlibcVersion,
    required this.sha256,
  });

  factory NativeManifestEntry.fromJson(String key, Map<String, Object?> json) {
    final os = json['os'];
    final arch = json['arch'];
    final path = json['path'];
    final archiveUrl = json['archiveUrl'];
    final archiveSha256 = json['archiveSha256'];
    final archiveMember = json['archiveMember'];
    final minimumOsVersion = json['minimumOsVersion'];
    final minimumGlibcVersion = json['minimumGlibcVersion'];
    final sha256 = json['sha256'];
    if (os is! String ||
        arch is! String ||
        path is! String ||
        archiveUrl is! String ||
        archiveSha256 is! String ||
        archiveMember is! String ||
        sha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(archiveSha256) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw NativeAssetBuildException('Manifest entry $key is incomplete.');
    }
    if (os == 'macos') {
      if (minimumOsVersion is! String ||
          !RegExp(r'^\d+\.\d+$').hasMatch(minimumOsVersion) ||
          minimumOsVersion != '13.0') {
        throw NativeAssetBuildException(
          'Manifest entry $key must declare minimumOsVersion 13.0.',
        );
      }
    } else if (json.containsKey('minimumOsVersion')) {
      throw NativeAssetBuildException(
        'Manifest entry $key must not declare minimumOsVersion.',
      );
    }
    if (os == 'linux') {
      if (minimumGlibcVersion is! String || minimumGlibcVersion != '2.17') {
        throw NativeAssetBuildException(
          'Manifest entry $key must declare minimumGlibcVersion 2.17.',
        );
      }
    } else if (json.containsKey('minimumGlibcVersion')) {
      throw NativeAssetBuildException(
        'Manifest entry $key must not declare minimumGlibcVersion.',
      );
    }
    final parsedArchiveUrl = Uri.parse(archiveUrl);
    if (parsedArchiveUrl.scheme != 'https') {
      throw NativeAssetBuildException(
        'Manifest entry $key archiveUrl must use HTTPS.',
      );
    }
    if (archiveMember.isEmpty ||
        archiveMember.contains('/') ||
        archiveMember.contains(r'\')) {
      throw NativeAssetBuildException(
        'Manifest entry $key archiveMember must name one root file.',
      );
    }
    return NativeManifestEntry(
      key: key,
      os: os,
      arch: arch,
      path: path,
      archiveUrl: parsedArchiveUrl,
      archiveSha256: archiveSha256,
      archiveMember: archiveMember,
      minimumOsVersion: minimumOsVersion as String?,
      minimumGlibcVersion: minimumGlibcVersion as String?,
      sha256: sha256,
    );
  }

  final String key;
  final String os;
  final String arch;
  final String path;

  /// Immutable official archive containing this bundled library.
  final Uri archiveUrl;
  final String archiveSha256;
  final String archiveMember;
  final String? minimumOsVersion;
  final String? minimumGlibcVersion;
  final String sha256;
}

class NativeAssetBuildEnvironment {
  const NativeAssetBuildEnvironment();

  bool fileExists(Uri uri) => File.fromUri(uri).existsSync();

  Future<void> verifySha256(Uri uri, String expected) async {
    final file = File.fromUri(uri);
    if (!file.existsSync()) {
      throw NativeAssetBuildException('Native binary is missing: ${file.path}');
    }
    final actual = sha256.convert(await file.readAsBytes()).toString();
    if (actual != expected) {
      throw NativeAssetIntegrityException(
        'SHA-256 mismatch for ${file.path}: expected $expected, got $actual.',
      );
    }
  }
}

class NativeAssetBuildException implements Exception {
  const NativeAssetBuildException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NativeAssetIntegrityException extends NativeAssetBuildException {
  const NativeAssetIntegrityException(super.message);
}

String _manifestOs(OS os) {
  if (os == OS.macOS) return 'macos';
  if (os == OS.linux) return 'linux';
  if (os == OS.windows) return 'windows';
  throw NativeAssetBuildException('Unsupported target OS: ${os.name}.');
}

String _manifestArch(Architecture architecture) {
  if (architecture == Architecture.arm64) return 'arm64';
  if (architecture == Architecture.x64) return 'x64';
  throw NativeAssetBuildException(
    'Unsupported target architecture: ${architecture.name}.',
  );
}
