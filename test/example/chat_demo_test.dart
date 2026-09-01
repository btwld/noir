import 'dart:async';
import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../../example/chat_demo.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

const _editDiff =
    'diff --git a/sample.dart b/sample.dart\n'
    '--- a/sample.dart\n'
    '+++ b/sample.dart\n'
    '@@ -1,3 +1,4 @@\n'
    ' String status() {\n'
    "-  return 'before';\n"
    '+  // checked by noir_probe\n'
    "+  return 'after';\n"
    ' }';

void main() {
  group('agent chat example', () {
    test(
      'Enter submits while Ctrl+J and paste preserve multiline text',
      () async {
        final harness = await _ChatHarness.create();
        addTearDown(harness.close);

        harness.app.mockInput
          ..typeText('first line')
          ..pressKittyKey(
            LogicalKeyboardKey.keyJ.keyId,
            modifiers: KeyModifiers.ctrl,
          )
          ..typeText('second line')
          ..paste('\nthird line');
        harness.app.pumpFrame();
        expect(harness.app.captureFrame().toText(), contains('third line'));

        harness.app.mockInput.pressEnter();
        await _settle(harness.app);

        expect(harness.controller.entries.single.kind, AgentEntryKind.user);
        expect(
          harness.controller.entries.single.text,
          'first line\nsecond line\nthird line',
        );
        expect(
          harness.backend.commands
              .singleWhere(
                (command) => command.kind == AgentBackendCommandKind.send,
              )
              .value,
          'first line\nsecond line\nthird line',
        );
      },
    );

    test(
      'command and path suggestions accept or dismiss without draft loss',
      () async {
        final harness = await _ChatHarness.create(
          pathSuggestions: const ['lib/noir.dart', 'README.md'],
        );
        addTearDown(harness.close);

        harness.app.mockInput.typeText('/rev');
        harness.app.pumpFrame();
        expect(harness.app.captureFrame().toText(), contains('/review'));

        harness.app.mockInput.pressEnter();
        await _settle(harness.app);
        expect(harness.controller.entries, isEmpty);
        expect(harness.app.captureFrame().toText(), contains('/review'));

        harness.app.mockInput.pressEnter();
        await _settle(harness.app);
        expect(harness.controller.entries.single.text, '/review');

        harness.backend.emit(
          AgentRequestCompletedEvent(
            id: 'done-review',
            requestId: harness.controller.activeRequestId!,
            inputTokens: 1,
            outputTokens: 1,
            costUsd: 0,
          ),
        );
        harness.app.mockInput.typeText('open @noir suffix');
        for (var index = 0; index < ' suffix'.length; index++) {
          harness.app.mockInput.pressArrow(ArrowDirection.left);
        }
        harness.app.pumpFrame();
        expect(harness.app.captureFrame().toText(), contains('@lib/noir.dart'));

        harness.app.mockInput
          ..pressTab()
          ..typeText('!');
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('open @lib/noir.dart! suffix'),
        );

        harness.app.mockInput
          ..typeText(' ')
          ..typeText('@');
        harness.app.pumpFrame();
        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyM.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        await _settle(harness.app);
        expect(harness.app.captureFrame().toText(), contains('Choose model'));

        harness.app.mockInput.pressEscape();
        await _settle(harness.app);
        expect(
          harness.app.captureFrame().toText(),
          isNot(contains('Choose model')),
          reason: 'the open modal must own Escape before hidden suggestions',
        );
        harness.app.mockInput.pressEscape();
        harness.app.pumpFrame();
        expect(harness.app.exitRequests, isEmpty);
        expect(
          harness.app.captureFrame().toText(),
          contains('open @lib/noir.dart! @ suffix'),
        );
      },
    );

    test('live composition hides and disables replay-only controls', () async {
      final harness = await _ChatHarness.create(
        enableReplayControls: false,
        pathSuggestions: const [],
      );
      addTearDown(harness.close);

      harness.app.mockInput.typeText('/');
      harness.app.pumpFrame();

      expect(harness.app.captureFrame().toText(), isNot(contains('/review')));
      harness.app.mockInput
        ..pressShiftTab()
        ..pressKittyKey(
          LogicalKeyboardKey.keyM.keyId,
          modifiers: KeyModifiers.ctrl,
        )
        ..pressKittyKey(
          LogicalKeyboardKey.keyR.keyId,
          modifiers: KeyModifiers.ctrl,
        );
      await _settle(harness.app);
      expect(harness.app.captureFrame().toText(), isNot(contains('Model')));
      expect(
        harness.app.captureFrame().toText(),
        isNot(contains('Shift+Tab mode')),
      );
      expect(
        harness.app.captureFrame().toText(),
        isNot(contains('@ for paths')),
      );
      expect(harness.app.captureFrame().toText(), isNot(contains(' · review')));
      expect(harness.controller.lastError, isNull);
      expect(harness.controller.entries, isEmpty);
    });

    test('Ctrl+C remains an idle exit while suggestions are visible', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);
      harness.app.mockInput.typeText('/');
      harness.app.pumpFrame();
      expect(harness.app.captureFrame().toText(), contains('/review'));

      harness.app.mockInput.pressKittyKey(
        LogicalKeyboardKey.keyC.keyId,
        modifiers: KeyModifiers.ctrl,
      );

      expect(harness.app.exitRequests, [0]);
    });

    test('boundary arrows restore history and its scratch draft', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);
      harness.app.mockInput
        ..typeText('first prompt')
        ..pressEnter();
      await _settle(harness.app);
      final requestId = harness.controller.activeRequestId!;
      harness.backend.emit(
        AgentRequestCompletedEvent(
          id: 'done-first',
          requestId: requestId,
          inputTokens: 0,
          outputTokens: 0,
          costUsd: 0,
        ),
      );
      harness.app.mockInput
        ..typeText('scratch')
        ..pressArrow(ArrowDirection.up);
      harness.app.pumpFrame();
      expect(harness.app.captureFrame().toText(), contains('first prompt'));

      harness.app.mockInput.pressArrow(ArrowDirection.down);
      harness.app.pumpFrame();
      expect(harness.app.captureFrame().toText(), contains('scratch'));
    });

    test(
      'Ctrl+O marks the continuous transcript without panel chrome',
      () async {
        final harness = await _ChatHarness.create();
        addTearDown(harness.close);
        final initial = harness.app.captureFrame().toText();
        expect(initial, isNot(contains('Transcript')));
        expect(initial, isNot(contains('─ Message')));

        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyO.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        harness.app.pumpFrame();

        final frame = harness.app.captureFrame().toText();
        expect(frame, contains('› Agent Chat'));
        expect(frame, isNot(contains('Transcript')));
        expect(frame, isNot(contains('─ Message')));
      },
    );

    test(
      'the continuous transcript scrolls and keeps no left border',
      () async {
        final snapshot = AgentSessionSnapshot(
          sessionId: 'wheel-history',
          model: 'sonnet',
          permissionMode: AgentPermissionMode.review,
          entries: [
            for (var index = 0; index < 32; index++)
              AgentSnapshotEntry(
                id: 'wheel-$index',
                kind: AgentSnapshotEntryKind.notice,
                text: 'Wheel marker ${index.toString().padLeft(2, '0')}',
              ),
          ],
        );
        final backend = ReplayAgentBackend(
          snapshots: {'wheel-history': snapshot},
        );
        final controller = AgentSessionController(backend: backend);
        await controller.start();
        await controller.loadSession('wheel-history');
        final harness = await _ChatHarness.create(
          backend: backend,
          controller: controller,
          width: 80,
          height: 24,
        );
        addTearDown(harness.close);

        final tail = harness.app.captureFrame();
        expect(tail.toText(), isNot(contains('Agent Chat')));
        // The page still has no left border. The marker gutter owns the
        // first inset column, so a notice body starts just after it.
        expect(tail.toText(), isNot(contains('\u2502')));
        expect(tail.findText('Wheel marker 31').single.x, 3);
        expect(tail.cursor.visible, isTrue);

        for (var index = 0; index < 12; index++) {
          harness.app.mockMouse.scroll(1, 5, ScrollDirection.up);
        }
        harness.app.pumpFrame();

        final detached = harness.app.captureFrame();
        expect(detached.toText(), isNot(contains('Wheel marker 31')));
        expect(detached.cursor.visible, isFalse);

        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyO.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        harness.app.pumpFrame();

        expect(harness.app.captureFrame().toText(), contains('› Agent Chat'));
      },
    );

    test('expanded semantic diff tool output uses DiffView colors', () async {
      final harness = await _ChatHarness.create(width: 80, height: 24);
      addTearDown(harness.close);
      harness.controller.submit('edit a file');
      final requestId = harness.controller.activeRequestId!;
      harness.backend
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
            output: _editDiff,
            contentKind: AgentToolContentKind.unifiedDiff,
          ),
        );
      await _settle(harness.app);

      final collapsed = harness.app.captureFrame();
      final details = collapsed.findText('Details').single;
      harness.app.mockMouse.click(details.x + 1, details.y);
      await _settle(harness.app);

      final expanded = harness.app.captureFrame();
      final deletion = expanded.findText("return 'before';").single;
      final addition = expanded.findText("return 'after';").single;
      expect(
        expanded.getBackgroundColor(deletion.x, deletion.y).toHex(),
        '#380f0fff',
      );
      expect(
        expanded.getBackgroundColor(addition.x, addition.y).toHex(),
        '#0d331aff',
      );

      harness.backend
        ..emit(
          AgentToolStartedEvent(
            id: 'broken-start',
            requestId: requestId,
            blockId: 'broken',
            name: 'Edit',
            summary: 'opaque output',
          ),
        )
        ..emit(
          AgentToolResultEvent(
            id: 'broken-result',
            requestId: requestId,
            blockId: 'broken',
            output: 'not a unified diff',
            contentKind: AgentToolContentKind.unifiedDiff,
          ),
        );
      await _settle(harness.app);
      final fallbackDetails = harness.app
          .captureFrame()
          .findText('Details')
          .single;
      harness.app.mockMouse.click(fallbackDetails.x + 1, fallbackDetails.y);
      await _settle(harness.app);
      expect(
        harness.app.captureFrame().toText(),
        contains('not a unified diff'),
      );
    });

    test(
      'permission modal traps focus, responds, and restores the composer',
      () async {
        final harness = await _ChatHarness.create();
        addTearDown(harness.close);
        harness.app.mockInput.typeText('preserved draft');
        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyO.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        harness.app.pumpFrame();
        expect(harness.app.captureFrame().toText(), contains('› Agent Chat'));
        harness.controller.submit('edit a file');
        final requestId = harness.controller.activeRequestId!;
        harness.backend.emit(
          AgentPermissionRequestEvent(
            id: 'permission',
            requestId: requestId,
            permissionId: 'permit-1',
            toolName: 'Edit',
            reason: 'Update example/chat_demo.dart',
            preview: _editDiff,
            previewContentKind: AgentToolContentKind.unifiedDiff,
          ),
        );
        await _settle(harness.app);
        final permissionFrame = harness.app.captureFrame();
        expect(
          permissionFrame.toText(),
          allOf(
            contains('Permission required'),
            contains('Deny'),
            contains('Allow'),
          ),
        );
        final deletion = permissionFrame.findText("return 'before';").single;
        final addition = permissionFrame.findText("return 'after';").single;
        expect(
          permissionFrame.getBackgroundColor(deletion.x, deletion.y).toHex(),
          '#380f0fff',
        );
        expect(
          permissionFrame.getBackgroundColor(addition.x, addition.y).toHex(),
          '#0d331aff',
        );

        harness.app.mockInput
          ..pressKittyKey(
            LogicalKeyboardKey.keyO.keyId,
            modifiers: KeyModifiers.ctrl,
          )
          ..typeText('must-not-reach-composer');
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          isNot(contains('must-not-reach-composer')),
        );

        harness.app.mockInput
          ..pressShiftTab()
          ..pressEnter();
        await _settle(harness.app);

        expect(harness.controller.permissionRequest, isNull);
        expect(
          harness.backend.commands.last,
          isA<AgentBackendCommand>()
              .having(
                (command) => command.kind,
                'kind',
                AgentBackendCommandKind.permission,
              )
              .having((command) => command.allowed, 'allowed', isTrue),
        );
        harness.app.mockInput.typeText(' restored');
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('preserved draft restored'),
        );
      },
    );

    test(
      'question choice is returned through the same decision surface',
      () async {
        final harness = await _ChatHarness.create();
        addTearDown(harness.close);
        harness.controller.submit('ask me');
        final requestId = harness.controller.activeRequestId!;
        harness.backend.emit(
          AgentQuestionRequestEvent(
            id: 'question',
            requestId: requestId,
            questionId: 'scope',
            prompt: 'Which scope?',
            choices: const ['Focused files', 'Whole package'],
            allowFreeText: true,
          ),
        );
        await _settle(harness.app);
        expect(harness.app.captureFrame().toText(), contains('Agent question'));

        harness.app.mockInput
          ..pressArrow(ArrowDirection.down)
          ..pressEnter();
        await _settle(harness.app);

        expect(harness.controller.questionRequest, isNull);
        expect(harness.backend.commands.last.targetId, 'scope');
        expect(harness.backend.commands.last.value, 'Whole package');
        harness.app.mockInput.typeText('after answer');
        harness.app.pumpFrame();
        expect(harness.app.captureFrame().toText(), contains('after answer'));
      },
    );

    test('a decision safely preempts an open picker', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);
      harness.controller.submit('request that needs a decision');
      final requestId = harness.controller.activeRequestId!;
      harness.app.mockInput.pressKittyKey(
        LogicalKeyboardKey.keyM.keyId,
        modifiers: KeyModifiers.ctrl,
      );
      await _settle(harness.app);
      expect(harness.app.captureFrame().toText(), contains('Choose model'));

      harness.backend.emit(
        AgentPermissionRequestEvent(
          id: 'preempting-permission',
          requestId: requestId,
          permissionId: 'preempt-picker',
          toolName: 'Edit',
          reason: 'A backend decision owns the active request',
        ),
      );
      await _settle(harness.app);

      expect(
        harness.app.captureFrame().toText(),
        allOf(contains('Permission required'), isNot(contains('Choose model'))),
      );
    });

    test('question modal submits free text and restores focus', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);
      harness.controller.submit('ask for detail');
      final requestId = harness.controller.activeRequestId!;
      harness.backend.emit(
        AgentQuestionRequestEvent(
          id: 'free-question',
          requestId: requestId,
          questionId: 'detail',
          prompt: 'What detail should be preserved?',
          choices: const [],
          allowFreeText: true,
        ),
      );
      await _settle(harness.app);

      harness.app.mockInput
        ..typeText('the causal guard')
        ..pressEnter();
      await _settle(harness.app);

      expect(harness.controller.questionRequest, isNull);
      expect(harness.backend.commands.last.targetId, 'detail');
      expect(harness.backend.commands.last.value, 'the causal guard');
      harness.app.mockInput.typeText('composer focus');
      harness.app.pumpFrame();
      expect(harness.app.captureFrame().toText(), contains('composer focus'));
    });

    test(
      'mode, model, and session changes preserve the current draft',
      () async {
        final backend = ReplayAgentBackend(
          sessions: const [
            AgentSessionSummary(
              id: 'saved',
              title: 'Saved review',
              updatedLabel: '2m ago',
            ),
          ],
          snapshots: {
            'saved': AgentSessionSnapshot(
              sessionId: 'saved',
              model: 'opus',
              permissionMode: AgentPermissionMode.plan,
              entries: const [
                AgentSnapshotEntry(
                  id: 'saved-entry',
                  kind: AgentSnapshotEntryKind.assistant,
                  text: 'Restored transcript marker',
                ),
              ],
            ),
          },
        );
        final harness = await _ChatHarness.create(backend: backend);
        addTearDown(harness.close);
        harness.app.mockInput
          ..typeText('keep this draft')
          ..pressShiftTab();
        await _settle(harness.app);
        expect(harness.controller.permissionMode, AgentPermissionMode.autoEdit);

        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyO.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        harness.app.pumpFrame();
        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyM.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        await _settle(harness.app);
        expect(harness.app.captureFrame().toText(), contains('Choose model'));
        harness.app.mockInput
          ..pressArrow(ArrowDirection.down)
          ..pressEnter();
        await _settle(harness.app);
        expect(harness.controller.model, 'opus');
        harness.app.mockInput.typeText(' after model');
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('keep this draft after model'),
        );

        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyO.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        harness.app.pumpFrame();
        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyR.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        await _settle(harness.app);
        expect(harness.app.captureFrame().toText(), contains('Saved review'));
        harness.app.mockInput.pressKittyKey(
          LogicalKeyboardKey.keyM.keyId,
          modifiers: KeyModifiers.ctrl,
        );
        await _settle(harness.app);
        expect(harness.app.captureFrame().toText(), contains('Saved review'));
        expect(
          harness.app.captureFrame().toText(),
          isNot(contains('Choose model')),
        );
        harness.app.mockInput.pressEnter();
        await _settle(harness.app);
        expect(harness.controller.sessionId, 'saved');
        harness.app.mockInput.typeText(' after session');
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('Restored transcript marker'),
        );
        expect(
          harness.app.captureFrame().toText(),
          contains('keep this draft after model after session'),
        );
      },
    );

    test(
      'detached transcript keeps its anchor until PageDown returns to tail',
      () async {
        final snapshot = AgentSessionSnapshot(
          sessionId: 'long',
          model: 'sonnet',
          permissionMode: AgentPermissionMode.review,
          entries: [
            for (var index = 0; index < 32; index++)
              AgentSnapshotEntry(
                id: 'history-$index',
                kind: AgentSnapshotEntryKind.notice,
                text: 'History marker ${index.toString().padLeft(2, '0')}',
              ),
          ],
        );
        final backend = ReplayAgentBackend(snapshots: {'long': snapshot});
        final controller = AgentSessionController(backend: backend);
        await controller.start();
        await controller.loadSession('long');
        final harness = await _ChatHarness.create(
          backend: backend,
          controller: controller,
        );
        addTearDown(harness.close);
        expect(
          harness.app.captureFrame().toText(),
          contains('History marker 31'),
        );

        harness.app.mockInput.pressPageUp();
        harness.app.pumpFrame();
        final detached = harness.app.captureFrame().toText();
        expect(detached, isNot(contains('History marker 31')));
        harness.app
          ..resize(80, 18)
          ..pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          isNot(contains('History marker 31')),
        );

        controller.submit('new request');
        final requestId = controller.activeRequestId!;
        backend
          ..emit(
            AgentTextFinalEvent(
              id: 'new-final',
              requestId: requestId,
              blockId: 'answer',
              text: 'new-tail-marker',
            ),
          )
          ..emit(
            AgentRequestCompletedEvent(
              id: 'new-done',
              requestId: requestId,
              inputTokens: 1,
              outputTokens: 1,
              costUsd: 0,
            ),
          );
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          isNot(contains('new-tail-marker')),
        );

        harness.app.mockInput
          ..pressPageDown()
          ..pressPageDown()
          ..pressPageDown();
        harness.app.pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('new-tail-marker'),
        );
      },
    );

    test(
      '64x18 and 120x30 keep decisions, composer, and cursor usable',
      () async {
        final harness = await _ChatHarness.create(width: 80, height: 24);
        addTearDown(harness.close);
        harness.app.mockInput.typeText('draft survives resize');
        harness.app
          ..resize(64, 18)
          ..pumpFrame();
        var capture = harness.app.captureFrame();
        expect(capture.toText(), contains('draft survives resize'));
        expect(capture.cursor.visible, isTrue);

        harness.controller.submit('permission flow');
        harness.backend.emit(
          AgentPermissionRequestEvent(
            id: 'resize-permission',
            requestId: harness.controller.activeRequestId!,
            permissionId: 'resize',
            toolName: 'Write',
            reason: 'Keep the active controls visible',
          ),
        );
        await _settle(harness.app);
        capture = harness.app.captureFrame();
        expect(capture.toText(), contains('Permission required'));
        expect(capture.toText(), contains('Allow'));

        harness.app
          ..resize(120, 30)
          ..pumpFrame();
        expect(
          harness.app.captureFrame().toText(),
          contains('Permission required'),
        );
      },
    );

    test('Escape interrupts busy work and exits only once idle', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);
      harness.controller.submit('keep working');

      harness.app.mockInput.pressEscape();
      await _settle(harness.app);
      expect(harness.controller.phase, AgentRunPhase.cancelled);
      expect(harness.app.exitRequests, isEmpty);
      expect(
        harness.backend.commands.last.kind,
        AgentBackendCommandKind.interrupt,
      );

      harness.app.mockInput.pressEscape();
      expect(harness.app.exitRequests, [0]);
    });

    test(
      'the owned replay handles a decision without network or installation',
      () async {
        final app = createTuiTestApp(
          const ChatDemoApp(enableAnimation: false),
          width: 64,
          height: 18,
          kittyKeyboard: true,
        );
        addTearDown(app.dispose);
        await _settle(app);
        app.mockInput
          ..typeText('/permission')
          ..pressEnter()
          ..pressEnter();
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await _settle(app);
        expect(app.captureFrame().toText(), contains('Permission required'));

        app.mockInput.pressEnter();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await _settle(app);
        final frame = app.captureFrame().toText();
        expect(frame, contains('Permission denied. No change was made.'));
        expect(frame, contains('READY'));
      },
    );

    test('the owned replay preserves colons in free-text answers', () async {
      final app = createTuiTestApp(
        const ChatDemoApp(enableAnimation: false),
        width: 64,
        height: 18,
        kittyKeyboard: true,
      );
      addTearDown(app.dispose);
      await _settle(app);
      app.mockInput
        ..typeText('/question')
        ..pressEnter()
        ..pressEnter();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Agent question'));

      app.mockInput
        ..pressTab()
        ..typeText('file:line')
        ..pressEnter();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await _settle(app);

      expect(
        app.captureFrame().toText(),
        contains('Answer recorded: file:line'),
      );
    });

    test(
      'controller replacement closes stale UI but borrows both owners',
      () async {
        final firstBackend = ReplayAgentBackend();
        final secondBackend = ReplayAgentBackend();
        final first = AgentSessionController(backend: firstBackend);
        final second = AgentSessionController(backend: secondBackend);
        await first.start();
        await second.start();
        final key = GlobalKey<_ControllerSwapHostState>();
        final app = createTuiTestApp(
          _ControllerSwapHost(key: key, controller: first),
          width: 64,
          height: 18,
        );
        try {
          await _settle(app);
          first.submit('first request');
          firstBackend.emit(
            AgentPermissionRequestEvent(
              id: 'stale-permission',
              requestId: first.activeRequestId!,
              permissionId: 'stale',
              toolName: 'Edit',
              reason: 'Belongs to the old controller',
            ),
          );
          await _settle(app);
          expect(app.captureFrame().toText(), contains('Permission required'));

          key.currentState!.replace(second);
          await _settle(app);
          expect(
            app.captureFrame().toText(),
            isNot(contains('Permission required')),
          );
          app.mockInput.typeText('new controller draft');
          app.pumpFrame();
          expect(app.captureFrame().toText(), contains('new controller draft'));
          expect(first.isClosed, isFalse);
          expect(second.isClosed, isFalse);
        } finally {
          app.dispose();
          await first.close();
          await second.close();
        }
      },
    );

    test(
      'stale picker completion cannot close a replacement decision modal',
      () async {
        final modelGate = Completer<void>();
        final firstBackend = ReplayAgentBackend(
          onCommand: (command) {
            if (command.kind == AgentBackendCommandKind.setModel) {
              return modelGate.future;
            }
          },
        );
        final secondBackend = ReplayAgentBackend();
        final first = AgentSessionController(backend: firstBackend);
        final second = AgentSessionController(backend: secondBackend);
        await first.start();
        await second.start();
        final key = GlobalKey<_ControllerSwapHostState>();
        final app = createTuiTestApp(
          _ControllerSwapHost(key: key, controller: first),
          width: 64,
          height: 18,
        );
        try {
          await _settle(app);
          app.mockInput.pressKittyKey(
            LogicalKeyboardKey.keyM.keyId,
            modifiers: KeyModifiers.ctrl,
          );
          await _settle(app);
          app.mockInput
            ..pressArrow(ArrowDirection.down)
            ..pressEnter();
          await Future<void>.delayed(Duration.zero);

          key.currentState!.replace(second);
          await _settle(app);
          second.submit('replacement request');
          secondBackend.emit(
            AgentPermissionRequestEvent(
              id: 'replacement-permission',
              requestId: second.activeRequestId!,
              permissionId: 'replacement',
              toolName: 'Edit',
              reason: 'Belongs to the replacement controller',
            ),
          );
          await _settle(app);
          expect(app.captureFrame().toText(), contains('Permission required'));

          modelGate.complete();
          await _settle(app);
          expect(
            app.captureFrame().toText(),
            contains('Permission required'),
            reason: 'completion from the detached controller must be stale',
          );
        } finally {
          if (!modelGate.isCompleted) modelGate.complete();
          app.dispose();
          await first.close();
          await second.close();
        }
      },
    );

    test(
      'a supplied session controller remains caller-owned on teardown',
      () async {
        final backend = ReplayAgentBackend();
        final controller = AgentSessionController(backend: backend);
        final app = createTuiTestApp(
          ChatDemoApp(controller: controller, enableAnimation: false),
        );
        await controller.start();
        await _settle(app);

        app.dispose();

        expect(controller.isClosed, isFalse);
        expect(controller.submit('still owned by caller'), isTrue);
        await controller.close();
      },
    );

    test('assistant and tool turns render a leading marker column', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);

      harness.controller.submit('inspect the change');
      final requestId = harness.controller.activeRequestId!;
      harness.backend
        ..emit(
          AgentToolStartedEvent(
            id: 'marker-tool-start',
            requestId: requestId,
            blockId: 'read',
            name: 'Read',
            summary: 'lib/noir.dart',
          ),
        )
        ..emit(
          AgentToolResultEvent(
            id: 'marker-tool-result',
            requestId: requestId,
            blockId: 'read',
            output: 'ok',
          ),
        )
        ..emit(
          AgentTextFinalEvent(
            id: 'marker-answer',
            requestId: requestId,
            blockId: 'answer',
            text: 'Marker body line.',
          ),
        );
      harness.app.pumpFrame();

      final text = harness.app.captureFrame().toText();
      expect(text, matches(RegExp('${Icons.circle} +DONE +Read')));
      expect(text, matches(RegExp('${Icons.circle} +Marker body line[.]')));
    });

    test('every transcript row shares one marker gutter', () async {
      final harness = await _ChatHarness.create(width: 70, height: 24);
      addTearDown(harness.close);

      harness.controller.submit('do the thing');
      final requestId = harness.controller.activeRequestId!;
      harness.backend
        ..emit(
          AgentTextFinalEvent(
            id: 'gutter-answer',
            requestId: requestId,
            blockId: 'answer',
            text: 'Assistant line.',
          ),
        )
        ..emit(
          AgentToolStartedEvent(
            id: 'gutter-tool',
            requestId: requestId,
            blockId: 'read',
            name: 'Read',
            summary: 'a.dart',
          ),
        )
        ..emit(
          AgentStderrEvent(
            id: 'gutter-notice',
            requestId: requestId,
            text: 'Notice line.',
          ),
        )
        ..emit(
          AgentUnknownEvent(
            id: 'gutter-unknown',
            requestId: requestId,
            originalType: 'mystery',
            payload: const {},
            diagnostic: 'Unknown line.',
          ),
        );
      await _settle(harness.app);

      final lines = harness.app.captureFrame().toText().split('\n');
      int bodyColumn(String needle) {
        final row = lines.indexWhere((line) => line.contains(needle));
        expect(row, greaterThanOrEqualTo(0), reason: 'missing: $needle');
        return lines[row].indexOf(needle);
      }

      // Marked turns, secondary rows, and the activity row share one body
      // column.
      final assistant = bodyColumn('Assistant line.');
      expect(bodyColumn('RUN'), assistant);
      expect(bodyColumn('Backend: Notice line.'), assistant);
      expect(bodyColumn('Unknown event'), assistant);
      final activity = lines.firstWhere(
        (line) => line.contains('WORKING') && !line.contains('Agent Chat'),
      );
      expect(activity.indexOf('WORKING'), assistant);

      // Only the agent turns carry the marker.
      expect(
        lines
            .firstWhere((line) => line.contains('Assistant line.'))
            .indexOf(Icons.circle),
        assistant - 2,
      );
      for (final secondary in const [
        'Backend: Notice line.',
        'Unknown event',
      ]) {
        expect(
          lines.firstWhere((line) => line.contains(secondary)),
          isNot(contains(Icons.circle)),
          reason: '$secondary must not claim to be an agent turn',
        );
      }
    });

    test('a wrapped assistant turn keeps a hanging indent', () async {
      final harness = await _ChatHarness.create(width: 40);
      addTearDown(harness.close);

      harness.controller.submit('inspect the change');
      final requestId = harness.controller.activeRequestId!;
      harness.backend.emit(
        AgentTextFinalEvent(
          id: 'wrap-answer',
          requestId: requestId,
          blockId: 'answer',
          text:
              'alpha bravo charlie delta echo foxtrot golf hotel india '
              'juliett kilo lima mike november',
        ),
      );
      harness.app.pumpFrame();

      final lines = harness.app.captureFrame().toText().split('\n');
      final markerRow = lines.indexWhere((line) => line.contains('alpha'));
      expect(markerRow, greaterThanOrEqualTo(0));
      final markerColumn = lines[markerRow].indexOf(Icons.circle);
      expect(markerColumn, greaterThanOrEqualTo(0));

      final bodyColumn = lines[markerRow].indexOf('alpha');
      expect(bodyColumn, greaterThan(markerColumn));

      final continuation = lines[markerRow + 1];
      expect(continuation.substring(0, bodyColumn).trim(), isEmpty);
      expect(continuation.trim(), isNotEmpty);
    });

    test('inline Markdown code drops the filled background', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);

      harness.controller.submit('inspect the change');
      final requestId = harness.controller.activeRequestId!;
      harness.backend.emit(
        AgentTextFinalEvent(
          id: 'inline-code-answer',
          requestId: requestId,
          blockId: 'answer',
          text: 'Returns `sentinel` now.',
        ),
      );
      harness.app.pumpFrame();

      final frame = harness.app.captureFrame();
      final lines = frame.toText().split('\n');
      final row = lines.indexWhere((line) => line.contains('sentinel'));
      expect(row, greaterThanOrEqualTo(0));
      final column = lines[row].indexOf('sentinel');

      expect(
        frame,
        isNot(
          BufferMatchers.hasBackgroundAt(
            column,
            row,
            ThemeData.dark.surfaceVariant,
          ),
        ),
      );
      expect(
        frame,
        BufferMatchers.hasColorAt(column, row, ThemeData.dark.info),
      );
    });

    test('the idle composer prompt uses the transcript chevron', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);

      harness.app.mockInput.typeText('composer probe');
      harness.app.pumpFrame();

      final lines = harness.app.captureFrame().toText().split('\n');
      final row = lines.indexWhere((line) => line.contains('composer probe'));
      expect(row, greaterThanOrEqualTo(0));
      expect(lines[row].trimLeft(), startsWith(Icons.chevronRight));
    });

    test('a fenced block in the transcript is highlighted', () async {
      final harness = await _ChatHarness.create();
      addTearDown(harness.close);

      harness.controller.submit('inspect the change');
      final requestId = harness.controller.activeRequestId!;
      harness.backend.emit(
        AgentTextFinalEvent(
          id: 'fenced-answer',
          requestId: requestId,
          blockId: 'answer',
          text: "```dart\nconst x = 'tok';\n```",
        ),
      );
      await _settle(harness.app);

      final frame = harness.app.captureFrame();
      final lines = frame.toText().split('\n');
      final row = lines.indexWhere((line) => line.contains("const x = 'tok';"));
      expect(row, greaterThanOrEqualTo(0));

      // The buffer stores 8-bit channels, so only exactly representable
      // colours compare equal. Color.info survives that round trip.
      expect(
        frame,
        BufferMatchers.hasColorAt(lines[row].indexOf('const'), row, Color.info),
      );

      final stringColor = frame.getForegroundColor(
        lines[row].indexOf("'tok'"),
        row,
      );
      expect(stringColor, isNot(ThemeData.dark.text));
      expect(stringColor, isNot(Color.info));
      expect(stringColor.r, greaterThan(stringColor.g));
      expect(stringColor.r, greaterThan(stringColor.b));
    });

    group('agent code highlighter', () {
      test('styles comments, strings, numbers, and keywords in order', () {
        const highlighter = AgentCodeHighlighter();
        const source =
            "// note\nString status() => 'after';\nconst int count = 42;";

        final ranges = highlighter.highlight(source, language: 'dart');

        expect(ranges, isNotEmpty);
        for (var index = 1; index < ranges.length; index++) {
          expect(
            ranges[index].start,
            greaterThanOrEqualTo(ranges[index - 1].end),
          );
        }
        expect(
          ranges.any(
            (range) => source.substring(range.start, range.end) == '// note',
          ),
          isTrue,
        );
        expect(
          ranges.any(
            (range) => source.substring(range.start, range.end) == "'after'",
          ),
          isTrue,
        );
        expect(
          ranges.any(
            (range) => source.substring(range.start, range.end) == 'const',
          ),
          isTrue,
        );
        expect(
          ranges.any(
            (range) => source.substring(range.start, range.end) == '42',
          ),
          isTrue,
        );
      });

      test('paints no word that the language does not reserve', () {
        const highlighter = AgentCodeHighlighter();
        // Idiomatic code whose identifiers are not reserved words in the
        // language shown, mapped to the exact words that language reserves.
        // One shared keyword set paints `in`, `interface`, `async`, `assert`,
        // and `func` here, and every one of those is wrong.
        const samples = <String, (String, List<String>)>{
          'java': ('InputStream in = socket.getInputStream();', []),
          'c': ('int in = read(fd, buf, n);', []),
          'cpp': ('auto interface = make_stream();', []),
          'go': ('result := load(in)', []),
          'kotlin': ('val result = async { load() }', []),
          'swift': ('let assert = Checker()', []),
          'javascript': ('const func = () => go(map.get(key));', ['const']),
          // TypeScript's own additions are contextual, so they stay plain.
          'typescript': (
            'const readonly = { never: a, unknown: b, keyof: c };',
            ['const'],
          ),
          'ts': ('let satisfies = declare(namespace, of);', ['let']),
          'dart': ("final func = go(map['key']);", ['final']),
        };

        samples.forEach((language, sample) {
          final (source, expected) = sample;
          expect(
            highlighter
                .highlight(source, language: language)
                .map((range) => source.substring(range.start, range.end))
                .where((token) => !token.startsWith("'"))
                .toList(),
            expected,
            reason: '$language over: $source',
          );
        });
      });

      test('a lexed language without a keyword set still lexes literals', () {
        const highlighter = AgentCodeHighlighter();
        const source = '// note\nx := "tok"\ny := 42';

        final painted = highlighter
            .highlight(source, language: 'go')
            .map((range) => source.substring(range.start, range.end))
            .toList();

        expect(painted, containsAll(<String>['// note', '"tok"', '42']));
      });

      test('returns no ranges for a language it does not lex', () {
        const highlighter = AgentCodeHighlighter();

        expect(
          highlighter.highlight("String s = 'x';", language: 'brainfuck'),
          isEmpty,
        );
        expect(highlighter.highlight("String s = 'x';"), isEmpty);
        // A Rust lifetime opens with a single quote, so Rust is not lexed.
        expect(
          highlighter.highlight("fn f(s: &'a str) {}", language: 'rust'),
          isEmpty,
        );
      });
    });

    test('presentation imports only the supported high-level Noir barrel', () {
      final source = io.File('example/chat_demo.dart').readAsStringSync();

      expect(source, contains("import 'package:noir/noir.dart';"));
      expect(source, isNot(contains('package:noir/src/')));
      expect(source, isNot(contains('package:noir/noir_low_level.dart')));
      expect(source, isNot(contains('package:noir/noir_ffi.dart')));
      expect(source, contains('.enableKittyKeyboard();'));
    });
  });
}

