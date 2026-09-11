import 'dart:async';

import 'package:noir/noir.dart'
    show Color, LogicalKeyboardKey, MouseButton, MouseEvent, MouseEventType;
import 'package:noir/src/framework/build_context.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:test/test.dart';

import '../../tool/patch_manager/patch_manager.dart';
import '../../tool/patch_manager/patch_manager_app.dart' show LayoutProbe;
import '../../tool/patch_manager/patch_theme.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('PatchManagerView', () {
    test('layout probe callback replacement is callback-only', () {
      final calls = <String>[];
      var visualUpdates = 0;
      final pipelineOwner = PipelineOwner(
        onNeedVisualUpdate: () => visualUpdates++,
      );
      final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
      const child = _StableLeaf();
      final element = LayoutProbe(
        onSizeChanged: (size) => calls.add('old:$size'),
        child: child,
      ).createElement()..mount(null, owner);
      final render =
          Element.findRenderObjectElement(element)!.renderObject! as RenderBox;
      pipelineOwner
        ..flushLayout(render, const BoxConstraints.tight(width: 4, height: 2))
        ..flushPaint(render, (_) {});
      calls.clear();
      visualUpdates = 0;

      element.update(
        LayoutProbe(
          onSizeChanged: (size) => calls.add('replacement:$size'),
          child: child,
        ),
      );

      expect(render.debugNeedsLayout, isFalse);
      expect(render.debugNeedsPaint, isFalse);
      expect(pipelineOwner.debugNeedsLayout, isFalse);
      expect(pipelineOwner.debugNeedsPaint, isFalse);
      expect(visualUpdates, 0);

      render.layout(const BoxConstraints.tight(width: 5, height: 2));

      expect(calls, ['replacement:Size(5, 2)']);
      expect(visualUpdates, 0);
    });

    test('renders a two-pane diff review surface', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final capture = BufferCapture(width: 140);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 140,
          ),
        );

        expect(buffer.containsText('Patch Manager'), isTrue);
        expect(buffer.containsText('Files'), isTrue);
        expect(buffer.containsText('Diff Review'), isTrue);
        expect(buffer.containsText('Review state'), isFalse);
        expect(buffer.containsText('Current Decision'), isFalse);
        expect(buffer.containsText('Index Preview'), isFalse);
        expect(buffer.containsText('lib/app.dart'), isTrue);
        expect(buffer.containsText('@@ -1,5 +1,5 @@'), isTrue);
        expect(buffer.containsText("print('new')"), isTrue);
        expect(buffer.containsText('staged 0/2'), isTrue);
        expect(buffer.containsText('skip'), isTrue);
        expect(buffer.containsText('stage hunk'), isTrue);
        expect(buffer.containsText('Approve'), isFalse);
        expect(buffer.containsText('approved'), isFalse);
        expect(buffer.containsText('Stage Selected'), isFalse);
        expect(buffer.containsText('Stage Approved'), isFalse);
        expect(buffer.containsText('Reset'), isFalse);
        expect(buffer.containsText('Discard'), isFalse);
      } finally {
        capture.dispose();
      }
    });

    test(
      'medium layout keeps direct hunk actions without compact review bar',
      () {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        final capture = BufferCapture(width: 100, height: 30);
        try {
          final buffer = capture.capture(
            PatchManagerView(
              controller: controller,
              autofocus: false,
              layoutWidthOverride: 100,
            ),
          );

          expect(buffer.containsText('Diff Review + Queue'), isFalse);
          expect(buffer.containsText('Diff Review'), isTrue);
          expect(buffer.containsText('Review:'), isFalse);
          expect(buffer.containsText('Current Decision'), isFalse);
          expect(buffer.containsText('Index Preview'), isFalse);
          expect(buffer.containsText('stage hunk'), isTrue);
          expect(buffer.containsText('Approve'), isFalse);
          expect(buffer.containsText('approved'), isFalse);
          expect(buffer.containsText('More: f file'), isTrue);
          expect(buffer.containsText('[f]'), isFalse);
          expect(buffer.containsText('Review Queue'), isFalse);
          expect(buffer.containsText("print('new')"), isTrue);
        } finally {
          capture.dispose();
        }
      },
    );

    test('medium file rows prioritize basename and parent path', () {
      final controller = PatchReviewController(
        parsePatchFixture(_shortParentDiff),
      );
      final capture = BufferCapture(width: 100, height: 30);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 100,
          ),
        );
        final leftPane = buffer.getRegion(0, 0, 30, 30);

        expect(leftPane, contains('foo.dart'));
        expect(leftPane, contains('api'));
        expect(leftPane, contains('+1'));
        expect(leftPane, contains('-1'));
        final plus = buffer
            .findText('+1')
            .singleWhere((position) => position.x < 30);
        final minus = buffer
            .findText('-1')
            .singleWhere((position) => position.x < 30);
        _expectColorClose(
          buffer.getForegroundColor(plus.x, plus.y),
          PatchTheme.green,
        );
        _expectColorClose(
          buffer.getForegroundColor(minus.x, minus.y),
          PatchTheme.red,
        );
      } finally {
        capture.dispose();
      }
    });

    test('wide sidebar uses the new capped thirty-percent width', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final capture = BufferCapture(width: 140, height: 30);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 140,
          ),
        );

        final leftPane = buffer.getRegion(0, 0, 42, 30);
        final diffPaneStart = buffer.toLines()[5].indexOf('Diff Review');

        expect(leftPane, contains('app.dart'));
        expect(leftPane, contains('+2'));
        expect(leftPane, contains('-1'));
        expect(diffPaneStart, greaterThanOrEqualTo(43));
        expect(diffPaneStart, lessThan(50));
      } finally {
        capture.dispose();
      }
    });

    test('left sidebar renders files in deterministic basename order', () {
      final controller = PatchReviewController(
        parsePatchFixture(_unsortedSidebarDiff),
      );
      final capture = BufferCapture(width: 140, height: 40);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 140,
          ),
        );

        final leftPane = buffer.getRegion(0, 0, 42, 40);
        final alphaOffset = leftPane.indexOf('alpha.dart');
        final betaOffset = leftPane.indexOf('beta.ts');
        final zetaOffset = leftPane.indexOf('zeta.dart');

        expect(alphaOffset, isNonNegative);
        expect(betaOffset, isNonNegative);
        expect(zetaOffset, isNonNegative);
        expect(alphaOffset, lessThan(betaOffset));
        expect(betaOffset, lessThan(zetaOffset));
      } finally {
        capture.dispose();
      }
    });

    test('arrow keys move through the sorted visible sidebar order', () async {
      final controller = PatchReviewController(
        parsePatchFixture(_unsortedSidebarDiff),
      );
      final driver = KeyDriver(
        PatchManagerView(controller: controller, layoutWidthOverride: 140),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      expect(presentedPath(controller.currentFile), 'apps/zeta/zeta.dart');

      await driver.sendLogicalKey(LogicalKeyboardKey.arrowUp);
      expect(presentedPath(controller.currentFile), 'packages/core/beta.ts');

      await driver.sendLogicalKey(LogicalKeyboardKey.arrowUp);
      expect(presentedPath(controller.currentFile), 'apps/api/alpha.dart');
      driver.dispose();
    });

    test('clicking a sorted sidebar row selects the matching file', () async {
      final controller = PatchReviewController(
        parsePatchFixture(_unsortedSidebarDiff),
      );
      final driver = KeyDriver(
        PatchManagerView(controller: controller, layoutWidthOverride: 140),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 5,
          y: 6,
        ),
      );
      expect(presentedPath(controller.currentFile), 'apps/api/alpha.dart');

      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 5,
          y: 7,
        ),
      );
      expect(presentedPath(controller.currentFile), 'packages/core/beta.ts');
      driver.dispose();
    });

    test('diff header shows semantic file totals', () {
      final controller = PatchReviewController(
        parsePatchFixture(_deepPathDiff),
      );
      final capture = BufferCapture(width: 100, height: 30);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 100,
          ),
        );
        final lines = buffer.toLines();
        final headerY = lines.indexWhere(
          (line) => line.contains('hunk 1 of 1'),
        );
        expect(headerY, isNonNegative);
        final plusX = lines[headerY].indexOf('+1');
        final minusX = lines[headerY].indexOf('-1');
        expect(plusX, isNonNegative);
        expect(minusX, isNonNegative);

        _expectColorClose(
          buffer.getForegroundColor(plusX, headerY),
          PatchTheme.green,
        );
        _expectColorClose(
          buffer.getForegroundColor(minusX, headerY),
          PatchTheme.red,
        );
      } finally {
        capture.dispose();
      }
    });

    test('renders truthful untracked preview notices for every state', () {
      final cases = <({DiffFile file, List<String> expected})>[
        (
          file: DiffFile.untracked(
            path: fixturePath('complete.txt'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.completeText,
            previewLines: const ['complete preview'],
          ),
          expected: const ['complete preview'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('truncated.txt'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.truncatedText,
            previewLines: const ['bounded prefix'],
          ),
          expected: const [
            'preview +1',
            'text preview is truncated',
            'bounded prefix',
          ],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('binary.dat'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.binary,
          ),
          expected: const ['Untracked binary file', 'stage the file'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('unavailable.txt'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.unavailable,
          ),
          expected: const ['preview unavailable', 'stage the path'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('omitted.txt'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.omitted,
          ),
          expected: const ['preview omitted', 'stage the path'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('complete.link'),
            entityKind: UntrackedEntityKind.symbolicLink,
            previewState: UntrackedPreviewState.completeText,
            previewLines: const ['../target'],
          ),
          expected: const ['symbolic-link target preview', '../target'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('truncated.link'),
            entityKind: UntrackedEntityKind.symbolicLink,
            previewState: UntrackedPreviewState.truncatedText,
            previewLines: const ['../partial'],
          ),
          expected: const [
            'preview +1',
            'target preview is truncated',
            '../partial',
          ],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('unavailable.link'),
            entityKind: UntrackedEntityKind.symbolicLink,
            previewState: UntrackedPreviewState.unavailable,
          ),
          expected: const ['preview unavailable', 'stage the path'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('omitted.link'),
            entityKind: UntrackedEntityKind.symbolicLink,
            previewState: UntrackedPreviewState.omitted,
          ),
          expected: const ['preview omitted', 'stage the path'],
        ),
        (
          file: DiffFile.untracked(
            path: fixturePath('vanished'),
            entityKind: UntrackedEntityKind.unknown,
            previewState: UntrackedPreviewState.unavailable,
          ),
          expected: const ['preview unavailable', 'stage the path'],
        ),
      ];

      for (final testCase in cases) {
        final capture = BufferCapture(width: 140, height: 30);
        try {
          final buffer = capture.capture(
            PatchManagerView(
              controller: PatchReviewController(DiffSet([testCase.file])),
              autofocus: false,
              layoutWidthOverride: 140,
            ),
          );
          for (final text in testCase.expected) {
            expect(
              buffer.containsText(text),
              isTrue,
              reason: '${presentedPath(testCase.file)} should show "$text"',
            );
          }
          if (testCase.file.untrackedPreviewState case final state
              when state == UntrackedPreviewState.binary ||
                  state == UntrackedPreviewState.unavailable ||
                  state == UntrackedPreviewState.omitted) {
            expect(
              buffer.containsText('+0 -0'),
              isFalse,
              reason:
                  '${presentedPath(testCase.file)} has no complete line totals',
            );
          }
        } finally {
          capture.dispose();
        }
      }
    });

    test('selected added lines keep addition colors', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final capture = BufferCapture(width: 140);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 140,
          ),
        );
        final addedText = buffer.findText("print('new')").single;

        _expectColorClose(
          buffer.getBackgroundColor(addedText.x, addedText.y),
          PatchTheme.diffAddBg,
        );
        _expectColorClose(
          buffer.getForegroundColor(addedText.x, addedText.y),
          PatchTheme.diffAddFg,
        );
      } finally {
        capture.dispose();
      }
    });

    test('selected diff line uses the arrow cursor marker', () {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final capture = BufferCapture(width: 140);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 140,
          ),
        );
        final addedText = buffer.findText("print('new')").single;
        final line = buffer.toLines()[addedText.y];

        expect(line, contains('${PatchTheme.caret} +'));
        expect(line, isNot(contains('> +')));
      } finally {
        capture.dispose();
      }
    });

    test('hunk action chips stage and skip the clicked hunk', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final stagePositions = _findHunkChipPositions(controller, 'stage hunk');
      final secondStagePosition = stagePositions.reduce(
        (a, b) => a.y > b.y ? a : b,
      );
      final stagedSelections = <ContentStageSelection>[];
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          layoutWidthOverride: 140,
          onStageContent: (selection) async {
            stagedSelections.add(selection);
            return const GitStageResult(
              outcome: GitStageOutcome.applied,
              stdout: '',
              stderr: '',
              patch: '',
            );
          },
        ),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: secondStagePosition.x + 1,
          y: secondStagePosition.y,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final secondHunk = controller.currentFile.hunks[1];
      expect(stagedSelections, hasLength(1));
      expect(
        stagedSelections.single.sections.map((section) => section.id),
        secondHunk.sections.map((section) => section.id),
      );
      expect(controller.statusForHunk(secondHunk), PatchReviewStatus.staged);
      expect(
        controller.statusForHunk(controller.currentFile.hunks.first),
        PatchReviewStatus.unreviewed,
      );
      driver.dispose();

      final skipController = PatchReviewController(
        parsePatchFixture(_twoHunkDiff),
      );
      final skipDriver = KeyDriver(
        PatchManagerView(controller: skipController, layoutWidthOverride: 140),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await skipDriver.ready();
      final skipPositions = _captureDriver(skipDriver)
          .findText('skip')
          .where(
            (position) =>
                position.y > 6 && position.x > 100 && position.x < 138,
          )
          .toList(growable: false);
      final secondSkipPosition = skipPositions.reduce(
        (a, b) => a.y > b.y ? a : b,
      );
      await skipDriver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: secondSkipPosition.x + 1,
          y: secondSkipPosition.y,
        ),
      );
      final skippedHunk = skipController.currentFile.hunks[1];
      expect(
        skipController.statusForHunk(skippedHunk),
        PatchReviewStatus.skipped,
      );
      expect(
        skipController.statusForHunk(skipController.currentFile.hunks.first),
        PatchReviewStatus.unreviewed,
      );
      skipDriver.dispose();
    });

    test(
      'Space, s, and S each stage the current unstaged hunk directly',
      () async {
        for (final key in [' ', 's', 'S']) {
          final controller = PatchReviewController(
            parsePatchFixture(_longSectionDiff),
          );
          final stagedSelections = <ContentStageSelection>[];
          final driver = KeyDriver(
            PatchManagerView(
              controller: controller,
              onStageContent: (selection) async {
                stagedSelections.add(selection);
                return const GitStageResult(
                  outcome: GitStageOutcome.applied,
                  stdout: '',
                  stderr: '',
                  patch: '',
                );
              },
            ),
            width: 100,
          );

          await driver.ready();
          final stagedHunk = controller.currentHunk!;
          await driver.sendCharacter(key);
          await Future<void>.delayed(Duration.zero);

          expect(stagedSelections, hasLength(1));
          expect(stagedSelections.single.sections, stagedHunk.sections);
          expect(
            controller.statusForHunk(stagedHunk),
            PatchReviewStatus.staged,
          );
          driver.dispose();
        }
      },
    );

    test(
      'whole-only content keys explain while skip then file stage remains valid',
      () async {
        final file = DiffFile.untracked(
          path: fixturePath('notes.txt'),
          entityKind: UntrackedEntityKind.regularFile,
          previewState: UntrackedPreviewState.completeText,
          previewLines: const ['direct preview line'],
        );
        final controller = PatchReviewController(DiffSet([file]));
        var contentCalls = 0;
        var wholeCalls = 0;
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            onStageContent: (selection) async {
              contentCalls++;
              return _stageResult(GitStageOutcome.applied);
            },
            onStageWholeFile: (change) async {
              wholeCalls++;
              expect(change, same(file.wholeFileStageUnit));
              return _stageResult(GitStageOutcome.applied);
            },
          ),
          width: 140,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        for (final key in [' ', 's', 'S']) {
          await driver.sendCharacter(key);
        }
        await _settleView();

        expect(contentCalls, 0);
        expect(wholeCalls, 0);
        expect(
          _captureDriver(driver).containsText('requires whole-file staging'),
          isTrue,
          reason: _captureDriver(driver).toLines().join('\n'),
        );
        expect(_captureDriver(driver).containsText('Untracked file'), isTrue);
        expect(_captureDriver(driver).containsText('stage file'), isTrue);
        expect(
          _captureDriver(driver).containsText('direct preview line'),
          isTrue,
        );

        await driver.sendCharacter('x');
        expect(
          controller.statusForWholeFile(file.wholeFileStageUnit!),
          PatchReviewStatus.skipped,
        );
        await driver.sendCharacter('f');
        await Future<void>.delayed(Duration.zero);

        expect(wholeCalls, 1);
        expect(
          controller.statusForWholeFile(file.wholeFileStageUnit!),
          PatchReviewStatus.staged,
        );
        driver.dispose();
      },
    );

    test(
      'whole-file card and header chips route the exact typed target',
      () async {
        for (final surface in ['header', 'card']) {
          final file = DiffFile.untracked(
            path: fixturePath('$surface-notes.txt'),
            entityKind: UntrackedEntityKind.regularFile,
            previewState: UntrackedPreviewState.completeText,
            previewLines: const ['direct preview line'],
          );
          final controller = PatchReviewController(DiffSet([file]));
          final whole = file.wholeFileStageUnit!;
          final contentSelections = <ContentStageSelection>[];
          final wholeChanges = <WholeFileChange>[];
          final driver = KeyDriver(
            PatchManagerView(
              controller: controller,
              layoutWidthOverride: 140,
              onStageContent: (selection) async {
                contentSelections.add(selection);
                return _stageResult(GitStageOutcome.applied);
              },
              onStageWholeFile: (change) async {
                wholeChanges.add(change);
                return _stageResult(GitStageOutcome.applied);
              },
            ),
            width: 140,
            height: 40,
            paintFrames: true,
          );

          await driver.ready();
          final positions =
              _captureDriver(
                  driver,
                ).findText('stage file').toList(growable: false)
                ..sort((left, right) => left.y.compareTo(right.y));
          expect(positions, hasLength(2), reason: surface);
          final position = surface == 'header'
              ? positions.first
              : positions.last;

          await driver.sendMouse(
            MouseEvent(
              type: MouseEventType.down,
              button: MouseButton.left,
              x: position.x + 1,
              y: position.y,
            ),
          );
          await _settleView();

          expect(contentSelections, isEmpty, reason: surface);
          expect(wholeChanges, [same(whole)]);
          expect(
            controller.statusForWholeFile(whole),
            PatchReviewStatus.staged,
            reason: surface,
          );
          driver.dispose();
        }
      },
    );

    test('locked whole-file card and header chips cannot stage', () async {
      final file = DiffFile.untracked(
        path: fixturePath('locked-notes.txt'),
        entityKind: UntrackedEntityKind.regularFile,
        previewState: UntrackedPreviewState.completeText,
        previewLines: const ['direct preview line'],
      );
      final controller = PatchReviewController(DiffSet([file]));
      var wholeCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          layoutWidthOverride: 140,
          onStageWholeFile: (change) async {
            wholeCalls++;
            return _stageResult(
              GitStageOutcome.failedRefreshRequired,
              stderr: 'whole pointer uncertainty',
            );
          },
        ),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      await driver.sendCharacter('f');
      await _settleView();
      expect(wholeCalls, 1);

      final positions =
          _captureDriver(driver).findText('stage file').toList(growable: false)
            ..sort((left, right) => left.y.compareTo(right.y));
      expect(positions, hasLength(2));
      for (final position in positions) {
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: position.x + 1,
            y: position.y,
          ),
        );
      }
      await _settleView();

      expect(wholeCalls, 1);
      expect(
        controller.statusForWholeFile(file.wholeFileStageUnit!),
        PatchReviewStatus.failed,
      );
      expect(
        _captureDriver(driver).containsText('index may have changed'),
        isTrue,
      );
      driver.dispose();
    });

    test('content-capable whole failure leaves content pending', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) async {
            contentCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
          onStageWholeFile: (change) async => _stageResult(
            GitStageOutcome.rejectedUnchanged,
            stderr: 'whole-file rejection',
          ),
        ),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      final whole = controller.currentWholeFileChange!;
      await driver.sendCharacter('f');
      await Future<void>.delayed(Duration.zero);

      expect(controller.statusForWholeFile(whole), PatchReviewStatus.failed);
      expect(
        controller.statusForFile(controller.currentFile),
        PatchReviewStatus.unreviewed,
      );
      expect(controller.pendingCount, 2);

      await driver.sendCharacter('s');
      await Future<void>.delayed(Duration.zero);

      expect(contentCalls, 1);
      expect(
        controller.statusForTarget(controller.currentFile.sections.first),
        PatchReviewStatus.staged,
      );
      driver.dispose();
    });

    test('escaped content staging callback exception locks staging', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      var wholeCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) {
            contentCalls++;
            throw StateError('content callback escaped');
          },
          onStageWholeFile: (change) async {
            wholeCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
        ),
        width: 180,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      final selected = controller.currentSection!;
      await driver.sendCharacter('s');
      await Future<void>.delayed(Duration.zero);

      expect(controller.statusForTarget(selected), PatchReviewStatus.failed);
      expect(
        controller.statusForWholeFile(controller.currentWholeFileChange!),
        PatchReviewStatus.unreviewed,
      );

      await driver.sendCharacter('s');
      await driver.sendCharacter('f');
      await _settleView();

      expect(contentCalls, 1);
      expect(wholeCalls, 0);
      final buffer = _captureDriver(driver);
      expect(
        buffer.containsText('index may have changed'),
        isTrue,
        reason: buffer.toLines().join('\n'),
      );
      expect(buffer.containsText('content callback escaped'), isTrue);
      expect(buffer.containsText('refresh required'), isTrue);
      driver.dispose();
    });

    test('escaped whole staging callback exception locks staging', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      var wholeCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) async {
            contentCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
          onStageWholeFile: (change) {
            wholeCalls++;
            throw StateError('whole callback escaped');
          },
        ),
        width: 180,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      final whole = controller.currentWholeFileChange!;
      await driver.sendCharacter('f');
      await Future<void>.delayed(Duration.zero);

      expect(controller.statusForWholeFile(whole), PatchReviewStatus.failed);
      expect(
        controller.statusForFile(controller.currentFile),
        PatchReviewStatus.unreviewed,
      );

      await driver.sendCharacter('f');
      await driver.sendCharacter('s');

      expect(wholeCalls, 1);
      expect(contentCalls, 0);
      final buffer = _captureDriver(driver);
      expect(buffer.containsText('index may have changed'), isTrue);
      expect(buffer.containsText('whole callback escaped'), isTrue);
      expect(buffer.containsText('refresh required'), isTrue);
      driver.dispose();
    });

    test('throwing-toString content staging callback locks staging', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      var wholeCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) {
            contentCalls++;
            throw _ThrowingToString();
          },
          onStageWholeFile: (change) async {
            wholeCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
        ),
        width: 180,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      final selected = controller.currentSection!;
      await driver.sendCharacter('s');
      await _settleView();

      expect(controller.statusForTarget(selected), PatchReviewStatus.failed);
      expect(
        controller.statusForWholeFile(controller.currentWholeFileChange!),
        PatchReviewStatus.unreviewed,
      );

      await driver.sendCharacter('s');
      await driver.sendCharacter('f');
      await _settleView();

      expect(contentCalls, 1);
      expect(wholeCalls, 0);
      final buffer = _captureDriver(driver);
      expect(buffer.containsText('index may have changed'), isTrue);
      expect(buffer.containsText('Exception text unavailable.'), isTrue);
      expect(
        buffer
            .toLines()
            .join('\n')
            .codeUnits
            .where((codeUnit) => codeUnit < 0x20 && codeUnit != 0x0a),
        isEmpty,
      );
      driver.dispose();
    });

    test('throwing-toString whole staging callback locks staging', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      var wholeCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) async {
            contentCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
          onStageWholeFile: (change) {
            wholeCalls++;
            throw _ThrowingToString();
          },
        ),
        width: 180,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      final whole = controller.currentWholeFileChange!;
      await driver.sendCharacter('f');
      await _settleView();

      expect(controller.statusForWholeFile(whole), PatchReviewStatus.failed);
      expect(
        controller.statusForFile(controller.currentFile),
        PatchReviewStatus.unreviewed,
      );

      await driver.sendCharacter('f');
      await driver.sendCharacter('s');
      await _settleView();

      expect(wholeCalls, 1);
      expect(contentCalls, 0);
      final buffer = _captureDriver(driver);
      expect(buffer.containsText('index may have changed'), isTrue);
      expect(buffer.containsText('Exception text unavailable.'), isTrue);
      driver.dispose();
    });

    test(
      'locked view keeps skip quit and refresh while blocking staging',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        var contentCalls = 0;
        var wholeCalls = 0;
        var refreshCalls = 0;
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            layoutWidthOverride: 180,
            onStageContent: (selection) async {
              contentCalls++;
              return _stageResult(
                GitStageOutcome.failedRefreshRequired,
                stderr: 'locked interaction uncertainty',
              );
            },
            onStageWholeFile: (change) async {
              wholeCalls++;
              return _stageResult(GitStageOutcome.applied);
            },
            onRefresh: () {
              refreshCalls++;
              throw StateError('locked refresh still callable');
            },
          ),
          width: 180,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        final currentHunk = controller.currentHunk!;
        await driver.sendCharacter('s');
        await _settleView();
        expect(contentCalls, 1);
        expect(controller.statusForHunk(currentHunk), PatchReviewStatus.failed);

        await driver.sendCharacter('x');
        expect(
          controller.statusForHunk(currentHunk),
          PatchReviewStatus.skipped,
        );
        await driver.sendCharacter('r');
        await _settleView();
        expect(refreshCalls, 1);

        await driver.sendCharacter('s');
        await driver.sendCharacter('f');
        final stageHunkPositions = _captureDriver(
          driver,
        ).findText('stage hunk').toList(growable: false);
        expect(stageHunkPositions, isNotEmpty);
        for (final position in stageHunkPositions) {
          await driver.sendMouse(
            MouseEvent(
              type: MouseEventType.down,
              button: MouseButton.left,
              x: position.x + 1,
              y: position.y,
            ),
          );
        }
        await _settleView();

        expect(contentCalls, 1);
        expect(wholeCalls, 0);
        final buffer = _captureDriver(driver);
        expect(buffer.containsText('locked interaction uncertainty'), isTrue);
        expect(buffer.containsText('locked refresh still callable'), isTrue);

        await driver.sendCharacter('q');
        expect(driver.exitRequests, [0]);
        driver.dispose();
      },
    );

    test(
      'failed refresh retains original stage diagnostic and reports latest refresh diagnostic',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        var contentCalls = 0;
        var wholeCalls = 0;
        var refreshCalls = 0;
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            onStageContent: (selection) async {
              contentCalls++;
              return _stageResult(
                GitStageOutcome.failedRefreshRequired,
                stderr: 'original mutation uncertainty',
              );
            },
            onStageWholeFile: (change) async {
              wholeCalls++;
              return _stageResult(GitStageOutcome.applied);
            },
            onRefresh: () async {
              refreshCalls++;
              throw StateError(
                refreshCalls == 1
                    ? 'first refresh failure'
                    : 'second refresh failure',
              );
            },
          ),
          width: 180,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        await driver.sendCharacter('s');
        await Future<void>.delayed(Duration.zero);
        expect(refreshCalls, 0, reason: 'staging must not auto-refresh');

        await driver.sendCharacter('r');
        await _settleView();
        var buffer = _captureDriver(driver);
        expect(buffer.containsText('original mutation uncertainty'), isTrue);
        expect(
          buffer.containsText('first refresh failure'),
          isTrue,
          reason: buffer.toLines().join('\n'),
        );

        await driver.sendCharacter('s');
        await driver.sendCharacter('f');
        expect(contentCalls, 1);
        expect(wholeCalls, 0);

        await driver.sendCharacter('r');
        await _settleView();
        buffer = _captureDriver(driver);
        expect(buffer.containsText('original mutation uncertainty'), isTrue);
        expect(buffer.containsText('second refresh failure'), isTrue);
        expect(buffer.containsText('first refresh failure'), isFalse);
        expect(refreshCalls, 2);
        driver.dispose();
      },
    );

    test('throwing-toString refresh error remains safely locked', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var contentCalls = 0;
      var wholeCalls = 0;
      var refreshCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) async {
            contentCalls++;
            return _stageResult(
              GitStageOutcome.failedRefreshRequired,
              stderr: 'original mutation uncertainty',
            );
          },
          onStageWholeFile: (change) async {
            wholeCalls++;
            return _stageResult(GitStageOutcome.applied);
          },
          onRefresh: () {
            refreshCalls++;
            throw _ThrowingToString();
          },
        ),
        width: 180,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();
      await driver.sendCharacter('s');
      await _settleView();
      await driver.sendCharacter('r');
      await _settleView();

      final buffer = _captureDriver(driver);
      expect(buffer.containsText('original mutation uncertainty'), isTrue);
      expect(buffer.containsText('Exception text unavailable.'), isTrue);
      expect(refreshCalls, 1);

      await driver.sendCharacter('s');
      await driver.sendCharacter('f');
      await _settleView();
      expect(contentCalls, 1);
      expect(wholeCalls, 0);
      driver.dispose();
    });

    test(
      'successful refresh unlocks and clears retained operation feedback',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        var contentCalls = 0;
        var wholeCalls = 0;
        var refreshCalls = 0;
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            onStageContent: (selection) async {
              contentCalls++;
              return contentCalls == 1
                  ? _stageResult(
                      GitStageOutcome.failedRefreshRequired,
                      stderr: 'retained stage diagnostic',
                    )
                  : _stageResult(GitStageOutcome.applied);
            },
            onStageWholeFile: (change) async {
              wholeCalls++;
              return _stageResult(GitStageOutcome.applied);
            },
            onRefresh: () async {
              refreshCalls++;
              if (refreshCalls == 1) {
                throw StateError('latest failed refresh');
              }
              return parsePatchFixture(_twoHunkDiff);
            },
          ),
          width: 180,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        await driver.sendCharacter('s');
        await Future<void>.delayed(Duration.zero);
        await driver.sendCharacter('r');
        await _settleView();
        expect(
          _captureDriver(driver).containsText('retained stage diagnostic'),
          isTrue,
          reason: _captureDriver(driver).toLines().join('\n'),
        );
        expect(
          _captureDriver(driver).containsText('latest failed refresh'),
          isTrue,
        );

        await driver.sendCharacter('r');
        await _settleView();
        var buffer = _captureDriver(driver);
        expect(buffer.containsText('Refreshed 2 changes.'), isTrue);
        expect(buffer.containsText('retained stage diagnostic'), isFalse);
        expect(buffer.containsText('latest failed refresh'), isFalse);

        await driver.sendCharacter('s');
        await Future<void>.delayed(Duration.zero);
        await driver.sendCharacter('f');
        await Future<void>.delayed(Duration.zero);

        expect(contentCalls, 2);
        expect(wholeCalls, 1);
        buffer = _captureDriver(driver);
        expect(buffer.containsText('Staged whole file.'), isTrue);
        driver.dispose();
      },
    );

    test(
      'successful stage shows staged feedback without auto-refresh',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        var refreshCalls = 0;
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            onStageContent: (selection) async => const GitStageResult(
              outcome: GitStageOutcome.applied,
              stdout: '',
              stderr: '',
              patch: '',
            ),
            onRefresh: () async {
              refreshCalls++;
              return parsePatchFixture(_secondHunkOnlyDiff);
            },
          ),
          width: 140,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        await driver.sendCharacter('s');
        await Future<void>.delayed(Duration.zero);

        expect(refreshCalls, 0);
        expect(
          controller.statusForHunk(controller.currentHunk!),
          PatchReviewStatus.staged,
        );

        final capture = BufferCapture(width: 140, height: 40);
        try {
          final buffer = capture.capture(
            PatchManagerView(
              controller: controller,
              autofocus: false,
              layoutWidthOverride: 140,
            ),
          );
          expect(buffer.containsText('staged'), isTrue);
        } finally {
          capture.dispose();
          driver.dispose();
        }
      },
    );

    test('refresh is single-flight, last-good, and retryable', () async {
      final originalDiff = parsePatchFixture(_twoHunkDiff);
      final controller = PatchReviewController(originalDiff)
        ..selectSection(1)
        ..skipCurrentReviewTarget();
      final retainedSectionId = controller.currentSection!.id;
      final refreshes = <Completer<DiffSet>>[];
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onRefresh: () {
            final completer = Completer<DiffSet>();
            refreshes.add(completer);
            return completer.future;
          },
        ),
      );
      await driver.ready();

      await driver.sendCharacter('r');
      await driver.sendCharacter('r');
      expect(refreshes, hasLength(1));

      refreshes.single.completeError(StateError('refresh failure'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.diff, same(originalDiff));
      expect(presentedPath(controller.currentFile), 'lib/app.dart');
      expect(controller.currentSection!.id, retainedSectionId);
      expect(
        controller.statusForTarget(controller.currentSection!),
        PatchReviewStatus.skipped,
      );

      await driver.sendCharacter('r');
      expect(refreshes, hasLength(2));
      final retainedDiff = parsePatchFixture(_twoHunkDiff);
      final addedFile = parsePatchFixture(_twoFileDiff).files.last;
      refreshes.last.complete(DiffSet([...retainedDiff.files, addedFile]));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(controller.diff.files, hasLength(2));
      expect(controller.currentSection!.id, retainedSectionId);
      expect(
        controller.statusForTarget(controller.currentSection!),
        PatchReviewStatus.skipped,
      );
      driver.dispose();
    });

    test(
      'refresh completions after disposal are consumed without mutation',
      () async {
        for (final fails in [false, true]) {
          final originalDiff = parsePatchFixture(_twoHunkDiff);
          final controller = PatchReviewController(originalDiff);
          final completer = Completer<DiffSet>();
          final driver = KeyDriver(
            PatchManagerView(
              controller: controller,
              onRefresh: () => completer.future,
            ),
          );
          await driver.ready();
          await driver.sendCharacter('r');
          driver.dispose();

          final uncaught = <Object>[];
          await runZonedGuarded(() async {
            if (fails) {
              completer.completeError(StateError('late refresh failure'));
            } else {
              completer.complete(parsePatchFixture(_secondHunkOnlyDiff));
            }
            await Future<void>.delayed(Duration.zero);
            await Future<void>.delayed(Duration.zero);
          }, (error, stackTrace) => uncaught.add(error));

          expect(uncaught, isEmpty, reason: 'fails=$fails');
          expect(controller.diff, same(originalDiff), reason: 'fails=$fails');
        }
      },
    );

    test('keyboard staging does not restage an already staged hunk', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      var stageCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) async {
            stageCalls++;
            return const GitStageResult(
              outcome: GitStageOutcome.applied,
              stdout: '',
              stderr: '',
              patch: '',
            );
          },
        ),
        width: 100,
      );

      await driver.ready();
      await driver.sendCharacter('s');
      await Future<void>.delayed(Duration.zero);
      await driver.sendCharacter('s');
      await Future<void>.delayed(Duration.zero);

      expect(stageCalls, 1);
      driver.dispose();
    });

    test(
      'whole staging remains available after partial content staging',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_twoHunkDiff),
        );
        controller.recordContentStageOutcome(
          ContentStageSelection(
            file: controller.currentFile,
            sections: [controller.currentFile.sections.first],
          ),
          GitStageOutcome.applied,
        );
        final stagedChanges = <WholeFileChange>[];
        final driver = KeyDriver(
          PatchManagerView(
            controller: controller,
            onStageWholeFile: (change) async {
              stagedChanges.add(change);
              return const GitStageResult(
                outcome: GitStageOutcome.applied,
                stdout: '',
                stderr: '',
                patch: '',
              );
            },
          ),
          width: 100,
        );

        await driver.ready();
        await driver.sendCharacter('f');
        await Future<void>.delayed(Duration.zero);

        expect(stagedChanges, [controller.currentFile.wholeFileStageUnit]);
        driver.dispose();
      },
    );

    test('x skips the current hunk', () async {
      final controller = PatchReviewController(
        parsePatchFixture(_longSectionDiff),
      );
      final driver = KeyDriver(
        PatchManagerView(controller: controller),
        width: 100,
      );

      await driver.ready();
      final skippedHunk = controller.currentHunk!;
      await driver.sendCharacter('x');

      expect(controller.statusForHunk(skippedHunk), PatchReviewStatus.skipped);
      for (final section in skippedHunk.sections) {
        expect(controller.statusForTarget(section), PatchReviewStatus.skipped);
      }
      driver.dispose();
    });

    test('clicking a file row selects the file under the cursor', () async {
      final controller = PatchReviewController(
        parsePatchFixture(_threeFileDiff),
      );
      final driver = KeyDriver(
        PatchManagerView(controller: controller, layoutWidthOverride: 140),
        width: 140,
        height: 40,
        paintFrames: true,
      );

      await driver.ready();

      Future<int> clickAt(int y) async {
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 5,
            y: y,
          ),
        );
        return controller.selectedFileIndex;
      }

      // The file pane chrome reserves the first ~6 terminal rows for the
      // outer padding, two-row header, separator, panel top border and
      // panel title. File row N lives at terminal y = 6 + N.
      expect(await clickAt(6), 0);
      expect(await clickAt(7), 1);
      expect(await clickAt(8), 2);
      // Clicking does not jump focus to the diff pane — the user keeps
      // navigating files with arrow keys afterwards.
      expect(
        presentedPath(controller.currentFile),
        'lib/third.dart',
        reason: 'clicking the third row should leave file 2 selected',
      );
      driver.dispose();
    });

    test(
      'clicking a file row still selects when focus is on the diff pane',
      () async {
        final controller = PatchReviewController(
          parsePatchFixture(_threeFileDiff),
        );
        final driver = KeyDriver(
          PatchManagerView(controller: controller, layoutWidthOverride: 140),
          width: 140,
          height: 40,
          paintFrames: true,
        );

        await driver.ready();
        // Move focus to the diff pane via Tab — same state Leo ends up in
        // after pressing Enter on a file row.
        await driver.sendLogicalKey(LogicalKeyboardKey.tab);
        // Now click the first file row.
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 5,
            y: 6,
          ),
        );
        expect(controller.selectedFileIndex, 0);
        // And the third file row.
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 5,
            y: 8,
          ),
        );
        expect(controller.selectedFileIndex, 2);
        driver.dispose();
      },
    );

    test('arrow keys browse files while the file pane is focused', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoFileDiff));
      final driver = KeyDriver(
        PatchManagerView(controller: controller),
        width: 100,
      );

      await driver.ready();
      await driver.sendLogicalKey(LogicalKeyboardKey.arrowDown);

      expect(controller.selectedFileIndex, 1);
      expect(presentedPath(controller.currentFile), 'lib/second.dart');
      driver.dispose();
    });

    test('stage exceptions mark the selected hunk failed', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) {
            throw StateError('patch drifted');
          },
        ),
        width: 100,
      );

      await driver.ready();
      final failedSection = controller.currentSection!;
      await driver.sendCharacter('S');
      await Future<void>.delayed(Duration.zero);

      expect(
        controller.statusForTarget(failedSection),
        PatchReviewStatus.failed,
      );
      driver.dispose();
    });

    test('busy state prevents duplicate staging requests', () async {
      final controller = PatchReviewController(parsePatchFixture(_twoHunkDiff));
      final completer = Completer<GitStageResult>();
      var stageCalls = 0;
      final driver = KeyDriver(
        PatchManagerView(
          controller: controller,
          onStageContent: (selection) {
            stageCalls++;
            return completer.future;
          },
        ),
        width: 100,
      );

      await driver.ready();
      await driver.sendCharacter('s');
      await driver.sendCharacter('s');

      expect(stageCalls, 1);
      completer.complete(
        const GitStageResult(
          outcome: GitStageOutcome.applied,
          stdout: '',
          stderr: '',
          patch: '',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      driver.dispose();
    });

    test('selected section remains visible in long diffs', () {
      final controller = PatchReviewController(
        parsePatchFixture(_longSectionDiff),
      )..selectSection(2);
      final capture = BufferCapture(width: 100);
      try {
        final buffer = capture.capture(
          PatchManagerView(
            controller: controller,
            autofocus: false,
            layoutWidthOverride: 100,
          ),
        );

        expect(buffer.containsText('line 42 changed'), isTrue);
      } finally {
        capture.dispose();
      }
    });
  });
}

