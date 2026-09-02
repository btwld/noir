import 'dart:convert';

import 'package:test/test.dart';

import '../../scripts/patch_manager/git_repository.dart' show GitCommandRunner;
import '../../scripts/patch_manager/patch_manager.dart';
import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('GitPath', () {
    test('owns exact bytes and derives stable byte identity', () {
      final source = <int>[0x66, 0x6f, 0x6f, 0x2f, 0xff];
      final path = GitPath.fromBytes(source);
      source[0] = 0x62;

      expect(path.bytes, [0x66, 0x6f, 0x6f, 0x2f, 0xff]);
      expect(path, GitPath.fromBytes([0x66, 0x6f, 0x6f, 0x2f, 0xff]));
      expect(path.hashCode, GitPath.fromBytes(path.bytes).hashCode);
      expect(path.identityKey, 'Zm9vL_8');
      expect(path.tryDecodeUtf8(), isNull);
      expect(identical(path.bytes, path.bytes), isFalse);
      expect(() => path.bytes[0] = 0, throwsUnsupportedError);

      final utf8Path = GitPath.utf8('café.txt');
      expect(utf8Path.tryDecodeUtf8(), 'café.txt');
      expect(utf8Path.bytes, utf8.encode('café.txt'));
    });

    test('rejects every invalid repository-relative shape', () {
      final invalid = <List<int>>[
        const [],
        const [0],
        const [0x2f, 0x61],
        const [0x61, 0x2f],
        const [0x61, 0x2f, 0x2f, 0x62],
        const [0x2e],
        const [0x2e, 0x2e],
        const [0x61, 0x2f, 0x2e],
        const [0x61, 0x2f, 0x2e, 0x2e, 0x2f, 0x62],
      ];
      for (final bytes in invalid) {
        expect(
          () => GitPath.fromBytes(bytes),
          throwsArgumentError,
          reason: '$bytes',
        );
      }
      expect(() => GitPath.fromBytes([-1]), throwsRangeError);
      expect(() => GitPath.fromBytes([256]), throwsRangeError);
      expect(
        () => GitPath.utf8(String.fromCharCode(0xd800)),
        throwsArgumentError,
      );
    });

    test('orders identities lexicographically by unsigned bytes', () {
      final paths = [
        GitPath.fromBytes([0x62]),
        GitPath.fromBytes([0x61, 0xff]),
        GitPath.fromBytes([0x61]),
        GitPath.fromBytes([0x61, 0x00 + 1]),
      ]..sort(compareGitPaths);

      expect(paths.map((path) => path.bytes), [
        [0x61],
        [0x61, 0x01],
        [0x61, 0xff],
        [0x62],
      ]);
    });
  });

  group('GitPathPresentation', () {
    test('is reversible printable ASCII with component-aware escaping', () {
      final path = GitPath.fromBytes([
        0x20,
        0x61,
        0x22,
        0x5c,
        0x20,
        0x2f,
        0x80,
        0x7f,
        0x09,
      ]);
      final presentation = GitPathPresentation.asciiSafe(path);

      expect(presentation.full, r'\x20a\"\\\x20/\x80\x7F\x09');
      expect(presentation.basename, r'\x80\x7F\x09');
      expect(presentation.parentHint, r'\x20a\"\\\x20');
      expect(
        presentation.full.codeUnits,
        everyElement(inInclusiveRange(0x20, 0x7e)),
      );
      expect(
        GitPathPresentation.asciiSafe(fixturePath('a b/c d.txt')).full,
        'a b/c d.txt',
      );
    });

    test('truncates only at complete presentation tokens', () {
      final presentation = GitPathPresentation.asciiSafe(
        GitPath.fromBytes([0x61, 0x62, 0x80, 0x63, 0x64]),
      );

      expect(presentation.basename, r'ab\x80cd');
      expect(presentation.truncateBasename(8), r'ab\x80cd');
      expect(presentation.truncateBasename(7), '...cd');
      expect(presentation.truncateBasename(5), '...cd');
      expect(presentation.truncateBasename(4), '...d');
      expect(presentation.truncateBasename(3), '...');
      expect(presentation.truncateBasename(2), '..');
      expect(presentation.truncateBasename(1), '.');
      expect(presentation.truncateBasename(0), '');
      expect(() => presentation.truncateBasename(-1), throwsArgumentError);
      expect(presentation.truncateBasename(7), isNot(contains(r'\x8')));
    });
  });

  group('Git diagnostics and byte results', () {
    test('sanitize arbitrary bytes to printable ASCII', () {
      final diagnostic = GitDiagnosticText.fromBytes([
        0x41,
        0x5c,
        0x09,
        0x0a,
        0x1b,
        0x7f,
        0x80,
      ]);

      expect(diagnostic.text, r'A\\\t\n\e\x7F\x80');
      expect(
        diagnostic.text.codeUnits,
        everyElement(inInclusiveRange(0x20, 0x7e)),
      );
      expect(() => GitDiagnosticText.fromBytes([256]), throwsRangeError);
    });

    test('object diagnostics are total, compact, printable, and nonempty', () {
      final diagnostic = GitDiagnosticText.fromObject(
        const _StringDiagnostic('  first\n second \x1b[31m\x7f  '),
      );

      expect(diagnostic.text, r'first second \e[31m\x7F');
      expect(
        diagnostic.text.codeUnits,
        everyElement(inInclusiveRange(0x20, 0x7e)),
      );
      expect(
        GitDiagnosticText.fromObject(const _ThrowingDiagnostic()).text,
        'Exception text unavailable.',
      );
      expect(
        GitDiagnosticText.fromObject(const _StringDiagnostic(' \n\t ')).text,
        'Exception text unavailable.',
      );
    });

    test('GitCommandResult detaches and validates both streams', () {
      final stdout = <int>[1, 2];
      final stderr = <int>[3, 4];
      final result = GitCommandResult(
        exitCode: 7,
        stdoutBytes: stdout,
        stderrBytes: stderr,
      );
      stdout[0] = 9;
      stderr[0] = 9;

      expect(result.exitCode, 7);
      expect(result.stdoutBytes, [1, 2]);
      expect(result.stderrBytes, [3, 4]);
      expect(() => result.stdoutBytes[0] = 0, throwsUnsupportedError);
      expect(
        () => GitCommandResult(
          exitCode: 0,
          stdoutBytes: const [256],
          stderrBytes: const [],
        ),
        throwsRangeError,
      );
    });
  });

  group('raw-plus-patch envelope', () {
    test('empty bytes are the only patch-free success', () {
      expect(UnifiedDiffParser().parse(const []).files, isEmpty);
      expect(
        () => UnifiedDiffParser().parse(ascii.encode('diff --git a/a b/a')),
        throwsFormatException,
      );
    });

    test('raw identity owns a quoted control-byte pathname', () {
      final path = GitPath.fromBytes([
        ...ascii.encode('lib/'),
        0x01,
        ...ascii.encode('.txt'),
      ]);
      final diff = parsePatchFixture(
        r'''
diff --git deliberately ignored tokens
index 1111111..2222222 100644
--- "a/lib/\001.txt"
+++ "b/lib/\001.txt"
@@ -1 +1 @@
-old
+new
''',
        records: [
          PatchFixtureRecord(status: 'M', oldPath: path, newPath: path),
        ],
      );

      final file = diff.files.single;
      expect(file.pathIdentity, path);
      expect(presentedPath(file), r'lib/\x01.txt');
      expect(file.changeKind, DiffChangeKind.modified);
      expect(file.payloadKind, DiffPayloadKind.text);
      expect(file.rawMetadata!.status, 'M');
      expect(file.hunks.single.filePath, path);
      expect(file.sections.single.filePath, path);
      expect(file.hunks.single.id, startsWith('${path.identityKey}|'));
    });

    test('decodes every accepted C pathname escape to exact bytes', () {
      final path = GitPath.fromBytes([
        ...ascii.encode('x'),
        0x22,
        0x5c,
        0x07,
        0x08,
        0x09,
        0x0a,
        0x0b,
        0x0c,
        0x0d,
        0xc3,
        0xa9,
        0xff,
        ...ascii.encode('.txt'),
      ]);
      final file = parsePatchFixture(
        r'''
diff --git ignored ignored
--- "a/x\"\\\a\b\t\n\v\f\r\303\251\377.txt"
+++ "b/x\"\\\a\b\t\n\v\f\r\303\251\377.txt"
@@ -1 +1 @@
-old
+new
''',
        records: [
          PatchFixtureRecord(status: 'M', oldPath: path, newPath: path),
        ],
      ).files.single;

      expect(file.pathIdentity.bytes, path.bytes);
      expect(
        presentedPath(file),
        r'x\"\\\x07\x08\x09\x0A\x0B\x0C\x0D\xC3\xA9\xFF.txt',
      );
    });

    test('strips only the structural side prefix and not path bytes', () {
      final path = fixturePath('a/b/file.txt');
      final file = parsePatchFixture(
        '''
diff --git deliberately ignored tokens
--- a/a/b/file.txt
+++ b/a/b/file.txt
@@ -1 +1 @@
-old
+new
''',
        records: [
          PatchFixtureRecord(status: 'M', oldPath: path, newPath: path),
        ],
      ).files.single;

      expect(file.pathIdentity, path);
      expect(presentedPath(file), 'a/b/file.txt');

      final devNullPath = fixturePath('dev/null');
      final devNullFile = parsePatchFixture(
        '''
diff --git ignored ignored
--- a/dev/null
+++ b/dev/null
@@ -1 +1 @@
-old
+new
''',
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: devNullPath,
            newPath: devNullPath,
          ),
        ],
      ).files.single;
      expect(devNullFile.pathIdentity, devNullPath);
    });

    test('maps every accepted one-path raw status and metadata axis', () {
      final path = fixturePath('status.txt');
      final cases =
          <
            ({
              PatchFixtureRecord record,
              String patch,
              DiffChangeKind kind,
              int hunks,
            })
          >[
            (
              record: PatchFixtureRecord(
                status: 'A',
                oldPath: null,
                newPath: path,
                oldMode: '000000',
              ),
              patch: '''
diff --git ignored ignored
new file mode 100644
--- /dev/null
+++ b/status.txt
@@ -0,0 +1 @@
+added
''',
              kind: DiffChangeKind.added,
              hunks: 1,
            ),
            (
              record: PatchFixtureRecord(
                status: 'D',
                oldPath: path,
                newPath: null,
                newMode: '000000',
              ),
              patch: '''
diff --git ignored ignored
deleted file mode 100644
--- a/status.txt
+++ /dev/null
@@ -1 +0,0 @@
-deleted
''',
              kind: DiffChangeKind.deleted,
              hunks: 1,
            ),
            (
              record: PatchFixtureRecord(
                status: 'M',
                score: 75,
                oldPath: path,
                newPath: path,
              ),
              patch: '''
diff --git ignored ignored
--- a/status.txt
+++ b/status.txt
@@ -1 +1 @@
-old
+new
''',
              kind: DiffChangeKind.modified,
              hunks: 1,
            ),
            (
              record: PatchFixtureRecord(
                status: 'T',
                oldPath: path,
                newPath: path,
                newMode: '120000',
                oldObjectId: '1' * 64,
                newObjectId: '2' * 64,
              ),
              patch:
                  '''
diff --git ignored ignored
deleted file mode 100644
index ${'1' * 64}..${'0' * 64}
--- a/status.txt
+++ /dev/null
@@ -1 +0,0 @@
-old
diff --git ignored ignored
new file mode 120000
index ${'0' * 64}..${'2' * 64}
--- /dev/null
+++ b/status.txt
@@ -0,0 +1 @@
+target
''',
              kind: DiffChangeKind.typeChanged,
              hunks: 0,
            ),
          ];

      for (final testCase in cases) {
        final file = parsePatchFixture(
          testCase.patch,
          records: [testCase.record],
        ).files.single;
        expect(file.changeKind, testCase.kind);
        expect(file.pathIdentity, path);
        expect(file.payloadKind, DiffPayloadKind.text);
        expect(file.hunks, hasLength(testCase.hunks));
        expect(file.rawMetadata!.status, testCase.record.status);
        expect(file.rawMetadata!.score, testCase.record.score);
        expect(file.rawMetadata!.oldMode, testCase.record.oldMode);
        expect(file.rawMetadata!.newMode, testCase.record.newMode);
        expect(file.rawMetadata!.oldObjectId, testCase.record.oldObjectId);
        expect(file.rawMetadata!.newObjectId, testCase.record.newObjectId);
      }
    });

    test('type-change grouping rejects every arity and side-shape drift', () {
      final path = fixturePath('status.txt');
      final metadata = ':100644 120000 ${'1' * 40} ${'2' * 40} T';
      const deletion = '''
diff --git ignored ignored
deleted file mode 100644
--- a/status.txt
+++ /dev/null
@@ -1 +0,0 @@
-old
''';
      const addition = '''
diff --git ignored ignored
new file mode 120000
--- /dev/null
+++ b/status.txt
@@ -0,0 +1 @@
+target
''';

      List<int> envelope(String patch) =>
          _rawEnvelope(metadata, [path], utf8.encode(patch));

      final malformed = <String>[
        deletion,
        '$deletion${addition}diff --git ignored ignored\nBinary files a/extra and b/extra differ\n',
        '$addition$deletion',
        '${deletion.replaceFirst('deleted file mode 100644', 'deleted file mode 100755')}$addition',
        '${deletion.replaceFirst('--- a/status.txt', '--- a/wrong.txt')}$addition',
        '${deletion.replaceFirst('deleted file mode 100644', 'new file mode 120000')}$addition',
      ];

      for (final patch in malformed) {
        expect(
          () => UnifiedDiffParser().parse(envelope(patch)),
          throwsFormatException,
          reason: patch,
        );
      }
    });

    test('type-change payload combines malformed text conservatively', () {
      final path = fixturePath('status.txt');
      const patch = '''
diff --git ignored ignored
deleted file mode 100644
--- a/status.txt
+++ /dev/null
@@ -1 +0,0 @@
-old
diff --git ignored ignored
new file mode 120000
--- /dev/null
+++ b/status.txt
@@ -0,0 +1 @@
+target
''';
      final bytes = buildPatchEnvelope(
        patch,
        records: [
          PatchFixtureRecord(
            status: 'T',
            oldPath: path,
            newPath: path,
            newMode: '120000',
          ),
        ],
      ).toList();
      final payload = _findBytes(bytes, ascii.encode('-old'));
      bytes[payload + 1] = 0xff;

      final file = UnifiedDiffParser().parse(bytes).files.single;

      expect(file.pathIdentity, path);
      expect(file.changeKind, DiffChangeKind.typeChanged);
      expect(file.payloadKind, DiffPayloadKind.unsupportedTextEncoding);
      expect(file.hunks, isEmpty);
      expect(file.sections, isEmpty);
      expect(file.canStageContent, isFalse);
      expect(file.canStageWholeFile, isTrue);
    });

    test('rename and copy identities come only from paired raw records', () {
      for (final fixture
          in <({String status, DiffChangeKind kind, String verb})>[
            (status: 'R', kind: DiffChangeKind.renamed, verb: 'rename'),
            (status: 'C', kind: DiffChangeKind.copied, verb: 'copy'),
          ]) {
        final oldPath = fixturePath('old name.txt');
        final newPath = fixturePath('new name.txt');
        final file = parsePatchFixture(
          '''
diff --git ignored ignored
similarity index 100%
${fixture.verb} from old name.txt
${fixture.verb} to new name.txt
''',
          records: [
            PatchFixtureRecord(
              status: fixture.status,
              score: 100,
              oldPath: oldPath,
              newPath: newPath,
            ),
          ],
        ).files.single;

        expect(file.oldPath, oldPath);
        expect(file.newPath, newPath);
        expect(file.changeKind, fixture.kind);
        expect(file.rawMetadata!.score, 100);
        expect(file.hunks, isEmpty);
        expect(file.canStageContent, isFalse);
        expect(file.canStageWholeFile, isTrue);
      }
    });

    test('binary rename retains independent change and payload axes', () {
      final oldPath = fixturePath('old.bin');
      final newPath = fixturePath('new.bin');
      final file = parsePatchFixture(
        '''
diff --git ignored ignored
similarity index 80%
rename from old.bin
rename to new.bin
Binary files a/old.bin and b/new.bin differ
''',
        records: [
          PatchFixtureRecord(
            status: 'R',
            score: 80,
            oldPath: oldPath,
            newPath: newPath,
          ),
        ],
      ).files.single;

      expect(file.oldPath, oldPath);
      expect(file.newPath, newPath);
      expect(file.changeKind, DiffChangeKind.renamed);
      expect(file.payloadKind, DiffPayloadKind.binary);
      expect(file.canStageContent, isFalse);
      expect(file.canStageWholeFile, isTrue);
    });

    test('hunk content that resembles structural headers stays content', () {
      final file = parsePatchFixture('''
diff --git a/content.txt b/content.txt
--- a/content.txt
+++ b/content.txt
@@ -1 +1 @@
---- a/decoy.txt
++++ b/decoy.txt
''').files.single;

      expect(file.hunks.single.lines, hasLength(2));
      expect(file.hunks.single.lines.first.type, DiffLineType.deletion);
      expect(file.hunks.single.lines.first.text, '--- a/decoy.txt');
      expect(file.hunks.single.lines.last.type, DiffLineType.addition);
      expect(file.hunks.single.lines.last.text, '+++ b/decoy.txt');
    });

    test('stable IDs use raw identity and ignore header spelling', () {
      const ordinary = '''
diff --git a/same.txt b/same.txt
--- a/same.txt
+++ b/same.txt
@@ -1 +1 @@
-old
+new
''';
      const ignoredDiffGit = '''
diff --git deliberately ignored tokens
--- a/same.txt
+++ b/same.txt
@@ -1 +1 @@
-old
+new
''';
      final record = PatchFixtureRecord(
        status: 'M',
        oldPath: fixturePath('same.txt'),
        newPath: fixturePath('same.txt'),
      );
      final first = parsePatchFixture(ordinary, records: [record]).files.single;
      final equivalent = parsePatchFixture(
        ignoredDiffGit,
        records: [record],
      ).files.single;
      final distinct = parsePatchFixture(
        ordinary.replaceAll('same.txt', 'other.txt'),
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('other.txt'),
            newPath: fixturePath('other.txt'),
          ),
        ],
      ).files.single;

      expect(first.hunks.single.id, equivalent.hunks.single.id);
      expect(first.sections.single.id, equivalent.sections.single.id);
      expect(first.hunks.single.id, isNot(distinct.hunks.single.id));
      expect(first.sections.single.id, isNot(distinct.sections.single.id));
    });

    test('contains malformed text payload without losing neighbors', () {
      const patch = '''
diff --git a/bad.txt b/bad.txt
index 1111111..2222222 100644
--- a/bad.txt
+++ b/bad.txt
@@ -1 +1 @@
-old
+bad
diff --git a/good.txt b/good.txt
index 3333333..4444444 100644
--- a/good.txt
+++ b/good.txt
@@ -1 +1 @@
-old
+good
''';
      final bytes = buildPatchEnvelope(
        patch,
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('bad.txt'),
            newPath: fixturePath('bad.txt'),
          ),
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('good.txt'),
            newPath: fixturePath('good.txt'),
          ),
        ],
      ).toList();
      final badPayload = _findBytes(bytes, ascii.encode('+bad'));
      bytes[badPayload + 1] = 0xff;

      final files = UnifiedDiffParser().parse(bytes).files;

      expect(files, hasLength(2));
      expect(files.first.pathIdentity, fixturePath('bad.txt'));
      expect(files.first.payloadKind, DiffPayloadKind.unsupportedTextEncoding);
      expect(files.first.hunks, isEmpty);
      expect(files.last.pathIdentity, fixturePath('good.txt'));
      expect(files.last.payloadKind, DiffPayloadKind.text);
      expect(files.last.hunks, hasLength(1));
    });

    test('fails closed on raw grammar and unsupported statuses', () {
      final validPatch = ascii.encode('''
diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/a.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+new
''');
      final malformedMetadata = <String>[
        ':10064 100644 ${'1' * 40} ${'2' * 40} M',
        ':100644 100644 ${'1' * 39} ${'2' * 40} M',
        ':100644 100644 ${'A' * 40} ${'2' * 40} M',
        ':100644 100644 ${'1' * 40} ${'2' * 40} A1',
        ':100644 100644 ${'1' * 40} ${'2' * 40} R',
        ':100644 100644 ${'1' * 40} ${'2' * 40} R101',
        ':100644 100644 ${'1' * 40} ${'2' * 40} Z',
        ':100644 100644 ${'1' * 40} ${'2' * 64} M',
      ];
      for (final metadata in malformedMetadata) {
        expect(
          () => UnifiedDiffParser().parse(
            _rawEnvelope(metadata, [fixturePath('a.txt')], validPatch),
          ),
          throwsFormatException,
          reason: metadata,
        );
      }
      for (final status in ['U', 'X']) {
        final metadata = ':100644 100644 ${'1' * 40} ${'2' * 40} $status';
        expect(
          () => UnifiedDiffParser().parse(
            _rawEnvelope(metadata, [fixturePath('a.txt')], validPatch),
          ),
          throwsFormatException,
          reason: status,
        );
      }
    });

    test('fails closed on framing and structural-path drift', () {
      const patch = '''
diff --git a/a.txt b/a.txt
index 1111111..2222222 100644
--- a/wrong.txt
+++ b/a.txt
@@ -1 +1 @@
-old
+new
''';
      expect(
        () => parsePatchFixture(
          patch,
          records: [
            PatchFixtureRecord(
              status: 'M',
              oldPath: fixturePath('a.txt'),
              newPath: fixturePath('a.txt'),
            ),
          ],
        ),
        throwsFormatException,
      );

      final envelope = buildPatchEnvelope(
        patch.replaceFirst('wrong.txt', 'a.txt'),
      ).toList();
      final separator = _findBytes(envelope, const [0, 0]);
      envelope.removeAt(separator);
      expect(() => UnifiedDiffParser().parse(envelope), throwsFormatException);

      final extraBlock =
          buildPatchEnvelope(patch.replaceFirst('wrong.txt', 'a.txt')).toList()
            ..addAll(
              ascii.encode(
                'diff --git a/b.txt b/b.txt\n'
                'Binary files a/b.txt and b/b.txt differ\n',
              ),
            );
      expect(
        () => UnifiedDiffParser().parse(extraBlock),
        throwsFormatException,
      );
    });

    test('rejects every malformed C pathname escape shape', () {
      final path = fixturePath('lib/q.txt');
      for (final field in [
        r'"a/lib/\q.txt"',
        r'"a/lib/\0.txt"',
        r'"a/lib/\01.txt"',
        r'"a/lib/\400.txt"',
        '"a/lib/q.txt',
        '"a/lib/q.txt"x',
        r'"a/lib/q.txt\"',
      ]) {
        final patch =
            '''
diff --git ignored ignored
--- $field
+++ b/lib/q.txt
@@ -1 +1 @@
-old
+new
''';
        expect(
          () => parsePatchFixture(
            patch,
            records: [
              PatchFixtureRecord(status: 'M', oldPath: path, newPath: path),
            ],
          ),
          throwsFormatException,
          reason: field,
        );
      }
    });
  });

  group('repository byte transport', () {
    test('untracked staging uses exact literal NUL pathspec stdin', () async {
      final path = GitPath.fromBytes([
        ...ascii.encode(':(glob)'),
        0xff,
        ...ascii.encode('*.txt'),
      ]);
      final file = DiffFile.untracked(
        path: path,
        entityKind: UntrackedEntityKind.unknown,
        previewState: UntrackedPreviewState.unavailable,
      );
      final runner = _RecordingGitRunner([
        fixtureGitResult(),
        fixtureGitResult(),
      ]);
      final repository = GitPatchRepository(
        worktreePath: '/unused',
        runner: runner,
      );

      final result = await repository.stageWholeFile(file.wholeFileStageUnit!);

      expect(result.outcome, GitStageOutcome.applied);
      expect(runner.commands, [
        [
          '--literal-pathspecs',
          'add',
          '--no-ignore-errors',
          '--dry-run',
          '--pathspec-from-file=-',
          '--pathspec-file-nul',
        ],
        [
          '--literal-pathspecs',
          'add',
          '--no-ignore-errors',
          '--pathspec-from-file=-',
          '--pathspec-file-nul',
        ],
      ]);
      expect(runner.stdinBytes, [
        [...path.bytes, 0],
        [...path.bytes, 0],
      ]);
    });

    test('invalid UTF-8 identities bypass filesystem preview', () async {
      final path = GitPath.fromBytes([0xff, ...ascii.encode('.txt')]);
      final runner = _RecordingGitRunner([
        fixtureGitResult(),
        fixtureGitResult(stdoutBytes: [...path.bytes, 0]),
      ]);

      final diff = await GitPatchRepository(
        worktreePath: '/path/that/must/not/be/used',
        runner: runner,
      ).loadWorkspace();

      final file = diff.files.single;
      expect(file.pathIdentity, path);
      expect(file.untrackedEntityKind, UntrackedEntityKind.unknown);
      expect(file.untrackedPreviewState, UntrackedPreviewState.unavailable);
      expect(presentedPath(file), r'\xFF.txt');
    });

    test('repository errors never expose raw terminal controls', () async {
      final runner = _RecordingGitRunner([
        fixtureGitResult(
          exitCode: 1,
          stderrBytes: const [0x62, 0x61, 0x64, 0x0a, 0x1b, 0xff],
        ),
      ]);

      await expectLater(
        GitPatchRepository(
          worktreePath: '/unused',
          runner: runner,
        ).loadTrackedDiff(),
        throwsA(
          isA<Object>().having(
            (error) => error.toString(),
            'safe message',
            r'bad\n\e\xFF',
          ),
        ),
      );
    });
  });
}

