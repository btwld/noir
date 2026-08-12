// ignore_for_file: cascade_invocations

import 'package:noir/src/tools/patch_manager/patch_manager.dart';
import 'package:test/test.dart';

import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('PatchReviewController', () {
    test('typed content status moves through skip failure and success', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final file = controller.currentFile;
      final section = controller.currentSection!;
      final hunk = controller.currentHunk!;
      final whole = controller.currentWholeFileChange!;
      final selection = controller.currentHunkContentSelection()!;

      expect(presentedPath(file), 'lib/app.dart');
      expect(section, file.sections.first);
      expect(controller.statusForTarget(section), PatchReviewStatus.unreviewed);
      expect(controller.statusForHunk(hunk), PatchReviewStatus.unreviewed);
      expect(controller.statusForFile(file), PatchReviewStatus.unreviewed);
      expect(
        controller.statusForWholeFile(whole),
        PatchReviewStatus.unreviewed,
      );

      controller.skipCurrentReviewTarget();
      expect(controller.statusForTarget(section), PatchReviewStatus.skipped);
      expect(controller.skippedCount, 1);
      expect(controller.pendingCount, 1);

      controller.recordContentStageOutcome(
        selection,
        GitStageOutcome.rejectedUnchanged,
      );
      expect(controller.statusForTarget(section), PatchReviewStatus.failed);
      expect(controller.skippedCount, 0);
      expect(controller.pendingCount, 2);

      controller.recordContentStageOutcome(selection, GitStageOutcome.applied);
      expect(controller.statusForTarget(section), PatchReviewStatus.staged);
      expect(controller.stagedCountFor(file), 1);
      expect(controller.skippedCountFor(file), 0);
      expect(controller.pendingCount, 1);
    });

    test('both content failure outcomes affect only selected content', () {
      for (final outcome in [
        GitStageOutcome.rejectedUnchanged,
        GitStageOutcome.failedRefreshRequired,
      ]) {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        final first = controller.currentSection!;
        final second = controller.currentFile.sections.last;

        controller.recordContentStageOutcome(
          controller.currentHunkContentSelection()!,
          outcome,
        );

        expect(
          controller.statusForTarget(first),
          PatchReviewStatus.failed,
          reason: outcome.name,
        );
        expect(
          controller.statusForTarget(second),
          PatchReviewStatus.unreviewed,
          reason: outcome.name,
        );
        expect(controller.stagedCount, 0, reason: outcome.name);
      }
    });

    test('stable refresh retains staged and skipped but clears failures', () {
      final original = parsePatchFixture(_threeHunkDiff);
      final controller = PatchReviewController(original);
      controller.recordContentStageOutcome(
        controller.currentHunkContentSelection()!,
        GitStageOutcome.applied,
      );
      controller
        ..selectSection(1)
        ..skipCurrentReviewTarget()
        ..recordWholeFileStageOutcome(
          controller.currentWholeFileChange!,
          GitStageOutcome.rejectedUnchanged,
        );

      expect(
        controller.statusForWholeFile(controller.currentWholeFileChange!),
        PatchReviewStatus.failed,
      );

      final equivalent = parsePatchFixture(_threeHunkDiff);
      controller.refresh(equivalent);
      final refreshed = equivalent.files.single.sections;

      expect(
        controller.statusForTarget(refreshed[0]),
        PatchReviewStatus.staged,
      );
      expect(
        controller.statusForTarget(refreshed[1]),
        PatchReviewStatus.skipped,
      );
      expect(
        controller.statusForTarget(refreshed[2]),
        PatchReviewStatus.unreviewed,
      );
      expect(
        controller.statusForWholeFile(
          equivalent.files.single.wholeFileStageUnit!,
        ),
        PatchReviewStatus.unreviewed,
      );
      expect(controller.selectedSectionIndex, 1);
      expect(controller.stagedCount, 1);
      expect(controller.skippedCount, 1);
      expect(controller.pendingCount, 1);
    });

    test('vanished live ids are pruned before equivalent ids reappear', () {
      final original = parsePatchFixture(_threeHunkDiff);
      final controller = PatchReviewController(original);
      controller.recordContentStageOutcome(
        controller.currentHunkContentSelection()!,
        GitStageOutcome.applied,
      );
      controller
        ..selectSection(1)
        ..skipCurrentReviewTarget()
        ..refresh(const DiffSet([]))
        ..refresh(parsePatchFixture(_threeHunkDiff));

      for (final section in controller.currentFile.sections) {
        expect(
          controller.statusForTarget(section),
          PatchReviewStatus.unreviewed,
        );
      }
      expect(controller.stagedCount, 0);
      expect(controller.skippedCount, 0);
      expect(controller.pendingCount, 3);
    });

    test('typed content selections exclude staged but include skipped', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final firstHunk = controller.currentHunk!;
      controller.recordContentStageOutcome(
        controller.currentHunkContentSelection()!,
        GitStageOutcome.applied,
      );

      expect(controller.contentSelectionForHunk(firstHunk), isNull);
      expect(controller.currentHunkContentSelection(), isNull);

      controller
        ..selectSection(1)
        ..skipCurrentReviewTarget();
      final skippedSelection = controller.currentHunkContentSelection()!;

      expect(skippedSelection.file, same(controller.currentFile));
      expect(skippedSelection.sections, [controller.currentSection]);
    });

    test('refresh clamps nullable content selection then handles empty', () {
      final first = parsePatchFixture(_twoHunkDiff).files.single;
      final second = parsePatchFixture(_secondFileTwoHunkDiff).files.single;
      final controller = PatchReviewController(DiffSet([first, second]))
        ..selectFile(1)
        ..selectSection(1);

      expect(controller.selectedFileIndex, 1);
      expect(controller.selectedSectionIndex, 1);

      final wholeOnly = _untrackedFile('notes.txt');
      controller.refresh(DiffSet([wholeOnly]));

      expect(controller.selectedFileIndex, 0);
      expect(controller.selectedSectionIndex, 0);
      expect(controller.currentSection, isNull);
      expect(controller.currentHunk, isNull);
      expect(controller.currentHunkContentSelection(), isNull);
      expect(
        controller.currentWholeFileChange,
        same(wholeOnly.wholeFileStageUnit),
      );

      controller.refresh(const DiffSet([]));

      expect(controller.hasFiles, isFalse);
      expect(controller.selectedFileIndex, 0);
      expect(controller.selectedSectionIndex, 0);
      expect(controller.currentSection, isNull);
      expect(controller.currentHunk, isNull);
      expect(controller.currentWholeFileChange, isNull);
      expect(controller.stagedCount, 0);
      expect(controller.skippedCount, 0);
      expect(controller.pendingCount, 0);
    });

    test('whole-only navigation skip failure and success are explicit', () {
      final file = _untrackedFile('notes.txt');
      final controller = PatchReviewController(DiffSet([file]));
      final whole = file.wholeFileStageUnit!;

      expect(controller.currentSection, isNull);
      expect(controller.currentHunk, isNull);
      expect(controller.currentHunkContentSelection(), isNull);
      expect(controller.currentWholeFileChange, same(whole));
      expect(controller.totalReviewCount, 1);
      expect(controller.pendingCount, 1);

      controller
        ..selectNextSection()
        ..selectPreviousSection()
        ..skipCurrentReviewTarget();
      expect(controller.selectedSectionIndex, 0);
      expect(controller.statusForWholeFile(whole), PatchReviewStatus.skipped);
      expect(controller.skippedCount, 1);
      expect(controller.pendingCount, 0);

      controller.recordWholeFileStageOutcome(
        whole,
        GitStageOutcome.failedRefreshRequired,
      );
      expect(controller.statusForWholeFile(whole), PatchReviewStatus.failed);
      expect(controller.skippedCount, 0);
      expect(controller.stagedCount, 0);
      expect(controller.pendingCount, 1);

      controller
        ..skipCurrentReviewTarget()
        ..recordWholeFileStageOutcome(whole, GitStageOutcome.applied)
        ..skipCurrentReviewTarget();
      expect(controller.statusForWholeFile(whole), PatchReviewStatus.staged);
      expect(controller.skippedCount, 0);
      expect(controller.stagedCount, 1);
      expect(controller.pendingCount, 0);
    });

    test('whole failure isolates content and success fans out to targets', () {
      for (final outcome in [
        GitStageOutcome.rejectedUnchanged,
        GitStageOutcome.failedRefreshRequired,
      ]) {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        final whole = controller.currentWholeFileChange!;

        controller.recordWholeFileStageOutcome(whole, outcome);

        expect(
          controller.statusForWholeFile(whole),
          PatchReviewStatus.failed,
          reason: outcome.name,
        );
        expect(
          controller.statusForFile(controller.currentFile),
          PatchReviewStatus.unreviewed,
          reason: outcome.name,
        );
        expect(controller.stagedCount, 0, reason: outcome.name);
        expect(controller.pendingCount, 2, reason: outcome.name);
      }

      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff))
        ..skipCurrentReviewTarget();
      final whole = controller.currentWholeFileChange!;
      controller.recordWholeFileStageOutcome(whole, GitStageOutcome.applied);

      expect(controller.statusForWholeFile(whole), PatchReviewStatus.staged);
      expect(
        controller.statusForFile(controller.currentFile),
        PatchReviewStatus.staged,
      );
      for (final target in controller.currentFile.reviewTargets) {
        expect(controller.statusForTarget(target), PatchReviewStatus.staged);
      }
      expect(controller.stagedCount, 2);
      expect(controller.skippedCount, 0);
      expect(controller.pendingCount, 0);
    });

    test('progress counts content targets and one whole-only target', () {
      final content = parsePatchFixture(_twoHunkDiff).files.single;
      final wholeOnly = _untrackedFile('notes.txt');
      final controller = PatchReviewController(DiffSet([content, wholeOnly]));

      expect(controller.totalReviewCount, 3);
      controller.recordContentStageOutcome(
        controller.currentHunkContentSelection()!,
        GitStageOutcome.applied,
      );
      controller
        ..selectFile(1)
        ..skipCurrentReviewTarget();

      expect(controller.stagedCount, 1);
      expect(controller.skippedCount, 1);
      expect(controller.pendingCount, 1);
    });
  });
}

DiffFile _untrackedFile(String path) => DiffFile.untracked(
  path: fixturePath(path),
  entityKind: UntrackedEntityKind.regularFile,
  previewState: UntrackedPreviewState.completeText,
  previewLines: const ['preview'],
);

const _twoHunkDiff = '''
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

const _threeHunkDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,4 +1,4 @@
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
@@ -40,3 +40,3 @@ void finish() {
-  closeOld();
+  closeNew();
 }
''';

const _secondFileTwoHunkDiff = '''
diff --git a/lib/second.dart b/lib/second.dart
index 3333333..4444444 100644
--- a/lib/second.dart
+++ b/lib/second.dart
@@ -1,3 +1,3 @@
 void first() {
-  oldFirst();
+  newFirst();
 }
@@ -20,3 +20,3 @@ void second() {
-  oldSecond();
+  newSecond();
 }
''';