List<BufferPosition> _findHunkChipPositions(
  PatchReviewController controller,
  String label,
) {
  final capture = BufferCapture(width: 140, height: 40);
  try {
    final buffer = capture.capture(
      PatchManagerView(
        controller: controller,
        autofocus: false,
        layoutWidthOverride: 140,
      ),
    );
    final positions = buffer
        .findText(label)
        .where(
          (position) => position.y > 6 && position.x > 42 && position.x < 138,
        )
        .toList(growable: false);
    expect(positions, isNotEmpty);
    return positions;
  } finally {
    capture.dispose();
  }
}

GitStageResult _stageResult(
  GitStageOutcome outcome, {
  String stdout = '',
  String stderr = '',
}) =>
    GitStageResult(outcome: outcome, stdout: stdout, stderr: stderr, patch: '');

CapturedBuffer _captureDriver(KeyDriver driver) {
  driver.app.debugFlushFrame();
  return CapturedBuffer.fromBuffer(driver.app.renderer!.debugCurrentBuffer);
}

Future<void> _settleView() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void _expectColorClose(Color actual, Color expected) {
  // Native buffer colors round normalized channels to an integer u16 value
  // in OpenTUI's 0..255 color domain before a capture converts them back.
  const channelTolerance = 0.5 / 255 + 0.000001;
  expect(actual.r, closeTo(expected.r, channelTolerance));
  expect(actual.g, closeTo(expected.g, channelTolerance));
  expect(actual.b, closeTo(expected.b, channelTolerance));
  expect(actual.a, closeTo(expected.a, channelTolerance));
}

