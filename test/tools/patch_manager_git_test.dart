import 'dart:convert';
import 'dart:io';

import 'package:noir/src/tools/patch_manager/git_repository.dart'
    show GitCommandRunner, GitPatchException;
import 'package:noir/src/tools/patch_manager/patch_manager.dart';
import 'package:test/test.dart';

import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('GitPatchRepository', () {
    late Directory repo;

    setUp(() async {
      repo = await Directory.systemTemp.createTemp('opentui_patch_manager_');
      await _git(repo, ['init']);
      await _git(repo, ['config', 'user.name', 'Patch Manager Test']);
      await _git(repo, ['config', 'user.email', 'patch-manager@example.test']);

      final file = File('${repo.path}/story.txt');
      await file.writeAsString(
        List.generate(24, (i) => 'line ${i + 1}').join('\n'),
      );
      await _git(repo, ['add', 'story.txt']);
      await _git(repo, ['commit', '-m', 'seed']);

      final lines = await file.readAsLines();
      lines[1] = 'line 2 changed';
      lines[17] = 'line 18 changed';
      await file.writeAsString('${lines.join('\n')}\n');
    });

    tearDown(() {
      if (repo.existsSync()) {
        repo.deleteSync(recursive: true);
      }
    });

    test(
      'workspace load returns visible diff after exactly two commands',
      () async {
        final runner = _QueuedGitRunner([
          fixtureGitResult(
            stdoutBytes: buildPatchEnvelope(_recordedTrackedDiff),
          ),
          fixtureGitResult(),
          fixtureGitResult(
            stdout: '1 file changed, 1 insertion(+), 1 deletion(-)',
          ),
        ]);

        final Object result = await GitPatchRepository(
          worktreePath: repo.path,
          runner: runner,
        ).loadWorkspace();

        expect(runner.commands, [_trackedDiffCommand, _untrackedCommand]);
        expect(runner.unconsumedResultCount, 1);
        expect(result, isA<DiffSet>());
        expect(presentedPath((result as DiffSet).files.single), 'lib/app.dart');
      },
    );

    test('shortstat-only failure cannot reject the visible diff', () async {
      final runner = _QueuedGitRunner([
        fixtureGitResult(stdoutBytes: buildPatchEnvelope(_recordedTrackedDiff)),
        fixtureGitResult(),
        fixtureGitResult(exitCode: 7, stderr: 'cached shortstat failed'),
      ]);

      final Object result = await GitPatchRepository(
        worktreePath: repo.path,
        runner: runner,
      ).loadWorkspace();

      expect(result, isA<DiffSet>());
      expect(presentedPath((result as DiffSet).files.single), 'lib/app.dart');
      expect(runner.commands, [_trackedDiffCommand, _untrackedCommand]);
      expect(runner.unconsumedResultCount, 1);
    });

    test('tracked discovery failure keeps its command and error', () async {
      final runner = _QueuedGitRunner([
        fixtureGitResult(exitCode: 4, stderr: 'tracked discovery failed'),
        fixtureGitResult(),
      ]);

      await expectLater(
        GitPatchRepository(
          worktreePath: repo.path,
          runner: runner,
        ).loadWorkspace(),
        throwsA(
          isA<GitPatchException>().having(
            (error) => error.message,
            'message',
            'tracked discovery failed',
          ),
        ),
      );
      expect(runner.commands, [_trackedDiffCommand]);
      expect(runner.unconsumedResultCount, 1);
    });

    test('untracked discovery failure keeps its command and error', () async {
      final runner = _QueuedGitRunner([
        fixtureGitResult(),
        fixtureGitResult(exitCode: 5, stderr: 'untracked discovery failed'),
        fixtureGitResult(),
      ]);

      await expectLater(
        GitPatchRepository(
          worktreePath: repo.path,
          runner: runner,
        ).loadWorkspace(),
        throwsA(
          isA<GitPatchException>().having(
            (error) => error.message,
            'message',
            'untracked discovery failed',
          ),
        ),
      );
      expect(runner.commands, [_trackedDiffCommand, _untrackedCommand]);
      expect(runner.unconsumedResultCount, 1);
    });

    test('content staging uses exactly check then mutation bytes', () async {
      final runner = _QueuedGitRunner([fixtureGitResult(), fixtureGitResult()]);
      final selection = _contentSelectionFixture();
      final repository = GitPatchRepository(runner: runner);

      final result = await repository.stageContent(selection);

      expect(result.outcome, GitStageOutcome.applied);
      expect(runner.commands, [
        ['apply', '--cached', '--check', '--whitespace=nowarn', '-'],
        ['apply', '--cached', '--whitespace=nowarn', '-'],
      ]);
      expect(runner.stdinInputs, [
        utf8.encode(result.patch),
        utf8.encode(result.patch),
      ]);
      expect(result.patch, isNotEmpty);
    });

    test(
      'whole staging uses exact literal ordered NUL pathspec bytes',
      () async {
        final runner = _QueuedGitRunner([
          fixtureGitResult(),
          fixtureGitResult(),
        ]);
        final change = _wholeChangeFixture();
        final repository = GitPatchRepository(runner: runner);

        final result = await repository.stageWholeFile(change);

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
        final expectedInput = [
          for (final path in change.pathspecs) ...[...path.bytes, 0],
        ];
        expect(runner.stdinInputs, [expectedInput, expectedInput]);
        expect(result.patch, isEmpty);
      },
    );

    test('content check runner exception is rejected unchanged', () async {
      final runner = _QueuedGitRunner([const _RunnerThrow('check exploded')]);

      final result = await GitPatchRepository(
        runner: runner,
      ).stageContent(_contentSelectionFixture());

      expect(result.outcome, GitStageOutcome.rejectedUnchanged);
      expect(result.stderr, contains('content apply check'));
      expect(runner.commands, hasLength(1));
    });

    test('whole dry-run runner exception is rejected unchanged', () async {
      final runner = _QueuedGitRunner([const _RunnerThrow('dry-run exploded')]);

      final result = await GitPatchRepository(
        runner: runner,
      ).stageWholeFile(_wholeChangeFixture());

      expect(result.outcome, GitStageOutcome.rejectedUnchanged);
      expect(result.stderr, contains('whole-file add dry-run'));
      expect(runner.commands, hasLength(1));
    });

    test('content mutation runner exception requires refresh', () async {
      final runner = _QueuedGitRunner([
        fixtureGitResult(),
        const _RunnerThrow('mutation\n\x1b[31mexploded\x7f'),
      ]);

      final result = await GitPatchRepository(
        runner: runner,
      ).stageContent(_contentSelectionFixture());

      expect(result.outcome, GitStageOutcome.failedRefreshRequired);
      expect(result.stderr, contains('content apply mutation'));
      expect(result.stderr, contains(r'\e[31mexploded\x7F'));
      expect(
        result.stderr.codeUnits,
        everyElement(inInclusiveRange(0x20, 0x7e)),
      );
      expect(runner.commands, hasLength(2));
    });

    test('whole mutation runner exception requires refresh', () async {
      final runner = _QueuedGitRunner([
        fixtureGitResult(),
        const _RunnerThrow('mutation exploded'),
      ]);

      final result = await GitPatchRepository(
        runner: runner,
      ).stageWholeFile(_wholeChangeFixture());

      expect(result.outcome, GitStageOutcome.failedRefreshRequired);
      expect(result.stderr, contains('whole-file add mutation'));
      expect(runner.commands, hasLength(2));
    });

    test(
      'throwing-toString runner errors retain every phase outcome',
      () async {
        Future<GitStageResult> content(Iterable<Object> steps) =>
            GitPatchRepository(
              runner: _QueuedGitRunner(steps),
            ).stageContent(_contentSelectionFixture());
        Future<GitStageResult> whole(Iterable<Object> steps) =>
            GitPatchRepository(
              runner: _QueuedGitRunner(steps),
            ).stageWholeFile(_wholeChangeFixture());

        final cases =
            <
              ({
                Future<GitStageResult> Function() run,
                GitStageOutcome outcome,
                String phase,
              })
            >[
              (
                run: () => content([_RunnerThrow(_ThrowingToString())]),
                outcome: GitStageOutcome.rejectedUnchanged,
                phase: 'content apply check',
              ),
              (
                run: () => content([
                  fixtureGitResult(),
                  _RunnerThrow(_ThrowingToString()),
                ]),
                outcome: GitStageOutcome.failedRefreshRequired,
                phase: 'content apply mutation',
              ),
              (
                run: () => whole([_RunnerThrow(_ThrowingToString())]),
                outcome: GitStageOutcome.rejectedUnchanged,
                phase: 'whole-file add dry-run',
              ),
              (
                run: () => whole([
                  fixtureGitResult(),
                  _RunnerThrow(_ThrowingToString()),
                ]),
                outcome: GitStageOutcome.failedRefreshRequired,
                phase: 'whole-file add mutation',
              ),
            ];

        for (final fixture in cases) {
          final result = await fixture.run();

          expect(result.outcome, fixture.outcome, reason: fixture.phase);
          expect(result.stderr, contains(fixture.phase), reason: fixture.phase);
          expect(
            result.stderr,
            contains('Exception text unavailable.'),
            reason: fixture.phase,
          );
          expect(
            result.stderr.codeUnits,
            everyElement(inInclusiveRange(0x20, 0x7e)),
            reason: fixture.phase,
          );
        }
      },
    );

    test(
      'returned nonzero stage outcomes retain the mutation boundary',
      () async {
        Future<GitStageOutcome> content(Iterable<Object> steps) async =>
            (await GitPatchRepository(
              runner: _QueuedGitRunner(steps),
            ).stageContent(_contentSelectionFixture())).outcome;
        Future<GitStageOutcome> whole(Iterable<Object> steps) async =>
            (await GitPatchRepository(
              runner: _QueuedGitRunner(steps),
            ).stageWholeFile(_wholeChangeFixture())).outcome;

        expect(
          await content([fixtureGitResult(exitCode: 1)]),
          GitStageOutcome.rejectedUnchanged,
        );
        expect(
          await content([fixtureGitResult(), fixtureGitResult(exitCode: 1)]),
          GitStageOutcome.rejectedUnchanged,
        );
        expect(
          await whole([fixtureGitResult(exitCode: 1)]),
          GitStageOutcome.rejectedUnchanged,
        );
        expect(
          await whole([fixtureGitResult(), fixtureGitResult(exitCode: 1)]),
          GitStageOutcome.failedRefreshRequired,
        );
      },
    );

    test('stages only selected tracked hunks into the index', () async {
      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadTrackedDiff();
      final file = diff.files.single;

      expect(file.hunks, hasLength(2));

      final result = await repository.stageContent(
        ContentStageSelection(file: file, sections: file.hunks.last.sections),
      );

      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);

      final cached = await _git(repo, ['diff', '--cached', '--', 'story.txt']);
      final unstaged = await _git(repo, ['diff', '--', 'story.txt']);
      final worktree = await File('${repo.path}/story.txt').readAsString();

      expect(cached.stdout, contains('line 18 changed'));
      expect(cached.stdout, isNot(contains('line 2 changed')));
      expect(unstaged.stdout, contains('line 2 changed'));
      expect(worktree, contains('line 2 changed'));
      expect(worktree, contains('line 18 changed'));
    });

    test(
      'content plus mode stages content while leaving mode unstaged',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('Executable-bit staging needs POSIX mode semantics.');
          return;
        }
        await _chmod('${repo.path}/story.txt', '755');
        final repository = GitPatchRepository(worktreePath: repo.path);
        final file = (await repository.loadTrackedDiff()).files.single;

        expect(
          file.wholeFileStageUnit!.reason,
          WholeFileChangeReason.contentAndMode,
        );
        final result = await repository.stageContent(
          ContentStageSelection(file: file, sections: file.sections),
        );

        expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
        final cachedRaw = await _git(repo, [
          'diff',
          '--cached',
          '--raw',
          '--',
          'story.txt',
        ]);
        final unstagedRaw = await _git(repo, [
          'diff',
          '--raw',
          '--',
          'story.txt',
        ]);
        expect(cachedRaw.stdout, contains(':100644 100644'));
        expect(unstagedRaw.stdout, contains(':100644 100755'));
      },
    );

    test(
      'whole staging covers mode-only deletion binary and rename states',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('Executable-bit staging needs POSIX mode semantics.');
          return;
        }
        await File('${repo.path}/mode-only.txt').writeAsString('mode\n');
        await File('${repo.path}/empty.txt').writeAsString('');
        await File('${repo.path}/image.bin').writeAsBytes([0, 1, 2]);
        await File('${repo.path}/old-name.txt').writeAsString('rename\n');
        await _git(repo, [
          'add',
          'mode-only.txt',
          'empty.txt',
          'image.bin',
          'old-name.txt',
        ]);
        await _git(repo, ['commit', '-m', 'add whole-stage fixtures']);

        await _chmod('${repo.path}/mode-only.txt', '755');
        await File('${repo.path}/empty.txt').delete();
        await File('${repo.path}/image.bin').writeAsBytes([0, 3, 4]);
        await File(
          '${repo.path}/old-name.txt',
        ).rename('${repo.path}/new-name.txt');

        final repository = GitPatchRepository(worktreePath: repo.path);
        final diff = await repository.loadTrackedDiff();
        final wholeFiles = <String, WholeFileChangeReason>{
          'mode-only.txt': WholeFileChangeReason.modeOnly,
          'empty.txt': WholeFileChangeReason.deleted,
          'image.bin': WholeFileChangeReason.binary,
        };
        for (final entry in wholeFiles.entries) {
          final file = diff.files.singleWhere(
            (candidate) => presentedPath(candidate) == entry.key,
          );
          expect(file.wholeFileStageUnit!.reason, entry.value);
          final result = await repository.stageWholeFile(
            file.wholeFileStageUnit!,
          );
          expect(
            result.outcome,
            GitStageOutcome.applied,
            reason: '${entry.value}: ${result.stderr}',
          );
        }
        final renamePaths = [
          fixturePath('old-name.txt'),
          fixturePath('new-name.txt'),
        ];
        final rename = WholeFileChange(
          id: WholeFileChange.canonicalId(
            reason: WholeFileChangeReason.renamed,
            pathspecs: renamePaths,
          ),
          pathspecs: renamePaths,
          reason: WholeFileChangeReason.renamed,
        );
        final renameResult = await repository.stageWholeFile(rename);
        expect(
          renameResult.outcome,
          GitStageOutcome.applied,
          reason: renameResult.stderr,
        );

        final cached = await _git(repo, [
          'diff',
          '--cached',
          '--name-status',
          '-M',
        ]);
        expect(cached.stdout, contains('mode-only.txt'));
        expect(cached.stdout, contains('empty.txt'));
        expect(cached.stdout, contains('image.bin'));
        expect(cached.stdout, contains('old-name.txt'));
        expect(cached.stdout, contains('new-name.txt'));
        expect(
          (await _git(repo, ['diff', '--cached', '--', 'story.txt'])).stdout,
          isEmpty,
        );
        expect(
          (await _git(repo, ['diff', '--', 'story.txt'])).stdout,
          contains('line 2 changed'),
        );
      },
    );

    test('loads and stages untracked files whole-file', () async {
      final untracked = File('${repo.path}/notes draft.txt');
      await untracked.writeAsString('first note\nsecond note\n');
      final repository = GitPatchRepository(worktreePath: repo.path);

      final diff = await repository.loadWorkspace();
      final file = diff.files.singleWhere((item) => item.isUntracked);

      expect(presentedPath(file), 'notes draft.txt');
      expect(file.canStageWholeFile, isTrue);
      expect(file.untrackedPreviewLines, ['first note', 'second note']);
      expect(file.sections, isEmpty);

      final result = await repository.stageWholeFile(file.wholeFileStageUnit!);

      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      final cachedNameOnly = await _git(repo, [
        'diff',
        '--cached',
        '--name-only',
      ]);
      expect(cachedNameOnly.stdout, contains('notes draft.txt'));
    });

    test('tracked UTF-8 path retains one exact identity', () async {
      final utf8File = File('${repo.path}/café.txt');
      await utf8File.writeAsString('before\n');
      await _git(repo, ['add', 'café.txt']);
      await _git(repo, ['commit', '-m', 'add UTF-8 path']);
      await utf8File.writeAsString('after\n');

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadTrackedDiff();

      final file = diff.files.singleWhere(
        (file) => file.pathIdentity == fixturePath('café.txt'),
      );
      expect(file.pathIdentity, fixturePath('café.txt'));
      expect(presentedPath(file), r'caf\xC3\xA9.txt');
    });

    test(
      'binary path containing b slash retains its complete identity',
      () async {
        final directory = Directory('${repo.path}/dir b');
        await directory.create();
        final binary = File('${directory.path}/foo.bin');
        await binary.writeAsBytes([0, 1, 2]);
        await _git(repo, ['add', 'dir b/foo.bin']);
        await _git(repo, ['commit', '-m', 'add ambiguous binary path']);
        await binary.writeAsBytes([0, 3, 4]);

        final diff = await GitPatchRepository(
          worktreePath: repo.path,
        ).loadTrackedDiff();

        final file = diff.files.singleWhere(
          (file) => file.pathIdentity == fixturePath('dir b/foo.bin'),
        );
        expect(file.pathIdentity, fixturePath('dir b/foo.bin'));
        expect(presentedPath(file), 'dir b/foo.bin');
        expect(file.payloadKind, DiffPayloadKind.binary);
      },
    );

    test('literal pathspec magic cannot widen untracked staging', () async {
      const literalPath = ':(glob)trap*.txt';
      await File('${repo.path}/$literalPath').writeAsString('literal\n');
      await File('${repo.path}/trap-match.txt').writeAsString('sibling\n');
      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadWorkspace();
      final literal = diff.files.singleWhere(
        (file) => file.pathIdentity == fixturePath(literalPath),
      );

      final result = await repository.stageWholeFile(
        literal.wholeFileStageUnit!,
      );

      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      final cached = await _git(repo, ['diff', '--cached', '--name-only']);
      expect(
        (cached.stdout as String).split('\n').where((path) => path.isNotEmpty),
        [literalPath],
      );
    });

    test('control-byte path reaches the index with exact bytes', () async {
      if (Platform.isWindows) {
        markTestSkipped('POSIX pathname controls are not a Windows fixture.');
        return;
      }
      const controlPath = 'control\n\t\x1b.txt';
      await File('${repo.path}/$controlPath').writeAsString('control\n');
      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadWorkspace();
      final identity = fixturePath(controlPath);
      final file = diff.files.singleWhere(
        (file) => file.pathIdentity == identity,
      );

      expect(file.pathIdentity, identity);
      expect(presentedPath(file), r'control\x0A\x09\x1B.txt');

      final result = await repository.stageWholeFile(file.wholeFileStageUnit!);

      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      final index = await _gitBytes(repo, ['ls-files', '-z']);
      expect(
        _containsBytes(index, [...identity.bytes, 0]),
        isTrue,
        reason: 'the index must retain the exact pathname bytes',
      );
    });

    test(
      'tracked invalid UTF-8 identity survives POSIX Git plumbing',
      () async {
        if (Platform.isWindows) {
          markTestSkipped(
            'Raw POSIX pathname bytes are not a Windows fixture.',
          );
          return;
        }
        final blobSource = File('${repo.path}/blob-source.txt');
        await blobSource.writeAsString('raw identity\n');
        final blob = (await _git(repo, [
          'hash-object',
          '-w',
          'blob-source.txt',
        ])).stdout.toString().trim();
        await blobSource.delete();
        final identity = GitPath.fromBytes([
          ...ascii.encode('invalid-'),
          0xff,
          ...ascii.encode('.txt'),
        ]);
        await _gitWithInputBytes(
          repo,
          ['update-index', '-z', '--index-info'],
          [...ascii.encode('100644 $blob\t'), ...identity.bytes, 0],
        );
        await _git(repo, ['commit', '-m', 'add raw-byte identity']);

        final diff = await GitPatchRepository(
          worktreePath: repo.path,
        ).loadTrackedDiff();
        final file = diff.files.singleWhere(
          (file) => file.pathIdentity == identity,
        );

        expect(file.pathIdentity, identity);
        expect(presentedPath(file), r'invalid-\xFF.txt');
        expect(file.changeKind, DiffChangeKind.deleted);
        expect(file.payloadKind, DiffPayloadKind.text);
        expect(file.hunks, hasLength(1));
      },
    );

    test(
      'regular-to-link type change groups before a following record',
      () async {
        if (Platform.isWindows) {
          markTestSkipped('Symbolic-link type changes need POSIX semantics.');
          return;
        }
        const typePath = 'a-type-change';
        final typeFile = File('${repo.path}/$typePath');
        await typeFile.writeAsString('old type\n');
        await _git(repo, ['add', typePath]);
        await _git(repo, ['commit', '-m', 'add regular type fixture']);
        await typeFile.delete();
        await Link('${repo.path}/$typePath').create('target');

        final diff = await GitPatchRepository(
          worktreePath: repo.path,
        ).loadTrackedDiff();

        expect(diff.files, hasLength(2));
        final typeChange = diff.files.first;
        expect(typeChange.pathIdentity, fixturePath(typePath));
        expect(typeChange.changeKind, DiffChangeKind.typeChanged);
        expect(typeChange.payloadKind, DiffPayloadKind.text);
        expect(typeChange.hunks, isEmpty);
        expect(typeChange.sections, isEmpty);
        expect(typeChange.canStageContent, isFalse);
        expect(typeChange.canStageWholeFile, isTrue);
        expect(typeChange.rawMetadata!.oldMode, '100644');
        expect(typeChange.rawMetadata!.newMode, '120000');

        final following = diff.files.last;
        expect(following.pathIdentity, fixturePath('story.txt'));
        expect(following.changeKind, DiffChangeKind.modified);
        expect(following.hunks, hasLength(2));
        expect(
          following.hunks.last.lines.any(
            (line) => line.text.contains('line 18 changed'),
          ),
          isTrue,
        );

        final repository = GitPatchRepository(worktreePath: repo.path);
        final result = await repository.stageWholeFile(
          typeChange.wholeFileStageUnit!,
        );
        expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
        final stagedEntry = await _git(repo, ['ls-files', '--stage', typePath]);
        expect(stagedEntry.stdout, startsWith('120000 '));
      },
    );

    test('link-to-regular type change remains one exact file', () async {
      if (Platform.isWindows) {
        markTestSkipped('Symbolic-link type changes need POSIX semantics.');
        return;
      }
      const typePath = 'link-to-regular';
      final link = Link('${repo.path}/$typePath');
      await link.create('target');
      await _git(repo, ['add', typePath]);
      await _git(repo, ['commit', '-m', 'add link type fixture']);
      await link.delete();
      await File('${repo.path}/$typePath').writeAsString('new type\n');

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadTrackedDiff();
      final typeChange = diff.files.singleWhere(
        (file) => file.pathIdentity == fixturePath(typePath),
      );

      expect(typeChange.changeKind, DiffChangeKind.typeChanged);
      expect(typeChange.payloadKind, DiffPayloadKind.text);
      expect(typeChange.rawMetadata!.oldMode, '120000');
      expect(typeChange.rawMetadata!.newMode, '100644');
      expect(typeChange.hunks, isEmpty);
      expect(typeChange.canStageContent, isFalse);
      expect(typeChange.canStageWholeFile, isTrue);
    });

    test('binary-to-link type change combines as binary', () async {
      if (Platform.isWindows) {
        markTestSkipped('Symbolic-link type changes need POSIX semantics.');
        return;
      }
      const typePath = 'binary-to-link';
      final binary = File('${repo.path}/$typePath');
      await binary.writeAsBytes([0, 1, 2]);
      await _git(repo, ['add', typePath]);
      await _git(repo, ['commit', '-m', 'add binary type fixture']);
      await binary.delete();
      await Link('${repo.path}/$typePath').create('target');

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadTrackedDiff();
      final typeChange = diff.files.singleWhere(
        (file) => file.pathIdentity == fixturePath(typePath),
      );

      expect(typeChange.changeKind, DiffChangeKind.typeChanged);
      expect(typeChange.payloadKind, DiffPayloadKind.binary);
      expect(typeChange.hunks, isEmpty);
      expect(typeChange.canStageContent, isFalse);
      expect(typeChange.canStageWholeFile, isTrue);
    });

    test(
      'stages one split section while sibling changes stay unstaged',
      () async {
        final file = File('${repo.path}/story.txt');
        final lines = List.generate(12, (i) => 'line ${i + 1}');
        await file.writeAsString('${lines.join('\n')}\n');
        await _git(repo, ['add', 'story.txt']);
        await _git(repo, ['commit', '-m', 'reset story']);

        final changed = await file.readAsLines();
        changed[1] = 'line 2 changed';
        changed.insert(4, 'line 4.5 inserted');
        changed[7] = 'line 7 changed';
        await file.writeAsString('${changed.join('\n')}\n');

        final repository = GitPatchRepository(worktreePath: repo.path);
        final diff = await repository.loadTrackedDiff();
        final hunk = diff.files.single.hunks.single;

        expect(hunk.sections, hasLength(3));

        final diffFile = diff.files.single;
        final result = await repository.stageContent(
          ContentStageSelection(file: diffFile, sections: [hunk.sections[1]]),
        );

        expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);

        final cached = await _git(repo, [
          'diff',
          '--cached',
          '--',
          'story.txt',
        ]);
        final unstaged = await _git(repo, ['diff', '--', 'story.txt']);

        expect(cached.stdout, contains('line 4.5 inserted'));
        expect(cached.stdout, isNot(contains('line 2 changed')));
        expect(cached.stdout, isNot(contains('line 7 changed')));
        expect(unstaged.stdout, contains('line 2 changed'));
        expect(unstaged.stdout, contains('line 7 changed'));
      },
    );

    test('stages selected sections across multiple files', () async {
      final second = File('${repo.path}/second.txt');
      await second.writeAsString('alpha\nbeta\n');
      await _git(repo, ['add', 'second.txt']);
      await _git(repo, ['commit', '-m', 'add second']);

      final secondLines = await second.readAsLines();
      secondLines[1] = 'beta changed';
      await second.writeAsString('${secondLines.join('\n')}\n');

      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadTrackedDiff();
      final first = diff.files.singleWhere(
        (file) => presentedPath(file) == 'story.txt',
      );
      final secondFile = diff.files.singleWhere(
        (file) => presentedPath(file) == 'second.txt',
      );

      final firstResult = await repository.stageContent(
        ContentStageSelection(file: first, sections: [first.sections.first]),
      );
      final secondResult = await repository.stageContent(
        ContentStageSelection(
          file: secondFile,
          sections: [secondFile.sections.first],
        ),
      );

      expect(
        [firstResult.outcome, secondResult.outcome],
        everyElement(GitStageOutcome.applied),
        reason: '${firstResult.stderr}${secondResult.stderr}',
      );
      final cached = await _git(repo, ['diff', '--cached']);
      expect(cached.stdout, contains('line 2 changed'));
      expect(cached.stdout, contains('beta changed'));
    });

    test('failed apply check does not change the index', () async {
      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadTrackedDiff();
      final file = diff.files.single;

      await _git(repo, ['add', 'story.txt']);
      final before = await _git(repo, ['diff', '--cached', '--', 'story.txt']);

      final result = await repository.stageContent(
        ContentStageSelection(file: file, sections: [file.sections.first]),
      );

      expect(result.outcome, GitStageOutcome.rejectedUnchanged);
      final after = await _git(repo, ['diff', '--cached', '--', 'story.txt']);
      expect(after.stdout, before.stdout);
    });

    test(
      'missing untracked whole-file staging does not partially stage',
      () async {
        final untracked = File('${repo.path}/notes draft.txt');
        await untracked.writeAsString('draft note\n');
        final repository = GitPatchRepository(worktreePath: repo.path);
        final diff = await repository.loadWorkspace();
        final untrackedFile = diff.files.singleWhere(
          (file) => file.isUntracked,
        );

        await untracked.delete();
        final beforeCached = await _git(repo, ['diff', '--cached']);

        final result = await repository.stageWholeFile(
          untrackedFile.wholeFileStageUnit!,
        );

        expect(result.outcome, GitStageOutcome.rejectedUnchanged);
        final afterCached = await _git(repo, ['diff', '--cached']);
        expect(afterCached.stdout, beforeCached.stdout);
      },
    );

    test('untracked preview limits are exact and explicit', () async {
      const byteLimit = 65536;
      const lineLimit = 400;
      const cellLimit = 32768;

      final bytePrefix = List.filled((byteLimit - 1) ~/ 3, 'e\u0301').join();
      final byteCases = <String, ({String contents, String state, int bytes})>{
        'byte-minus.txt': (
          contents: bytePrefix,
          state: 'completeText',
          bytes: byteLimit - 1,
        ),
        'byte-exact.txt': (
          contents: '${bytePrefix}a',
          state: 'completeText',
          bytes: byteLimit,
        ),
        'byte-plus.txt': (
          contents: '${bytePrefix}ab',
          state: 'truncatedText',
          bytes: byteLimit - 1,
        ),
      };
      for (final entry in byteCases.entries) {
        await File(
          '${repo.path}/${entry.key}',
        ).writeAsString(entry.value.contents);
      }

      for (final count in [lineLimit - 1, lineLimit, lineLimit + 1]) {
        await File(
          '${repo.path}/lines-$count.txt',
        ).writeAsString(List.filled(count, 'x').join('\n'));
      }
      for (final count in [cellLimit - 1, cellLimit, cellLimit + 1]) {
        await File('${repo.path}/cells-$count.txt').writeAsString('x' * count);
      }

      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadWorkspace();

      for (final entry in byteCases.entries) {
        final file = diff.files.singleWhere(
          (file) => presentedPath(file) == entry.key,
        );
        expect(_previewStateName(file), entry.value.state);
        expect(
          utf8.encode(file.untrackedPreviewLines.single),
          hasLength(entry.value.bytes),
        );
      }

      for (final count in [lineLimit - 1, lineLimit, lineLimit + 1]) {
        final file = diff.files.singleWhere(
          (file) => presentedPath(file) == 'lines-$count.txt',
        );
        expect(
          file.untrackedPreviewLines,
          hasLength(count.clamp(0, lineLimit)),
        );
        expect(
          _previewStateName(file),
          count > lineLimit ? 'truncatedText' : 'completeText',
        );
      }

      for (final count in [cellLimit - 1, cellLimit, cellLimit + 1]) {
        final file = diff.files.singleWhere(
          (file) => presentedPath(file) == 'cells-$count.txt',
        );
        expect(
          file.untrackedPreviewLines.single,
          hasLength(count.clamp(0, cellLimit)),
        );
        expect(
          _previewStateName(file),
          count > cellLimit ? 'truncatedText' : 'completeText',
        );
      }

      final truncated = diff.files.singleWhere(
        (file) => presentedPath(file) == 'byte-plus.txt',
      );
      final result = await repository.stageWholeFile(
        truncated.wholeFileStageUnit!,
      );
      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      final staged = await _git(repo, ['show', ':byte-plus.txt']);
      expect(staged.stdout, byteCases['byte-plus.txt']!.contents);
    });

    test('retained NUL is binary but the look-ahead byte is not', () async {
      const byteLimit = 65536;
      await File(
        '${repo.path}/nul-retained.dat',
      ).writeAsBytes([...utf8.encode(_lowCellUtf8(byteLimit - 1)), 0]);
      await File(
        '${repo.path}/nul-lookahead.dat',
      ).writeAsBytes([...utf8.encode(_lowCellUtf8(byteLimit)), 0]);

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadWorkspace();
      final retained = diff.files.singleWhere(
        (file) => presentedPath(file) == 'nul-retained.dat',
      );
      final lookahead = diff.files.singleWhere(
        (file) => presentedPath(file) == 'nul-lookahead.dat',
      );

      expect(retained.untrackedPreviewState, UntrackedPreviewState.binary);
      expect(retained.untrackedPreviewLines, isEmpty);
      expect(
        lookahead.untrackedPreviewState,
        UntrackedPreviewState.truncatedText,
      );
      expect(
        utf8.encode(lookahead.untrackedPreviewLines.single),
        hasLength(byteLimit - 1),
      );
    });

    test('byte truncation keeps only complete full-source graphemes', () async {
      const byteLimit = 65536;
      final cases = <String, ({String contents, String expected})>{
        'scalar-cut.txt': (
          contents: '${_lowCellUtf8(byteLimit - 2)}😀tail',
          expected: _lowCellUtf8(byteLimit - 3),
        ),
        'combining-cut.txt': (
          contents: '${_lowCellUtf8(byteLimit - 1)}e\u0301tail',
          expected: _lowCellUtf8(byteLimit - 1),
        ),
        'zwj-cut.txt': (
          contents: '${_lowCellUtf8(byteLimit - 4)}👩\u200D💻tail',
          expected: _lowCellUtf8(byteLimit - 4),
        ),
        'flag-cut.txt': (
          contents: '${_lowCellUtf8(byteLimit - 4)}🇺🇸tail',
          expected: _lowCellUtf8(byteLimit - 4),
        ),
      };
      for (final entry in cases.entries) {
        await File(
          '${repo.path}/${entry.key}',
        ).writeAsString(entry.value.contents);
      }
      await File(
        '${repo.path}/incomplete-at-eof.dat',
      ).writeAsBytes([0x61, 0xf0, 0x9f]);

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadWorkspace();
      for (final entry in cases.entries) {
        final file = diff.files.singleWhere(
          (file) => presentedPath(file) == entry.key,
        );
        final preview = file.untrackedPreviewLines.single;
        expect(file.untrackedPreviewState, UntrackedPreviewState.truncatedText);
        expect(preview, entry.value.expected);
        expect(preview, isNot(contains('\uFFFD')));
      }

      final incomplete = diff.files.singleWhere(
        (file) => presentedPath(file) == 'incomplete-at-eof.dat',
      );
      expect(incomplete.untrackedPreviewState, UntrackedPreviewState.binary);
      expect(incomplete.untrackedPreviewLines, isEmpty);
    });

    test('workspace byte budget reserves a one-byte look-ahead', () async {
      const byteLimit = 65536;
      for (var i = 0; i < 15; i++) {
        await File(
          '${repo.path}/${i.toString().padLeft(2, '0')}-byte-budget.txt',
        ).writeAsString(_lowCellUtf8(byteLimit + 1));
      }
      await File(
        '${repo.path}/15-byte-budget-tail.txt',
      ).writeAsString(_lowCellUtf8(65520));
      await File(
        '${repo.path}/zz-byte-omitted.txt',
      ).writeAsString('must remain stageable');

      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadWorkspace();
      final tail = diff.files.singleWhere(
        (file) => presentedPath(file) == '15-byte-budget-tail.txt',
      );
      final omitted = diff.files.singleWhere(
        (file) => presentedPath(file) == 'zz-byte-omitted.txt',
      );

      expect(tail.untrackedPreviewState, UntrackedPreviewState.completeText);
      expect(omitted.untrackedEntityKind, UntrackedEntityKind.regularFile);
      expect(omitted.untrackedPreviewState, UntrackedPreviewState.omitted);
      expect(omitted.hunks, isEmpty);
      expect(omitted.untrackedPreviewLines, isEmpty);
      expect(omitted.canStageWholeFile, isTrue);

      final result = await repository.stageWholeFile(
        omitted.wholeFileStageUnit!,
      );
      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      expect(
        (await _git(repo, ['show', ':zz-byte-omitted.txt'])).stdout,
        'must remain stageable',
      );
    });

    test(
      'workspace line budget preserves later identities as omitted',
      () async {
        for (var i = 0; i < 10; i++) {
          await File(
            '${repo.path}/${i.toString().padLeft(2, '0')}-line-budget.txt',
          ).writeAsString(List<String>.filled(400, 'x').join('\n'));
        }
        await File(
          '${repo.path}/zz-line-omitted.txt',
        ).writeAsString('still here');

        final diff = await GitPatchRepository(
          worktreePath: repo.path,
        ).loadWorkspace();
        expect(
          diff.files
              .where((file) => presentedPath(file).endsWith('-line-budget.txt'))
              .expand((file) => file.untrackedPreviewLines),
          hasLength(4000),
        );
        final omitted = diff.files.singleWhere(
          (file) => presentedPath(file) == 'zz-line-omitted.txt',
        );
        expect(omitted.untrackedPreviewState, UntrackedPreviewState.omitted);
        expect(omitted.canStageWholeFile, isTrue);
      },
    );

    test('early binary detection bounds a sparse file preview', () async {
      final sparse = File('${repo.path}/sparse.bin');
      final handle = await sparse.open(mode: FileMode.write);
      try {
        await handle.setPosition(2 * 1024 * 1024);
        await handle.writeByte(1);
      } finally {
        await handle.close();
      }

      final repository = GitPatchRepository(worktreePath: repo.path);
      final diff = await repository.loadWorkspace();
      final file = diff.files.singleWhere(
        (file) => presentedPath(file) == 'sparse.bin',
      );
      expect(file.untrackedPreviewState, UntrackedPreviewState.binary);
      expect(file.hunks, isEmpty);

      final result = await repository.stageWholeFile(file.wholeFileStageUnit!);
      expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
      expect(
        int.parse(
          (await _git(repo, [
            'cat-file',
            '-s',
            ':sparse.bin',
          ])).stdout.toString().trim(),
        ),
        2 * 1024 * 1024 + 1,
      );
    });

    test(
      'relative absolute broken and escaped links preview and stage targets',
      () async {
        final outside = await Directory.systemTemp.createTemp(
          'opentui_patch_link_target_',
        );
        addTearDown(() async {
          if (outside.existsSync()) await outside.delete(recursive: true);
        });
        final outsideFile = File('${outside.path}/secret.txt');
        await outsideFile.writeAsString('outside-secret');
        final escapedTarget = 'back\\slash\n\r\t\x01\x1b\x7f\u0080界';
        final targets = <String, String>{
          'relative.link': 'story.txt',
          'absolute.link': outsideFile.path,
          'broken.link': 'missing-target',
          'escaped.link': escapedTarget,
        };

        final storedTargets = <String, String>{};
        try {
          for (final entry in targets.entries) {
            final link = Link('${repo.path}/${entry.key}');
            await link.create(entry.value);
            storedTargets[entry.key] = await link.target();
          }
        } on FileSystemException catch (error) {
          markTestSkipped('Symbolic links unavailable: $error');
          return;
        }

        final repository = GitPatchRepository(worktreePath: repo.path);
        final diff = await repository.loadWorkspace();
        final links = <DiffFile>[];
        for (final entry in targets.entries) {
          final file = diff.files.singleWhere(
            (file) => presentedPath(file) == entry.key,
          );
          links.add(file);
          expect(_entityKindName(file), 'symbolicLink');
          expect(_previewStateName(file), 'completeText');
          expect(file.headerLines, isEmpty);
          expect(
            file.untrackedPreviewLines.single,
            _escapedLinkTarget(storedTargets[entry.key]!),
          );
          expect(
            _decodeEscapedLinkTarget(file.untrackedPreviewLines.single),
            storedTargets[entry.key],
          );
          expect(
            file.untrackedPreviewLines.join('\n'),
            isNot(contains('outside-secret')),
          );
        }

        for (final file in links) {
          final stageResult = await repository.stageWholeFile(
            file.wholeFileStageUnit!,
          );
          expect(
            stageResult.outcome,
            GitStageOutcome.applied,
            reason: stageResult.stderr,
          );
        }

        final index = await _git(repo, [
          'ls-files',
          '-s',
          '--',
          ...targets.keys,
        ]);
        expect(
          index.stdout.toString().split('\n').where((line) => line.isNotEmpty),
          everyElement(startsWith('120000 ')),
        );
        for (final entry in targets.entries) {
          final staged = await _git(repo, ['show', ':${entry.key}']);
          expect(staged.stdout, _gitIndexLinkTarget(storedTargets[entry.key]!));
        }
      },
    );

    test('link display never emits half of a wide token', () async {
      const cellLimit = 32768;
      for (var i = 0; i < 7; i++) {
        await File(
          '${repo.path}/0$i-cell-budget.txt',
        ).writeAsString('x' * cellLimit);
      }
      await File(
        '${repo.path}/07-cell-budget.txt',
      ).writeAsString('x' * (cellLimit - 1));
      final link = Link('${repo.path}/zz-wide.link');
      late String storedTarget;
      try {
        await link.create('界');
        storedTarget = await link.target();
      } on FileSystemException catch (error) {
        markTestSkipped('Symbolic links unavailable: $error');
        return;
      }

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
      ).loadWorkspace();
      final preview = diff.files.singleWhere(
        (file) => presentedPath(file) == 'zz-wide.link',
      );
      expect(preview.untrackedEntityKind, UntrackedEntityKind.symbolicLink);
      expect(
        preview.untrackedPreviewState,
        UntrackedPreviewState.truncatedText,
      );
      expect(preview.untrackedPreviewLines, isEmpty);
      expect(storedTarget, isNotEmpty);
    });

    test('vanished identities remain while readable siblings load', () async {
      await File('${repo.path}/sibling.txt').writeAsString('sibling');
      final runner = _QueuedGitRunner([
        fixtureGitResult(),
        fixtureGitResult(
          stdoutBytes: utf8.encode('vanished.txt\u0000sibling.txt\u0000'),
        ),
      ]);

      final diff = await GitPatchRepository(
        worktreePath: repo.path,
        runner: runner,
      ).loadWorkspace();
      final vanished = diff.files.singleWhere(
        (file) => presentedPath(file) == 'vanished.txt',
      );
      final sibling = diff.files.singleWhere(
        (file) => presentedPath(file) == 'sibling.txt',
      );

      expect(vanished.untrackedEntityKind, UntrackedEntityKind.unknown);
      expect(vanished.untrackedPreviewState, UntrackedPreviewState.unavailable);
      expect(vanished.canStageWholeFile, isTrue);
      expect(sibling.untrackedEntityKind, UntrackedEntityKind.regularFile);
      expect(sibling.untrackedPreviewState, UntrackedPreviewState.completeText);
      expect(sibling.untrackedPreviewLines.single, 'sibling');
    });

    test(
      'an omitted link keeps link identity without reading its target',
      () async {
        const cellLimit = 32768;
        for (var i = 0; i < 8; i++) {
          await File(
            '${repo.path}/00-budget-$i.txt',
          ).writeAsString('x' * cellLimit);
        }
        final link = Link('${repo.path}/zz-omitted.link');
        late String storedTarget;
        try {
          await link.create('story.txt');
          storedTarget = await link.target();
        } on FileSystemException catch (error) {
          markTestSkipped('Symbolic links unavailable: $error');
          return;
        }

        var targetReads = 0;
        final repository =
            Function.apply(GitPatchRepository.new, const [], {
                  #worktreePath: repo.path,
                  #linkTargetReader: (String _) async {
                    targetReads++;
                    throw StateError('omitted target must not be read');
                  },
                })
                as GitPatchRepository;

        final diff = await repository.loadWorkspace();
        final omitted = diff.files.singleWhere(
          (file) => presentedPath(file) == 'zz-omitted.link',
        );
        expect(targetReads, 0);
        expect(_entityKindName(omitted), 'symbolicLink');
        expect(_previewStateName(omitted), 'omitted');
        expect(omitted.headerLines, isEmpty);
        expect(omitted.canStageWholeFile, isTrue);

        final result = await repository.stageWholeFile(
          omitted.wholeFileStageUnit!,
        );
        expect(result.outcome, GitStageOutcome.applied, reason: result.stderr);
        final staged = await _git(repo, ['show', ':zz-omitted.link']);
        expect(staged.stdout, storedTarget);
      },
    );

    test('untracked loader forbids every whole-file read API', () {
      final source = _withoutDartComments(
        File(
          'lib/src/tools/patch_manager/git_repository.dart',
        ).readAsStringSync(),
      );
      for (final method in [
        'readAsBytes',
        'readAsString',
        'readAsLines',
        'readAsBytesSync',
        'readAsStringSync',
        'readAsLinesSync',
        'openRead',
      ]) {
        expect(
          RegExp('\\.\\s*$method\\s*\\(').hasMatch(source),
          isFalse,
          reason: 'Untracked previews must not invoke $method',
        );
        expect(
          RegExp('\\.\\s*$method\\s*\\(').hasMatch(
            _withoutDartComments(
              '// ignored.$method()\n'
              '/* outer /* ignored.$method() */ still ignored */',
            ),
          ),
          isFalse,
          reason: 'Comments are not API invocations',
        );
        expect(
          RegExp('\\.\\s*$method\\s*\\(').hasMatch(
            _withoutDartComments(
              'final url = "https://example.test"; actual.$method();',
            ),
          ),
          isTrue,
          reason: 'Comment markers inside strings cannot hide invocations',
        );
      }
    });
  });
}

