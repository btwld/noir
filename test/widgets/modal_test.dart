import 'package:noir/noir.dart';
import 'package:noir/src/widgets/overlay.dart' show RootOverlay;
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('detached controller rejects open and treats close as a no-op', () {
    final controller = ModalController();

    expect(controller.isOpen, isFalse);
    expect(
      controller.open,
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('before the controller was attached'),
        ),
      ),
    );
    expect(controller.close, returnsNormally);
  });

  test(
    'open mounts fresh content, takes initial focus, and close restores focus',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final first = FocusNode(debugLabel: 'first-modal-action');
      var builds = 0;
      var opens = 0;
      var closes = 0;
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: first,
          onOpen: () => opens++,
          onClose: () => closes++,
          modalBuilder: (context) {
            builds++;
            return SizedBox(
              width: 24,
              height: 5,
              child: Button(
                label: 'Modal action',
                focusNode: first,
                onPressed: () {},
              ),
            );
          },
          child: Button(
            label: 'Open modal',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        expect(launcher.hasFocus, isTrue);
        expect(controller.isOpen, isFalse);
        expect(builds, 0);

        controller.open();
        await _settle(app);
        expect(controller.isOpen, isTrue);
        expect(opens, 1);
        expect(closes, 0);
        expect(builds, 1);
        expect(app.captureFrame().toText(), contains('Modal action'));
        expect(first.hasFocus, isTrue);
        expect(launcher.hasFocus, isFalse);

        controller.open();
        await _settle(app);
        expect(opens, 1);
        expect(builds, 1, reason: 'already-open open preserves modal State');
        expect(first.hasFocus, isTrue);

        controller.close();
        await _settle(app);
        expect(controller.isOpen, isFalse);
        expect(closes, 1);
        expect(app.captureFrame().toText(), isNot(contains('Modal action')));
        expect(launcher.hasFocus, isTrue);

        controller.close();
        expect(closes, 1);

        controller.open();
        await _settle(app);
        expect(builds, 2, reason: 'reopening builds fresh modal State');
        expect(
          first.hasFocus,
          isTrue,
          reason: 'each fresh open reapplies focus',
        );
      } finally {
        app.dispose();
        launcher.dispose();
        first.dispose();
      }

      expect(controller.isOpen, isFalse);
    },
  );

  test(
    'Tab loop follows live nested descendants after dynamic changes',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final first = FocusNode(debugLabel: 'first');
      final second = FocusNode(debugLabel: 'second');
      final third = FocusNode(debugLabel: 'third');
      final contentKey = GlobalKey<_DynamicModalContentState>();
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: first,
          modalBuilder: (context) => _DynamicModalContent(
            key: contentKey,
            first: first,
            second: second,
            third: third,
          ),
          child: Button(
            label: 'Launcher',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);
        expect(first.hasFocus, isTrue);

        launcher.requestFocus();
        await _settle(app);
        expect(
          first.hasFocus,
          isTrue,
          reason: 'an external focus request is repaired inside the modal',
        );

        app.mockInput.pressTab();
        await _settle(app);
        expect(second.hasFocus, isTrue, reason: 'nested scopes stay in order');

        app.mockInput.pressTab();
        await _settle(app);
        expect(first.hasFocus, isTrue, reason: 'forward traversal wraps');
        expect(launcher.hasFocus, isFalse);

        app.mockInput.pressShiftTab();
        await _settle(app);
        expect(second.hasFocus, isTrue, reason: 'reverse traversal wraps');

        contentKey.currentState!.setSecondEnabled(enabled: false);
        await _settle(app);
        expect(
          first.hasFocus,
          isTrue,
          reason: 'disabling the focused node rehomes focus inside',
        );

        app.mockInput.pressTab();
        await _settle(app);
        expect(first.hasFocus, isTrue, reason: 'one live node wraps to itself');
        expect(launcher.hasFocus, isFalse);

        contentKey.currentState!.setThirdVisible(visible: true);
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        expect(third.hasFocus, isTrue, reason: 'insertions join the live loop');

        contentKey.currentState!.setThirdVisible(visible: false);
        await _settle(app);
        expect(
          first.hasFocus,
          isTrue,
          reason:
              'removing the focused node rehomes focus inside; '
              'primary=${app.binding.buildOwner.focusManager.primaryFocus}, '
              'firstAttached=${first.isAttached}, '
              'thirdAttached=${third.isAttached}',
        );

        contentKey.currentState!.setSecondEnabled(enabled: true);
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        expect(
          second.hasFocus,
          isTrue,
          reason: 'a re-enabled descendant rejoins the live traversal list',
        );
      } finally {
        app.dispose();
        launcher.dispose();
        first.dispose();
        second.dispose();
        third.dispose();
      }
    },
  );

  test(
    'an initial node outside the modal falls back to its first child',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'outside-launcher');
      final first = FocusNode(debugLabel: 'first-modal-child');
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: launcher,
          modalBuilder: (context) =>
              Button(label: 'First', focusNode: first, onPressed: () {}),
          child: Button(
            label: 'Launcher',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);

        expect(first.hasFocus, isTrue);
        expect(launcher.hasFocus, isFalse);
      } finally {
        app.dispose();
        launcher.dispose();
        first.dispose();
      }
    },
  );

  test('closing a top modal restores focus into the modal below it', () async {
    final lowerController = ModalController();
    final upperController = ModalController();
    final launcher = FocusNode(debugLabel: 'launcher');
    final lowerAction = FocusNode(debugLabel: 'lower-action');
    final upperAction = FocusNode(debugLabel: 'upper-action');
    final app = createTuiTestApp(
      Column(
        children: [
          Modal(
            controller: lowerController,
            initialFocusNode: lowerAction,
            modalBuilder: (context) => Button(
              label: 'Lower action',
              focusNode: lowerAction,
              onPressed: () {},
            ),
            child: Button(
              label: 'Launcher',
              focusNode: launcher,
              autofocus: true,
              onPressed: lowerController.open,
            ),
          ),
          Modal(
            controller: upperController,
            initialFocusNode: upperAction,
            modalBuilder: (context) => Button(
              label: 'Upper action',
              focusNode: upperAction,
              onPressed: () {},
            ),
            child: const Text('Upper modal host'),
          ),
        ],
      ),
    );

    try {
      await _settle(app);
      lowerController.open();
      await _settle(app);
      expect(lowerAction.hasFocus, isTrue);

      upperController.open();
      await _settle(app);
      expect(upperAction.hasFocus, isTrue);
      expect(lowerController.isOpen, isTrue);

      upperController.close();
      await _settle(app);
      expect(lowerAction.hasFocus, isTrue);
      expect(lowerController.isOpen, isTrue);

      lowerController.close();
      await _settle(app);
      expect(launcher.hasFocus, isTrue);
    } finally {
      app.dispose();
      launcher.dispose();
      lowerAction.dispose();
      upperAction.dispose();
    }
  });

  test(
    'reopening a lower modal promotes its focus and keyboard boundary',
    () async {
      final lowerController = ModalController();
      final upperController = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final lowerFirst = FocusNode(debugLabel: 'lower-first');
      final lowerSecond = FocusNode(debugLabel: 'lower-second');
      final upperAction = FocusNode(debugLabel: 'upper-action');
      final app = createTuiTestApp(
        Column(
          children: [
            Modal(
              controller: lowerController,
              initialFocusNode: lowerFirst,
              modalBuilder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    label: 'Lower first',
                    focusNode: lowerFirst,
                    onPressed: () {},
                  ),
                  Button(
                    label: 'Lower second',
                    focusNode: lowerSecond,
                    onPressed: () {},
                  ),
                ],
              ),
              child: Button(
                label: 'Launcher',
                focusNode: launcher,
                autofocus: true,
                onPressed: lowerController.open,
              ),
            ),
            Modal(
              controller: upperController,
              initialFocusNode: upperAction,
              modalBuilder: (context) => Button(
                label: 'Upper action',
                focusNode: upperAction,
                onPressed: () {},
              ),
              child: const Text('Upper modal host'),
            ),
          ],
        ),
      );

      try {
        await _settle(app);
        lowerController.open();
        await _settle(app);
        upperController.open();
        await _settle(app);
        expect(upperAction.hasFocus, isTrue);

        lowerController.open();
        await _settle(app);
        expect(lowerFirst.hasFocus, isTrue);

        app.mockInput.pressTab();
        await _settle(app);
        expect(lowerSecond.hasFocus, isTrue);
        expect(upperAction.hasFocus, isFalse);

        app.mockInput.pressEscape();
        await _settle(app);
        expect(lowerController.isOpen, isFalse);
        expect(upperController.isOpen, isTrue);
        expect(upperAction.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
        lowerFirst.dispose();
        lowerSecond.dispose();
        upperAction.dispose();
      }
    },
  );

  test(
    'closing a top modal repairs focus when its lower snapshot is unavailable',
    () async {
      final lowerController = ModalController();
      final upperController = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final lowerUnavailable = FocusNode(debugLabel: 'lower-unavailable');
      final lowerFallback = FocusNode(debugLabel: 'lower-fallback');
      final upperAction = FocusNode(debugLabel: 'upper-action');
      final app = createTuiTestApp(
        Column(
          children: [
            Modal(
              controller: lowerController,
              initialFocusNode: lowerUnavailable,
              modalBuilder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Button(
                    label: 'Unavailable',
                    focusNode: lowerUnavailable,
                    onPressed: () {},
                  ),
                  Button(
                    label: 'Fallback',
                    focusNode: lowerFallback,
                    onPressed: () {},
                  ),
                ],
              ),
              child: Button(
                label: 'Launcher',
                focusNode: launcher,
                autofocus: true,
                onPressed: lowerController.open,
              ),
            ),
            Modal(
              controller: upperController,
              initialFocusNode: upperAction,
              modalBuilder: (context) => Button(
                label: 'Upper action',
                focusNode: upperAction,
                onPressed: () {},
              ),
              child: const Text('Upper modal host'),
            ),
          ],
        ),
      );

      try {
        await _settle(app);
        lowerController.open();
        await _settle(app);
        expect(lowerUnavailable.hasFocus, isTrue);

        upperController.open();
        await _settle(app);
        expect(upperAction.hasFocus, isTrue);

        lowerUnavailable.canRequestFocus = false;
        upperController.close();
        await _settle(app);

        expect(lowerController.isOpen, isTrue);
        expect(lowerFallback.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
        lowerUnavailable.dispose();
        lowerFallback.dispose();
        upperAction.dispose();
      }
    },
  );

  test('an empty modal keeps focus on its private scope across Tab', () async {
    final controller = ModalController();
    final launcher = FocusNode(debugLabel: 'launcher');
    final app = createTuiTestApp(
      Modal(
        controller: controller,
        modalBuilder: (context) =>
            const SizedBox(width: 12, height: 3, child: Text('No actions')),
        child: Button(
          label: 'Launcher',
          focusNode: launcher,
          autofocus: true,
          onPressed: controller.open,
        ),
      ),
    );

    try {
      await _settle(app);
      controller.open();
      await _settle(app);
      final modalFocus = app.binding.buildOwner.focusManager.primaryFocus;
      expect(modalFocus, isA<FocusScopeNode>());
      expect(launcher.hasFocus, isFalse);

      app.mockInput.pressTab();
      await _settle(app);
      expect(
        app.binding.buildOwner.focusManager.primaryFocus,
        same(modalFocus),
      );
      expect(launcher.hasFocus, isFalse);
    } finally {
      app.dispose();
      launcher.dispose();
    }
  });

  test('Escape dismisses by default and can be left to an ancestor', () async {
    Future<void> exercise({required bool dismissOnEscape}) async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final action = FocusNode(debugLabel: 'modal-action');
      var ancestorEscapes = 0;
      final app = createTuiTestApp(
        Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event.isPress &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              ancestorEscapes++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Modal(
            controller: controller,
            initialFocusNode: action,
            dismissOnEscape: dismissOnEscape,
            modalBuilder: (context) =>
                Button(label: 'Action', focusNode: action, onPressed: () {}),
            child: Button(
              label: 'Launcher',
              focusNode: launcher,
              autofocus: true,
              onPressed: controller.open,
            ),
          ),
        ),
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);

        app.mockInput.pressEscape();
        await _settle(app);

        expect(controller.isOpen, !dismissOnEscape);
        expect(ancestorEscapes, dismissOnEscape ? 0 : 1);
        expect(launcher.hasFocus, dismissOnEscape);
      } finally {
        app.dispose();
        launcher.dispose();
        action.dispose();
      }
    }

    await exercise(dismissOnEscape: true);
    await exercise(dismissOnEscape: false);
  });

  test(
    'outside events are blocked and only opted-in left-down dismisses',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      var baseEvents = 0;
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          dismissOnOutsideClick: true,
          modalBuilder: (context) =>
              const SizedBox(width: 20, height: 5, child: Text('Dialog')),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PointerListener(
                onPointerDown: (event) => baseEvents++,
                onPointerUp: (event) => baseEvents++,
                onPointerMove: (event) => baseEvents++,
                onPointerScroll: (event) => baseEvents++,
                child: const SizedBox(width: 40, height: 12),
              ),
              Button(
                label: 'Launcher',
                focusNode: launcher,
                autofocus: true,
                onPressed: controller.open,
              ),
            ],
          ),
        ),
        width: 40,
        height: 12,
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);
        final dialog = app.captureFrame().findText('Dialog').single;

        final inside = MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: dialog.x + 10,
          y: dialog.y + 2,
        );
        app.binding.inputManager.dispatchMouse(inside);
        await _settle(app);
        expect(controller.isOpen, isTrue, reason: 'inert interior is inside');
        expect(baseEvents, 0);

        for (final event in <MouseEvent>[
          MouseEvent(
            type: MouseEventType.move,
            button: MouseButton.left,
            x: 0,
            y: 0,
          ),
          MouseEvent(
            type: MouseEventType.up,
            button: MouseButton.left,
            x: 0,
            y: 0,
          ),
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.right,
            x: 0,
            y: 0,
          ),
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.middle,
            x: 0,
            y: 0,
          ),
          MouseEvent(
            type: MouseEventType.scroll,
            button: MouseButton.middle,
            x: 0,
            y: 0,
            scroll: MouseScroll(direction: MouseScrollDirection.down),
          ),
        ]) {
          app.binding.inputManager.dispatchMouse(event);
          await _settle(app);
          expect(event.isConsumed, isTrue, reason: '${event.type}');
          expect(controller.isOpen, isTrue, reason: '${event.type}');
          expect(baseEvents, 0, reason: '${event.type} reached the base');
        }

        final outsideLeft = MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        );
        app.binding.inputManager.dispatchMouse(outsideLeft);
        await _settle(app);
        expect(outsideLeft.isConsumed, isTrue);
        expect(controller.isOpen, isFalse);
        expect(baseEvents, 0);
        expect(launcher.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
      }
    },
  );

  test('safe outside default blocks left-down without dismissing', () async {
    final controller = ModalController();
    var basePresses = 0;
    final app = createTuiTestApp(
      Modal(
        controller: controller,
        modalBuilder: (context) => const Text('Dialog'),
        child: PointerListener(
          onPointerDown: (event) => basePresses++,
          child: const SizedBox(width: 30, height: 8),
        ),
      ),
      width: 30,
      height: 8,
    );

    try {
      await _settle(app);
      controller.open();
      await _settle(app);
      final event = MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 29,
        y: 7,
      );
      app.binding.inputManager.dispatchMouse(event);
      await _settle(app);

      expect(event.isConsumed, isTrue);
      expect(controller.isOpen, isTrue);
      expect(basePresses, 0);
    } finally {
      app.dispose();
    }
  });

  test(
    'resize recenters without recreating content or changing focus',
    () async {
      final controller = ModalController();
      final action = FocusNode(debugLabel: 'action');
      var mounts = 0;
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: action,
          modalBuilder: (context) => _MountProbe(
            onMount: () => mounts++,
            child: SizedBox(
              width: 20,
              height: 5,
              child: Button(
                label: 'Dialog action',
                focusNode: action,
                onPressed: () {},
              ),
            ),
          ),
          child: const Text('Base'),
        ),
        width: 40,
        height: 12,
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);
        final before = app.captureFrame().findText('Dialog action').single;
        expect(mounts, 1);
        expect(action.hasFocus, isTrue);

        app.resize(60, 20);
        await _settle(app);
        final after = app.captureFrame().findText('Dialog action').single;

        expect(after.x - before.x, 10);
        expect(after.y - before.y, 4);
        expect(controller.isOpen, isTrue);
        expect(mounts, 1);
        expect(action.hasFocus, isTrue);
      } finally {
        app.dispose();
        action.dispose();
      }
    },
  );

  test(
    'callback failures settle the requested state before rethrowing',
    () async {
      final openError = StateError('open callback failed');
      final closeError = StateError('close callback failed');
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final action = FocusNode(debugLabel: 'action');
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: action,
          onOpen: () {
            expect(controller.isOpen, isTrue);
            throw openError;
          },
          onClose: () {
            expect(controller.isOpen, isFalse);
            throw closeError;
          },
          modalBuilder: (context) =>
              Button(label: 'Action', focusNode: action, onPressed: () {}),
          child: Button(
            label: 'Launcher',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        expect(controller.open, throwsA(same(openError)));
        await _settle(app);
        expect(controller.isOpen, isTrue);
        expect(app.captureFrame().toText(), contains('Action'));
        expect(action.hasFocus, isTrue);

        expect(controller.close, throwsA(same(closeError)));
        await _settle(app);
        expect(controller.isOpen, isFalse);
        expect(app.captureFrame().toText(), isNot(contains('Action')));
        expect(launcher.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
        action.dispose();
      }
    },
  );

  test(
    'reentrant callbacks honor final state and original restore focus',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final action = FocusNode(debugLabel: 'action');
      final calls = <String>[];
      var closeFromOpen = true;
      var reopenFromClose = false;
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: action,
          onOpen: () {
            calls.add('open');
            if (closeFromOpen) controller.close();
          },
          onClose: () {
            calls.add('close');
            if (reopenFromClose) controller.open();
          },
          modalBuilder: (context) =>
              Button(label: 'Action', focusNode: action, onPressed: () {}),
          child: Button(
            label: 'Launcher',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);
        expect(calls, ['open', 'close']);
        expect(controller.isOpen, isFalse);
        expect(launcher.hasFocus, isTrue);

        closeFromOpen = false;
        controller.open();
        await _settle(app);
        expect(action.hasFocus, isTrue);

        reopenFromClose = true;
        controller.close();
        await _settle(app);
        expect(calls, ['open', 'close', 'open', 'close', 'open']);
        expect(controller.isOpen, isTrue);
        expect(action.hasFocus, isTrue);

        reopenFromClose = false;
        controller.close();
        await _settle(app);
        expect(controller.isOpen, isFalse);
        expect(launcher.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
        action.dispose();
      }
    },
  );

  test(
    'controller replacement preserves the open subtree without callbacks',
    () async {
      final firstController = ModalController();
      final secondController = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final action = FocusNode(debugLabel: 'action');
      final key = GlobalKey<_ReplaceableModalState>();
      var opens = 0;
      var closes = 0;
      var mounts = 0;
      final app = createTuiTestApp(
        _ReplaceableModal(
          key: key,
          initialController: firstController,
          launcher: launcher,
          action: action,
          onOpen: () => opens++,
          onClose: () => closes++,
          onMount: () => mounts++,
        ),
      );

      try {
        await _settle(app);
        firstController.open();
        await _settle(app);
        expect(opens, 1);
        expect(mounts, 1);
        expect(action.hasFocus, isTrue);

        key.currentState!.replaceController(secondController);
        await _settle(app);

        expect(firstController.isOpen, isFalse);
        expect(secondController.isOpen, isTrue);
        expect(opens, 1);
        expect(closes, 0);
        expect(mounts, 1);
        expect(action.hasFocus, isTrue);
        expect(firstController.open, throwsStateError);

        secondController.close();
        await _settle(app);
        expect(launcher.hasFocus, isTrue);
      } finally {
        app.dispose();
        launcher.dispose();
        action.dispose();
      }
    },
  );

  test('failed controller replacement preserves both live attachments', () {
    final first = ModalController();
    final occupied = ModalController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: Column(
            children: [
              Modal(
                controller: first,
                modalBuilder: (context) => const Text('first-modal'),
                child: const Text('first-child'),
              ),
              Modal(
                controller: occupied,
                modalBuilder: (context) => const Text('second-modal'),
                child: const Text('second-child'),
              ),
            ],
          ),
        ),
      );

    try {
      expect(
        () => host.update(
          RootOverlay(
            child: Column(
              children: [
                Modal(
                  controller: occupied,
                  modalBuilder: (context) => const Text('invalid'),
                  child: const Text('first-child'),
                ),
                Modal(
                  controller: occupied,
                  modalBuilder: (context) => const Text('second-modal'),
                  child: const Text('second-child'),
                ),
              ],
            ),
          ),
        ),
        throwsStateError,
      );

      expect(first.open, returnsNormally);
      expect(occupied.open, returnsNormally);
      expect(first.isOpen, isTrue);
      expect(occupied.isOpen, isTrue);
    } finally {
      host.dispose();
    }
  });

  test(
    'close skips an unavailable restore node without choosing a fallback',
    () async {
      final controller = ModalController();
      final launcher = FocusNode(debugLabel: 'launcher');
      final action = FocusNode(debugLabel: 'action');
      final app = createTuiTestApp(
        Modal(
          controller: controller,
          initialFocusNode: action,
          modalBuilder: (context) =>
              Button(label: 'Action', focusNode: action, onPressed: () {}),
          child: Button(
            label: 'Launcher',
            focusNode: launcher,
            autofocus: true,
            onPressed: controller.open,
          ),
        ),
      );

      try {
        await _settle(app);
        controller.open();
        await _settle(app);
        launcher.canRequestFocus = false;

        controller.close();
        await _settle(app);

        expect(launcher.hasFocus, isFalse);
        expect(app.binding.buildOwner.focusManager.primaryFocus, isNull);
      } finally {
        app.dispose();
        launcher.dispose();
        action.dispose();
      }
    },
  );

  test('teardown while open detaches without onClose', () async {
    final controller = ModalController();
    var closes = 0;
    final app = createTuiTestApp(
      Modal(
        controller: controller,
        onClose: () => closes++,
        modalBuilder: (context) => const Text('Dialog'),
        child: const Text('Base'),
      ),
    );

    await _settle(app);
    controller.open();
    await _settle(app);
    app.dispose();

    expect(controller.isOpen, isFalse);
    expect(closes, 0);
  });
}

