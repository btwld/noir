import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../example/src/agent_chat_protocol.dart';
import '../../example/src/agent_session_controller.dart';
import '../../example/src/claude_cli_backend.dart';

void main() {
  test('system process close cannot block forever on stdin', () async {
    final stdinCloseGate = Completer<void>();
    final process = _FakeSystemProcess(stdinCloseGate);
    final launcher = SystemClaudeProcessLauncher(
      startProcess: (executable, arguments, {workingDirectory}) async =>
          process,
    );
    final handle = await launcher.start(
      'claude',
      const [],
      workingDirectory: '/fixture',
    );

    final closeExpectation = expectLater(
      handle.close(gracePeriod: const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final killedBeforeInputClosed = process.killSignals.isNotEmpty;
    stdinCloseGate.complete();
    await closeExpectation;

    expect(killedBeforeInputClosed, isTrue);
    expect(process.killSignals, [ProcessSignal.sigterm]);
  });

  group('ClaudeStreamEventDecoder', () {
    test('normalizes the pinned partial stream without duplicating text', () {
      final decoder = ClaudeStreamEventDecoder()..beginRequest('request-1');
      final events = File(
        'test/fixtures/claude_cli/stream_2_1_246.jsonl',
      ).readAsLinesSync().expand(decoder.decodeLine).toList();

      final session = events.whereType<AgentSessionEvent>().single;
      expect(session.sessionId, 'fixture-session');
      // The adapter always starts the CLI with `dontAsk`, and the header
      // must not report that as a reviewing session.
      expect(session.permissionMode, AgentPermissionMode.unattended);
      expect(
        events.whereType<AgentTextDeltaEvent>().map((event) => event.delta),
        ['NOIR_', 'SPIKE_OK'],
      );
      final finalText = events.whereType<AgentTextFinalEvent>().single;
      expect(finalText.blockId, 'message-1:0');
      expect(finalText.text, 'NOIR_SPIKE_OK');
      expect(
        events.whereType<AgentUnknownEvent>().map(
          (event) => event.originalType,
        ),
        ['future_event'],
      );
      final completed = events.whereType<AgentRequestCompletedEvent>().single;
      expect(completed.requestId, 'request-1');
      expect(completed.inputTokens, 5375);
      expect(completed.outputTokens, 15);
      expect(completed.costUsd, closeTo(0.0101438, 0.0000001));
    });

    test(
      'normalizes tool use/results, retry, failure, and malformed input',
      () {
        final decoder = ClaudeStreamEventDecoder()..beginRequest('request-2');
        final events = <AgentEvent>[
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'stream_event',
              'uuid': 'tool-start',
              'event': {
                'type': 'message_start',
                'message': {'id': 'message-2'},
              },
            }),
          ),
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'assistant',
              'uuid': 'tool-final',
              'message': {
                'id': 'message-2',
                'content': [
                  {
                    'type': 'tool_use',
                    'id': 'tool-1',
                    'name': 'Read',
                    'input': {'file_path': 'README.md'},
                  },
                ],
              },
            }),
          ),
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'stream_event',
              'uuid': 'tool-block',
              'event': {
                'type': 'content_block_start',
                'index': 0,
                'content_block': {
                  'type': 'tool_use',
                  'id': 'tool-1',
                  'name': 'Read',
                  'input': {'file_path': 'README.md'},
                },
              },
            }),
          ),
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'user',
              'uuid': 'tool-result',
              'message': {
                'content': [
                  {
                    'type': 'tool_result',
                    'tool_use_id': 'tool-1',
                    'content': 'contents',
                    'is_error': false,
                  },
                ],
              },
            }),
          ),
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'system',
              'subtype': 'api_retry',
              'uuid': 'retry-1',
              'attempt': 2,
              'max_retries': 4,
              'retry_delay_ms': 250,
              'error_status': 529,
              'error': {
                'message': 'Service overloaded',
                'formatted': 'Overloaded; retrying',
              },
            }),
          ),
          ...decoder.decodeLine('{not json'),
          ...decoder.decodeLine(
            jsonEncode({
              'type': 'result',
              'subtype': 'error_during_execution',
              'uuid': 'failed-1',
              'is_error': true,
              'errors': ['request failed'],
              'terminal_reason': 'api_error',
            }),
          ),
        ];

        final started = events.whereType<AgentToolStartedEvent>().single;
        expect(started.blockId, 'tool-1');
        expect(started.name, 'Read');
        expect(started.summary, contains('README.md'));
        final result = events.whereType<AgentToolResultEvent>().single;
        expect(result.output, 'contents');
        expect(result.isError, isFalse);
        expect(events.whereType<AgentRetryEvent>().single.attempt, 2);
        expect(
          events.whereType<AgentRetryEvent>().single.message,
          contains('Service overloaded'),
        );
        expect(
          events.whereType<AgentUnknownEvent>().single.originalType,
          'malformed',
        );
        expect(
          events.whereType<AgentRequestFailedEvent>().last.message,
          'request failed',
        );
        expect(events.whereType<AgentRequestFailedEvent>(), hasLength(2));
      },
    );

    test('fails the request on a permission mode it cannot name', () {
      final decoder = ClaudeStreamEventDecoder()..beginRequest('request-1');
      final events = decoder.decodeLine(
        '{"type":"system","subtype":"init","session_id":"s",'
        '"model":"claude-sonnet-5","permissionMode":"bypassPermissions",'
        '"uuid":"init-1"}',
      );

      expect(events.map((event) => event.runtimeType), [
        AgentUnknownEvent,
        AgentRequestFailedEvent,
      ]);
      expect(
        (events.first as AgentUnknownEvent).diagnostic,
        contains('permissionMode bypassPermissions'),
      );
    });

    test('maps official-shaped error and abort result records', () {
      final decoder = ClaudeStreamEventDecoder()..beginRequest('request-3');

      final failed = decoder.decodeLine(
        jsonEncode({
          'type': 'result',
          'subtype': 'error_during_execution',
          'uuid': 'failed-official',
          'is_error': true,
          'errors': ['tool failed', 'request could not continue'],
          'terminal_reason': 'api_error',
        }),
      );
      final cancelled = decoder.decodeLine(
        jsonEncode({
          'type': 'result',
          'subtype': 'error_during_execution',
          'uuid': 'cancelled-official',
          'is_error': true,
          'errors': ['Interrupted by user'],
          'terminal_reason': 'aborted_streaming',
        }),
      );

      expect(
        failed.whereType<AgentRequestFailedEvent>().single.message,
        'tool failed\nrequest could not continue',
      );
      expect(
        cancelled.whereType<AgentRequestCancelledEvent>().single.reason,
        'Interrupted by user',
      );
    });
  });

  group('ClaudeCliBackend', () {
    test(
      'launches with isolated bounded arguments and streams one request',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          executable: '/opt/claude',
          workingDirectory: '/fixture',
          maxBudgetUsd: 0.02,
          launcher: launcher,
        );
        addTearDown(backend.close);
        final events = <AgentEvent>[];
        final subscription = backend.events.listen(events.add);
        addTearDown(subscription.cancel);

        await backend.start();

        expect(launcher.executable, '/opt/claude');
        expect(launcher.workingDirectory, '/fixture');
        expect(launcher.arguments, [
          '--safe-mode',
          '-p',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--verbose',
          '--include-partial-messages',
          '--disable-slash-commands',
          '--strict-mcp-config',
          '--mcp-config',
          '{"mcpServers":{}}',
          '--tools',
          '',
          '--permission-mode',
          'dontAsk',
          '--no-session-persistence',
          '--max-budget-usd',
          '0.02',
          '--model',
          'sonnet',
        ]);

        await backend.send(
          const AgentRequest(id: 'request-live', prompt: 'hello'),
        );
        final sent = jsonDecode(launcher.process.writes.single);
        expect(sent, {
          'type': 'user',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'hello'},
            ],
          },
          'parent_tool_use_id': null,
        });

        final bytes = utf8.encode(
          '{"type":"stream_event","uuid":"d1","event":{"type":'
          '"message_start","message":{"id":"m1"}}}\n'
          '{"type":"stream_event","uuid":"d2","event":{"type":'
          '"content_block_delta","index":0,"delta":{"type":"text_delta",'
          '"text":"hi"}}}\n'
          '{"type":"assistant","uuid":"f1","message":{"id":"m1",'
          '"content":[{"type":"text","text":"hi"}]}}\n'
          '{"type":"result","uuid":"r1","subtype":"success",'
          '"is_error":false,"total_cost_usd":0.001,"usage":'
          '{"input_tokens":1,"output_tokens":1}}\n',
        );
        launcher.process.stdout.add(bytes.sublist(0, 37));
        launcher.process.stdout.add(bytes.sublist(37));
        await _flushAsync();

        expect(events.whereType<AgentTextDeltaEvent>().single.delta, 'hi');
        expect(events.whereType<AgentTextFinalEvent>().single.text, 'hi');
        expect(events.whereType<AgentRequestCompletedEvent>(), hasLength(1));

        launcher.process.stdout.add(
          utf8.encode(
            '{"type":"result","uuid":"r2","subtype":"success",'
            '"is_error":false,"total_cost_usd":0.001,"usage":'
            '{"input_tokens":1,"output_tokens":1}}\n',
          ),
        );
        await _flushAsync();
        expect(events.whereType<AgentRequestCompletedEvent>(), hasLength(1));
      },
    );

    test(
      'serializes a send behind interruption and can restart after exit',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        addTearDown(backend.close);
        await backend.start();
        await backend.send(const AgentRequest(id: 'first', prompt: 'one'));

        final interrupt = backend.interrupt('first');
        final second = backend.send(
          const AgentRequest(id: 'second', prompt: 'two'),
        );
        await _flushAsync();
        expect(launcher.process.interruptCount, 1);
        expect(launcher.process.writes, hasLength(1));

        launcher.process.stdout.add(
          utf8.encode(
            '{"type":"result","uuid":"cancelled","subtype":'
            '"error_during_execution","is_error":true,'
            '"errors":["Interrupted by user"], '
            '"terminal_reason":"aborted_streaming"}\n',
          ),
        );
        await interrupt;
        await second;
        expect(launcher.processes, hasLength(2));
        expect(launcher.processes.first.writes, hasLength(1));
        expect(launcher.processes.last.writes, hasLength(1));

        launcher.process.completeExit(9);
        await _flushAsync();
        await backend.send(const AgentRequest(id: 'third', prompt: 'three'));
        expect(launcher.processes, hasLength(3));
        expect(launcher.processes.last.writes, hasLength(1));
      },
    );

    test('interrupt cancels a request that is still respawning', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      addTearDown(backend.close);
      await backend.start();
      launcher.process.completeExit(9);
      await _flushAsync();

      final spawnGate = Completer<void>();
      launcher.startGate = spawnGate;
      final interruptedSend = backend.send(
        const AgentRequest(id: 'interrupted', prompt: 'do not send'),
      );
      await _flushAsync();

      await backend.interrupt('interrupted');
      final replacementSend = backend.send(
        const AgentRequest(id: 'replacement', prompt: 'send this'),
      );
      spawnGate.complete();
      await interruptedSend;
      await replacementSend;

      expect(launcher.processes, hasLength(2));
      expect(launcher.processes.last.writes, hasLength(1));
      expect(
        jsonDecode(launcher.processes.last.writes.single),
        containsPair(
          'message',
          containsPair('content', contains(containsPair('text', 'send this'))),
        ),
      );
    });

    test(
      'an interrupt-triggered exit cannot fail a replacement request',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        expect(controller.submit('first'), isTrue);
        await _flushAsync();

        final oldProcess = launcher.process;
        final closeGate = Completer<void>();
        oldProcess.closeGate = closeGate;
        final interrupt = controller.interrupt();
        await _flushAsync();
        oldProcess.completeExit(130);
        await interrupt;

        expect(controller.phase, AgentRunPhase.cancelled);
        expect(controller.submit('replacement'), isTrue);
        await _flushAsync();
        expect(launcher.processes, hasLength(2));

        closeGate.complete();
        await _flushAsync();
        expect(controller.phase, AgentRunPhase.running);
        expect(controller.lastError, isNull);
      },
    );

    test('rejects concurrent sends before either write can complete', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      addTearDown(backend.close);
      await backend.start();
      final writeGate = Completer<void>();
      launcher.process.writeGate = writeGate;

      final first = backend.send(
        const AgentRequest(id: 'first', prompt: 'one'),
      );
      final secondExpectation = expectLater(
        backend.send(const AgentRequest(id: 'second', prompt: 'two')),
        throwsStateError,
      );
      await _flushAsync();

      expect(launcher.process.writes, hasLength(1));
      writeGate.complete();
      await first;
      await secondExpectation;
    });

    test('interrupt failure retires the turn before a retry', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      addTearDown(backend.close);
      await backend.start();
      await backend.send(const AgentRequest(id: 'first', prompt: 'one'));
      launcher.process.interruptError = StateError('signal failed');

      await expectLater(backend.interrupt('first'), throwsStateError);
      final retry = backend.send(
        const AgentRequest(id: 'second', prompt: 'two'),
      );
      await _flushAsync();

      expect(launcher.processes, hasLength(2));
      await retry;
    });

    test(
      'surfaces stderr/exit, rejects unsupported calls, and closes once',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final events = <AgentEvent>[];
        backend.events.listen(events.add);
        await backend.start();

        launcher.process.stderr.add(utf8.encode('warning\n'));
        launcher.process.completeExit(17);
        await _flushAsync();
        expect(events.whereType<AgentStderrEvent>().single.text, 'warning');
        expect(events.whereType<AgentProcessExitEvent>().single.exitCode, 17);
        expect(
          () => backend.respondToPermission(
            requestId: 'r',
            permissionId: 'p',
            allow: true,
          ),
          throwsUnsupportedError,
        );
        expect(
          () => backend.answerQuestion(
            requestId: 'r',
            questionId: 'q',
            answer: 'a',
          ),
          throwsUnsupportedError,
        );
        expect(() => backend.loadSession('session'), throwsUnsupportedError);
        expect(await backend.listSessions(), isEmpty);

        await backend.close();
        await backend.close();
        expect(launcher.process.closeCount, 1);
        expect(backend.start, throwsStateError);
      },
    );

    test(
      'close waits for an in-flight stdin flush before closing the child',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        await backend.start();
        final writeGate = Completer<void>();
        launcher.process.writeGate = writeGate;

        final send = backend.send(
          const AgentRequest(id: 'request-write', prompt: 'pending'),
        );
        await _flushAsync();
        final close = backend.close();
        await _flushAsync();

        expect(launcher.process.closeCount, 0);
        writeGate.complete();
        await send;
        await close;
        expect(launcher.process.closeCount, 1);
      },
    );

    test('startup and write failures do not strand the reducer', () async {
      final failedLauncher = _FakeClaudeProcessLauncher()
        ..startError = StateError('spawn failed');
      final failedBackend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: failedLauncher,
      );
      final failedController = AgentSessionController(backend: failedBackend);
      addTearDown(failedController.close);

      await failedController.start();
      expect(failedController.phase, AgentRunPhase.failed);
      expect(failedController.isBusy, isFalse);

      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      launcher.process.writeError = StateError('write failed');

      expect(controller.submit('first'), isTrue);
      await _flushAsync();
      expect(controller.phase, AgentRunPhase.failed);
      expect(controller.isBusy, isFalse);

      launcher.process.writeError = null;
      expect(controller.submit('retry'), isTrue);
      launcher.process.stdout.add(
        utf8.encode(
          '{"type":"result","uuid":"retry-ok","subtype":"success",'
          '"is_error":false,"usage":{}}\n',
        ),
      );
      await _flushAsync();
      expect(controller.phase, AgentRunPhase.idle);
    });

    test(
      'stdout failure retires the unusable process and permits retry',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        expect(controller.submit('first'), isTrue);

        launcher.process.stdout.addError(StateError('decoder stream failed'));
        await _flushAsync();

        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.isBusy, isFalse);
        expect(controller.submit('retry'), isTrue);
        await _flushAsync();
        expect(launcher.processes, hasLength(2));
      },
    );

    test('close waits for a previously retired child cleanup', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      await backend.start();
      await backend.send(const AgentRequest(id: 'first', prompt: 'one'));
      final process = launcher.process;
      final closeGate = Completer<void>();
      process.closeGate = closeGate;
      process.stdout.addError(StateError('stdout failed'));
      await _flushAsync();

      var closeCompleted = false;
      final close = backend.close().then((_) => closeCompleted = true);
      await _flushAsync();
      expect(closeCompleted, isFalse);

      closeGate.complete();
      await close;
      expect(process.closeCount, 1);
    });

    test(
      'clean stdout closure fails the active request and permits retry',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        expect(controller.submit('first'), isTrue);

        await launcher.process.stdout.close();
        await _flushAsync();

        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.isBusy, isFalse);
        expect(controller.submit('retry'), isTrue);
        await _flushAsync();
        expect(launcher.processes, hasLength(2));
      },
    );

    test('malformed result fails rather than stranding the request', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      expect(controller.submit('first'), isTrue);

      launcher.process.stdout.add(
        utf8.encode('{"type":"result","uuid":"bad-result","subtype":7}\n'),
      );
      await _flushAsync();

      expect(controller.phase, AgentRunPhase.failed);
      expect(controller.isBusy, isFalse);
      expect(
        controller.entries.where(
          (entry) => entry.kind == AgentEntryKind.unknown,
        ),
        hasLength(1),
      );
    });

    test('invalid JSON fails, retires, and preserves its diagnostic', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      expect(controller.submit('first'), isTrue);

      launcher.process.stdout.add(utf8.encode('{not json\n'));
      await _flushAsync();

      expect(controller.phase, AgentRunPhase.failed);
      expect(controller.isBusy, isFalse);
      expect(
        controller.entries.where(
          (entry) => entry.kind == AgentEntryKind.unknown,
        ),
        hasLength(1),
      );
      expect(controller.submit('retry'), isTrue);
      await _flushAsync();
      expect(launcher.processes, hasLength(2));
    });

    test(
      'well-formed future events remain diagnostic and nonterminal',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        expect(controller.submit('first'), isTrue);

        launcher.process.stdout.add(
          utf8.encode('{"type":"future_event","uuid":"future"}\n'),
        );
        await _flushAsync();
        expect(controller.phase, AgentRunPhase.running);
        expect(controller.isBusy, isTrue);
        expect(launcher.processes, hasLength(1));
        expect(
          controller.entries.where(
            (entry) => entry.kind == AgentEntryKind.unknown,
          ),
          hasLength(1),
        );

        launcher.process.stdout.add(
          utf8.encode(
            '{"type":"result","uuid":"complete","subtype":"success",'
            '"is_error":false,"usage":{}}\n',
          ),
        );
        await _flushAsync();
        expect(controller.phase, AgentRunPhase.idle);
      },
    );

    test('terminal publication permits synchronous resubmission', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      var resubmitted = false;
      controller.addListener(() {
        if (!resubmitted && controller.phase == AgentRunPhase.idle) {
          resubmitted = true;
          expect(controller.submit('second'), isTrue);
        }
      });
      expect(controller.submit('first'), isTrue);

      launcher.process.stdout.add(
        utf8.encode(
          '{"type":"result","uuid":"first-complete","subtype":"success",'
          '"is_error":false,"usage":{}}\n',
        ),
      );
      await _flushAsync();

      expect(resubmitted, isTrue);
      expect(controller.phase, AgentRunPhase.running);
      expect(controller.lastError, isNull);
      expect(launcher.process.writes, hasLength(2));
    });

    test(
      'a current exit-future error fails and releases the request',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        final controller = AgentSessionController(backend: backend);
        addTearDown(controller.close);
        await controller.start();
        expect(controller.submit('first'), isTrue);

        launcher.process.completeExitError(StateError('exit status failed'));
        await _flushAsync();

        expect(controller.phase, AgentRunPhase.failed);
        expect(controller.isBusy, isFalse);
        expect(controller.lastError, contains('exit status failed'));
        expect(controller.submit('retry'), isTrue);
        await _flushAsync();
        expect(launcher.processes, hasLength(2));
      },
    );

    test('an old exit error cannot finish a newer process turn', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      addTearDown(backend.close);
      await backend.start();
      final oldProcess = launcher.process..completeExitOnClose = false;
      await backend.send(const AgentRequest(id: 'first', prompt: 'one'));
      oldProcess.stdout.addError(StateError('stdout failed'));
      await _flushAsync();

      await backend.send(const AgentRequest(id: 'second', prompt: 'two'));
      oldProcess.completeExitError(StateError('late exit failure'));
      await _flushAsync();

      await expectLater(
        backend.send(const AgentRequest(id: 'third', prompt: 'three')),
        throwsStateError,
      );
    });

    test(
      'retired child output and cleanup cannot contaminate a newer turn',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        addTearDown(backend.close);
        final events = <AgentEvent>[];
        backend.events.listen(events.add);
        await backend.start();
        final oldProcess = launcher.process;
        final closeGate = Completer<void>();
        oldProcess.closeGate = closeGate;
        oldProcess.closeError = StateError('old cleanup failed');
        await backend.send(const AgentRequest(id: 'first', prompt: 'one'));
        oldProcess.completeExit(9);
        await _flushAsync();

        await backend.send(const AgentRequest(id: 'second', prompt: 'two'));
        oldProcess.stdout.add(
          utf8.encode(
            '{"type":"stream_event","uuid":"stale-start","event":{"type":'
            '"message_start","message":{"id":"stale-message"}}}\n'
            '{"type":"stream_event","uuid":"stale","event":{"type":'
            '"content_block_delta","index":0,"delta":{"type":'
            '"text_delta","text":"stale"}}}\n',
          ),
        );
        await _flushAsync();

        expect(events.whereType<AgentTextDeltaEvent>(), isEmpty);
        closeGate.complete();
        await _flushAsync();
        final cleanup = events
            .whereType<AgentStderrEvent>()
            .where((event) => event.text.contains('old cleanup failed'))
            .single;
        expect(cleanup.requestId, isNot('second'));
      },
    );

    test(
      'close during startup owns the late child and closes events once',
      () async {
        final launcher = _FakeClaudeProcessLauncher();
        final startGate = Completer<void>();
        launcher.startGate = startGate;
        final backend = ClaudeCliBackend(
          workingDirectory: '/fixture',
          launcher: launcher,
        );
        var doneCount = 0;
        backend.events.listen(null, onDone: () => doneCount++);

        final start = backend.start();
        final startExpectation = expectLater(start, throwsStateError);
        await _flushAsync();
        final close = backend.close();
        await _flushAsync();
        expect(launcher.processes, isEmpty);

        startGate.complete();
        await startExpectation;
        await close;
        await backend.close();
        expect(launcher.process.closeCount, 1);
        expect(doneCount, 1);
      },
    );

    test('close reports a late-started child cleanup failure', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final startGate = Completer<void>();
      launcher
        ..startGate = startGate
        ..nextProcessCloseError = StateError('late child close failed');
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );

      final startExpectation = expectLater(backend.start(), throwsStateError);
      await _flushAsync();
      final closeExpectation = expectLater(backend.close(), throwsStateError);
      startGate.complete();

      await startExpectation;
      await closeExpectation;
      expect(launcher.process.closeCount, 1);
    });

    test('keeps tools off, because there is no permission channel', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      addTearDown(backend.close);
      await backend.start();

      final arguments = launcher.arguments!;
      final tools = arguments.indexOf('--tools');
      expect(tools, greaterThanOrEqualTo(0));
      expect(arguments[tools + 1], isEmpty);

      // Nothing may approve a tool call, so nothing may request one.
      await expectLater(
        backend.respondToPermission(
          requestId: 'r',
          permissionId: 'p',
          allow: true,
        ),
        throwsUnsupportedError,
      );
    });

    test('validates executable, directory, budget, and timeouts', () {
      expect(() => ClaudeCliBackend(workingDirectory: ''), throwsArgumentError);
      expect(
        () => ClaudeCliBackend(workingDirectory: 'relative/project'),
        throwsArgumentError,
      );
      expect(
        () => ClaudeCliBackend(workingDirectory: '.'),
        throwsArgumentError,
      );
      expect(
        () => ClaudeCliBackend(workingDirectory: '/fixture', executable: ' '),
        throwsArgumentError,
      );
      expect(
        () => ClaudeCliBackend(
          workingDirectory: '/fixture',
          maxBudgetUsd: double.nan,
        ),
        throwsArgumentError,
      );
      expect(
        () => ClaudeCliBackend(
          workingDirectory: '/fixture',
          shutdownGracePeriod: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => ClaudeCliBackend(
          workingDirectory: '/fixture',
          interruptTimeout: Duration.zero,
        ),
        throwsArgumentError,
      );
    });

    test('live normalized events drive the existing reducer', () async {
      final launcher = _FakeClaudeProcessLauncher();
      final backend = ClaudeCliBackend(
        workingDirectory: '/fixture',
        launcher: launcher,
      );
      final controller = AgentSessionController(backend: backend);
      addTearDown(controller.close);
      await controller.start();
      expect(controller.submit('hello'), isTrue);

      final raw = File(
        'test/fixtures/claude_cli/stream_2_1_246.jsonl',
      ).readAsBytesSync();
      launcher.process.stdout.add(raw);
      await _flushAsync();

      expect(controller.phase, AgentRunPhase.idle);
      expect(controller.sessionId, 'fixture-session');
      expect(controller.model, 'claude-sonnet-5');
      expect(
        controller.entries
            .where((entry) => entry.kind == AgentEntryKind.assistant)
            .single
            .text,
        'NOIR_SPIKE_OK',
      );
      expect(controller.inputTokens, 5375);
      expect(controller.outputTokens, 15);
    });
  });
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