String _entityKindName(DiffFile file) => file.untrackedEntityKind!.name;

String _previewStateName(DiffFile file) => file.untrackedPreviewState!.name;

String _gitIndexLinkTarget(String storedTarget) =>
    Platform.isWindows ? storedTarget.replaceAll(r'\', '/') : storedTarget;

String _escapedLinkTarget(String target) {
  final output = StringBuffer();
  for (final rune in target.runes) {
    switch (rune) {
      case 0x5c:
        output.write(r'\\');
      case 0x0a:
        output.write(r'\n');
      case 0x0d:
        output.write(r'\r');
      case 0x09:
        output.write(r'\t');
      case 0x1b:
        output.write(r'\e');
      case < 0x20 || (>= 0x7f && <= 0x9f):
        output.write(
          '\\u{${rune.toRadixString(16).toUpperCase().padLeft(4, '0')}}',
        );
      default:
        output.writeCharCode(rune);
    }
  }
  return output.toString();
}

String _decodeEscapedLinkTarget(String encoded) {
  final output = StringBuffer();
  var offset = 0;
  while (offset < encoded.length) {
    final slash = encoded.indexOf(r'\', offset);
    if (slash < 0) {
      output.write(encoded.substring(offset));
      break;
    }
    output.write(encoded.substring(offset, slash));
    final escape = encoded[slash + 1];
    switch (escape) {
      case r'\':
        output.write(r'\');
        offset = slash + 2;
      case 'n':
        output.write('\n');
        offset = slash + 2;
      case 'r':
        output.write('\r');
        offset = slash + 2;
      case 't':
        output.write('\t');
        offset = slash + 2;
      case 'e':
        output.writeCharCode(0x1b);
        offset = slash + 2;
      case 'u':
        final close = encoded.indexOf('}', slash + 3);
        output.writeCharCode(
          int.parse(encoded.substring(slash + 3, close), radix: 16),
        );
        offset = close + 1;
      default:
        fail('Unexpected link-target escape at offset $slash: $encoded');
    }
  }
  return output.toString();
}

String _lowCellUtf8(int byteLength) {
  final cluster = 'e${List<String>.filled(30, '\u0301').join()}';
  const clusterBytes = 61;
  final repetitions = byteLength ~/ clusterBytes;
  final remainder = byteLength % clusterBytes;
  return '${cluster * repetitions}${'x' * remainder}';
}

String _withoutDartComments(String source) {
  final output = StringBuffer();
  var offset = 0;
  while (offset < source.length) {
    if (source.startsWith('//', offset)) {
      final newline = source.indexOf('\n', offset + 2);
      if (newline < 0) break;
      output.write('\n');
      offset = newline + 1;
      continue;
    }
    if (source.startsWith('/*', offset)) {
      var depth = 1;
      offset += 2;
      while (offset < source.length && depth > 0) {
        if (source.startsWith('/*', offset)) {
          depth++;
          offset += 2;
        } else if (source.startsWith('*/', offset)) {
          depth--;
          offset += 2;
        } else {
          if (source.codeUnitAt(offset) == 0x0a) output.write('\n');
          offset++;
        }
      }
      continue;
    }

    final codeUnit = source.codeUnitAt(offset);
    if (codeUnit == 0x72 &&
        offset + 1 < source.length &&
        _isDartQuote(source.codeUnitAt(offset + 1))) {
      output.writeCharCode(codeUnit);
      offset = _copyDartString(source, offset + 1, output, raw: true);
    } else if (_isDartQuote(codeUnit)) {
      offset = _copyDartString(source, offset, output, raw: false);
    } else {
      output.writeCharCode(codeUnit);
      offset++;
    }
  }
  return output.toString();
}

int _copyDartString(
  String source,
  int start,
  StringBuffer output, {
  required bool raw,
}) {
  final quote = source.codeUnitAt(start);
  final triple =
      start + 2 < source.length &&
      source.codeUnitAt(start + 1) == quote &&
      source.codeUnitAt(start + 2) == quote;
  final delimiterLength = triple ? 3 : 1;
  output.write(source.substring(start, start + delimiterLength));
  var offset = start + delimiterLength;
  while (offset < source.length) {
    if (!raw && source.codeUnitAt(offset) == 0x5c) {
      output.writeCharCode(source.codeUnitAt(offset));
      offset++;
      if (offset < source.length) {
        output.writeCharCode(source.codeUnitAt(offset));
        offset++;
      }
      continue;
    }
    final closes = triple
        ? offset + 2 < source.length &&
              source.codeUnitAt(offset) == quote &&
              source.codeUnitAt(offset + 1) == quote &&
              source.codeUnitAt(offset + 2) == quote
        : source.codeUnitAt(offset) == quote;
    if (closes) {
      output.write(source.substring(offset, offset + delimiterLength));
      return offset + delimiterLength;
    }
    output.writeCharCode(source.codeUnitAt(offset));
    offset++;
  }
  return offset;
}

bool _isDartQuote(int codeUnit) => codeUnit == 0x22 || codeUnit == 0x27;

ContentStageSelection _contentSelectionFixture() {
  final file = parsePatchFixture('''
diff --git a/content.txt b/content.txt
--- a/content.txt
+++ b/content.txt
@@ -1 +1 @@
-before
+after
''').files.single;
  return ContentStageSelection(file: file, sections: file.sections);
}

WholeFileChange _wholeChangeFixture() {
  final paths = [
    GitPath.fromBytes([0x2d, 0x6f, 0x6c, 0x64, 0x0a]),
    GitPath.fromBytes([0x3a, 0x28, 0x67, 0x6c, 0x6f, 0x62, 0x29]),
  ];
  final id = WholeFileChange.canonicalId(
    reason: WholeFileChangeReason.renamed,
    pathspecs: paths,
  );
  return WholeFileChange(
    id: id,
    pathspecs: paths,
    reason: WholeFileChangeReason.renamed,
  );
}

final class _RunnerThrow {
  const _RunnerThrow(this.error);

  final Object error;
}

final class _ThrowingToString extends Error {
  @override
  String toString() => throw StateError('toString must not escape');
}

class _QueuedGitRunner implements GitCommandRunner {
  _QueuedGitRunner(Iterable<Object> results)
    : _results = List<Object>.of(results);

  final List<Object> _results;
  final List<List<String>> commands = [];
  final List<List<int>?> stdinInputs = [];

  int get unconsumedResultCount => _results.length;

  @override
  Future<GitCommandResult> run(
    List<String> args, {
    List<int>? stdinBytes,
  }) async {
    commands.add(List<String>.unmodifiable(args));
    stdinInputs.add(
      stdinBytes == null ? null : List<int>.unmodifiable(stdinBytes),
    );
    if (_results.isEmpty) {
      throw StateError('Unexpected git command: ${args.join(' ')}');
    }
    final result = _results.removeAt(0);
    if (result case _RunnerThrow(:final error)) {
      if (error is String) throw StateError(error);
      if (error is Error) throw error;
      if (error is Exception) throw error;
      throw StateError('Unsupported runner fixture error.');
    }
    return result as GitCommandResult;
  }
}

const _trackedDiffCommand = [
  '-c',
  'core.quotePath=true',
  'diff',
  '--no-ext-diff',
  '--no-color',
  '--raw',
  '-z',
  '--patch',
  '--unified=3',
  '--abbrev=64',
  '--src-prefix=a/',
  '--dst-prefix=b/',
  '--',
];

const _untrackedCommand = ['ls-files', '--others', '--exclude-standard', '-z'];

const _recordedTrackedDiff = '''
diff --git a/lib/app.dart b/lib/app.dart
index 1111111..2222222 100644
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -1 +1 @@
-old
+new
''';

Future<ProcessResult> _git(Directory repo, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repo.path,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    fail('git ${args.join(' ')} failed:\n${result.stderr}');
  }
  return result;
}

Future<void> _chmod(String path, String mode) async {
  final result = await Process.run('chmod', [mode, path]);
  if (result.exitCode != 0) {
    fail('chmod $mode $path failed:\n${result.stderr}');
  }
}

Future<List<int>> _gitBytes(Directory repo, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: repo.path,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  if (result.exitCode != 0) {
    fail(
      'git ${args.join(' ')} failed: '
      '${GitDiagnosticText.fromBytes(result.stderr as List<int>)}',
    );
  }
  return List<int>.unmodifiable(result.stdout as List<int>);
}

Future<void> _gitWithInputBytes(
  Directory repo,
  List<String> args,
  List<int> input,
) async {
  final process = await Process.start('git', args, workingDirectory: repo.path);
  final stdout = process.stdout.expand((chunk) => chunk).toList();
  final stderr = process.stderr.expand((chunk) => chunk).toList();
  process.stdin.add(input);
  await process.stdin.close();
  final exitCode = await process.exitCode;
  final stderrBytes = await stderr;
  await stdout;
  if (exitCode != 0) {
    fail(
      'git ${args.join(' ')} failed: '
      '${GitDiagnosticText.fromBytes(stderrBytes)}',
    );
  }
}

bool _containsBytes(List<int> source, List<int> pattern) {
  for (var offset = 0; offset + pattern.length <= source.length; offset++) {
    var matches = true;
    for (var i = 0; i < pattern.length; i++) {
      if (source[offset + i] != pattern[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
