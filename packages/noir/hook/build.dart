// ignore_for_file: unreachable_from_main

import 'dart:convert';
import 'dart:io';
import 'dart:math' show min;
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

  final manifestUri = input.packageRoot.resolve(_manifestPath);
  output.dependencies.add(manifestUri);
  final manifest = NativeManifest.fromFile(File.fromUri(manifestUri));
  final entry = manifest.entryFor(
    input.config.code.targetOS,
    input.config.code.targetArchitecture,
  );
  final library = await resolveNativeAsset(
    packageRoot: input.packageRoot,
    entry: entry,
    environment: environment,
  );
  output.dependencies.add(library);

  if (!input.config.linkingEnabled) {
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: openTuiNativeAssetName,
        linkMode: DynamicLoadingSystem(library),
      ),
    );
    return;
  }

  if (input.config.code.targetOS == OS.macOS) {
    // `dart build` derives the bundled install name from this file's basename,
    // so keep the canonical name and separate architectures by directory.
    final bundleReadyLibrary = input.outputDirectoryShared.resolve(
      'macos-${entry.arch}/libopentui.dylib',
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
      linkMode: DynamicLoadingBundled(),
      file: library,
    ),
  );
}

const _machO64LittleEndianMagic = 0xFEEDFACF;
const _machOHeaderSize = 32;
const _lcSegment64 = 0x19;
const _lcIdDylib = 0x0D;
const _lcCodeSignature = 0x1D;
const _lcFunctionStarts = 0x26;
const _lcSourceVersion = 0x2A;
const _dylibCommandSize = 24;
const _linkeditDataCommandSize = 16;
const _sZeroFill = 0x1;
const _sThreadLocalZeroFill = 0x12;

/// Install-name prefix `dart build` gives bundled dylibs.
///
/// Dart sets `@rpath/lib/<basename of the code asset file>` and copies every
/// bundled code asset flat into `bundle/lib/`.
const macOSBundleInstallNamePrefix = '@rpath/lib/';

/// Makes room for Dart's relocatable install-name rewrite in a build copy.
///
/// Canonical OpenTUI v0.5.1 fills the Mach-O load-command area exactly: it was
/// linked without `-headerpad_max_install_names`. When `dart build` bundles a
/// linked application, it rewrites the install name to
/// [macOSBundleInstallNamePrefix] plus the basename of [destination] and then
/// ad-hoc signs the copy. For `libopentui.dylib` that grows `LC_ID_DYLIB` from
/// 48 to 56 bytes. `install_name_tool` also reserves 16 bytes for
/// `LC_CODE_SIGNATURE` when the library has none (the x64 asset).
///
/// So this removes the optional 16-byte `LC_SOURCE_VERSION` command and, when
/// it describes no data, the 16-byte `LC_FUNCTION_STARTS` command from a hook
/// output copy, then verifies the rewrite will fit (see
/// [MacOSInstallNameHeadroom]). The tracked official library remains
/// byte-for-byte unchanged; Dart performs its normal install-name rewrite and
/// ad-hoc signing only on this derivative application asset.
Future<void> prepareMacOSBundleLibrary(Uri source, Uri destination) async {
  final bytes = await File.fromUri(source).readAsBytes();
  stripOptionalMacOSLoadCommands(bytes);

  final headroom = MacOSInstallNameHeadroom.of(
    bytes,
    installName:
        '$macOSBundleInstallNamePrefix${destination.pathSegments.last}',
  );
  if (headroom.margin < 0) {
    throw NativeAssetBuildException(headroom.shortfallMessage);
  }

  final destinationFile = File.fromUri(destination);
  await destinationFile.parent.create(recursive: true);
  await destinationFile.writeAsBytes(bytes, flush: true);
}

/// Removes the load commands [prepareMacOSBundleLibrary] drops, in place.
///
/// `LC_SOURCE_VERSION` is required, as before. `LC_FUNCTION_STARTS` is removed
/// only when its data size is zero, so it describes nothing.
void stripOptionalMacOSLoadCommands(Uint8List bytes) {
  final sourceVersion = _findLoadCommand(bytes, _lcSourceVersion);
  if (sourceVersion == null) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset is missing LC_SOURCE_VERSION padding.',
    );
  }
  if (sourceVersion.size != 16) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset has an unexpected '
      'LC_SOURCE_VERSION size.',
    );
  }
  _removeLoadCommand(bytes, sourceVersion);

  final functionStarts = _findLoadCommand(bytes, _lcFunctionStarts);
  if (functionStarts != null && _describesNoData(bytes, functionStarts)) {
    _removeLoadCommand(bytes, functionStarts);
  }
}

bool _describesNoData(Uint8List bytes, _LoadCommand command) =>
    command.size == _linkeditDataCommandSize &&
    ByteData.sublistView(bytes).getUint32(command.offset + 12, Endian.little) ==
        0;