class _StableLeaf extends RenderObjectWidget {
  const _StableLeaf();

  @override
  RenderObject createRenderObject(BuildContext context) => _StableRenderBox();
}

class _StableRenderBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.constrainWidth(1), constraints.constrainHeight(1));
  }
}

final class _ThrowingToString extends Error {
  @override
  String toString() => throw StateError('toString must not escape');
}

const _twoHunkDiff =
    '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1,5 +1,5 @@
 void main() {
-  print('old');
+  print('new');
 }
${' '}
 void untouched() {}
@@ -20,4 +20,5 @@ void later() {
   final value = 1;
+  final next = 2;
   print(value);
 }
''';

const _secondHunkOnlyDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -20,4 +20,5 @@ void later() {
  final value = 1;
+  final next = 2;
  print(value);
 }
''';

const _twoFileDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1 +1 @@
-old
+new
diff --git a/lib/second.dart b/lib/second.dart
index 3333333..4444444 100644
--- a/lib/second.dart
+++ b/lib/second.dart
@@ -1 +1 @@
-alpha
+beta
''';

const _threeFileDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1 +1 @@
-old
+new
diff --git a/lib/second.dart b/lib/second.dart
index 3333333..4444444 100644
--- a/lib/second.dart
+++ b/lib/second.dart
@@ -1 +1 @@
-alpha
+beta
diff --git a/lib/third.dart b/lib/third.dart
index 5555555..6666666 100644
--- a/lib/third.dart
+++ b/lib/third.dart
@@ -1 +1 @@
-x
+y
''';