List<int> _rawEnvelope(String metadata, List<GitPath> paths, List<int> patch) {
  final output = <int>[...ascii.encode(metadata), 0];
  for (final path in paths) {
    output
      ..addAll(path.bytes)
      ..add(0);
  }
  return [...output, 0, ...patch];
}

int _findBytes(List<int> source, List<int> pattern) {
  for (var offset = 0; offset + pattern.length <= source.length; offset++) {
    var matches = true;
    for (var i = 0; i < pattern.length; i++) {
      if (source[offset + i] != pattern[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return offset;
  }
  throw StateError('Pattern not found: $pattern');
}

final class _RecordingGitRunner implements GitCommandRunner {
  _RecordingGitRunner(Iterable<GitCommandResult> results)
    : _results = List<GitCommandResult>.of(results);

  final List<GitCommandResult> _results;
  final List<List<String>> commands = [];
  final List<List<int>?> stdinBytes = [];

  @override
  Future<GitCommandResult> run(
    List<String> args, {
    List<int>? stdinBytes,
  }) async {
    commands.add(List<String>.unmodifiable(args));
    this.stdinBytes.add(
      stdinBytes == null ? null : List<int>.unmodifiable(stdinBytes),
    );
    if (_results.isEmpty) {
      throw StateError('Unexpected git command: ${args.join(' ')}');
    }
    return _results.removeAt(0);
  }
}

final class _StringDiagnostic {
  const _StringDiagnostic(this.value);

  final String value;

  @override
  String toString() => value;
}

final class _ThrowingDiagnostic {
  const _ThrowingDiagnostic();

  @override
  String toString() => throw StateError('toString must not escape');
}
