import 'dart:io';

Future<void> main() async {
  final repositoryRoot = File.fromUri(Platform.script).parent.parent;
  final rootPubignore = File(
    '${repositoryRoot.path}${Platform.pathSeparator}.pubignore',
  );
  if (!rootPubignore.existsSync()) {
    stderr.writeln(
      'Expected ${rootPubignore.path} to exist. Run this script from the Noir '
      'repository checkout.',
    );
    exitCode = 64;
    return;
  }

  final backupDirectory = Directory(
    '${repositoryRoot.path}${Platform.pathSeparator}.dart_tool',
  )..createSync(recursive: true);
  final backup = File(
    '${backupDirectory.path}${Platform.pathSeparator}'
    'noir_hooks_root.pubignore',
  );
  if (backup.existsSync()) {
    stderr.writeln(
      'Refusing to overwrite the existing validation backup at ${backup.path}.',
    );
    exitCode = 73;
    return;
  }

  // The root package excludes /packages/ from its own archive. Pub reads
  // ignore files from the Git repository root even when publishing a nested
  // workspace member, so temporarily remove only that ancestor ignore file.
  rootPubignore.renameSync(backup.path);
  try {
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>['pub', '-C', 'packages/noir_hooks', 'publish', '--dry-run'],
      workingDirectory: repositoryRoot.path,
      mode: ProcessStartMode.inheritStdio,
    );
    exitCode = await process.exitCode;
  } finally {
    if (rootPubignore.existsSync()) {
      rootPubignore.deleteSync();
    }
    backup.renameSync(rootPubignore.path);
  }
}
