import 'dart:async';

import 'package:noir/noir.dart'
    show BuildContext, GlobalKey, State, StatefulWidget, Text, Widget;
import 'package:noir/src/framework/diagnostics.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

import '../../tool/patch_manager/patch_manager.dart';
import '../helpers/key_driver.dart';
import '../helpers/patch_manager_fixtures.dart';

void main() {
  group('generation-ordered workspace loads', () {
    test('newer success wins over older success (B then A)', () async {
      final repo = _QueuedGitPatchRepository([
        _QueuedOutcome.pending(),
        _QueuedOutcome.pending(),
      ]);
      final driver = KeyDriver(PatchManagerApp(repository: repo));
      await driver.ready();
      await _drain(driver);
      expect(repo.calls, 1);
      expect(_treeText(driver), contains('Loading workspace changes...'));

      await driver.sendCharacter('r');
      await _drain(driver);
      expect(
        repo.calls,
        2,
        reason: 'second load must start before completing B',
      );
      expect(_treeText(driver), contains('Starting another workspace load...'));

      repo.complete(1, _workspaceDiff('newer.dart'));
      await _drain(driver);
      expect(
        _treeText(driver),
        contains('newer.dart'),
        reason:
            'tree after B complete: ${_treeText(driver)}; calls=${repo.calls}',
      );
      expect(_treeText(driver), isNot(contains('older.dart')));

      repo.complete(0, _workspaceDiff('older.dart'));
      await _drain(driver);
      expect(_treeText(driver), contains('newer.dart'));
      expect(_treeText(driver), isNot(contains('older.dart')));

      driver.dispose();
    });

    test('stale failure cannot overwrite newer success', () async {
      final repo = _QueuedGitPatchRepository([
        _QueuedOutcome.pending(),
        _QueuedOutcome.pending(),
      ]);
      final driver = KeyDriver(PatchManagerApp(repository: repo));
      await driver.ready();
      await _drain(driver);
      await driver.sendCharacter('r');
      await _drain(driver);

      repo.complete(1, _workspaceDiff('newer.dart'));
      await _drain(driver);
      expect(_treeText(driver), contains('newer.dart'));

      repo.fail(0, 'old error');
      await _drain(driver);
      expect(_treeText(driver), contains('newer.dart'));
      expect(_treeText(driver), isNot(contains('old error')));

      driver.dispose();
    });

    test('stale success cannot hide newer failure', () async {
      final repo = _QueuedGitPatchRepository([
        _QueuedOutcome.pending(),
        _QueuedOutcome.pending(),
      ]);
      final driver = KeyDriver(PatchManagerApp(repository: repo));
      await driver.ready();
      await _drain(driver);
      await driver.sendCharacter('r');
      await _drain(driver);

      repo.fail(1, 'new error');
      await _drain(driver);
      expect(_treeText(driver), contains('new error'));
      expect(_treeText(driver), contains('r retry'));

      repo.complete(0, _workspaceDiff('older.dart'));
      await _drain(driver);
      expect(_treeText(driver), contains('new error'));
      expect(_treeText(driver), isNot(contains('older.dart')));

      driver.dispose();
    });

    test('stale failure cannot replace newer failure', () async {
      final repo = _QueuedGitPatchRepository([
        _QueuedOutcome.pending(),
        _QueuedOutcome.pending(),
      ]);
      final driver = KeyDriver(PatchManagerApp(repository: repo));
      await driver.ready();
      await _drain(driver);
      await driver.sendCharacter('r');
      await _drain(driver);

      repo.fail(1, 'new error');
      await _drain(driver);
      expect(_treeText(driver), contains('new error'));

      repo.fail(0, 'old error');
      await _drain(driver);
      expect(_treeText(driver), contains('new error'));
      expect(_treeText(driver), isNot(contains('old error')));

      driver.dispose();
    });

    test(
      'active load error with throwing toString is safely rendered',
      () async {
        final repo = _QueuedGitPatchRepository([_QueuedOutcome.pending()]);
        final driver = KeyDriver(PatchManagerApp(repository: repo));
        await driver.ready();
        await _drain(driver);

        final uncaught = <Object>[];
        await runZonedGuarded(() async {
          repo.fail(0, _ThrowingToString());
          await _drain(driver);
        }, (error, stackTrace) => uncaught.add(error));

        expect(uncaught, isEmpty);
        expect(_treeText(driver), contains('Exception text unavailable.'));
        expect(_treeText(driver), contains('r retry'));
        driver.dispose();
      },
    );

    test(
      'stale success while newer pending leaves load-again feedback',
      () async {
        final repo = _QueuedGitPatchRepository([
          _QueuedOutcome.pending(),
          _QueuedOutcome.pending(),
        ]);
        final driver = KeyDriver(PatchManagerApp(repository: repo));
        await driver.ready();
        await _drain(driver);
        await driver.sendCharacter('r');
        await _drain(driver);
        expect(
          _treeText(driver),
          contains('Starting another workspace load...'),
        );

        repo.complete(0, _workspaceDiff('older.dart'));
        await _drain(driver);
        expect(
          _treeText(driver),
          contains('Starting another workspace load...'),
        );
        expect(_treeText(driver), isNot(contains('older.dart')));

        repo.complete(1, _workspaceDiff('newer.dart'));
        await _drain(driver);
        expect(_treeText(driver), contains('newer.dart'));

        driver.dispose();
      },
    );

    test(
      'retry after failure shows retry feedback then accepts success',
      () async {
        final repo = _QueuedGitPatchRepository([
          _QueuedOutcome.failNow('first boom'),
          _QueuedOutcome.pending(),
        ]);
        final driver = KeyDriver(PatchManagerApp(repository: repo));
        await driver.ready();
        await _drain(driver);
        expect(_treeText(driver), contains('first boom'));
        expect(_treeText(driver), contains('r retry'));

        await driver.sendCharacter('r');
        await _drain(driver);
        expect(_treeText(driver), contains('Retrying workspace load...'));

        repo.complete(1, _workspaceDiff('recovered.dart'));
        await _drain(driver);
        expect(_treeText(driver), contains('recovered.dart'));

        driver.dispose();
      },
    );

    test(
      'repository replacement defers and catches a synchronous throw',
      () async {
        final oldRepo = _QueuedGitPatchRepository([
          _QueuedOutcome.success(_workspaceDiff('old.dart')),
        ]);
        final throwingRepo = _QueuedGitPatchRepository([
          _QueuedOutcome.failNow('sync replacement failure'),
        ]);
        final key = GlobalKey<_RepositoryHostState>();
        final driver = KeyDriver(
          _RepositoryHost(key: key, repository: oldRepo),
        );
        await driver.ready();
        await _drain(driver);
        expect(_treeText(driver), contains('old.dart'));

        key.currentState!.replaceRepository(throwingRepo);
        driver.app.buildOwner.buildScope();

        expect(throwingRepo.calls, 0);
        expect(_treeText(driver), contains('Loading workspace changes...'));
        expect(_treeText(driver), isNot(contains('old.dart')));

        final uncaught = <Object>[];
        await runZonedGuarded(
          () async => _drain(driver),
          (error, stackTrace) => uncaught.add(error),
        );

        expect(uncaught, isEmpty);
        expect(_treeText(driver), contains('sync replacement failure'));
        expect(_treeText(driver), contains('r retry'));
        driver.dispose();
      },
    );

    test(
      'repository rebinding clears old state and stages only through new repo',
      () async {
        final oldRepo = _QueuedGitPatchRepository([
          _QueuedOutcome.success(_workspaceDiff('old.dart')),
        ]);
        final newRepo = _QueuedGitPatchRepository([_QueuedOutcome.pending()]);
        final key = GlobalKey<_RepositoryHostState>();
        final driver = KeyDriver(
          _RepositoryHost(key: key, repository: oldRepo),
        );
        await driver.ready();
        await _drain(driver);
        expect(_treeText(driver), contains('old.dart'));

        key.currentState!.replaceRepository(oldRepo);
        await _drain(driver);
        expect(oldRepo.calls, 1);

        key.currentState!.replaceRepository(newRepo);
        driver.app.buildOwner.buildScope();
        expect(newRepo.calls, 0);
        expect(_treeText(driver), contains('Loading workspace changes...'));
        expect(_treeText(driver), isNot(contains('old.dart')));

        await _drain(driver);
        newRepo.complete(0, _workspaceDiff('new.dart'));
        await _drain(driver);

        await driver.sendCharacter('s');
        await _drain(driver);
        expect(oldRepo.stageCalls, 0);
        expect(newRepo.stageCalls, 1);
        driver.dispose();
      },
    );

    test(
      'old completion cannot overwrite an accepted replacement diff',
      () async {
        final oldRepo = _QueuedGitPatchRepository([_QueuedOutcome.pending()]);
        final newRepo = _QueuedGitPatchRepository([_QueuedOutcome.pending()]);
        final key = GlobalKey<_RepositoryHostState>();
        final driver = KeyDriver(
          _RepositoryHost(key: key, repository: oldRepo),
        );
        await driver.ready();
        await _drain(driver);

        key.currentState!.replaceRepository(newRepo);
        await _drain(driver);
        newRepo.complete(0, _workspaceDiff('replacement.dart'));
        await _drain(driver);
        oldRepo.complete(0, _workspaceDiff('stale-old.dart'));
        await _drain(driver);

        expect(_treeText(driver), contains('replacement.dart'));
        expect(_treeText(driver), isNot(contains('stale-old.dart')));
        driver.dispose();
      },
    );

    test(
      'stale failure while third generation pending leaves C as sole owner',
      () async {
        final repo = _QueuedGitPatchRepository([
          _QueuedOutcome.pending(),
          _QueuedOutcome.pending(),
          _QueuedOutcome.pending(),
        ]);
        final driver = KeyDriver(PatchManagerApp(repository: repo));
        await driver.ready();
        await _drain(driver);
        await driver.sendCharacter('r');
        await _drain(driver);
        await driver.sendCharacter('r');
        await _drain(driver);
        expect(repo.calls, 3);
        expect(
          _treeText(driver),
          contains('Starting another workspace load...'),
        );

        repo.fail(0, 'A fail');
        await _drain(driver);
        expect(
          _treeText(driver),
          contains('Starting another workspace load...'),
        );
        expect(_treeText(driver), isNot(contains('A fail')));

        repo.fail(1, 'B fail');
        await _drain(driver);
        expect(
          _treeText(driver),
          contains('Starting another workspace load...'),
        );
        expect(_treeText(driver), isNot(contains('B fail')));

        repo.complete(2, _workspaceDiff('final.dart'));
        await _drain(driver);
        expect(_treeText(driver), contains('final.dart'));

        driver.dispose();
      },
    );

    test(
      'dispose revokes pending completions without setState errors',
      () async {
        final repo = _QueuedGitPatchRepository([
          _QueuedOutcome.pending(),
          _QueuedOutcome.pending(),
        ]);
        final driver = KeyDriver(PatchManagerApp(repository: repo));
        await driver.ready();
        await _drain(driver);
        await driver.sendCharacter('r');
        await _drain(driver);
        driver.dispose();

        final errors = <Object>[];
        await runZonedGuarded(() async {
          repo
            ..complete(0, _workspaceDiff('a.dart'))
            ..complete(1, _workspaceDiff('b.dart'));
          await _drain();
        }, (error, stack) => errors.add(error));

        expect(errors, isEmpty);
      },
    );
  });
}

