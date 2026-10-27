import 'dart:io';
import 'dart:typed_data';

import 'package:noir/src/devtools/source_stamps.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory fixture;
  late File source;
  setUp(() {
    fixture = Directory.systemTemp.createTempSync('noir_source_stamps_');
    source = File(path.join(fixture.path, 'widget.dart'))
      ..writeAsStringSync("String label() => 'before';\n");
  });
  tearDown(() => fixture.deleteSync(recursive: true));

  test('same-size edits preserving mtime still change source identity', () {
    final before = readSourceStamps([fixture]);
    final modified = source.lastModifiedSync();
    source
      ..writeAsStringSync("String label() => 'after!';\n")
      ..setLastModifiedSync(modified);

    final after = readSourceStamps([fixture]);

    expect(after[source.absolute.path]!.modified, modified);
    expect(
      after[source.absolute.path]!.size,
      before[source.absolute.path]!.size,
    );
    expect(after, isNot(before));
  });

  test('unchanged sources retain equal identities across polls', () {
    expect(readSourceStamps([fixture]), readSourceStamps([fixture]));
  });

  for (final failure in <FileSystemException>[
    const PathNotFoundException(
      'lib/removed',
      OSError('directory disappeared', 2),
    ),
    const FileSystemException('recursive listing failed'),
  ]) {
    test('listing failure is retried on a later poll: $failure', () {
      var unavailable = true;
      final root = _ListedDirectory(() {
        if (unavailable) throw failure;
        return fixture.listSync();
      });

      expect(readSourceStamps([root]), isEmpty);
      // A failed root must not prevent the other watched roots being scanned.
      expect(readSourceStamps([root, fixture]).keys, [source.absolute.path]);

      unavailable = false;
      expect(readSourceStamps([root]), readSourceStamps([fixture]));
    });
  }

  test('source additions and removals remain observable', () {
    final before = readSourceStamps([fixture]);
    final nested = File(path.join(fixture.path, 'lib', 'new.dart'));
    nested.parent.createSync();
    nested.writeAsStringSync('void main() {}');
    File(
      path.join(fixture.path, 'ignored.txt'),
    ).writeAsStringSync('not a source');

    final added = readSourceStamps([fixture]);
    expect(
      added.keys,
      containsAll([source.absolute.path, nested.absolute.path]),
    );
    expect(added, hasLength(2));
    nested.deleteSync();
    expect(readSourceStamps([fixture]), before);
  });

  test('a listed source may disappear and return on a later scan', () {
    final before = readSourceStamps([fixture]);
    final listedThenRemoved = _ListedDirectory(() {
      final entries = fixture.listSync();
      source.deleteSync();
      return entries;
    });

    expect(readSourceStamps([listedThenRemoved]), isEmpty);

    source.writeAsStringSync("String label() => 'replacement';\n");
    final after = readSourceStamps([fixture]);
    expect(after.keys, [source.absolute.path]);
    expect(
      after[source.absolute.path]!.digest,
      isNot(before[source.absolute.path]!.digest),
    );
  });

  test('a source removed between its read and stat is absent', () {
    final removedAfterRead = _ReadInterceptedFile(source, () {
      final bytes = source.readAsBytesSync();
      source.deleteSync();
      return bytes;
    });

    expect(
      readSourceStamps([
        _ListedDirectory(() => [removedAfterRead]),
      ]),
      isEmpty,
    );
  });

  test('an unrelated source read failure keeps its original identity', () {
    final failure = FileSystemException('unreadable source', source.path);
    final unreadable = _ReadInterceptedFile(source, () => throw failure);

    expect(
      () => readSourceStamps([
        _ListedDirectory(() => [unreadable]),
      ]),
      throwsA(same(failure)),
    );
    expect(source.existsSync(), isTrue);
  });
}

class _ListedDirectory implements Directory {
  _ListedDirectory(this.entries);

  final List<FileSystemEntity> Function() entries;

  @override
  bool existsSync() => true;

  @override
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => entries();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadInterceptedFile implements File {
  _ReadInterceptedFile(this.source, this.read);

  final File source;
  final Uint8List Function() read;

  @override
  String get path => source.path;

  @override
  File get absolute => source.absolute;

  @override
  Uint8List readAsBytesSync() => read();

  @override
  FileStat statSync() => source.statSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
