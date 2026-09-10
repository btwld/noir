import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';

void main() {
  group('active text selection ownership', () {
    test('unfocused external controllers remain cleared and hide cursors', () {
      for (final widgetKind in _EditorKind.values) {
        final controller = TextEditingController(text: 'abc\ndef');
        final capture = BufferCapture(width: 12, height: 3);
        addTearDown(controller.dispose);
        addTearDown(capture.dispose);

        final buffer = capture.capture(widgetKind.widget(controller));

        expect(controller.selection, const TextSelection.collapsed(offset: -1));
        expect(buffer.cursor.visible, isFalse);
      }
    });

    test('unfocused owned initial text stays cleared and hides cursor', () {
      for (final widgetKind in _EditorKind.values) {
        final capture = BufferCapture(width: 12, height: 3);
        addTearDown(capture.dispose);

        final buffer = capture.capture(widgetKind.owned(value: 'abc\ndef'));
        expect(buffer.cursor.visible, isFalse);
        expect(buffer.toText(), contains('abc'));
      }
    });

    test(
      'autofocus repairs invalid external selection to document end',
      () async {
        for (final widgetKind in _EditorKind.values) {
          final controller = TextEditingController(text: 'abc\ndef');
          final driver = KeyDriver(
            widgetKind.widget(controller, autofocus: true),
            paintFrames: true,
            width: 12,
            height: 3,
          );
          await driver.ready();

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 7),
            reason: '$widgetKind',
          );
          expect(
            driver.app.buildOwner.cursorController.isVisible,
            isTrue,
            reason: '$widgetKind',
          );

          driver.dispose();
          controller.dispose();
        }
      },
    );

    test('owned multiline autofocus repairs to whole-document end', () async {
      // Owned TextArea must repair to whole-document end, not first-line end.
      final areaDriver = KeyDriver(
        const TextArea(
          value: 'abc\ndef',
          autofocus: true,
          height: 3,
          width: 12,
        ),
        paintFrames: true,
        width: 12,
        height: 3,
      );
      await areaDriver.ready();
      final areaCursor = areaDriver.app.buildOwner.cursorController;
      expect(areaCursor.isVisible, isTrue);
      expect(areaCursor.x, 3, reason: 'last-line end x');
      expect(areaCursor.y, 1, reason: 'last-line end y');
      areaDriver.dispose();

      // Owned single-line TextInput also repairs selection to document end.
      final inputDriver = KeyDriver(
        const TextInput(value: 'hello', autofocus: true),
        paintFrames: true,
        width: 12,
        height: 1,
      );
      await inputDriver.ready();
      final inputCursor = inputDriver.app.buildOwner.cursorController;
      expect(inputCursor.isVisible, isTrue);
      expect(inputCursor.x, 5, reason: 'document-end x');
      inputDriver.dispose();
    });

    test('focus preserves a usable directional range selection', () async {
      const selection = TextSelection(
        baseOffset: 6,
        extentOffset: 2,
        affinity: TextAffinity.upstream,
        isDirectional: true,
      );
      for (final widgetKind in _EditorKind.values) {
        final controller = TextEditingController(text: 'abcdefg')
          ..selection = selection;
        final driver = KeyDriver(
          widgetKind.widget(controller, autofocus: true),
        );
        await driver.ready();

        expect(controller.selection, selection, reason: '$widgetKind');

        driver.dispose();
        controller.dispose();
      }
    });

    test(
      'focused controller.text repairs synchronously without onChanged',
      () async {
        for (final widgetKind in _EditorKind.values) {
          final changes = <String>[];
          final controller = TextEditingController(text: 'old');
          final driver = KeyDriver(
            widgetKind.widget(
              controller,
              autofocus: true,
              onChanged: changes.add,
            ),
          );
          await driver.ready();
          var rawNotifications = 0;
          controller
            ..addListener(() => rawNotifications++)
            ..text = 'new value';

          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 9),
            reason: '$widgetKind',
          );
          expect(rawNotifications, 2, reason: '$widgetKind');
          expect(changes, isEmpty, reason: '$widgetKind');

          driver.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'focused invalid value is repaired but usable value is preserved',
      () async {
        for (final widgetKind in _EditorKind.values) {
          final controller = TextEditingController(text: 'start');
          final driver = KeyDriver(
            widgetKind.widget(controller, autofocus: true),
          );
          await driver.ready();

          const usable = TextSelection(
            baseOffset: 3,
            extentOffset: 1,
            isDirectional: true,
          );
          controller.value = const TextEditingValue(
            text: 'abcd',
            selection: usable,
          );
          expect(controller.selection, usable, reason: '$widgetKind usable');

          controller.value = const TextEditingValue(
            text: 'abc',
            selection: TextSelection.collapsed(offset: 99),
          );
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 3),
            reason: '$widgetKind invalid',
          );

          driver.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'blur preserves selection and refocus repairs later cleared text',
      () async {
        for (final widgetKind in _EditorKind.values) {
          final focusNode = FocusNode();
          final controller = TextEditingController(text: 'abc');
          final driver = KeyDriver(
            widgetKind.widget(
              controller,
              focusNode: focusNode,
              autofocus: true,
            ),
            paintFrames: true,
            width: 12,
            height: 3,
          );
          await driver.ready();
          expect(controller.selection.extentOffset, 3);
          expect(driver.app.buildOwner.cursorController.isVisible, isTrue);

          focusNode.unfocus();
          driver.app.debugFlushFrame();
          expect(controller.selection.extentOffset, 3);
          expect(driver.app.buildOwner.cursorController.isVisible, isFalse);

          controller.text = 'replacement';
          expect(controller.selection.isValid, isFalse);
          driver.app.debugFlushFrame();
          expect(driver.app.buildOwner.cursorController.isVisible, isFalse);

          focusNode.requestFocus();
          driver.app.debugFlushFrame();
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 11),
            reason: '$widgetKind',
          );
          expect(driver.app.buildOwner.cursorController.isVisible, isTrue);

          driver.dispose();
          controller.dispose();
          focusNode.dispose();
        }
      },
    );

    test('focused controller replacement reconciles final controller once', () {
      for (final widgetKind in _EditorKind.values) {
        final focusNode = FocusNode();
        final first = TextEditingController(text: 'first');
        final second = TextEditingController(text: 'second');
        final host = TestElementHost()
          ..mount(widgetKind.widget(first, focusNode: focusNode));
        focusNode.requestFocus();
        expect(first.selection.extentOffset, 5);

        host.root!.update(widgetKind.widget(second, focusNode: focusNode));
        host.owner.buildScope();

        expect(
          second.selection,
          const TextSelection.collapsed(offset: 6),
          reason: '$widgetKind',
        );
        host.dispose();
        first.text = 'external survives';
        second.text = 'external survives';

        first.dispose();
        second.dispose();
        focusNode.dispose();
      }
    });

    test('owned value updates preserve the current focus state', () {
      for (final widgetKind in _EditorKind.values) {
        final focusNode = FocusNode();
        final host = TestElementHost()
          ..mount(widgetKind.owned(value: 'old', focusNode: focusNode));

        host.root!.update(
          widgetKind.owned(value: 'next', focusNode: focusNode),
        );
        host.owner.buildScope();
        expect(focusNode.hasFocus, isFalse);

        focusNode.requestFocus();
        host.owner.buildScope();

        host.root!.update(
          widgetKind.owned(value: 'focused-update', focusNode: focusNode),
        );
        host.owner.buildScope();
        expect(focusNode.hasFocus, isTrue);

        host.dispose();
        focusNode.dispose();
      }
    });

    test('controller swap permutations preserve ownership rules', () {
      for (final widgetKind in _EditorKind.values) {
        for (final focused in [false, true]) {
          final focusNode = FocusNode();
          final ownedHost = TestElementHost()
            ..mount(widgetKind.owned(value: 'owned-a', focusNode: focusNode));
          if (focused) focusNode.requestFocus();

          final externalA = TextEditingController(text: 'ext-a');
          ownedHost.root!.update(
            widgetKind.widget(externalA, focusNode: focusNode),
          );
          ownedHost.owner.buildScope();
          if (focused) {
            expect(
              externalA.selection,
              const TextSelection.collapsed(offset: 5),
              reason: '$widgetKind owned->external focused',
            );
          } else {
            expect(
              externalA.selection.isValid,
              isFalse,
              reason: '$widgetKind owned->external unfocused',
            );
          }

          final externalB = TextEditingController(text: 'ext-b-long')
            ..selection = const TextSelection.collapsed(offset: 3);
          ownedHost.root!.update(
            widgetKind.widget(externalB, focusNode: focusNode),
          );
          ownedHost.owner.buildScope();
          if (focused) {
            expect(
              externalB.selection,
              const TextSelection.collapsed(offset: 3),
              reason: '$widgetKind externalA->B usable focused',
            );
          } else {
            expect(
              externalB.selection,
              const TextSelection.collapsed(offset: 3),
              reason: '$widgetKind externalA->B usable unfocused',
            );
          }

          final invalidExternal = TextEditingController(text: 'bad');
          ownedHost.root!.update(
            widgetKind.widget(invalidExternal, focusNode: focusNode),
          );
          ownedHost.owner.buildScope();
          if (focused) {
            expect(
              invalidExternal.selection,
              const TextSelection.collapsed(offset: 3),
              reason: '$widgetKind invalid external repair',
            );
          } else {
            expect(
              invalidExternal.selection.isValid,
              isFalse,
              reason: '$widgetKind invalid external unfocused',
            );
          }

          ownedHost.root!.update(
            widgetKind.owned(value: 'owned-again', focusNode: focusNode),
          );
          ownedHost.owner.buildScope();

          ownedHost.dispose();
          // Externals survive host disposal.
          externalA.text = 'still-alive-a';
          externalB.text = 'still-alive-b';
          invalidExternal.text = 'still-alive-bad';
          externalA.dispose();
          externalB.dispose();
          invalidExternal.dispose();
          focusNode.dispose();
        }
      }
    });

    test('focus-node replacement preserves or repairs selection', () {
      for (final widgetKind in _EditorKind.values) {
        final firstNode = FocusNode();
        final secondNode = FocusNode();
        final controller = TextEditingController(text: 'abc');
        final host = TestElementHost()
          ..mount(widgetKind.widget(controller, focusNode: firstNode));
        firstNode.requestFocus();
        expect(controller.selection.extentOffset, 3);

        // Focused programmatic text repairs synchronously to document end.
        controller.text = 'replaced';
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 8),
          reason: '$widgetKind focused repair',
        );

        // Replace the focus node while still focused. The new node attaches
        // unfocused; usable selection is preserved and cursor leaves.
        host.root!.update(widgetKind.widget(controller, focusNode: secondNode));
        host.owner.buildScope();
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 8),
          reason: '$widgetKind selection preserved across node swap',
        );
        expect(secondNode.hasFocus, isFalse);

        // Unfocused programmatic clear stays cleared.
        controller
          ..text = 'again'
          ..selection = const TextSelection.collapsed(offset: -1);
        expect(controller.selection.isValid, isFalse);

        // Focusing the replacement node repairs to current document end.
        secondNode.requestFocus();
        host.owner.buildScope();
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: 5),
          reason: '$widgetKind replacement node focus repair',
        );
        expect(secondNode.hasFocus, isTrue);

        host.dispose();
        controller.dispose();
        firstNode.dispose();
        secondNode.dispose();
      }
    });

    test('same-controller style rebuild does not grow listeners', () {
      for (final widgetKind in _EditorKind.values) {
        final controller = TextEditingController(text: 'stable');
        var raw = 0;
        void count() => raw++;
        controller.addListener(count);

        final focusNode = FocusNode();
        final host = TestElementHost()
          ..mount(widgetKind.widget(controller, focusNode: focusNode));
        focusNode.requestFocus();
        raw = 0;
        controller.text = 'one';
        final afterFirst = raw;

        host.root!.update(
          widgetKind.widget(
            controller,
            focusNode: focusNode,
            color: Color.yellow,
          ),
        );
        host.owner.buildScope();
        raw = 0;
        controller.text = 'two';
        expect(raw, afterFirst, reason: '$widgetKind listener count stable');

        host.dispose();
        // After detach, only the test listener remains.
        raw = 0;
        controller.text = 'three';
        expect(raw, 1, reason: '$widgetKind only external after detach');

        controller
          ..removeListener(count)
          ..dispose();
        focusNode.dispose();
      }
    });

    test('repeated teardown detach is idempotent', () {
      for (final widgetKind in _EditorKind.values) {
        final controller = TextEditingController(text: 'abc');
        var raw = 0;
        controller.addListener(() => raw++);

        (TestElementHost()..mount(widgetKind.widget(controller))).dispose();
        // Second dispose path: re-mount and dispose again.
        (TestElementHost()..mount(widgetKind.widget(controller))).dispose();

        raw = 0;
        controller.text = 'after';
        // Only the external test listener fires; mixin listeners are gone.
        expect(raw, 1, reason: '$widgetKind');
        controller.dispose();
      }
    });

    test(
      'same State double detach is idempotent via controller swap A→B→A',
      () {
        for (final widgetKind in _EditorKind.values) {
          final controllerA = TextEditingController(text: 'aaa');
          final controllerB = TextEditingController(text: 'bbb');
          var rawA = 0;
          var rawB = 0;
          controllerA.addListener(() => rawA++);
          controllerB.addListener(() => rawB++);

          final host = TestElementHost()..mount(widgetKind.widget(controllerA));
          // Real detach: A → B removes the mixin listener from A.
          host.root!.update(widgetKind.widget(controllerB));
          host.owner.buildScope();
          rawA = 0;
          controllerA.text = 'A-after-detach';
          expect(rawA, 1, reason: '$widgetKind only external after A→B');

          // Second real detach: B → A removes the mixin listener from B.
          host.root!.update(widgetKind.widget(controllerA));
          host.owner.buildScope();
          rawB = 0;
          controllerB.text = 'B-after-detach';
          expect(rawB, 1, reason: '$widgetKind only external after B→A');

          // A is attached again; dispose must leave only the external listener.
          host.dispose();
          rawA = 0;
          controllerA.text = 'A-after-dispose';
          expect(rawA, 1, reason: '$widgetKind only external after dispose');

          controllerA.dispose();
          controllerB.dispose();
        }
      },
    );

    test(
      'direct dispose of host detaches without notifying after teardown',
      () {
        for (final widgetKind in _EditorKind.values) {
          final changes = <String>[];
          final controller = TextEditingController(text: 'abc');
          (TestElementHost()
                ..mount(widgetKind.widget(controller, onChanged: changes.add)))
              .dispose();
          controller.text = 'zombie';
          expect(changes, isEmpty, reason: '$widgetKind');
          controller.dispose();
        }
      },
    );

    test(
      'callback cardinality for edit move focus paste repair submit',
      () async {
        for (final widgetKind in _EditorKind.values) {
          final changes = <String>[];
          var submits = 0;
          final controller = TextEditingController(text: 'ab');
          var raw = 0;
          controller.addListener(() => raw++);

          final driver = KeyDriver(
            widgetKind.widget(
              controller,
              autofocus: true,
              onChanged: changes.add,
              onSubmit: () => submits++,
            ),
            paintFrames: true,
            width: 12,
            height: 3,
          );
          await driver.ready();
          // Autofocus repair may have already fired raw notifications via
          // the mixin's listener; reset counters after settle.
          raw = 0;
          changes.clear();
          submits = 0;

          // User text edit: one onChanged, raw fires once for the edit.
          await driver.sendCharacter('c');
          expect(controller.text, 'abc', reason: '$widgetKind edit text');
          expect(changes, ['abc'], reason: '$widgetKind edit onChanged');
          expect(raw, 1, reason: '$widgetKind edit raw');
          final afterEditRaw = raw;
          final afterEditChanges = changes.length;

          // Caret move: no onChanged.
          await driver.sendLogicalKey(LogicalKeyboardKey.arrowLeft);
          expect(
            controller.selection.extentOffset,
            2,
            reason: '$widgetKind move',
          );
          expect(
            changes.length,
            afterEditChanges,
            reason: '$widgetKind move onChanged',
          );
          expect(
            raw,
            greaterThan(afterEditRaw),
            reason: '$widgetKind move raw',
          );
          raw = 0;
          changes.clear();

          // Focus loss: no onChanged, no raw from selection (preserved).
          // Use explicit unfocus via second field is hard; request via node.
          driver.dispose();
          controller.dispose();

          // Fresh harness for paste / repair / submit / blur paths.
          final focusNode = FocusNode();
          final controller2 = TextEditingController(text: 'xy');
          final changes2 = <String>[];
          var submits2 = 0;
          var raw2 = 0;
          controller2.addListener(() => raw2++);
          final driver2 = KeyDriver(
            widgetKind.widget(
              controller2,
              focusNode: focusNode,
              autofocus: true,
              onChanged: changes2.add,
              onSubmit: () => submits2++,
            ),
            paintFrames: true,
            width: 12,
            height: 3,
          );
          await driver2.ready();
          raw2 = 0;
          changes2.clear();
          submits2 = 0;

          await driver2.sendPaste('Z');
          expect(controller2.text, 'xyZ', reason: '$widgetKind paste text');
          expect(changes2, ['xyZ'], reason: '$widgetKind paste onChanged');
          expect(raw2, 1, reason: '$widgetKind paste raw');
          raw2 = 0;
          changes2.clear();

          // Programmatic repair path: two raw (clear + repair), zero onChanged.
          controller2.text = 'programmatic';
          expect(raw2, 2, reason: '$widgetKind repair raw');
          expect(changes2, isEmpty, reason: '$widgetKind repair onChanged');
          expect(
            controller2.selection,
            const TextSelection.collapsed(offset: 12),
          );
          raw2 = 0;

          // Submit: one onSubmit, no onChanged when text unchanged.
          if (widgetKind == _EditorKind.input) {
            await driver2.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
          } else {
            await driver2.sendLogicalKey(
              LogicalKeyboardKey.enter,
              code: 13,
              modifiers: KeyModifiers.ctrl,
            );
          }
          expect(submits2, 1, reason: '$widgetKind onSubmit');
          expect(changes2, isEmpty, reason: '$widgetKind submit onChanged');

          // Focus loss: no onChanged, cursor hides, selection preserved.
          final preserved = controller2.selection;
          focusNode.unfocus();
          driver2.app.debugFlushFrame();
          expect(controller2.selection, preserved);
          expect(changes2, isEmpty);
          expect(driver2.app.buildOwner.cursorController.isVisible, isFalse);

          // Nested invalidation after detach: no delivery.
          driver2.dispose();
          raw2 = 0;
          changes2.clear();
          controller2.text = 'detached';
          expect(raw2, 1, reason: '$widgetKind only external after dispose');
          expect(
            changes2,
            isEmpty,
            reason: '$widgetKind no onChanged after dispose',
          );

          controller2.dispose();
          focusNode.dispose();
        }
      },
    );

    test(
      'TextArea viewport hook scrolls after focused programmatic end',
      () async {
        final controller = TextEditingController(
          text: List.generate(8, (i) => 'line$i').join('\n'),
        );
        final driver = KeyDriver(
          TextArea(
            controller: controller,
            autofocus: true,
            height: 3,
            width: 8,
          ),
          paintFrames: true,
          width: 8,
          height: 3,
        );
        await driver.ready();

        controller.text = List.generate(10, (i) => 'row$i').join('\n');
        driver.app.debugFlushFrame();

        final cursor = driver.app.buildOwner.cursorController;
        expect(cursor.isVisible, isTrue);
        expect(cursor.y, 2, reason: 'viewport scrolled so end is visible');
        expect(
          controller.selection,
          TextSelection.collapsed(offset: controller.text.length),
        );

        driver.dispose();
        controller.dispose();
      },
    );

    test(
      'parent-update controller identity change hooks without setState owner',
      () {
        final focusNode = FocusNode();
        final first = TextEditingController(text: 'aaa');
        final second = TextEditingController(text: 'bbbb');
        final host = TestElementHost()
          ..mount(
            TextArea(
              controller: first,
              focusNode: focusNode,
              height: 3,
              width: 12,
            ),
          );
        focusNode.requestFocus();
        expect(first.selection.extentOffset, 3);

        host.root!.update(
          TextArea(
            controller: second,
            focusNode: focusNode,
            height: 3,
            width: 12,
          ),
        );
        host.owner.buildScope();
        expect(second.selection, const TextSelection.collapsed(offset: 4));

        host.dispose();
        first.dispose();
        second.dispose();
        focusNode.dispose();
      },
    );

    test('direct connection rejects unusable selection before mutation', () {
      final controller = TextEditingController(text: 'abc');
      final connection = TextInputConnection(controller: controller);

      expect(() => connection.insertText('x'), throwsStateError);
      expect(controller.text, 'abc');
      expect(controller.selection.isValid, isFalse);

      controller.dispose();
    });

    test('connection edit delete move families require usable selection', () {
      final controller = TextEditingController(text: 'abcdef');
      final connection = TextInputConnection(controller: controller);

      // Unusable: all mutating/moving families fail before change.
      expect(() => connection.insertText('x'), throwsStateError);
      expect(
        () => connection.actions[DeleteBackwardIntent]!.invoke(
          const DeleteBackwardIntent(),
          _FakeBuildContext(),
        ),
        throwsStateError,
      );
      expect(
        () => connection.actions[DeleteForwardIntent]!.invoke(
          const DeleteForwardIntent(),
          _FakeBuildContext(),
        ),
        throwsStateError,
      );
      expect(
        () => connection.actions[MoveCaretLeftIntent]!.invoke(
          const MoveCaretLeftIntent(),
          _FakeBuildContext(),
        ),
        throwsStateError,
      );
      expect(
        () => connection.actions[MoveCaretRightIntent]!.invoke(
          const MoveCaretRightIntent(),
          _FakeBuildContext(),
        ),
        throwsStateError,
      );
      expect(
        () => connection.actions[MoveCaretDocumentEndIntent]!.invoke(
          const MoveCaretDocumentEndIntent(),
          _FakeBuildContext(),
        ),
        throwsStateError,
      );
      expect(controller.text, 'abcdef');
      expect(controller.selection.isValid, isFalse);

      // Usable directional selection: edit/delete/move succeed.
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
        isDirectional: true,
      );
      expect(connection.insertText('X'), KeyEventResult.handled);
      expect(controller.text, 'aXef');
      expect(controller.selection, const TextSelection.collapsed(offset: 2));

      controller
        ..text = 'abcdef'
        ..selection = const TextSelection.collapsed(offset: 3);
      expect(
        connection.actions[DeleteBackwardIntent]!.invoke(
          const DeleteBackwardIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.text, 'abdef');

      controller
        ..text = 'abcdef'
        ..selection = const TextSelection.collapsed(offset: 2);
      expect(
        connection.actions[DeleteForwardIntent]!.invoke(
          const DeleteForwardIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.text, 'abdef');

      controller
        ..text = 'abcdef'
        ..selection = const TextSelection.collapsed(offset: 3);
      expect(
        connection.actions[MoveCaretLeftIntent]!.invoke(
          const MoveCaretLeftIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selection.extentOffset, 2);
      expect(
        connection.actions[MoveCaretRightIntent]!.invoke(
          const MoveCaretRightIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selection.extentOffset, 3);
      expect(
        connection.actions[MoveCaretDocumentEndIntent]!.invoke(
          const MoveCaretDocumentEndIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selection.extentOffset, 6);
      expect(
        connection.actions[MoveCaretDocumentStartIntent]!.invoke(
          const MoveCaretDocumentStartIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(controller.selection.extentOffset, 0);

      // Submit does not require usable selection.
      controller.selection = const TextSelection.collapsed(offset: -1);
      var submitted = 0;
      final submitConnection = TextInputConnection(
        controller: controller,
        onSubmit: () => submitted++,
      );
      expect(
        submitConnection.actions[SubmitTextIntent]!.invoke(
          const SubmitTextIntent(),
          _FakeBuildContext(),
        ),
        KeyEventResult.handled,
      );
      expect(submitted, 1);

      controller.dispose();
    });

    test('connection ignores read-only and maxLength limit paths', () {
      final controller = TextEditingController(text: 'ab')
        ..selection = const TextSelection.collapsed(offset: 2);
      final readOnly = TextInputConnection(
        controller: controller,
        readOnly: true,
      );
      expect(readOnly.insertText('x'), KeyEventResult.ignored);
      expect(controller.text, 'ab');

      final limited = TextInputConnection(controller: controller, maxLength: 2);
      expect(limited.insertText('x'), KeyEventResult.ignored);
      expect(controller.text, 'ab');

      // Under limit still works.
      controller
        ..text = 'a'
        ..selection = const TextSelection.collapsed(offset: 1);
      expect(limited.insertText('b'), KeyEventResult.handled);
      expect(controller.text, 'ab');

      controller.dispose();
    });
  });
}

/// Minimal BuildContext stand-in for invoking connection actions directly.
class _FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _EditorKind {
  input,
  area;

  Widget widget(
    TextEditingController controller, {
    bool autofocus = false,
    FocusNode? focusNode,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmit,
    Color color = Color.white,
  }) => switch (this) {
    input => TextInput(
      controller: controller,
      autofocus: autofocus,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmit: onSubmit,
      color: color,
    ),
    area => TextArea(
      controller: controller,
      autofocus: autofocus,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmit: onSubmit,
      color: color,
      height: 3,
      width: 12,
    ),
  };

  Widget owned({
    required String value,
    bool autofocus = false,
    FocusNode? focusNode,
  }) => switch (this) {
    input => TextInput(
      value: value,
      autofocus: autofocus,
      focusNode: focusNode,
    ),
    area => TextArea(
      value: value,
      autofocus: autofocus,
      focusNode: focusNode,
      height: 3,
      width: 12,
    ),
  };
}
