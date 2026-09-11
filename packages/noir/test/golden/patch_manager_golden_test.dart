import 'dart:io';

import 'package:test/test.dart';

import '../../tool/patch_manager/patch_manager.dart';
import '../helpers/golden_testing.dart';
import '../helpers/patch_manager_fixtures.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('PatchManager Golden', () {
    test('large review workstation', () async {
      final tester = GoldenTester(width: 140, height: 40);
      try {
        await tester.expectGolden(
          _workspace(layoutWidth: 140),
          'patch_manager_workspace_large',
          updateGoldens: _updateGoldens,
        );
      } finally {
        tester.dispose();
      }
    });

    test('medium review workstation fallback', () async {
      final tester = GoldenTester(width: 100, height: 30);
      try {
        await tester.expectGolden(
          _workspace(layoutWidth: 100),
          'patch_manager_workspace_medium',
          updateGoldens: _updateGoldens,
        );
      } finally {
        tester.dispose();
      }
    });
  });
}

PatchManagerView _workspace({required int layoutWidth}) {
  final parsed = parsePatchFixture(_splitDiff);
  final binary = parsePatchFixture(_binaryDiff).files.single;
  final diff = DiffSet([
    ...parsed.files,
    DiffFile.untracked(
      path: fixturePath('notes draft.txt'),
      entityKind: UntrackedEntityKind.regularFile,
      previewState: UntrackedPreviewState.completeText,
      previewLines: const ['alpha', 'beta'],
    ),
    DiffFile.untracked(
      path: fixturePath('docs/truncated.txt'),
      entityKind: UntrackedEntityKind.regularFile,
      previewState: UntrackedPreviewState.truncatedText,
      previewLines: const ['bounded preview line'],
    ),
    DiffFile.untracked(
      path: fixturePath('links/current.link'),
      entityKind: UntrackedEntityKind.symbolicLink,
      previewState: UntrackedPreviewState.completeText,
      previewLines: const ['../releases/current'],
    ),
    DiffFile.untracked(
      path: fixturePath('assets/raw logo.png'),
      entityKind: UntrackedEntityKind.regularFile,
      previewState: UntrackedPreviewState.binary,
    ),
    binary,
  ]);
  final controller = PatchReviewController(diff);
  final file = controller.currentFile;
  controller
    ..recordContentStageOutcome(
      ContentStageSelection(file: file, sections: [file.sections[1]]),
      GitStageOutcome.applied,
    )
    ..recordContentStageOutcome(
      ContentStageSelection(file: file, sections: [file.sections[2]]),
      GitStageOutcome.rejectedUnchanged,
    );

  return PatchManagerView(
    controller: controller,
    autofocus: false,
    layoutWidthOverride: layoutWidth,
  );
}

const _splitDiff =
    '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,12 +1,14 @@
 void main() {
-  print('old');
+  print('new');
 }
${' '}
 void layout() {
   final columns = 3;
+  final rows = 8;
   print(columns);
 }
${' '}
 void footer() {
-  print('draft');
+  print('ready');
 }
''';

const _binaryDiff = '''
diff --git a/assets/logo.png b/assets/logo.png
index 1111111..2222222 100644
Binary files a/assets/logo.png and b/assets/logo.png differ
''';
