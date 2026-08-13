import 'package:noir/src/tools/patch_manager/patch_manager.dart';
import 'package:test/test.dart';

import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('UnifiedDiffParser', () {
    test('parses modified files with multiple hunks', () {
      const rawDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,5 +1,5 @@
 void main() {
-  print('old');
+  print('new');
 }
 
 void untouched() {}
@@ -20,4 +20,5 @@ void later() {
   final value = 1;
+  final next = 2;
   print(value);
 }
''';

      final diff = parsePatchFixture(rawDiff);

      expect(diff.files, hasLength(1));
      final file = diff.files.single;
      expect(file.oldPath, fixturePath('lib/app.dart'));
      expect(file.newPath, fixturePath('lib/app.dart'));
      expect(presentedPath(file), 'lib/app.dart');
      expect(file.changeKind, DiffChangeKind.modified);
      expect(file.payloadKind, DiffPayloadKind.text);
      expect(file.canStageWholeFile, isTrue);
      expect(file.hunks, hasLength(2));

      expect(file.hunks.first.oldStart, 1);
      expect(file.hunks.first.oldCount, 5);
      expect(file.hunks.first.newStart, 1);
      expect(file.hunks.first.newCount, 5);
      expect(file.hunks.first.lines.map((line) => line.type), [
        DiffLineType.context,
        DiffLineType.deletion,
        DiffLineType.addition,
        DiffLineType.context,
        DiffLineType.context,
        DiffLineType.context,
      ]);
      expect(file.hunks.first.lines[0].oldLineNumber, 1);
      expect(file.hunks.first.lines[0].newLineNumber, 1);
      expect(file.hunks.first.lines[1].oldLineNumber, 2);
      expect(file.hunks.first.lines[1].newLineNumber, isNull);
      expect(file.hunks.first.lines[2].oldLineNumber, isNull);
      expect(file.hunks.first.lines[2].newLineNumber, 2);
      expect(file.hunks.first.sections, hasLength(1));
      expect(file.hunks.first.sections.single.additionCount, 1);
      expect(file.hunks.first.sections.single.deletionCount, 1);

      expect(file.hunks.last.oldStart, 20);
      expect(file.hunks.last.newCount, 5);
      expect(
        file.hunks.last.lines.singleWhere((line) => line.isAddition).text,
        '  final next = 2;',
      );
    });

    test('classifies binary files as whole-file-only staging targets', () {
      const rawDiff = '''
diff --git a/assets/logo.png b/assets/logo.png
index 1111111..2222222 100644
Binary files a/assets/logo.png and b/assets/logo.png differ
''';

      final diff = parsePatchFixture(rawDiff);

      expect(diff.files, hasLength(1));
      expect(presentedPath(diff.files.single), 'assets/logo.png');
      expect(diff.files.single.changeKind, DiffChangeKind.modified);
      expect(diff.files.single.payloadKind, DiffPayloadKind.binary);
      expect(diff.files.single.canStageContent, isFalse);
      expect(diff.files.single.canStageWholeFile, isTrue);
      expect(diff.files.single.hunks, isEmpty);
    });

    test('parses binary paths with spaces from diff git headers', () {
      const rawDiff = '''
diff --git a/assets/raw logo.png b/assets/raw logo.png
index 1111111..2222222 100644
Binary files a/assets/raw logo.png and b/assets/raw logo.png differ
''';

      final file = parsePatchFixture(rawDiff).files.single;

      expect(file.oldPath, fixturePath('assets/raw logo.png'));
      expect(file.newPath, fixturePath('assets/raw logo.png'));
      expect(presentedPath(file), 'assets/raw logo.png');
      expect(file.changeKind, DiffChangeKind.modified);
      expect(file.payloadKind, DiffPayloadKind.binary);
    });

    test('parses paths with spaces from patch headers', () {
      const rawDiff = '''
diff --git a/lib/app file.dart b/lib/app file.dart
index 1111111..2222222 100644
--- a/lib/app file.dart
+++ b/lib/app file.dart
@@ -1 +1 @@
-old
+new
''';

      final file = parsePatchFixture(rawDiff).files.single;

      expect(file.oldPath, fixturePath('lib/app file.dart'));
      expect(file.newPath, fixturePath('lib/app file.dart'));
      expect(presentedPath(file), 'lib/app file.dart');
    });

    test('parses quoted Git paths with escapes', () {
      const rawDiff = '''
diff --git "a/lib/quoted name.dart" "b/lib/quoted name.dart"
index 1111111..2222222 100644
--- "a/lib/quoted name.dart"
+++ "b/lib/quoted name.dart"
@@ -1 +1 @@
-old
+new
''';

      final file = parsePatchFixture(
        rawDiff,
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('lib/quoted name.dart'),
            newPath: fixturePath('lib/quoted name.dart'),
          ),
        ],
      ).files.single;

      expect(file.oldPath, fixturePath('lib/quoted name.dart'));
      expect(file.newPath, fixturePath('lib/quoted name.dart'));
    });

    test('splits a larger hunk into reviewable change sections', () {
      const rawDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,10 +1,12 @@
 line 1
-line 2
+line 2 changed
 line 3
 line 4
 line 5
+line 5.5
 line 6
 line 7
-line 8
+line 8 changed
 line 9
 line 10
''';

      final hunk = parsePatchFixture(rawDiff).files.single.hunks.single;

      expect(hunk.sections, hasLength(3));
      expect(hunk.sections[0].oldStart, 2);
      expect(hunk.sections[0].newStart, 2);
      expect(hunk.sections[0].additionCount, 1);
      expect(hunk.sections[0].deletionCount, 1);
      expect(hunk.sections[1].oldStart, 5);
      expect(hunk.sections[1].newStart, 6);
      expect(hunk.sections[1].additionCount, 1);
      expect(hunk.sections[1].deletionCount, 0);
      expect(hunk.sections[2].oldStart, 8);
      expect(hunk.sections[2].newStart, 9);
    });
  });

  group('explicit staging parser', () {
    test('opaque diff git opener matrix stays eligible and verbatim', () {
      const openers = [
        'diff --git deliberately ignored tokens',
        'diff --git a/wrong.txt b/wrong.txt',
      ];
      GitPath? expectedIdentity;
      List<String>? expectedTargetIds;

      for (final opener in openers) {
        final file = parsePatchFixture(
          '''
$opener
old mode 100644
new mode 100755
--- a/mode.txt
+++ b/mode.txt
@@ -1 +1 @@
-before
+after
''',
          records: [
            PatchFixtureRecord(
              status: 'M',
              oldPath: fixturePath('mode.txt'),
              newPath: fixturePath('mode.txt'),
              newMode: '100755',
            ),
          ],
        ).files.single;
        final patch = PatchGenerator().buildContentPatch(
          ContentStageSelection(file: file, sections: file.sections),
        );
        final targetIds = file.reviewTargets
            .map((target) => target.id)
            .toList(growable: false);

        expectedIdentity ??= file.pathIdentity;
        expectedTargetIds ??= targetIds;
        expect(file.pathIdentity, expectedIdentity);
        expect(targetIds, expectedTargetIds);
        expect(file.canStageContent, isTrue);
        expect(file.canStageWholeFile, isTrue);
        expect(file.contentStageUnits, file.sections);
        expect(file.reviewTargets, file.contentStageUnits);
        expect(file.contentPatchHeader!.diffGitLine, opener);
        expect(file.contentPatchHeader!.oldFileLine, '--- a/mode.txt');
        expect(file.contentPatchHeader!.newFileLine, '+++ b/mode.txt');
        expect(
          file.wholeFileStageUnit!.reason,
          WholeFileChangeReason.contentAndMode,
        );
        expect(
          DiffSet([file]).stageableReviewTargetCount,
          file.sections.length,
        );
        expect(patch, startsWith('$opener\n--- a/mode.txt\n+++ b/mode.txt\n'));
        expect(patch, isNot(contains('old mode')));
        expect(patch, isNot(contains('new mode')));
      }
    });

    test('accepted zero-hunk states expose exact whole-file reasons', () {
      final modeOnly = parsePatchFixture(
        '''
diff --git a/mode-only.txt b/mode-only.txt
old mode 100644
new mode 100755
''',
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('mode-only.txt'),
            newPath: fixturePath('mode-only.txt'),
            newMode: '100755',
          ),
        ],
      ).files.single;
      final binary = parsePatchFixture('''
diff --git a/image.bin b/image.bin
Binary files a/image.bin and b/image.bin differ
''').files.single;
      final emptyDeletion = parsePatchFixture('''
diff --git a/empty.txt b/empty.txt
deleted file mode 100644
--- a/empty.txt
+++ /dev/null
''').files.single;
      final typeChange = parsePatchFixture(
        '''
diff --git a/node b/node
deleted file mode 120000
--- a/node
+++ /dev/null
diff --git a/node b/node
new file mode 100644
--- /dev/null
+++ b/node
''',
        records: [
          PatchFixtureRecord(
            status: 'T',
            oldPath: fixturePath('node'),
            newPath: fixturePath('node'),
            oldMode: '120000',
          ),
        ],
      ).files.single;

      final files = <DiffFile>[modeOnly, binary, emptyDeletion, typeChange];
      expect(files.map((file) => file.hunks.length), everyElement(0));
      expect(files.map((file) => file.sections.length), everyElement(0));
      expect(files.map((file) => file.wholeFileStageUnit!.reason), [
        WholeFileChangeReason.modeOnly,
        WholeFileChangeReason.binary,
        WholeFileChangeReason.deleted,
        WholeFileChangeReason.typeChanged,
      ]);
      expect(
        files.map((file) => file.reviewTargets.single),
        files.map((file) => file.wholeFileStageUnit),
      );
      expect(files.map((file) => file.wholeFileStageUnit!.pathspecs), [
        [fixturePath('mode-only.txt')],
        [fixturePath('image.bin')],
        [fixturePath('empty.txt')],
        [fixturePath('node')],
      ]);
    });

    test('untracked previews have no synthetic patch structures', () {
      final file = DiffFile.untracked(
        path: fixturePath('notes.txt'),
        entityKind: UntrackedEntityKind.regularFile,
        previewState: UntrackedPreviewState.completeText,
        previewLines: const ['first note', 'second note'],
      );

      expect(file.untrackedPreviewLines, ['first note', 'second note']);
      expect(file.hunks, isEmpty);
      expect(file.sections, isEmpty);
      expect(file.headerLines, isEmpty);
      expect(file.contentPatchHeader, isNull);
      expect(file.contentStageUnits, isEmpty);
      expect(file.reviewTargets, [file.wholeFileStageUnit]);
      expect(file.wholeFileStageUnit!.reason, WholeFileChangeReason.untracked);
      expect(file.wholeFileStageUnit!.pathspecs, [fixturePath('notes.txt')]);
    });

    test('derives the remaining whole-file reason and path matrix', () {
      final modified = parsePatchFixture('''
diff --git a/modified.txt b/modified.txt
--- a/modified.txt
+++ b/modified.txt
@@ -1 +1 @@
-before
+after
''').files.single;

      final unsupportedBytes = buildPatchEnvelope('''
diff --git a/unsupported.txt b/unsupported.txt
--- a/unsupported.txt
+++ b/unsupported.txt
@@ -1 +1 @@
-before
+after
''').toList();
      unsupportedBytes[unsupportedBytes.lastIndexOf(0x2b) + 1] = 0xff;
      final unsupported = UnifiedDiffParser()
          .parse(unsupportedBytes)
          .files
          .single;

      final added = parsePatchFixture('''
diff --git a/added.txt b/added.txt
new file mode 100644
--- /dev/null
+++ b/added.txt
@@ -0,0 +1 @@
+new
''').files.single;

      final renamedOld = fixturePath('old.txt');
      final renamedNew = fixturePath('new.txt');
      final renamed = parsePatchFixture(
        '''
diff --git ignored ignored
similarity index 100%
rename from old.txt
rename to new.txt
''',
        records: [
          PatchFixtureRecord(
            status: 'R',
            score: 100,
            oldPath: renamedOld,
            newPath: renamedNew,
          ),
        ],
      ).files.single;

      final copiedNew = fixturePath('copy.txt');
      final copied = parsePatchFixture(
        '''
diff --git ignored ignored
similarity index 100%
copy from source.txt
copy to copy.txt
''',
        records: [
          PatchFixtureRecord(
            status: 'C',
            score: 100,
            oldPath: fixturePath('source.txt'),
            newPath: copiedNew,
          ),
        ],
      ).files.single;

      final sameOld = fixturePath('same.txt');
      final sameNew = GitPath.fromBytes(sameOld.bytes);
      expect(identical(sameOld, sameNew), isFalse);
      final deduplicatedRename = parsePatchFixture(
        '''
diff --git ignored ignored
similarity index 100%
rename from same.txt
rename to same.txt
''',
        records: [
          PatchFixtureRecord(
            status: 'R',
            score: 100,
            oldPath: sameOld,
            newPath: sameNew,
          ),
        ],
      ).files.single;

      final expected = <DiffFile, (WholeFileChangeReason, List<GitPath>)>{
        modified: (
          WholeFileChangeReason.modified,
          [fixturePath('modified.txt')],
        ),
        unsupported: (
          WholeFileChangeReason.unsupportedTextEncoding,
          [fixturePath('unsupported.txt')],
        ),
        added: (WholeFileChangeReason.added, [fixturePath('added.txt')]),
        renamed: (WholeFileChangeReason.renamed, [renamedOld, renamedNew]),
        copied: (WholeFileChangeReason.copied, [copiedNew]),
        deduplicatedRename: (WholeFileChangeReason.renamed, [sameOld]),
      };

      for (final MapEntry(key: file, value: expectation) in expected.entries) {
        final whole = file.wholeFileStageUnit!;
        expect(whole.reason, expectation.$1, reason: presentedPath(file));
        expect(whole.pathspecs, expectation.$2, reason: presentedPath(file));
        expect(
          whole.id,
          WholeFileChange.canonicalId(
            reason: expectation.$1,
            pathspecs: expectation.$2,
          ),
          reason: presentedPath(file),
        );
      }
      expect(modified.canStageContent, isTrue);
      expect(unsupported.canStageContent, isFalse);
      expect(added.reviewTargets, [added.wholeFileStageUnit]);
      expect(renamed.reviewTargets, [renamed.wholeFileStageUnit]);
      expect(copied.reviewTargets, [copied.wholeFileStageUnit]);
      expect(deduplicatedRename.reviewTargets, [
        deduplicatedRename.wholeFileStageUnit,
      ]);
    });
  });

  group('explicit staging models', () {
    test('content selection is detached, canonical, and content-prefixed', () {
      final parsed = parsePatchFixture('''
diff --git a/story.txt b/story.txt
--- a/story.txt
+++ b/story.txt
@@ -1,5 +1,6 @@
-first
+first changed
 context
+inserted
 context
-last
+last changed
''').files.single;
      final file = DiffFile(
        oldPath: parsed.oldPath,
        newPath: parsed.newPath,
        changeKind: parsed.changeKind,
        payloadKind: parsed.payloadKind,
        headerLines: parsed.headerLines,
        hunks: parsed.hunks,
        rawMetadata: parsed.rawMetadata,
        contentPatchHeader: const ContentPatchHeader(
          diffGitLine: 'diff --git a/story.txt b/story.txt',
          oldFileLine: '--- a/story.txt',
          newFileLine: '+++ b/story.txt',
        ),
      );
      final reversed = file.sections.reversed.toList();

      final selection = ContentStageSelection(file: file, sections: reversed);
      reversed.clear();

      expect(selection.sections, file.contentStageUnits);
      expect(selection.sections, hasLength(3));
      expect(selection.sections, everyElement(isA<PatchReviewTarget>()));
      expect(
        selection.sections.map((section) => section.id),
        everyElement(startsWith('content:')),
      );
      expect(
        () => selection.sections.add(file.sections.first),
        throwsUnsupportedError,
      );
      expect(
        () => ContentStageSelection(file: file, sections: const []),
        throwsArgumentError,
      );
      expect(
        () => ContentStageSelection(
          file: file,
          sections: [file.sections.first, file.sections.first],
        ),
        throwsArgumentError,
      );
    });

    test('content selection rejects a foreign equivalent section', () {
      const patch = '''
diff --git a/story.txt b/story.txt
--- a/story.txt
+++ b/story.txt
@@ -1 +1 @@
-before
+after
''';
      final file = parsePatchFixture(patch).files.single;
      final reparsed = parsePatchFixture(patch).files.single;
      final foreign = reparsed.sections.single;

      expect(foreign.id, file.sections.single.id);
      expect(identical(foreign, file.sections.single), isFalse);
      expect(
        () => ContentStageSelection(file: file, sections: [foreign]),
        throwsArgumentError,
      );
    });

    test('WholeFileChange rejects empty and duplicate pathspecs', () {
      final path = fixturePath('same.txt');

      expect(
        () => WholeFileChange(
          id: WholeFileChange.canonicalId(
            reason: WholeFileChangeReason.modified,
            pathspecs: const [],
          ),
          pathspecs: const [],
          reason: WholeFileChangeReason.modified,
        ),
        throwsArgumentError,
      );
      expect(
        () => WholeFileChange(
          id: WholeFileChange.canonicalId(
            reason: WholeFileChangeReason.renamed,
            pathspecs: [path, path],
          ),
          pathspecs: [path, GitPath.fromBytes(path.bytes)],
          reason: WholeFileChangeReason.renamed,
        ),
        throwsArgumentError,
      );
    });

    test('derived target and preview lists are detached and unmodifiable', () {
      final parsed = parsePatchFixture('''
diff --git a/story.txt b/story.txt
--- a/story.txt
+++ b/story.txt
@@ -1 +1 @@
-before
+after
''').files.single;
      final sourceHunks = parsed.hunks.toList();
      final sourceHeaders = parsed.headerLines.toList();
      final rebuilt = DiffFile(
        oldPath: parsed.oldPath,
        newPath: parsed.newPath,
        changeKind: parsed.changeKind,
        payloadKind: parsed.payloadKind,
        headerLines: sourceHeaders,
        hunks: sourceHunks,
        rawMetadata: parsed.rawMetadata,
        contentPatchHeader: parsed.contentPatchHeader,
      );
      sourceHunks.clear();
      sourceHeaders.clear();

      expect(rebuilt.hunks, hasLength(1));
      expect(rebuilt.contentStageUnits, hasLength(1));
      expect(rebuilt.reviewTargets, [rebuilt.contentStageUnits.single]);
      expect(rebuilt.headerLines, isNotEmpty);
      expect(rebuilt.headerLines.clear, throwsUnsupportedError);
      expect(rebuilt.hunks.clear, throwsUnsupportedError);
      expect(rebuilt.sections.clear, throwsUnsupportedError);
      expect(rebuilt.contentStageUnits.clear, throwsUnsupportedError);
      expect(rebuilt.reviewTargets.clear, throwsUnsupportedError);

      final previewSource = <String>['first', 'second'];
      final untracked = DiffFile.untracked(
        path: fixturePath('notes.txt'),
        entityKind: UntrackedEntityKind.regularFile,
        previewState: UntrackedPreviewState.completeText,
        previewLines: previewSource,
      );
      previewSource.clear();

      expect(untracked.untrackedPreviewLines, ['first', 'second']);
      expect(untracked.untrackedPreviewLines.clear, throwsUnsupportedError);
      expect(untracked.reviewTargets, [untracked.wholeFileStageUnit]);
      expect(untracked.reviewTargets.clear, throwsUnsupportedError);
    });

    test('DiffFile rejects duplicate derived review-target IDs', () {
      final parsed = parsePatchFixture('''
diff --git a/story.txt b/story.txt
--- a/story.txt
+++ b/story.txt
@@ -1 +1 @@
-before
+after
''').files.single;

      expect(
        () => DiffFile(
          oldPath: parsed.oldPath,
          newPath: parsed.newPath,
          changeKind: parsed.changeKind,
          payloadKind: parsed.payloadKind,
          headerLines: parsed.headerLines,
          hunks: [parsed.hunks.single, parsed.hunks.single],
          rawMetadata: parsed.rawMetadata,
          contentPatchHeader: parsed.contentPatchHeader,
        ),
        throwsArgumentError,
      );
    });

    test('WholeFileChange rejects an ID with the wrong reason', () {
      final path = fixturePath('mode.txt');
      final id = WholeFileChange.canonicalId(
        reason: WholeFileChangeReason.modeOnly,
        pathspecs: [path],
      );

      expect(
        () => WholeFileChange(
          id: id,
          pathspecs: [path],
          reason: WholeFileChangeReason.binary,
        ),
        throwsArgumentError,
      );
    });

    test('WholeFileChange rejects an ID with an omitted path identity', () {
      final oldPath = fixturePath('old.txt');
      final newPath = fixturePath('new.txt');
      final id = WholeFileChange.canonicalId(
        reason: WholeFileChangeReason.renamed,
        pathspecs: [oldPath],
      );

      expect(
        () => WholeFileChange(
          id: id,
          pathspecs: [oldPath, newPath],
          reason: WholeFileChangeReason.renamed,
        ),
        throwsArgumentError,
      );
    });

    test('WholeFileChange rejects an ID with reordered path identities', () {
      final oldPath = fixturePath('old.txt');
      final newPath = fixturePath('new.txt');
      final id = WholeFileChange.canonicalId(
        reason: WholeFileChangeReason.renamed,
        pathspecs: [newPath, oldPath],
      );

      expect(
        () => WholeFileChange(
          id: id,
          pathspecs: [oldPath, newPath],
          reason: WholeFileChangeReason.renamed,
        ),
        throwsArgumentError,
      );
    });

    test('WholeFileChange rejects an ID with a substituted path identity', () {
      final oldPath = fixturePath('old.txt');
      final newPath = fixturePath('new.txt');
      final substituted = fixturePath('substituted.txt');
      final id = WholeFileChange.canonicalId(
        reason: WholeFileChangeReason.renamed,
        pathspecs: [oldPath, substituted],
      );

      expect(
        () => WholeFileChange(
          id: id,
          pathspecs: [oldPath, newPath],
          reason: WholeFileChangeReason.renamed,
        ),
        throwsArgumentError,
      );
    });

    test('WholeFileChange accepts the exact ordered multi-path rename ID', () {
      final oldPath = fixturePath('old.txt');
      final newPath = fixturePath('new.txt');
      final source = [oldPath, newPath];
      final id = WholeFileChange.canonicalId(
        reason: WholeFileChangeReason.renamed,
        pathspecs: source,
      );

      final change = WholeFileChange(
        id: id,
        pathspecs: source,
        reason: WholeFileChangeReason.renamed,
      );
      source.clear();

      expect(
        change.id,
        'whole:renamed:${oldPath.identityKey}:${newPath.identityKey}',
      );
      expect(change.pathspecs, [oldPath, newPath]);
      expect(change.pathspecs.clear, throwsUnsupportedError);
    });
  });

  group('PatchGenerator', () {
    test('builds a patch from every section in only the selected hunk', () {
      const rawDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,5 +1,5 @@
 void main() {
-  print('old');
+  print('new');
 }
 
 void untouched() {}
@@ -20,4 +20,5 @@ void later() {
   final value = 1;
+  final next = 2;
   print(value);
 }
''';

      final file = parsePatchFixture(rawDiff).files.single;
      final patch = PatchGenerator().buildContentPatch(
        ContentStageSelection(file: file, sections: file.hunks.last.sections),
      );

      expect(patch, contains('diff --git a/lib/app.dart b/lib/app.dart'));
      expect(patch, contains('@@ -20,3 +20,4 @@ void later() {'));
      expect(patch, contains('+  final next = 2;'));
      expect(patch, isNot(contains("print('new')")));
      expect(patch.endsWith('\n'), isTrue);
    });

    test('builds normalized patches for selected split sections', () {
      const rawDiff = '''
diff --git a/story.txt b/story.txt
index 1111111..2222222 100644
--- a/story.txt
+++ b/story.txt
@@ -1,8 +1,10 @@
 line 1
-line 2
+line 2 changed
 line 3
 line 4
+line 4.5
 line 5
-line 6
+line 6 changed
 line 7
 line 8
''';
      final file = parsePatchFixture(rawDiff).files.single;

      final patch = PatchGenerator().buildContentPatch(
        ContentStageSelection(
          file: file,
          sections: [file.hunks.single.sections[1]],
        ),
      );

      expect(patch, contains('diff --git a/story.txt b/story.txt'));
      expect(patch, contains('@@ -2,6 +2,7 @@'));
      expect(patch, contains('+line 4.5'));
      expect(patch, isNot(contains('+line 2 changed')));
      expect(patch, isNot(contains('+line 6 changed')));
      expect(patch, isNot(contains('-line 2')));
      expect(patch, isNot(contains('-line 6')));
    });

    test('writes only the retained content header and selected content', () {
      const opener = 'diff --git deliberately ignored tokens';
      final file = parsePatchFixture(
        '''
$opener
old mode 100644
new mode 100755
index 1111111..2222222 100644
--- a/mode.txt
+++ b/mode.txt
@@ -1 +1 @@
-before
+after
''',
        records: [
          PatchFixtureRecord(
            status: 'M',
            oldPath: fixturePath('mode.txt'),
            newPath: fixturePath('mode.txt'),
            newMode: '100755',
          ),
        ],
      ).files.single;

      final patch = PatchGenerator().buildContentPatch(
        ContentStageSelection(file: file, sections: file.sections),
      );

      expect(patch, startsWith('$opener\n--- a/mode.txt\n+++ b/mode.txt\n'));
      expect(patch, isNot(contains('old mode')));
      expect(patch, isNot(contains('new mode')));
      expect(patch, isNot(contains('index ')));
      expect(patch, contains('-before\n+after\n'));
    });

    test('uses canonical coordinates for zero-sided content changes', () {
      final addFromEmpty = parsePatchFixture('''
diff --git a/empty.txt b/empty.txt
--- a/empty.txt
+++ b/empty.txt
@@ -0,0 +1,2 @@
+first
+second
''').files.single;
      final deleteAll = parsePatchFixture('''
diff --git a/full.txt b/full.txt
--- a/full.txt
+++ b/full.txt
@@ -1,2 +0,0 @@
-first
-second
''').files.single;

      final addPatch = PatchGenerator().buildContentPatch(
        ContentStageSelection(
          file: addFromEmpty,
          sections: addFromEmpty.sections,
        ),
      );
      final deletePatch = PatchGenerator().buildContentPatch(
        ContentStageSelection(file: deleteAll, sections: deleteAll.sections),
      );

      expect(addPatch, contains('@@ -0,0 +1,2 @@'));
      expect(deletePatch, contains('@@ -1,2 +0,0 @@'));
    });

    test('rebases later hunks by selected earlier delta only', () {
      final file = parsePatchFixture('''
diff --git a/story.txt b/story.txt
--- a/story.txt
+++ b/story.txt
@@ -1,2 +1,3 @@
 line 1
+inserted
 line 2
@@ -10 +11 @@
-before
+after
''').files.single;
      final later = file.hunks.last.sections.single;

      final laterOnly = PatchGenerator().buildContentPatch(
        ContentStageSelection(file: file, sections: [later]),
      );
      final both = PatchGenerator().buildContentPatch(
        ContentStageSelection(file: file, sections: file.sections),
      );

      expect(laterOnly, contains('@@ -10,1 +10,1 @@'));
      expect(both, contains('@@ -1,2 +1,3 @@'));
      expect(both, contains('@@ -10,1 +11,1 @@'));
    });
  });
}
