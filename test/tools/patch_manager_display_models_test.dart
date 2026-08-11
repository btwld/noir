import 'package:noir/src/tools/patch_manager/display_models.dart';
import 'package:noir/src/tools/patch_manager/patch_manager.dart';
import 'package:noir/src/tools/patch_manager/patch_theme.dart';
import 'package:test/test.dart';

import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('Patch Manager display models', () {
    test('choose wide and medium layout modes from workspace width', () {
      expect(PatchLayoutMode.fromWidth(140), PatchLayoutMode.wide);
      expect(PatchLayoutMode.fromWidth(116), PatchLayoutMode.wide);
      expect(PatchLayoutMode.fromWidth(100), PatchLayoutMode.medium);
    });

    test('expose only safe actions for each review state', () {
      final unreviewed = PatchActionSet.forTarget(
        PatchReviewStatus.unreviewed,
        stagesContent: true,
      );
      expect(unreviewed.labels, ['stage hunk', 'skip']);
      expect(unreviewed.items.map((item) => item.kind), [
        PatchActionKind.stage,
        PatchActionKind.skip,
      ]);
      expect(unreviewed.items.map((item) => item.selected), [false, false]);

      final skipped = PatchActionSet.forTarget(
        PatchReviewStatus.skipped,
        stagesContent: true,
      );
      expect(skipped.labels, ['stage hunk', 'skip']);
      expect(skipped.items.first.selected, isFalse);
      expect(skipped.items[1].selected, isTrue);

      expect(
        PatchActionSet.forTarget(
          PatchReviewStatus.staged,
          stagesContent: true,
        ).labels,
        ['staged'],
      );
      expect(
        PatchActionSet.forTarget(
          PatchReviewStatus.failed,
          stagesContent: true,
        ).labels,
        ['stage hunk', 'failed'],
      );

      final labels = [
        ...PatchActionSet.header(
          stagesContent: true,
          stagingEnabled: true,
        ).labels,
        for (final status in PatchReviewStatus.values)
          ...PatchActionSet.forTarget(status, stagesContent: true).labels,
      ].join(' ');
      expect(labels, isNot(contains('Reset')));
      expect(labels, isNot(contains('Discard')));
      expect(labels, isNot(contains('Stage Selected')));
      expect(labels, isNot(contains('checkout')));
      expect(labels, isNot(contains('restore')));
    });

    test('format basename-first file rows with parent and state hints', () {
      final diff = parsePatchFixture(_deepPathDiff);
      final file = diff.files.single;
      final row = PatchFileRowModel.fromFile(
        file,
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.medium,
      );

      expect(row.basename, 'patch_manager_app.dart');
      expect(row.fileStatusLetter, 'M');
      expect(row.fileKindGlyph, 'D');
      expect(row.fileKindColor.toHex(), PatchTheme.cyan.toHex());
      expect(row.additionCount, 1);
      expect(row.deletionCount, 1);
      expect(row.fallbackMetadata, isNull);
      expect(row.hasLineTotals, isTrue);
      expect(row.parentHint, contains('patch_manager'));
    });

    test('cleans low-value parent hints', () {
      final topLevel = PatchFileRowModel.fromFile(
        DiffFile.untracked(
          path: fixturePath('README.md'),
          entityKind: UntrackedEntityKind.regularFile,
          previewState: UntrackedPreviewState.completeText,
          previewLines: const ['hello'],
        ),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );
      final dotted = PatchFileRowModel.fromFile(
        _displayFile('foo.dart'),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );
      final compactDeep = PatchFileRowModel.fromFile(
        _displayFile('apps/web/components/workflow/sidebar.tsx'),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.medium,
      );
      final wideDeep = PatchFileRowModel.fromFile(
        _displayFile('apps/web/components/workflow/sidebar.tsx'),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );
      final wideTestPath = PatchFileRowModel.fromFile(
        _displayFile('test/tools/patch_manager_view_test.dart'),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );

      expect(topLevel.parentHint, isEmpty);
      expect(dotted.parentHint, isEmpty);
      expect(compactDeep.parentHint, 'workflow');
      expect(wideDeep.parentHint, 'workflow');
      expect(wideTestPath.parentHint, 'tools');
      expect(wideDeep.parentHint, isNot('.'));
    });

    test('categorizes common file-kind glyphs with safe one-cell letters', () {
      PatchFileRowModel row(String path) => PatchFileRowModel.fromFile(
        _displayFile(path),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );

      expect(row('lib/main.dart').fileKindGlyph, 'D');
      expect(row('src/index.ts').fileKindGlyph, 'T');
      expect(row('src/App.tsx').fileKindGlyph, 'X');
      expect(row('src/index.js').fileKindGlyph, 'J');
      expect(row('src/App.jsx').fileKindGlyph, 'J');
      expect(row('pubspec.yaml').fileKindGlyph, 'C');
      expect(row('config.toml').fileKindGlyph, 'C');
      expect(row('README.md').fileKindGlyph, 'T');
      expect(row('bin/tool').fileKindGlyph, 'F');
      expect(row('src/App.tsx').fileKindColor.toHex(), PatchTheme.cyan.toHex());
      expect(
        row('src/index.js').fileKindColor.toHex(),
        PatchTheme.amber.toHex(),
      );
    });

    test('expose only the two rendered header actions', () {
      final header = PatchActionSet.header(
        stagesContent: true,
        stagingEnabled: true,
      );

      expect(header.labels, ['stage hunk', 'skip']);
      expect(header.items.map((item) => item.kind), [
        PatchActionKind.stage,
        PatchActionKind.skip,
      ]);
    });

    test('disable only staging actions behind the refresh interlock', () {
      final contentHeader = PatchActionSet.header(
        stagesContent: true,
        stagingEnabled: false,
      );
      final wholeHeader = PatchActionSet.header(
        stagesContent: false,
        stagingEnabled: false,
      );
      final hunk = PatchActionSet.forTarget(
        PatchReviewStatus.unreviewed,
        stagesContent: true,
        stagingEnabled: false,
      );
      final whole = PatchActionSet.forTarget(
        PatchReviewStatus.skipped,
        stagesContent: false,
        stagingEnabled: false,
      );

      expect(contentHeader.labels, ['stage hunk', 'skip']);
      expect(wholeHeader.labels, ['stage file', 'skip']);
      expect(contentHeader.items.map((item) => item.enabled), [false, true]);
      expect(wholeHeader.items.map((item) => item.enabled), [false, true]);
      expect(hunk.items.map((item) => item.enabled), [false, true]);
      expect(whole.items.map((item) => item.enabled), [false, true]);
    });

    test('whole-file presentation is reason-specific', () {
      final titles = <WholeFileChangeReason, String>{
        WholeFileChangeReason.modified: 'Whole-file content change',
        WholeFileChangeReason.contentAndMode: 'Content and mode change',
        WholeFileChangeReason.modeOnly: 'File mode change',
        WholeFileChangeReason.binary: 'Binary file change',
        WholeFileChangeReason.unsupportedTextEncoding:
            'Unsupported text encoding',
        WholeFileChangeReason.added: 'Added file',
        WholeFileChangeReason.deleted: 'Deleted file',
        WholeFileChangeReason.renamed: 'Renamed file',
        WholeFileChangeReason.copied: 'Copied file',
        WholeFileChangeReason.typeChanged: 'File type change',
        WholeFileChangeReason.untracked: 'Untracked file',
      };

      for (final entry in titles.entries) {
        final paths = entry.key == WholeFileChangeReason.renamed
            ? [fixturePath('old.txt'), fixturePath('new.txt')]
            : [fixturePath('${entry.key.name}.txt')];
        final change = WholeFileChange(
          id: WholeFileChange.canonicalId(reason: entry.key, pathspecs: paths),
          pathspecs: paths,
          reason: entry.key,
        );
        final presentation = WholeFileChangeDisplay.fromChange(change);

        expect(presentation.title, entry.value, reason: entry.key.name);
        expect(presentation.description, isNotEmpty, reason: entry.key.name);
      }
    });

    test('expose footer text with medium key reminders', () {
      final wide = PatchFooterText.fromStatus(
        status: 'Idle.',
        busy: false,
        mode: PatchLayoutMode.wide,
      ).text;
      final medium = PatchFooterText.fromStatus(
        status: 'Idle.',
        busy: false,
        mode: PatchLayoutMode.medium,
      ).text;
      final working = PatchFooterText.fromStatus(
        status: 'Staging...',
        busy: true,
        mode: PatchLayoutMode.medium,
      ).text;

      expect(wide, 'Idle.');
      expect(medium, contains('Idle.'));
      expect(medium, contains('More: f file'));
      expect(medium, contains('r refresh'));
      expect(medium, contains('Tab panes'));
      expect(medium, contains('q quit'));
      expect(working, startsWith('Working...'));
    });

    test('mark binary and untracked file rows explicitly', () {
      final untracked = DiffFile.untracked(
        path: fixturePath('assets/raw logo.png'),
        entityKind: UntrackedEntityKind.regularFile,
        previewState: UntrackedPreviewState.binary,
      );
      final row = PatchFileRowModel.fromFile(
        untracked,
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );

      expect(row.basename, 'raw logo.png');
      expect(row.fileStatusLetter, 'U');
      expect(row.fileKindGlyph, 'B');
      expect(row.fileKindColor.toHex(), PatchTheme.amber.toHex());
      expect(row.additionCount, isNull);
      expect(row.deletionCount, isNull);
      expect(row.fallbackMetadata, contains('binary'));
      expect(row.hasLineTotals, isFalse);
      expect(row.parentHint, contains('assets'));
      expect(
        PatchFileRowModel.fromFile(
          untracked,
          status: PatchReviewStatus.staged,
          mode: PatchLayoutMode.wide,
        ).fileStatusLetter,
        'S',
      );
      expect(
        PatchFileRowModel.fromFile(
          untracked,
          status: PatchReviewStatus.skipped,
          mode: PatchLayoutMode.wide,
        ).fileStatusLetter,
        'K',
      );

      final trackedBinary = parsePatchFixture(_binaryDiff).files.single;
      final trackedRow = PatchFileRowModel.fromFile(
        trackedBinary,
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );
      expect(trackedRow.additionCount, isNull);
      expect(trackedRow.deletionCount, isNull);
      expect(trackedRow.fallbackMetadata, contains('binary'));
      expect(trackedRow.hasLineTotals, isFalse);
    });

    test('describe every untracked preview state without claiming totals', () {
      PatchFileRowModel row(
        UntrackedEntityKind kind,
        UntrackedPreviewState state, {
        List<String> lines = const [],
      }) => PatchFileRowModel.fromFile(
        DiffFile.untracked(
          path: fixturePath('entry.txt'),
          entityKind: kind,
          previewState: state,
          previewLines: lines,
        ),
        status: PatchReviewStatus.unreviewed,
        mode: PatchLayoutMode.wide,
      );

      final complete = row(
        UntrackedEntityKind.regularFile,
        UntrackedPreviewState.completeText,
        lines: const ['one', 'two'],
      );
      expect(complete.additionCount, 2);
      expect(complete.fallbackMetadata, isNull);

      final truncated = row(
        UntrackedEntityKind.regularFile,
        UntrackedPreviewState.truncatedText,
        lines: const ['one', 'two'],
      );
      expect(truncated.hasLineTotals, isFalse);
      expect(truncated.fallbackMetadata, 'preview 2 lines');

      expect(
        row(
          UntrackedEntityKind.regularFile,
          UntrackedPreviewState.binary,
        ).fallbackMetadata,
        'untracked binary',
      );
      expect(
        row(
          UntrackedEntityKind.regularFile,
          UntrackedPreviewState.unavailable,
        ).fallbackMetadata,
        'preview unavailable',
      );
      expect(
        row(
          UntrackedEntityKind.regularFile,
          UntrackedPreviewState.omitted,
        ).fallbackMetadata,
        'preview omitted',
      );

      final link = row(
        UntrackedEntityKind.symbolicLink,
        UntrackedPreviewState.completeText,
        lines: const ['target'],
      );
      expect(link.fileKindGlyph, 'L');
      expect(link.fallbackMetadata, 'link target');
      expect(link.hasLineTotals, isFalse);

      final truncatedLink = row(
        UntrackedEntityKind.symbolicLink,
        UntrackedPreviewState.truncatedText,
        lines: const ['target'],
      );
      expect(truncatedLink.fileKindGlyph, 'L');
      expect(truncatedLink.fallbackMetadata, 'link preview truncated');

      for (final state in [
        UntrackedPreviewState.unavailable,
        UntrackedPreviewState.omitted,
      ]) {
        final model = row(UntrackedEntityKind.symbolicLink, state);
        expect(model.fileKindGlyph, 'L');
        expect(model.hasLineTotals, isFalse);
        expect(model.fallbackMetadata, isNotEmpty);
      }

      final oneLine = row(
        UntrackedEntityKind.regularFile,
        UntrackedPreviewState.truncatedText,
        lines: const ['one'],
      );
      expect(oneLine.fallbackMetadata, 'preview 1 line');

      for (final state in [
        UntrackedPreviewState.unavailable,
        UntrackedPreviewState.omitted,
      ]) {
        final model = row(UntrackedEntityKind.unknown, state);
        expect(model.hasLineTotals, isFalse);
        expect(model.fallbackMetadata, isNotEmpty);
      }
    });

    test('derive untracked mode from entity kind independently of preview', () {
      for (final state in [
        UntrackedPreviewState.completeText,
        UntrackedPreviewState.truncatedText,
        UntrackedPreviewState.unavailable,
        UntrackedPreviewState.omitted,
      ]) {
        final link = DiffFile.untracked(
          path: fixturePath('${state.name}.link'),
          entityKind: UntrackedEntityKind.symbolicLink,
          previewState: state,
          previewLines:
              state == UntrackedPreviewState.completeText ||
                  state == UntrackedPreviewState.truncatedText
              ? const ['target']
              : const [],
        );
        expect(link.headerLines, isEmpty);
        expect(link.hunks, isEmpty);
        expect(link.sections, isEmpty);
        expect(
          link.wholeFileStageUnit!.reason,
          WholeFileChangeReason.untracked,
        );
        expect(link.canStageWholeFile, isTrue);
      }

      final unknown = DiffFile.untracked(
        path: fixturePath('vanished'),
        entityKind: UntrackedEntityKind.unknown,
        previewState: UntrackedPreviewState.unavailable,
      );
      expect(unknown.headerLines, isNot(contains('new file mode 100644')));
      expect(unknown.headerLines, isNot(contains('new file mode 120000')));
      expect(unknown.canStageWholeFile, isTrue);
    });
  });
}

DiffFile _displayFile(String path) {
  final identity = fixturePath(path);
  return DiffFile(
    oldPath: identity,
    newPath: identity,
    changeKind: DiffChangeKind.modified,
    payloadKind: DiffPayloadKind.text,
    headerLines: const [],
    hunks: const [],
    rawMetadata: const GitDiffMetadata(
      oldMode: '100644',
      newMode: '100644',
      oldObjectId: '1111111111111111111111111111111111111111',
      newObjectId: '2222222222222222222222222222222222222222',
      status: 'M',
      score: null,
    ),
  );
}

const _deepPathDiff = '''
diff --git a/lib/src/tools/patch_manager/patch_manager_app.dart b/lib/src/tools/patch_manager/patch_manager_app.dart
index 1111111..2222222 100644
--- a/lib/src/tools/patch_manager/patch_manager_app.dart
+++ b/lib/src/tools/patch_manager/patch_manager_app.dart
@@ -1 +1 @@
-old
+new
''';

const _binaryDiff = '''
diff --git a/assets/logo.png b/assets/logo.png
index 1111111..2222222 100644
Binary files a/assets/logo.png and b/assets/logo.png differ
''';