/// Header space for `dart build`'s install-name rewrite of a Mach-O dylib.
///
/// Mirrors the check in Apple's `install_name_tool` (cctools 1035.1.102,
/// `misc/install_name_tool.c`): the 32-byte header plus the updated load
/// commands, plus 16 bytes reserved for `LC_CODE_SIGNATURE` only when the
/// library has none, must not pass the file offset of the first non-empty,
/// non-zero-fill section.
final class MacOSInstallNameHeadroom {
  const MacOSInstallNameHeadroom._({
    required this.installName,
    required this.requiredBytes,
    required this.availableBytes,
    required this.reservesCodeSignature,
  });

  /// Measures [bytes] as if its install name were set to [installName].
  factory MacOSInstallNameHeadroom.of(
    Uint8List bytes, {
    required String installName,
  }) {
    final data = ByteData.sublistView(bytes);
    final commands = _readLoadCommands(bytes);
    _LoadCommand? id;
    var hasCodeSignature = false;
    final fileOffsets = <int>[];
    for (final command in commands) {
      switch (command.command) {
        case _lcIdDylib:
          id = command;
        case _lcCodeSignature:
          hasCodeSignature = true;
        case _lcSegment64:
          final segment = command.offset;
          final sectionCount = data.getUint32(segment + 64, Endian.little);
          if (sectionCount == 0 &&
              data.getUint64(segment + 48, Endian.little) != 0) {
            fileOffsets.add(data.getUint64(segment + 40, Endian.little));
          }
          for (var index = 0; index < sectionCount; index++) {
            final section = segment + 72 + 80 * index;
            final flags = data.getUint32(section + 64, Endian.little);
            if (data.getUint64(section + 40, Endian.little) != 0 &&
                (flags & _sZeroFill) != _sZeroFill &&
                (flags & _sThreadLocalZeroFill) != _sThreadLocalZeroFill) {
              fileOffsets.add(data.getUint32(section + 48, Endian.little));
            }
          }
      }
    }
    final idCommand = id;
    if (idCommand == null || fileOffsets.isEmpty) {
      throw const NativeAssetBuildException(
        'Official macOS OpenTUI asset must have an LC_ID_DYLIB command and '
        'file-backed sections.',
      );
    }

    final newIdSize = _roundUp(
      _dylibCommandSize + utf8.encode(installName).length + 1,
      8,
    );
    final commandBytes = data.getUint32(20, Endian.little);
    return MacOSInstallNameHeadroom._(
      installName: installName,
      requiredBytes:
          _machOHeaderSize +
          commandBytes -
          idCommand.size +
          newIdSize +
          (hasCodeSignature ? 0 : _linkeditDataCommandSize),
      availableBytes: fileOffsets.reduce(min),
      reservesCodeSignature: !hasCodeSignature,
    );
  }

  /// The install name `dart build` will set.
  final String installName;

  /// Header plus updated load commands, plus any code-signature reserve.
  final int requiredBytes;

  /// File offset of the first section, where load commands must end.
  final int availableBytes;

  /// Whether `install_name_tool` reserves room for a missing signature.
  final bool reservesCodeSignature;

  /// Spare bytes after the rewrite; negative means it will fail.
  int get margin => availableBytes - requiredBytes;

  /// Explains a negative [margin] in place of `install_name_tool`'s error.
  String get shortfallMessage {
    final reserve = reservesCodeSignature
        ? ' (including 16 bytes install_name_tool reserves for '
              'LC_CODE_SIGNATURE)'
        : '';
    return 'macOS OpenTUI asset has no room for the install name '
        '"$installName" that `dart build` sets: it needs $requiredBytes bytes '
        'of Mach-O header and load commands$reserve, but only $availableBytes '
        'are available. The OpenTUI library must be relinked with '
        '-headerpad_max_install_names. '
        'See https://github.com/btwld/noir/issues/139.';
  }
}

final class _LoadCommand {
  const _LoadCommand(this.offset, this.command, this.size);

  final int offset;
  final int command;
  final int size;
}

List<_LoadCommand> _readLoadCommands(Uint8List bytes) {
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

  final commands = <_LoadCommand>[];
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
    commands.add(_LoadCommand(offset, command, size));
    offset += size;
  }
  if (offset != commandsEnd) {
    throw const NativeAssetBuildException(
      'Official macOS OpenTUI asset load-command sizes are inconsistent.',
    );
  }
  return commands;
}

_LoadCommand? _findLoadCommand(Uint8List bytes, int command) {
  for (final candidate in _readLoadCommands(bytes)) {
    if (candidate.command == command) return candidate;
  }
  return null;
}

void _removeLoadCommand(Uint8List bytes, _LoadCommand command) {
  final data = ByteData.sublistView(bytes);
  final commandCount = data.getUint32(16, Endian.little);
  final commandBytes = data.getUint32(20, Endian.little);
  final commandsEnd = _machOHeaderSize + commandBytes;
  bytes.setRange(
    command.offset,
    commandsEnd - command.size,
    bytes,
    command.offset + command.size,
  );
  bytes.fillRange(commandsEnd - command.size, commandsEnd, 0);
  data
    ..setUint32(16, commandCount - 1, Endian.little)
    ..setUint32(20, commandBytes - command.size, Endian.little);
}

int _roundUp(int value, int alignment) =>
    (value + alignment - 1) ~/ alignment * alignment;

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