const _unsortedSidebarDiff = '''
diff --git a/apps/zeta/zeta.dart b/apps/zeta/zeta.dart
index 1111111..2222222 100644
--- a/apps/zeta/zeta.dart
+++ b/apps/zeta/zeta.dart
@@ -1 +1 @@
-zeta old
+zeta new
diff --git a/apps/api/alpha.dart b/apps/api/alpha.dart
index 3333333..4444444 100644
--- a/apps/api/alpha.dart
+++ b/apps/api/alpha.dart
@@ -1 +1 @@
-alpha old
+alpha new
diff --git a/packages/core/beta.ts b/packages/core/beta.ts
index 5555555..6666666 100644
--- a/packages/core/beta.ts
+++ b/packages/core/beta.ts
@@ -1 +1 @@
-beta old
+beta new
''';

const _deepPathDiff = '''
diff --git a/scripts/patch_manager/patch_manager_app.dart b/scripts/patch_manager/patch_manager_app.dart
index 1111111..2222222 100644
--- a/scripts/patch_manager/patch_manager_app.dart
+++ b/scripts/patch_manager/patch_manager_app.dart
@@ -1 +1 @@
-old
+new
''';

const _shortParentDiff = '''
diff --git a/apps/api/foo.dart b/apps/api/foo.dart
index 1111111..2222222 100644
--- a/apps/api/foo.dart
+++ b/apps/api/foo.dart
@@ -1 +1 @@
-old
+new
''';

const _longSectionDiff = '''
diff --git a/story.txt b/story.txt
index 1111111..2222222 100644
--- a/story.txt
+++ b/story.txt
@@ -1,48 +1,48 @@
 line 1
-line 2
+line 2 changed
 line 3
 line 4
 line 5
 line 6
 line 7
 line 8
 line 9
 line 10
 line 11
 line 12
 line 13
 line 14
 line 15
 line 16
 line 17
 line 18
 line 19
 line 20
 line 21
-line 22
+line 22 changed
 line 23
 line 24
 line 25
 line 26
 line 27
 line 28
 line 29
 line 30
 line 31
 line 32
 line 33
 line 34
 line 35
 line 36
 line 37
 line 38
 line 39
 line 40
 line 41
-line 42
+line 42 changed
 line 43
 line 44
 line 45
 line 46
 line 47
 line 48
''';