class _DynamicModalContent extends StatefulWidget {
  const _DynamicModalContent({
    required this.first,
    required this.second,
    required this.third,
    super.key,
  });

  final FocusNode first;
  final FocusNode second;
  final FocusNode third;

  @override
  State<_DynamicModalContent> createState() => _DynamicModalContentState();
}

class _DynamicModalContentState extends State<_DynamicModalContent> {
  var _secondEnabled = true;
  var _thirdVisible = false;

  void setSecondEnabled({required bool enabled}) =>
      setState(() => _secondEnabled = enabled);

  void setThirdVisible({required bool visible}) =>
      setState(() => _thirdVisible = visible);

  @override
  Widget build(BuildContext context) {
    final first = Button(
      key: const ValueKey<String>('first'),
      label: 'First',
      focusNode: widget.first,
      onPressed: () {},
    );
    final second = FocusScope(
      key: const ValueKey<String>('nested-scope'),
      child: Button(
        key: const ValueKey<String>('second'),
        label: 'Second',
        focusNode: widget.second,
        onPressed: _secondEnabled ? () {} : null,
      ),
    );
    return SizedBox(
      width: 24,
      height: 6,
      child: Column(
        children: [
          first,
          second,
          if (_thirdVisible)
            Button(
              key: const ValueKey<String>('third'),
              label: 'Third',
              focusNode: widget.third,
              onPressed: () {},
            ),
        ],
      ),
    );
  }
}