Future<void> _drain([KeyDriver? driver]) async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
    driver?.app.buildOwner.buildScope();
    if (driver?.app.debugHasScheduledFrame ?? false) {
      driver!.app.debugFlushFrame();
    }
  }
}

/// Collects plain text from mounted [Text] widgets (avoids paint-buffer invalidation).
String _treeText(KeyDriver driver) {
  final texts = <String>[];
  void walk(Element element) {
    final widget = element.widget;
    if (widget is Text) {
      final data = widget.data;
      if (data != null && data.isNotEmpty) {
        texts.add(data);
      }
      final span = widget.textSpan;
      if (span != null) {
        final buffer = StringBuffer();
        span.computePlainText(buffer);
        final plain = buffer.toString();
        if (plain.isNotEmpty) texts.add(plain);
      }
    }
    element.visitChildren(walk);
  }

  final root = WidgetInspectorService.instance.rootElement;
  if (root != null) {
    walk(root);
  }
  return texts.join('\n');
}

DiffSet _workspaceDiff(String path) {
  final diff = parsePatchFixture('''
diff --git a/$path b/$path
index 1111111..2222222 100644
--- a/$path
+++ b/$path
@@ -1,1 +1,1 @@
-old
+new
''');
  return diff;
}

class _QueuedOutcome {
  _QueuedOutcome._({this.completer, this.immediateError, this.immediateDiff});

