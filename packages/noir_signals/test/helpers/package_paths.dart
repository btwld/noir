import 'dart:io';

/// Resolves this package's root and the repository root that owns it.
///
/// Tests read example sources and stage the package by path, so they must not
/// assume the process was started from any one directory. `dart test` from
/// `packages/noir_signals/` and from the repository root both work.
Directory get companionRoot {
  for (
    var directory = Directory.current.absolute;
    ;
    directory = directory.parent
  ) {
    if (_isPackage(directory, 'noir_signals')) {
      return directory;
    }
    final nested = Directory('${directory.path}/packages/noir_signals');
    if (_isPackage(nested, 'noir_signals')) {
      return nested;
    }
    if (directory.parent.path == directory.path) {
      throw StateError(
        'Run the companion tests inside the Noir checkout: no '
        'packages/noir_signals package above ${Directory.current.path}.',
      );
    }
  }
}

/// The repository root, which is also the `noir` package and workspace root.
Directory get repositoryRoot {
  final root = companionRoot.parent.parent;
  if (!_isPackage(root, 'noir')) {
    throw StateError('${root.path} is not the noir package root.');
  }
  return root;
}

/// Resolves [relativePath] against [companionRoot].
File companionFile(String relativePath) =>
    File('${companionRoot.path}/$relativePath');

bool _isPackage(Directory directory, String name) {
  final pubspec = File('${directory.path}/pubspec.yaml');
  return pubspec.existsSync() &&
      pubspec.readAsStringSync().contains('name: $name');
}
