import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

/// Exports Pub's selected bytes locally and validates the extracted package.
/// This prepares files only; it does not provide a rendering harness.
Future<Directory> extractPublishedPackage(
  Directory sourceRoot,
  Directory temporary,
) async {
  final archivePath = path.join(temporary.path, 'noir.tar.gz');
  // Pub owns file selection. This local export mode never uploads; do not
  // replace it with --force/--from-archive or an approximate ignore parser.
  final export = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'publish',
    '--to-archive=$archivePath',
  ], workingDirectory: sourceRoot.path);
  expect(export.exitCode, 0, reason: '${export.stdout}\n${export.stderr}');
  final archiveBytes = File(archivePath).readAsBytesSync();
  final archive = TarDecoder().decodeBytes(
    GZipDecoder().decodeBytes(archiveBytes),
  );
  final files = {
    for (final file in archive.files)
      if (file.isFile) file.name: file,
  };
  expect(
    files.keys,
    containsAll([
      'pubspec.yaml',
      'LICENSE',
      'THIRD_PARTY_NOTICES.md',
      'third_party/opentui-v0.5.1/LICENSE-YOGA',
      'hook/build.dart',
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
      'bin/health_check.dart',
    ]),
  );
  for (final name in files.keys) {
    expect(
      name,
      isNot(
        matches(
          r'^(?:test|scripts|packages|external|website|\.context|\.dart_tool)/',
        ),
      ),
    );
  }
  final manifest =
      jsonDecode(utf8.decode(files['native_manifest.json']!.content))
          as Map<String, Object?>;
  for (final asset in (manifest['assets']! as Map<String, Object?>).values) {
    final entry = asset! as Map<String, Object?>;
    final name = entry['path']! as String;
    expect(sha256.convert(files[name]!.content).toString(), entry['sha256']);
  }

  final extracted = Directory(path.join(temporary.path, 'package'))
    ..createSync();
  for (final file in files.values) {
    final target = path.join(extracted.path, file.name);
    expect(path.isWithin(extracted.path, target), isTrue);
    File(target)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(file.content);
  }
  return extracted;
}