class _ControllerSwapHost extends StatefulWidget {
  const _ControllerSwapHost({required this.controller, super.key});

  final AgentSessionController controller;

  @override
  State<_ControllerSwapHost> createState() => _ControllerSwapHostState();
}

class _ControllerSwapHostState extends State<_ControllerSwapHost> {
  late AgentSessionController _controller = widget.controller;

  void replace(AgentSessionController controller) {
    setState(() => _controller = controller);
  }

  @override
  Widget build(BuildContext context) =>
      ChatDemoApp(controller: _controller, enableAnimation: false);
}

final class _ChatHarness {
  _ChatHarness({
    required this.app,
    required this.backend,
    required this.controller,
  });

  static Future<_ChatHarness> create({
    ReplayAgentBackend? backend,
    AgentSessionController? controller,
    List<String> pathSuggestions = const ['lib/noir.dart'],
    bool enableReplayControls = true,
    int width = 64,
    int height = 18,
  }) async {
    final resolvedBackend = backend ?? ReplayAgentBackend();
    final resolvedController =
        controller ?? AgentSessionController(backend: resolvedBackend);
    final app = createTuiTestApp(
      ChatDemoApp(
        controller: resolvedController,
        pathSuggestions: pathSuggestions,
        enableReplayControls: enableReplayControls,
        enableAnimation: false,
      ),
      width: width,
      height: height,
      kittyKeyboard: true,
    );
    await resolvedController.start();
    await _settle(app);
    return _ChatHarness(
      app: app,
      backend: resolvedBackend,
      controller: resolvedController,
    );
  }

  final TuiTestApp app;
  final ReplayAgentBackend backend;
  final AgentSessionController controller;

  Future<void> close() async {
    app.dispose();
    await controller.close();
  }
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
