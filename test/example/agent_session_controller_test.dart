import 'dart:async';

import 'package:test/test.dart';

import '../../example/src/agent_chat_protocol.dart';
import '../../example/src/agent_session_controller.dart';

void main() {
  group('AgentSessionController', () {
    test(
      'reduces streaming text once and ignores duplicate or stale events',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        expect(controller.submit('inspect this change'), isTrue);
        final requestId = controller.activeRequestId!;
        expect(controller.entries.single.text, 'inspect this change');
        expect(controller.phase, AgentRunPhase.running);

        backend
          ..emit(
            AgentTextDeltaEvent(
              id: 'delta-1',
              requestId: requestId,
              blockId: 'answer',
              delta: 'I found ',
            ),
          )
          ..emit(
            AgentTextDeltaEvent(
              id: 'delta-2',
              requestId: requestId,
              blockId: 'answer',
              delta: 'two issues.',
            ),
          )
          ..emit(
            AgentTextFinalEvent(
              id: 'final-1',
              requestId: requestId,
              blockId: 'answer',
              text: 'I found **two** issues.',
            ),
          )
          ..emit(
            AgentTextFinalEvent(
              id: 'final-1',
              requestId: requestId,
              blockId: 'answer',
              text: 'duplicate must not win',
            ),
          )
          ..emit(
            AgentRequestCompletedEvent(
              id: 'done-1',
              requestId: requestId,
              inputTokens: 12,
              outputTokens: 7,
              costUsd: 0.004,
            ),
          )
          ..emit(
            AgentTextDeltaEvent(
              id: 'late-1',
              requestId: requestId,
              blockId: 'answer',
              delta: ' late',
            ),
          );

        final assistant = controller.entries.where(
          (entry) => entry.kind == AgentEntryKind.assistant,
        );
        expect(assistant, hasLength(1));
        expect(assistant.single.text, 'I found **two** issues.');
        expect(assistant.single.status, AgentEntryStatus.complete);
        expect(controller.phase, AgentRunPhase.idle);
        expect(controller.activeRequestId, isNull);
        expect(controller.inputTokens, 12);
        expect(controller.outputTokens, 7);
        expect(controller.costUsd, 0.004);
        expect(controller.ignoredEventCount, 2);
      },
    );

    test('updates one tool block through progress and failure', () async {
      final backend = ReplayAgentBackend();
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      controller.submit('read the file');
      final requestId = controller.activeRequestId!;

      backend
        ..emit(
          AgentToolStartedEvent(
            id: 'tool-start',
            requestId: requestId,
            blockId: 'tool-1',
            name: 'Read',
            summary: 'lib/main.dart',
          ),
        )
        ..emit(
          AgentToolProgressEvent(
            id: 'tool-progress',
            requestId: requestId,
            blockId: 'tool-1',
            message: 'Reading 40 lines',
          ),
        )
        ..emit(
          AgentToolResultEvent(
            id: 'tool-result',
            requestId: requestId,
            blockId: 'tool-1',
            output: 'Permission denied',
            isError: true,
          ),
        );

      final tool = controller.entries.singleWhere(
        (entry) => entry.kind == AgentEntryKind.tool,
      );
      expect(tool.title, 'Read · lib/main.dart');
      expect(tool.text, 'Permission denied');
      expect(tool.status, AgentEntryStatus.failed);
      expect(controller.toggleToolExpanded(tool.id), isTrue);
      expect(
        controller.entries.singleWhere((entry) => entry.id == tool.id).expanded,
        isTrue,
      );
    });

    test('preserves semantic diff output and permission previews', () async {
      const diff = '''
@@ -1 +1 @@
-before
+after''';
      final backend = ReplayAgentBackend();
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      controller.submit('edit the file');
      final requestId = controller.activeRequestId!;

      backend
        ..emit(
          AgentToolStartedEvent(
            id: 'edit-start',
            requestId: requestId,
            blockId: 'edit',
            name: 'Edit',
            summary: 'sample.dart',
          ),
        )
        ..emit(
          AgentToolResultEvent(
            id: 'edit-result',
            requestId: requestId,
            blockId: 'edit',
            output: diff,
            contentKind: AgentToolContentKind.unifiedDiff,
          ),
        )
        ..emit(
          AgentPermissionRequestEvent(
            id: 'edit-permission',
            requestId: requestId,
            permissionId: 'permit-edit',
            toolName: 'Edit',
            reason: 'Update sample.dart',
            preview: diff,
            previewContentKind: AgentToolContentKind.unifiedDiff,
          ),
        );

      final tool = controller.entries.singleWhere(
        (entry) => entry.kind == AgentEntryKind.tool,
      );
      expect(tool.contentKind, AgentToolContentKind.unifiedDiff);
      expect(controller.permissionRequest?.preview, diff);
      expect(
        controller.permissionRequest?.previewContentKind,
        AgentToolContentKind.unifiedDiff,
      );
    });

    test(
      'completion keeps streamed text and cancels an unreported tool',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('finish partial blocks');
        final requestId = controller.activeRequestId!;

        backend
          ..emit(
            AgentTextDeltaEvent(
              id: 'partial-text',
              requestId: requestId,
              blockId: 'answer',
              delta: 'Partial but retained.',
            ),
          )
          ..emit(
            AgentToolStartedEvent(
              id: 'partial-tool',
              requestId: requestId,
              blockId: 'tool',
              name: 'Read',
              summary: 'one file',
            ),
          )
          ..emit(
            AgentRequestCompletedEvent(
              id: 'partial-complete',
              requestId: requestId,
              inputTokens: 1,
              outputTokens: 1,
              costUsd: 0,
            ),
          );

        final assistant = controller.entries.singleWhere(
          (entry) => entry.kind == AgentEntryKind.assistant,
        );
        final tool = controller.entries.singleWhere(
          (entry) => entry.kind == AgentEntryKind.tool,
        );
        expect(assistant.status, AgentEntryStatus.complete);
        // The run ended before the tool reported, so the transcript must not
        // claim a result it never received.
        expect(tool.status, AgentEntryStatus.cancelled);
        expect(controller.phase, AgentRunPhase.idle);

        backend
          ..emit(
            AgentTextFinalEvent(
              id: 'late-final',
              requestId: requestId,
              blockId: 'answer',
              text: 'must not replace the retained partial',
            ),
          )
          ..emit(
            AgentToolResultEvent(
              id: 'late-result',
              requestId: requestId,
              blockId: 'tool',
              output: 'must not replace the retained tool state',
            ),
          );
        expect(
          controller.entries
              .singleWhere((entry) => entry.kind == AgentEntryKind.assistant)
              .text,
          'Partial but retained.',
        );
        expect(controller.ignoredEventCount, 2);
      },
    );

    test(
      'stream errors terminalize active work and allow another request',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('work before transport failure');
        final requestId = controller.activeRequestId!;

        backend
          ..emit(
            AgentTextDeltaEvent(
              id: 'streaming-text',
              requestId: requestId,
              blockId: 'answer',
              delta: 'Partial response',
            ),
          )
          ..emit(
            AgentToolStartedEvent(
              id: 'running-tool',
              requestId: requestId,
              blockId: 'tool',
              name: 'Read',
              summary: 'one file',
            ),
          )
          ..emit(
            AgentPermissionRequestEvent(
              id: 'pending-permission',
              requestId: requestId,
              permissionId: 'permit',
              toolName: 'Edit',
              reason: 'Update one file',
            ),
          )
          ..emitError(StateError('transport lost'));

        expect(controller.activeRequestId, isNull);
        expect(controller.permissionRequest, isNull);
        expect(controller.decisionInFlight, isFalse);
        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.lastError, contains('transport lost'));
        expect(
          controller.entries
              .where((entry) => entry.requestId == requestId)
              .where(
                (entry) =>
                    entry.kind == AgentEntryKind.assistant ||
                    entry.kind == AgentEntryKind.tool,
              )
              .map((entry) => entry.status),
          everyElement(AgentEntryStatus.failed),
        );
        expect(controller.submit('retry after stream error'), isTrue);
      },
    );

    test(
      'an unexpected stream close releases decisions and session loading',
      () async {
        final backend = ReplayAgentBackend(
          snapshots: {'saved': _snapshot('saved', 'saved transcript')},
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('work before stream close');
        final requestId = controller.activeRequestId!;

        backend
          ..emit(
            AgentToolStartedEvent(
              id: 'running-tool',
              requestId: requestId,
              blockId: 'tool',
              name: 'Read',
              summary: 'one file',
            ),
          )
          ..emit(
            AgentQuestionRequestEvent(
              id: 'pending-question',
              requestId: requestId,
              questionId: 'choice',
              prompt: 'Continue?',
              choices: const ['Yes', 'No'],
            ),
          );
        await backend.finishEvents();

        expect(controller.activeRequestId, isNull);
        expect(controller.questionRequest, isNull);
        expect(controller.decisionInFlight, isFalse);
        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.lastError, contains('closed unexpectedly'));
        expect(
          controller.entries
              .singleWhere((entry) => entry.kind == AgentEntryKind.tool)
              .status,
          AgentEntryStatus.failed,
        );
        expect(await controller.loadSession('saved'), isTrue);
        expect(controller.sessionId, 'saved');
        expect(controller.phase, AgentRunPhase.idle);
      },
    );

    test(
      'send failure terminalizes partial blocks and pending decisions',
      () async {
        late final ReplayAgentBackend backend;
        backend = ReplayAgentBackend(
          onCommand: (command) {
            if (command.kind != AgentBackendCommandKind.send) return;
            final requestId = command.requestId!;
            backend
              ..emit(
                AgentTextDeltaEvent(
                  id: 'partial-text',
                  requestId: requestId,
                  blockId: 'answer',
                  delta: 'Partial response',
                ),
              )
              ..emit(
                AgentToolStartedEvent(
                  id: 'partial-tool',
                  requestId: requestId,
                  blockId: 'tool',
                  name: 'Read',
                  summary: 'one file',
                ),
              )
              ..emit(
                AgentPermissionRequestEvent(
                  id: 'partial-permission',
                  requestId: requestId,
                  permissionId: 'permit',
                  toolName: 'Edit',
                  reason: 'Update one file',
                ),
              );
            throw StateError('send transport failed');
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        expect(controller.submit('trigger send failure'), isTrue);
        final requestId = controller.activeRequestId!;
        await Future<void>.delayed(Duration.zero);

        expect(controller.activeRequestId, isNull);
        expect(controller.permissionRequest, isNull);
        expect(controller.decisionInFlight, isFalse);
        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.lastError, contains('send transport failed'));
        expect(
          controller.entries
              .where((entry) => entry.requestId == requestId)
              .where(
                (entry) =>
                    entry.kind == AgentEntryKind.assistant ||
                    entry.kind == AgentEntryKind.tool,
              )
              .map((entry) => entry.status),
          everyElement(AgentEntryStatus.failed),
        );
      },
    );

    test(
      'retains retry, unknown, stderr, failure, and exit diagnostics',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('diagnose');
        final requestId = controller.activeRequestId!;

        backend
          ..emit(
            AgentRetryEvent(
              id: 'retry',
              requestId: requestId,
              attempt: 2,
              message: 'temporary API failure',
            ),
          )
          ..emit(
            AgentUnknownEvent(
              id: 'unknown',
              requestId: requestId,
              originalType: 'future_event',
              payload: const {'value': 1},
              diagnostic: 'Unsupported normalized event type.',
            ),
          )
          ..emit(const AgentStderrEvent(id: 'stderr', text: 'backend warning'))
          ..emit(
            AgentRequestFailedEvent(
              id: 'failed',
              requestId: requestId,
              message: 'request failed',
            ),
          )
          ..emit(const AgentProcessExitEvent(id: 'exit', exitCode: 17));

        final text = controller.entries.map((entry) => entry.text).join('\n');
        expect(text, contains('Retry 2'));
        expect(text, contains('future_event'));
        expect(text, contains('backend warning'));
        expect(text, contains('request failed'));
        expect(text, contains('exited with status 17'));
        expect(controller.phase, AgentRunPhase.failed);
      },
    );

    test(
      'interrupt clears a pending decision and rejects its late events',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('change a file');
        final requestId = controller.activeRequestId!;

        backend.emit(
          AgentPermissionRequestEvent(
            id: 'permission',
            requestId: requestId,
            permissionId: 'permit-1',
            toolName: 'Write',
            reason: 'Update lib/main.dart',
          ),
        );
        expect(controller.permissionRequest, isNotNull);
        expect(controller.phase, AgentRunPhase.waitingPermission);

        await controller.interrupt();
        expect(controller.permissionRequest, isNull);
        expect(controller.activeRequestId, isNull);
        expect(controller.phase, AgentRunPhase.cancelled);
        expect(backend.commands.last.kind, AgentBackendCommandKind.interrupt);

        backend.emit(
          AgentTextDeltaEvent(
            id: 'late',
            requestId: requestId,
            blockId: 'answer',
            delta: 'must be ignored',
          ),
        );
        expect(
          controller.entries.map((entry) => entry.text),
          isNot(contains('must be ignored')),
        );
      },
    );

    test(
      'permission decisions are single-flight, retryable, and record allow and deny',
      () async {
        var failNextPermission = true;
        final permissionGate = Completer<void>();
        final backend = ReplayAgentBackend(
          onCommand: (command) async {
            if (command.kind != AgentBackendCommandKind.permission) return;
            if (failNextPermission) {
              failNextPermission = false;
              throw StateError('decision transport failed');
            }
            if (!permissionGate.isCompleted) await permissionGate.future;
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('edit the file');
        final requestId = controller.activeRequestId!;
        backend.emit(
          AgentPermissionRequestEvent(
            id: 'permission-1',
            requestId: requestId,
            permissionId: 'permit-1',
            toolName: 'Edit',
            reason: 'Update a test',
          ),
        );

        expect(await controller.respondToPermission(allow: true), isFalse);
        expect(controller.permissionRequest?.permissionId, 'permit-1');
        expect(controller.decisionInFlight, isFalse);
        expect(controller.lastError, contains('decision transport failed'));

        final accepted = controller.respondToPermission(allow: true);
        expect(controller.decisionInFlight, isTrue);
        expect(
          await controller.respondToPermission(allow: false),
          isFalse,
          reason: 'a second response must not overtake the in-flight decision',
        );
        permissionGate.complete();
        expect(await accepted, isTrue);
        expect(controller.permissionRequest, isNull);
        expect(controller.phase, AgentRunPhase.running);

        backend.emit(
          AgentPermissionRequestEvent(
            id: 'permission-2',
            requestId: requestId,
            permissionId: 'permit-2',
            toolName: 'Shell',
            reason: 'Run a focused test',
          ),
        );
        expect(await controller.respondToPermission(allow: false), isTrue);
        final decisions = backend.commands.where(
          (command) => command.kind == AgentBackendCommandKind.permission,
        );
        expect(decisions.map((command) => command.allowed), [
          true,
          true,
          false,
        ]);
      },
    );

    test('question choices and free text remain semantic answers', () async {
      final backend = ReplayAgentBackend();
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      controller.submit('choose an approach');
      final requestId = controller.activeRequestId!;

      backend.emit(
        AgentQuestionRequestEvent(
          id: 'question-1',
          requestId: requestId,
          questionId: 'approach',
          prompt: 'Which approach?',
          choices: const ['Small patch', 'Rewrite'],
        ),
      );
      expect(controller.questionRequest?.choices, ['Small patch', 'Rewrite']);
      expect(await controller.answerQuestion('Small patch'), isTrue);

      backend.emit(
        AgentQuestionRequestEvent(
          id: 'question-2',
          requestId: requestId,
          questionId: 'detail',
          prompt: 'Anything else?',
          choices: const [],
          allowFreeText: true,
        ),
      );
      expect(controller.questionRequest?.allowFreeText, isTrue);
      expect(await controller.answerQuestion('  preserve file:line  '), isTrue);
      final answers = backend.commands.where(
        (command) => command.kind == AgentBackendCommandKind.answer,
      );
      expect(answers.map((command) => command.targetId), [
        'approach',
        'detail',
      ]);
      expect(answers.map((command) => command.value), [
        'Small patch',
        'preserve file:line',
      ]);
    });

    test(
      'choosing current settings invalidates older pending changes',
      () async {
        final modelGate = Completer<void>();
        final modeGate = Completer<void>();
        final backend = ReplayAgentBackend(
          onCommand: (command) => switch (command.kind) {
            AgentBackendCommandKind.setModel => modelGate.future,
            AgentBackendCommandKind.setPermissionMode => modeGate.future,
            _ => null,
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        final olderModel = controller.selectModel('opus');
        await Future<void>.delayed(Duration.zero);
        expect(await controller.selectModel('sonnet'), isTrue);
        modelGate.complete();
        expect(await olderModel, isFalse);
        expect(controller.model, 'sonnet');

        final olderMode = controller.selectPermissionMode(
          AgentPermissionMode.autoEdit,
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          await controller.selectPermissionMode(AgentPermissionMode.review),
          isTrue,
        );
        modeGate.complete();
        expect(await olderMode, isFalse);
        expect(controller.permissionMode, AgentPermissionMode.review);
      },
    );

    test(
      'snapshot publication invalidates older model and mode changes',
      () async {
        final modelGate = Completer<void>();
        final modeGate = Completer<void>();
        final backend = ReplayAgentBackend(
          snapshots: {'saved': _snapshot('saved', 'saved transcript')},
          onCommand: (command) => switch (command.kind) {
            AgentBackendCommandKind.setModel => modelGate.future,
            AgentBackendCommandKind.setPermissionMode => modeGate.future,
            _ => null,
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        final oldModel = controller.selectModel('haiku');
        final oldMode = controller.selectPermissionMode(
          AgentPermissionMode.autoEdit,
        );
        await Future<void>.delayed(Duration.zero);
        expect(await controller.loadSession('saved'), isTrue);
        modelGate.complete();
        modeGate.complete();

        expect(await oldModel, isFalse);
        expect(await oldMode, isFalse);
        expect(controller.model, 'opus');
        expect(controller.permissionMode, AgentPermissionMode.plan);
      },
    );

    test(
      'backend failure invalidates a pending snapshot before retry submit',
      () async {
        final snapshotGate = Completer<AgentSessionSnapshot>();
        final backend = ReplayAgentBackend(
          onLoadSession: (_) => snapshotGate.future,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        final load = controller.loadSession('slow');
        await Future<void>.delayed(Duration.zero);
        backend.emitError(StateError('stream failed during load'));
        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.submit('retry after failed load'), isTrue);
        final retryRequestId = controller.activeRequestId;

        snapshotGate.complete(_snapshot('slow', 'stale transcript'));
        expect(await load, isFalse);
        expect(controller.sessionId, 'local');
        expect(controller.activeRequestId, retryRequestId);
        expect(
          controller.entries.map((entry) => entry.text),
          contains('retry after failed load'),
        );
      },
    );

    test(
      'late interrupt failure cannot contaminate a loaded snapshot',
      () async {
        final interruptGate = Completer<void>();
        final backend = ReplayAgentBackend(
          snapshots: {'saved': _snapshot('saved', 'saved transcript')},
          onCommand: (command) {
            if (command.kind == AgentBackendCommandKind.interrupt) {
              return interruptGate.future;
            }
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        controller.submit('request to interrupt');

        final interrupt = controller.interrupt();
        expect(await controller.loadSession('saved'), isTrue);
        interruptGate.completeError(StateError('late interrupt failure'));
        await interrupt;

        expect(controller.sessionId, 'saved');
        expect(controller.lastError, isNull);
        expect(controller.entries.single.text, 'saved transcript');
      },
    );

    test(
      'close suppresses completion from a pending decision callback',
      () async {
        final pending = Completer<void>();
        final backend = ReplayAgentBackend(
          onCommand: (command) {
            if (command.kind == AgentBackendCommandKind.permission) {
              return pending.future;
            }
          },
        );
        final controller = AgentSessionController(backend: backend);
        await controller.start();
        controller.submit('write a file');
        backend.emit(
          AgentPermissionRequestEvent(
            id: 'permission',
            requestId: controller.activeRequestId!,
            permissionId: 'permit',
            toolName: 'Write',
            reason: 'Write output',
          ),
        );
        var notifications = 0;
        controller.addListener(() => notifications++);

        final response = controller.respondToPermission(allow: true);
        await Future<void>.delayed(Duration.zero);
        await controller.close();
        final afterClose = notifications;
        pending.complete();

        expect(await response, isFalse);
        expect(notifications, afterClose);
        expect(controller.phase, AgentRunPhase.closed);
        expect(
          backend.commands.where(
            (command) => command.kind == AgentBackendCommandKind.close,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'close still closes the backend and disposes after cancel fails',
      () async {
        final backend = _CancelFailureBackend();
        final controller = AgentSessionController(backend: backend);
        await controller.start();

        await expectLater(
          controller.close(),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'subscription cancel failed',
            ),
          ),
        );
        expect(backend.closeCount, 1);
        expect(controller.phase, AgentRunPhase.closed);
        expect(
          () => controller.addListener(() {}),
          throwsStateError,
          reason: 'the controller must dispose even when cancellation fails',
        );

        await expectLater(controller.close(), throwsStateError);
        expect(backend.closeCount, 1);
      },
    );

    test(
      'session loading publishes only the latest snapshot and preserves state on failure',
      () async {
        final oldLoad = Completer<AgentSessionSnapshot>();
        final latestLoad = Completer<AgentSessionSnapshot>();
        final backend = ReplayAgentBackend(
          onLoadSession: (sessionId) => switch (sessionId) {
            'old' => oldLoad.future,
            'latest' => latestLoad.future,
            _ => throw StateError('snapshot unavailable'),
          },
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();

        final oldResult = controller.loadSession('old');
        final latestResult = controller.loadSession('latest');
        oldLoad.complete(_snapshot('old', 'old transcript'));
        expect(await oldResult, isFalse);
        expect(controller.sessionId, 'local');
        expect(controller.phase, AgentRunPhase.loadingSession);
        expect(
          controller.submit('must not race the pending snapshot'),
          isFalse,
        );
        expect(controller.entries, isEmpty);

        latestLoad.complete(_snapshot('latest', 'latest transcript'));
        expect(await latestResult, isTrue);
        expect(controller.sessionId, 'latest');
        expect(controller.model, 'opus');
        expect(controller.permissionMode, AgentPermissionMode.plan);
        expect(controller.entries.single.text, 'latest transcript');
        expect(controller.inputTokens, 21);
        expect(controller.outputTokens, 34);
        expect(controller.costUsd, 0.12);

        final before = controller.entries;
        expect(await controller.loadSession('missing'), isFalse);
        expect(controller.sessionId, 'latest');
        expect(controller.entries, before);
        expect(controller.lastError, contains('snapshot unavailable'));
      },
    );

    test('session snapshots retain semantic tool presentation', () async {
      final backend = ReplayAgentBackend(
        snapshots: {
          'diff': AgentSessionSnapshot(
            sessionId: 'diff',
            model: 'sonnet',
            permissionMode: AgentPermissionMode.review,
            entries: const [
              AgentSnapshotEntry(
                id: 'saved-diff',
                kind: AgentSnapshotEntryKind.tool,
                title: 'Edit · sample.dart',
                text: '@@ -1 +1 @@\n-before\n+after',
                contentKind: AgentToolContentKind.unifiedDiff,
              ),
            ],
          ),
        },
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();

      expect(await controller.loadSession('diff'), isTrue);
      expect(
        controller.entries.single.contentKind,
        AgentToolContentKind.unifiedDiff,
      );
    });
  });
}

AgentSessionSnapshot _snapshot(String id, String text) => AgentSessionSnapshot(
  sessionId: id,
  model: 'opus',
  permissionMode: AgentPermissionMode.plan,
  entries: [
    AgentSnapshotEntry(
      id: '$id-entry',
      kind: AgentSnapshotEntryKind.assistant,
      text: text,
    ),
  ],
  inputTokens: 21,
  outputTokens: 34,
  costUsd: 0.12,
);

final class _CancelFailureBackend implements AgentBackend {
  _CancelFailureBackend() {
    _events = StreamController<AgentEvent>(
      onCancel: () async {
        throw StateError('subscription cancel failed');
      },
    );
  }

  late final StreamController<AgentEvent> _events;
  int closeCount = 0;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> send(AgentRequest request) async {}

  @override
  Future<void> interrupt(String requestId) async {}

  @override
  Future<void> respondToPermission({
    required String requestId,
    required String permissionId,
    required bool allow,
  }) async {}

  @override
  Future<void> answerQuestion({
    required String requestId,
    required String questionId,
    required String answer,
  }) async {}

  @override
  Future<void> setModel(String model) async {}

  @override
  Future<void> setPermissionMode(AgentPermissionMode mode) async {}

  @override
  Future<List<AgentSessionSummary>> listSessions() async => const [];

  @override
  Future<AgentSessionSnapshot> loadSession(String sessionId) async =>
      throw StateError('no sessions');

  @override
  Future<void> close() async {
    closeCount++;
    await _events.close();
  }
}
