import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  group('Shortcuts / Actions', () {
    test(
      'raw ANSI bytes dispatch through shortcut intent action path',
      () async {
        final invoked = <String>[];
        final focusNode = FocusNode();
        final app = createTuiTestApp(
          Shortcuts(
            shortcuts: {
              const SingleActivator(LogicalKeyboardKey.arrowDown):
                  const MoveSelectionDownIntent(),
            },
            child: Actions(
              actions: {
                MoveSelectionDownIntent:
                    CallbackAction<MoveSelectionDownIntent>((intent, context) {
                      invoked.add('down');
                      return KeyEventResult.handled;
                    }),
              },
              child: Focus(
                focusNode: focusNode,
                autofocus: true,
                child: const SizedBox(width: 1, height: 1),
              ),
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        app.mockInput.pressArrow(ArrowDirection.down);
        await Future<void>.delayed(Duration.zero);

        expect(invoked, ['down']);
        app.dispose();
      },
    );

    test('Tab and Shift+Tab route through traversal policy', () async {
      final a = FocusNode(debugLabel: 'a');
      final b = FocusNode(debugLabel: 'b');
      final app = createTuiTestApp(
        Column(
          children: [
            Focus(
              focusNode: a,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
            Focus(focusNode: b, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      app.mockInput.pressTab();
      await Future<void>.delayed(Duration.zero);
      expect(b.hasFocus, isTrue);

      app.mockInput.pressKittyKey(9, modifiers: KeyModifiers.shift);
      await Future<void>.delayed(Duration.zero);
      expect(a.hasFocus, isTrue);

      app.dispose();
    });

    test('TextArea Tab and Shift+Tab route through traversal policy', () async {
      final before = FocusNode(debugLabel: 'before');
      final textArea = FocusNode(debugLabel: 'text-area');
      final after = FocusNode(debugLabel: 'after');
      final controller = TextEditingController();
      final app = createTuiTestApp(
        Column(
          children: [
            Focus(
              focusNode: before,
              child: const SizedBox(width: 1, height: 1),
            ),
            TextArea(
              focusNode: textArea,
              autofocus: true,
              controller: controller,
              height: 2,
              width: 12,
            ),
            Focus(focusNode: after, child: const SizedBox(width: 1, height: 1)),
          ],
        ),
        kittyKeyboard: true,
      );

      try {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(textArea.hasFocus, isTrue);

        app.mockInput.pressTab();
        await Future<void>.delayed(Duration.zero);
        expect(after.hasFocus, isTrue);
        expect(controller.text, isEmpty);

        textArea.requestFocus();
        await Future<void>.delayed(Duration.zero);

        app.mockInput.pressKittyKey(9, modifiers: KeyModifiers.shift);
        await Future<void>.delayed(Duration.zero);
        expect(before.hasFocus, isTrue);
        expect(controller.text, isEmpty);
      } finally {
        app.dispose();
        controller.dispose();
      }
    });

    test(
      'TextInput editing keys route through parser-backed intents',
      () async {
        final focusNode = FocusNode();
        final controller = TextEditingController();
        final app = createTuiTestApp(
          TextInput(
            focusNode: focusNode,
            autofocus: true,
            controller: controller,
          ),
          kittyKeyboard: true,
        );

        try {
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          app.mockInput.typeText('abcd');
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 4),
          );

          app.mockInput.pressKittyKey(57356); // Home.
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );

          app.mockInput.pressKittyKey(57349); // Delete.
          await Future<void>.delayed(Duration.zero);
          expect(controller.text, 'bcd');

          app.mockInput.pressKittyKey(57357); // End.
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 3),
          );
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'TextArea document movement keys route through parser-backed intents',
      () async {
        final controller = TextEditingController();
        final app = createTuiTestApp(
          TextArea(
            autofocus: true,
            controller: controller,
            height: 3,
            width: 12,
          ),
          kittyKeyboard: true,
        );

        try {
          await Future<void>.delayed(Duration.zero);
          await Future<void>.delayed(Duration.zero);

          app.mockInput.typeText('ab\ncd');
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 5),
          );

          app.mockInput.pressKittyKey(57356, modifiers: KeyModifiers.ctrl);
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 0),
          );

          app.mockInput.pressKittyKey(57357, modifiers: KeyModifiers.ctrl);
          await Future<void>.delayed(Duration.zero);
          expect(
            controller.selection,
            const TextSelection.collapsed(offset: 5),
          );
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test('key releases do not invoke shortcuts', () async {
      final invoked = <String>[];
      final focusNode = FocusNode();
      final app = createTuiTestApp(
        Shortcuts(
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.arrowDown):
                const MoveSelectionDownIntent(),
          },
          child: Actions(
            actions: {
              MoveSelectionDownIntent: CallbackAction<MoveSelectionDownIntent>((
                intent,
                context,
              ) {
                invoked.add('down');
                return KeyEventResult.handled;
              }),
            },
            child: Focus(
              focusNode: focusNode,
              autofocus: true,
              child: const SizedBox(width: 1, height: 1),
            ),
          ),
        ),
        kittyKeyboard: true,
      );

      try {
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        app.mockInput.pressKittyKey(57353, eventType: 3);
        await Future<void>.delayed(Duration.zero);

        expect(invoked, isEmpty);
      } finally {
        app.dispose();
      }
    });

    test('Select consumes parser-backed movement intents', () async {
      final changes = <int>[];
      final app = createTuiTestApp(
        Select<int>(
          autofocus: true,
          height: 3,
          options: const [
            SelectOption(name: 'A', value: 0),
            SelectOption(name: 'B', value: 1),
            SelectOption(name: 'C', value: 2),
          ],
          onChanged: (index, option) => changes.add(index),
        ),
      );

      try {
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);

        app.mockInput.pressArrow(ArrowDirection.down);
        await Future<void>.delayed(Duration.zero);

        expect(changes, [1]);
      } finally {
        app.dispose();
      }
    });

    test('ScrollBox consumes parser-backed scroll intents', () async {
      final controller = ScrollController();
      final app = createTuiTestApp(
        SizedBox(
          width: 12,
          height: 3,
          child: ScrollBox(
            autofocus: true,
            controller: controller,
            child: Column(
              children: List<Widget>.generate(
                12,
                (index) => Text('Item $index'),
              ),
            ),
          ),
        ),
      );

      try {
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);

        app.mockInput.pressArrow(ArrowDirection.down);
        await Future<void>.delayed(Duration.zero);

        expect(controller.offset, 1);
      } finally {
        app.dispose();
      }
    });
  });
}
