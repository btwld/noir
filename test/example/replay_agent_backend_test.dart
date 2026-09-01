import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../example/src/agent_chat_protocol.dart';

void main() {
  group('AgentEventCodec', () {
    test('decodes known events and retains unknown or malformed lines', () {
      final delta = AgentEventCodec.decodeLine(
        '{"type":"text_delta","id":"e1","requestId":"r1",'
        '"blockId":"b1","delta":"hello"}',
      );
      expect(delta, isA<AgentTextDeltaEvent>());
      expect((delta as AgentTextDeltaEvent).delta, 'hello');

      final future = AgentEventCodec.decodeLine(
        '{"type":"future_shape","id":"e2","answer":42}',
      );
      expect(future, isA<AgentUnknownEvent>());
      expect((future as AgentUnknownEvent).originalType, 'future_shape');
      expect(future.payload['answer'], 42);

      final malformed = AgentEventCodec.decodeLine('{not json');
      expect(malformed, isA<AgentUnknownEvent>());
      expect((malformed as AgentUnknownEvent).originalType, 'malformed');
      expect(malformed.payload['raw'], '{not json');

      final otherMalformed = AgentEventCodec.decodeLine('{still not json');
      expect(otherMalformed.id, isNot(malformed.id));
    });

    test('decodes semantic tool presentation and rejects unknown kinds', () {
      final result = AgentEventCodec.decodeLine(
        jsonEncode({
          'type': 'tool_result',
          'id': 'result',
          'requestId': 'request',
          'blockId': 'edit',
          'output': '@@ -1 +1 @@\n-before\n+after',
          'isError': false,
          'contentKind': 'unified_diff',
        }),
      );
      expect(result, isA<AgentToolResultEvent>());
      expect(
        (result as AgentToolResultEvent).contentKind,
        AgentToolContentKind.unifiedDiff,
      );

      final permission = AgentEventCodec.decodeLine(
        jsonEncode({
          'type': 'permission',
          'id': 'permission',
          'requestId': 'request',
          'permissionId': 'permit',
          'toolName': 'Edit',
          'reason': 'Update sample.dart',
          'preview': '@@ -1 +1 @@\n-before\n+after',
          'previewContentKind': 'unified_diff',
        }),
      );
      expect(permission, isA<AgentPermissionRequestEvent>());
      expect(
        (permission as AgentPermissionRequestEvent).previewContentKind,
        AgentToolContentKind.unifiedDiff,
      );
      expect(permission.preview, contains('-before'));

      final unsupported = AgentEventCodec.decodeLine(
        jsonEncode({
          'type': 'tool_result',
          'id': 'unsupported',
          'requestId': 'request',
          'blockId': 'edit',
          'output': 'opaque',
          'isError': false,
          'contentKind': 'ansi_screen',
        }),
      );
      expect(unsupported, isA<AgentUnknownEvent>());
    });

    test('decodes the tracked normalized fixture without data loss', () {
      final events = File(
        'test/fixtures/agent_chat/core.jsonl',
      ).readAsLinesSync().map(AgentEventCodec.decodeLine).toList();

      expect(events, hasLength(15));
      expect(events.map((event) => event.runtimeType), [
        AgentSessionEvent,
        AgentTextDeltaEvent,
        AgentTextFinalEvent,
        AgentToolStartedEvent,
        AgentToolProgressEvent,
        AgentToolResultEvent,
        AgentRetryEvent,
        AgentPermissionRequestEvent,
        AgentQuestionRequestEvent,
        AgentRequestCompletedEvent,
        AgentRequestCancelledEvent,
        AgentRequestFailedEvent,
        AgentStderrEvent,
        AgentProcessExitEvent,
        AgentUnknownEvent,
      ]);
      expect((events[8] as AgentQuestionRequestEvent).choices, [
        'Add a guard',
        'Leave unchanged',
      ]);
      expect(
        (events[5] as AgentToolResultEvent).contentKind,
        AgentToolContentKind.plainText,
      );
      expect(
        (events[7] as AgentPermissionRequestEvent).previewContentKind,
        AgentToolContentKind.plainText,
      );
      expect((events.last as AgentUnknownEvent).payload['future'], true);
    });

    test('turns every malformed fixture line into a diagnostic event', () {
      final events = File(
        'test/fixtures/agent_chat/malformed.jsonl',
      ).readAsLinesSync().map(AgentEventCodec.decodeLine).toList();

      expect(events, hasLength(6));
      expect(events, everyElement(isA<AgentUnknownEvent>()));
      expect(
        events.cast<AgentUnknownEvent>().map((event) => event.diagnostic),
        everyElement(isNotEmpty),
      );
    });

    test('keeps the complete normalized scenario fixture set decodable', () {
      final directory = Directory('test/fixtures/agent_chat');
      final files =
          directory
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.jsonl'))
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));

      expect(files.map((file) => file.uri.pathSegments.last), [
        'core.jsonl',
        'decisions.jsonl',
        'errors.jsonl',
        'malformed.jsonl',
        'sessions_long_history.jsonl',
        'streaming_tools.jsonl',
      ]);
      for (final file in files) {
        final lines = file.readAsLinesSync();
        expect(lines, isNotEmpty, reason: file.path);
        expect(
          lines.map(AgentEventCodec.decodeLine),
          everyElement(isA<AgentEvent>()),
          reason: file.path,
        );
      }
    });
  });

  group('ReplayAgentBackend', () {
    test('records commands and emits one script in order', () async {
      final backend = ReplayAgentBackend(
        scripts: {
          'hello': [
            AgentReplayStep.forRequest(
              Duration.zero,
              (requestId) => AgentTextDeltaEvent(
                id: 'one',
                requestId: requestId,
                blockId: 'answer',
                delta: 'Hi',
              ),
            ),
            AgentReplayStep.forRequest(
              Duration.zero,
              (requestId) => AgentRequestCompletedEvent(
                id: 'two',
                requestId: requestId,
                inputTokens: 1,
                outputTokens: 1,
                costUsd: 0.001,
              ),
            ),
          ],
        },
      );
      addTearDown(backend.close);
      final events = <AgentEvent>[];
      final subscription = backend.events.listen(events.add);
      addTearDown(subscription.cancel);

      await backend.start();
      await backend.send(const AgentRequest(id: 'request-7', prompt: 'hello'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backend.commands.map((command) => command.kind), [
        AgentBackendCommandKind.start,
        AgentBackendCommandKind.send,
      ]);
      expect(events, hasLength(2));
      expect(events.map((event) => event.requestId), everyElement('request-7'));
    });

    test(
      'close is idempotent, cancels pending replay, and rejects commands',
      () async {
        final backend = ReplayAgentBackend(
          scripts: {
            'wait': [
              AgentReplayStep(
                const Duration(hours: 1),
                AgentTextDeltaEvent(
                  id: 'late',
                  requestId: r'$request',
                  blockId: 'answer',
                  delta: 'late',
                ),
              ),
            ],
          },
        );
        final events = <AgentEvent>[];
        backend.events.listen(events.add);
        await backend.start();
        await backend.send(const AgentRequest(id: 'r1', prompt: 'wait'));

        await backend.close();
        await backend.close();

        expect(events, isEmpty);
        expect(
          () => backend.send(const AgentRequest(id: 'r2', prompt: 'wait')),
          throwsStateError,
        );
        expect(
          backend.commands.where(
            (command) => command.kind == AgentBackendCommandKind.close,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'close wins over a send callback before it can schedule replay',
      () async {
        final commandGate = Completer<void>();
        final backend = ReplayAgentBackend(
          fallbackScript: [
            AgentReplayStep(
              Duration.zero,
              const AgentProcessExitEvent(id: 'must-not-emit', exitCode: 0),
            ),
          ],
          onCommand: (command) {
            if (command.kind == AgentBackendCommandKind.send) {
              return commandGate.future;
            }
          },
        );
        final events = <AgentEvent>[];
        backend.events.listen(events.add);
        await backend.start();

        final send = backend.send(const AgentRequest(id: 'r1', prompt: 'wait'));
        await Future<void>.delayed(Duration.zero);
        await backend.close();
        commandGate.complete();

        await expectLater(send, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
      },
    );

    test(
      'finishing the event stream suppresses pending replay timers',
      () async {
        final backend = ReplayAgentBackend(
          fallbackScript: [
            AgentReplayStep(
              const Duration(milliseconds: 10),
              const AgentProcessExitEvent(id: 'must-not-emit', exitCode: 0),
            ),
          ],
        );
        addTearDown(backend.close);
        final events = <AgentEvent>[];
        backend.events.listen(events.add);
        await backend.start();
        await backend.send(const AgentRequest(id: 'r1', prompt: 'wait'));

        await backend.finishEvents();
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(events, isEmpty);
      },
    );

    test('replay steps reject negative delays in every build mode', () {
      expect(
        () => AgentReplayStep(
          const Duration(milliseconds: -1),
          const AgentProcessExitEvent(id: 'invalid', exitCode: 0),
        ),
        throwsArgumentError,
      );
      expect(
        () => AgentReplayStep.forRequest(
          const Duration(milliseconds: -1),
          (requestId) =>
              const AgentProcessExitEvent(id: 'invalid-builder', exitCode: 0),
        ),
        throwsArgumentError,
      );
    });
  });
}