final class _FakeClaudeProcessLauncher implements ClaudeProcessLauncher {
  String? executable;
  String? workingDirectory;
  List<String>? arguments;
  final List<_FakeClaudeProcess> processes = [];
  Completer<void>? startGate;
  Error? startError;
  Error? nextProcessCloseError;

  _FakeClaudeProcess get process => processes.last;

  @override
  Future<ClaudeProcessHandle> start(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    await startGate?.future;
    if (startError case final error?) throw error;
    this.executable = executable;
    this.arguments = List<String>.of(arguments);
    this.workingDirectory = workingDirectory;
    final process = _FakeClaudeProcess()..closeError = nextProcessCloseError;
    nextProcessCloseError = null;
    processes.add(process);
    return process;
  }
}

final class _FakeClaudeProcess implements ClaudeProcessHandle {
  final stdout = StreamController<List<int>>.broadcast();
  final stderr = StreamController<List<int>>.broadcast();
  final _exitCode = Completer<int>();
  final List<String> writes = [];
  int interruptCount = 0;
  int closeCount = 0;
  Completer<void>? writeGate;
  Error? writeError;
  Error? interruptError;
  Error? closeError;
  bool completeExitOnClose = true;
  Completer<void>? closeGate;

  @override
  Stream<List<int>> get stdoutBytes => stdout.stream;