  factory _QueuedOutcome.pending() =>
      _QueuedOutcome._(completer: Completer<DiffSet>());

  factory _QueuedOutcome.success(DiffSet diff) =>
      _QueuedOutcome._(immediateDiff: diff);

  factory _QueuedOutcome.failNow(String message) =>
      _QueuedOutcome._(immediateError: message);

  final Completer<DiffSet>? completer;
  final String? immediateError;
  final DiffSet? immediateDiff;
}

class _QueuedGitPatchRepository extends GitPatchRepository {
  _QueuedGitPatchRepository(this._queue) : super(worktreePath: '/tmp/fake');

  final List<_QueuedOutcome> _queue;
  int calls = 0;
  int stageCalls = 0;

  void complete(int index, DiffSet diff) {
    final completer = _queue[index].completer;
    if (completer == null) {
      throw StateError('outcome $index is not pending');
    }
    completer.complete(diff);
  }

  void fail(int index, Object error) {
    final completer = _queue[index].completer;
    if (completer == null) {
      throw StateError('outcome $index is not pending');
    }
    completer.completeError(error is String ? StateError(error) : error);
  }

  @override
  Future<DiffSet> loadWorkspace() {
    if (calls >= _queue.length) {
      throw StateError('unexpected load call ${calls + 1}');
    }
    final outcome = _queue[calls++];
    final immediateError = outcome.immediateError;
    if (immediateError != null) {
      throw StateError(immediateError);
    }
    final immediateDiff = outcome.immediateDiff;
    if (immediateDiff != null) {
      return Future<DiffSet>.value(immediateDiff);
    }
    return outcome.completer!.future;
  }

  @override
  Future<GitStageResult> stageContent(ContentStageSelection selection) {
    stageCalls++;
    return Future<GitStageResult>.value(
      const GitStageResult(
        outcome: GitStageOutcome.applied,
        stdout: '',
        stderr: '',
        patch: '',
      ),
    );
  }

  @override
  Future<GitStageResult> stageWholeFile(WholeFileChange change) {
    stageCalls++;
    return Future<GitStageResult>.value(
      const GitStageResult(
        outcome: GitStageOutcome.applied,
        stdout: '',
        stderr: '',
        patch: '',
      ),
    );
  }
}

class _RepositoryHost extends StatefulWidget {
  const _RepositoryHost({required this.repository, super.key});

  final GitPatchRepository repository;

  @override
  State<_RepositoryHost> createState() => _RepositoryHostState();
}

class _RepositoryHostState extends State<_RepositoryHost> {
  late GitPatchRepository _repository = widget.repository;

  void replaceRepository(GitPatchRepository repository) {
    setState(() => _repository = repository);
  }

  @override
  Widget build(BuildContext context) =>
      PatchManagerApp(repository: _repository);
}

final class _ThrowingToString extends Error {
  @override
  String toString() => throw StateError('toString must not escape');
}