class _MountProbe extends StatefulWidget {
  const _MountProbe({required this.onMount, required this.child});

  final VoidCallback onMount;
  final Widget child;

  @override
  State<_MountProbe> createState() => _MountProbeState();
}

class _MountProbeState extends State<_MountProbe> {
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReplaceableModal extends StatefulWidget {
  const _ReplaceableModal({
    required this.initialController,
    required this.launcher,
    required this.action,
    required this.onOpen,
    required this.onClose,
    required this.onMount,
    super.key,
  });

  final ModalController initialController;
  final FocusNode launcher;
  final FocusNode action;
  final VoidCallback onOpen;
  final VoidCallback onClose;
  final VoidCallback onMount;

  @override
  State<_ReplaceableModal> createState() => _ReplaceableModalState();
}

class _ReplaceableModalState extends State<_ReplaceableModal> {
  late ModalController _controller = widget.initialController;

  void replaceController(ModalController value) =>
      setState(() => _controller = value);

  @override
  Widget build(BuildContext context) => Modal(
    controller: _controller,
    initialFocusNode: widget.action,
    onOpen: widget.onOpen,
    onClose: widget.onClose,
    modalBuilder: (context) => _MountProbe(
      onMount: widget.onMount,
      child: Button(
        label: 'Action',
        focusNode: widget.action,
        onPressed: () {},
      ),
    ),
    child: Button(
      label: 'Launcher',
      focusNode: widget.launcher,
      autofocus: true,
      onPressed: _controller.open,
    ),
  );
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