  @override
  Stream<List<int>> get stderrBytes => stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  Future<void> writeLine(String line) async {
    writes.add(line);
    await writeGate?.future;
    if (writeError case final error?) throw error;
  }

  @override
  Future<void> interrupt() async {
    interruptCount++;
    if (interruptError case final error?) throw error;
  }

  @override
  Future<void> close({required Duration gracePeriod}) async {
    closeCount++;
    await closeGate?.future;
    if (completeExitOnClose && !_exitCode.isCompleted) _exitCode.complete(0);
    await stdout.close();
    await stderr.close();
    if (closeError case final error?) throw error;
  }

  void completeExit(int code) {
    if (!_exitCode.isCompleted) _exitCode.complete(code);
  }

  void completeExitError(Object error) {
    if (!_exitCode.isCompleted) _exitCode.completeError(error);
  }
}

final class _FakeSystemProcess implements Process {
  _FakeSystemProcess(Completer<void> stdinCloseGate)
    : stdin = IOSink(_GatedInputConsumer(stdinCloseGate));

  @override
  final IOSink stdin;
  @override
  final Stream<List<int>> stdout = const Stream<List<int>>.empty();
  @override
  final Stream<List<int>> stderr = const Stream<List<int>>.empty();
  final Completer<int> _exitCode = Completer<int>();
  final List<ProcessSignal> killSignals = [];

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1234;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (!_exitCode.isCompleted) _exitCode.complete(-signal.signalNumber);
    return true;
  }
}

final class _GatedInputConsumer implements StreamConsumer<List<int>> {
  _GatedInputConsumer(this.closeGate);

  final Completer<void> closeGate;

  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.drain<void>();

  @override
  Future<void> close() => closeGate.future;
}
