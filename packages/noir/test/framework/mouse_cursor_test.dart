// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_internal_member
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show HitTestResult;
import 'package:noir/src/core/input.dart'
    show InputManagerKernelAccess, InputPriority;
import 'package:noir/src/widgets/select.dart' show RenderSelect;
import 'package:test/test.dart';
import '../helpers/key_driver.dart';

MouseEvent move(int x) =>
    MouseEvent(type: MouseEventType.move, button: MouseButton.left, x: x, y: 0);

void main() {
  test(
    'empty selectable ListView does not advertise or confirm a row',
    () async {
      var changes = 0;
      var confirmations = 0;
      final driver = KeyDriver(
        PointerListener(
          mouseCursor: MouseCursor.pointer,
          child: SizedBox(
            width: 12,
            height: 3,
            child: ListView(
              itemCount: 0,
              height: 3,
              selectedIndex: 0,
              itemBuilder: (_, index, _) => Text('Row $index'),
              onChanged: (_) => changes++,
              onSelect: (_) => confirmations++,
            ),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      await driver.sendMouse(move(1));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 0,
        ),
      );
      expect(changes, 0);
      expect(confirmations, 0);
    },
  );

  test(
    'ListView cursor matches extent bands, gutter and blank remainder',
    () async {
      var selected = -1;
      final driver = KeyDriver(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 12,
            height: 7,
            child: ListView(
              itemCount: 2,
              height: 7,
              itemExtent: 2,
              selectedIndex: 0,
              showScrollIndicator: true,
              itemBuilder: (_, index, _) => Text('Row $index'),
              onSelect: (index) => selected = index,
            ),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      for (final x in [1, 11]) {
        for (final y in [0, 1, 2, 3, 4, 6]) {
          await driver.sendMouse(
            MouseEvent(
              type: MouseEventType.move,
              button: MouseButton.left,
              x: x,
              y: y,
            ),
          );
          expect(
            driver.app.buildOwner.mouseCursor,
            y < 4 ? MouseCursor.pointer : MouseCursor.basic,
            reason: 'cell ($x,$y)',
          );
        }
      }
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 11,
          y: 3,
        ),
      );
      expect(selected, 1);
    },
  );

  test(
    'plain ListView masks ancestor hand but preserves inner text cursor',
    () async {
      final driver = KeyDriver(
        PointerListener(
          mouseCursor: MouseCursor.pointer,
          child: SizedBox(
            width: 12,
            height: 3,
            child: ListView(
              itemCount: 2,
              height: 3,
              itemBuilder: (_, index, _) => index == 0
                  ? const PointerListener(
                      mouseCursor: MouseCursor.text,
                      child: Text('edit'),
                    )
                  : const Text('plain'),
            ),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      for (final y in [0, 1, 2]) {
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.move,
            button: MouseButton.left,
            x: 1,
            y: y,
          ),
        );
        expect(
          driver.app.buildOwner.mouseCursor,
          y == 0 ? MouseCursor.text : MouseCursor.basic,
        );
      }
    },
  );

  test('TabSelect only advertises visible clickable tab cells', () async {
    var selected = -1;
    final driver = KeyDriver(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 12,
          height: 3,
          child: TabSelect<int>(
            tabWidth: 4,
            options: const [
              SelectOption(name: 'A', value: 0),
              SelectOption(name: 'B', value: 1),
            ],
            onSelect: (index, _) => selected = index,
          ),
        ),
      ),
    );
    addTearDown(driver.dispose);
    await driver.ready();
    for (final position in [
      const Offset(1, 0),
      const Offset(5, 0),
      const Offset(9, 0),
      const Offset(1, 1),
      const Offset(1, 2),
    ]) {
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.move,
          button: MouseButton.left,
          x: position.dx,
          y: position.dy,
        ),
      );
      expect(
        driver.app.buildOwner.mouseCursor,
        position.dy == 0 && position.dx < 8
            ? MouseCursor.pointer
            : MouseCursor.basic,
        reason: 'cell $position',
      );
    }
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 5,
        y: 0,
      ),
    );
    expect(selected, 1);
  });

  test(
    'TabSelect hand follows scrolled metrics and clears when empty',
    () async {
      for (final empty in [false, true]) {
        var selected = -1;
        final driver = KeyDriver(
          PointerListener(
            mouseCursor: MouseCursor.pointer,
            child: SizedBox(
              width: 6,
              height: 1,
              child: TabSelect<int>(
                tabWidth: 4,
                selectedIndex: empty ? 0 : 3,
                showDescription: false,
                showUnderline: false,
                options: empty
                    ? const []
                    : List.generate(
                        4,
                        (index) => SelectOption(name: '$index', value: index),
                      ),
                onSelect: (index, _) => selected = index,
              ),
            ),
          ),
        );
        await driver.ready();
        await driver.sendMouse(move(1));
        expect(
          driver.app.buildOwner.mouseCursor,
          empty ? MouseCursor.basic : MouseCursor.pointer,
        );
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 1,
            y: 0,
          ),
        );
        expect(selected, empty ? -1 : 3);
        driver.dispose();
      }
    },
  );

  test('standalone RenderSelect remains noninteractive', () {
    final render = RenderSelect<int>(
      options: const [SelectOption(name: 'One', value: 1)],
      highlighted: 0,
      scrollOffset: 0,
      visibleRows: 1,
      showScrollIndicator: false,
      color: Color.white,
      backgroundColor: null,
      selectedBackgroundColor: Color.black,
      selectedTextColor: Color.white,
      descriptionColor: Color.white,
    );
    render.performBoxLayout(const BoxConstraints.tight(width: 8, height: 1));
    final result = HitTestResult();
    expect(render.hitTest(result, const Offset(1, 0)), isFalse);
    expect(result.path, isEmpty);
    expect(render.mouseCursorAt(const Offset(1, 0)), isNull);
  });

  test(
    'empty Select masks an ancestor hand and never confirms blank rows',
    () async {
      var confirmations = 0;
      final driver = KeyDriver(
        PointerListener(
          mouseCursor: MouseCursor.pointer,
          child: SizedBox(
            width: 12,
            height: 3,
            child: Select<int>(
              options: const [],
              height: 3,
              onSelect: (_, _) => confirmations++,
            ),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      await driver.sendMouse(move(1));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 0,
        ),
      );
      expect(confirmations, 0);
    },
  );

  test(
    'Select advertises only painted option rows and still confirms clicks',
    () async {
      var selected = -1;
      final driver = KeyDriver(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 12,
            height: 5,
            child: Select<int>(
              height: 4,
              options: const [
                SelectOption(name: 'One', value: 1),
                SelectOption(name: 'Two', value: 2),
              ],
              onSelect: (index, option) => selected = index,
            ),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      for (final row in [0, 1, 2, 4]) {
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.move,
            button: MouseButton.left,
            x: 1,
            y: row,
          ),
        );
        expect(
          driver.app.buildOwner.mouseCursor,
          row < 2 ? MouseCursor.pointer : MouseCursor.basic,
          reason: 'row $row',
        );
      }
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 1,
        ),
      );
      expect(selected, 1);
    },
  );

  test('Select cursor follows constrained scrolled option viewport', () async {
    var selected = -1;
    final driver = KeyDriver(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 12,
          height: 2,
          child: Select<int>(
            height: 6,
            autofocus: true,
            selectedIndex: 4,
            options: List.generate(
              6,
              (index) => SelectOption(name: 'Row $index', value: index),
            ),
            onSelect: (index, option) => selected = index,
          ),
        ),
      ),
    );
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendLogicalKey(LogicalKeyboardKey.end);
    driver.app.debugFlushFrame();
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.move,
        button: MouseButton.left,
        x: 1,
        y: 1,
      ),
    );
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 1,
        y: 1,
      ),
    );
    expect(selected, 5);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.move,
        button: MouseButton.left,
        x: 1,
        y: 2,
      ),
    );
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
  });

  test(
    'cursor metadata works without callbacks and clears outside bounds',
    () async {
      final driver = KeyDriver(
        const Align(
          alignment: Alignment.topLeft,
          child: PointerListener(
            mouseCursor: MouseCursor.pointer,
            child: SizedBox(width: 4, height: 1),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      await driver.sendMouse(move(1));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
      await driver.sendMouse(move(6));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
    },
  );

  test('unannotated inner listener defers; explicit basic overrides', () async {
    for (final inner in [null, MouseCursor.basic, MouseCursor.text]) {
      final driver = KeyDriver(
        PointerListener(
          mouseCursor: MouseCursor.pointer,
          child: PointerListener(
            mouseCursor: inner,
            onPointerDown: (event) => event.consume(),
            child: const SizedBox(width: 4, height: 1),
          ),
        ),
      );
      await driver.ready();
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 0,
        ),
      );
      expect(driver.app.buildOwner.mouseCursor, inner ?? MouseCursor.pointer);
      driver.dispose();
    }
  });

  for (final multiline in [false, true]) {
    test(
      'text cursor preserves ${multiline ? 'multiline' : 'single-line'} editing',
      () async {
        final controller = TextEditingController(text: 'abc');
        final driver = KeyDriver(
          SizedBox(
            width: 12,
            height: 3,
            child: multiline
                ? TextArea(controller: controller, height: 3)
                : TextInput(controller: controller),
          ),
        );
        addTearDown(() {
          driver.dispose();
          controller.dispose();
        });
        await driver.ready();
        await driver.sendMouse(move(1));
        expect(driver.app.buildOwner.mouseCursor, MouseCursor.text);
        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 1,
            y: 0,
          ),
        );
        await driver.sendCharacter('X');
        driver.app.debugFlushFrame();
        expect(controller.text, 'abcX');
        expect(driver.app.buildOwner.mouseCursor, MouseCursor.text);
      },
    );
  }

  test(
    'modal barrier replaces underlying hand and closing restores it without movement',
    () async {
      final modal = ModalController();
      var presses = 0;
      final driver = KeyDriver(
        Modal(
          controller: modal,
          modalBuilder: (context) => const SizedBox(width: 10, height: 3),
          child: Align(
            alignment: Alignment.topLeft,
            child: Button(label: 'Open', onPressed: () => presses++),
          ),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      await driver.sendMouse(move(1));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
      modal.open();
      driver.app.debugFlushFrame();
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 1,
          y: 0,
        ),
      );
      expect(presses, 0);
      modal.close();
      driver.app.debugFlushFrame();
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
    },
  );

  test('clipped clickable overflow does not advertise a hand', () async {
    final driver = KeyDriver(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 3,
          height: 1,
          child: Stack(
            children: [
              Positioned(
                left: 1,
                width: 8,
                height: 1,
                child: Button(label: 'Overflow', onPressed: () {}),
              ),
            ],
          ),
        ),
      ),
    );
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendMouse(move(2));
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
    await driver.sendMouse(move(3));
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
  });

  test(
    'app-consumed movement still clears a hand after leaving the button',
    () async {
      final driver = KeyDriver(
        Align(
          alignment: Alignment.topLeft,
          child: Button(label: 'Go', onPressed: () {}),
        ),
      );
      addTearDown(driver.dispose);
      await driver.ready();
      await driver.sendMouse(move(1));
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
      final subscription = driver.app.inputManager.dispatcher.onMouse(
        (event) => event.consume(),
        priority: InputPriority.app,
      );
      addTearDown(subscription.cancel);
      await driver.sendMouse(move(20));
      driver.app.debugFlushFrame();
      expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
    },
  );

  test('button disabling under stationary pointer refreshes shape', () async {
    var presses = 0;
    final driver = KeyDriver(_DisablingButton(onPressed: () => presses++));
    addTearDown(driver.dispose);
    await driver.ready();
    await driver.sendMouse(move(1));
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.pointer);
    await driver.sendMouse(
      MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 1,
        y: 0,
      ),
    );
    driver.app.debugFlushFrame();
    expect(presses, 1);
    expect(driver.app.buildOwner.mouseCursor, MouseCursor.basic);
  });
}

class _DisablingButton extends StatefulWidget {
  const _DisablingButton({required this.onPressed});
  final VoidCallback onPressed;
  @override
  State<_DisablingButton> createState() => _DisablingButtonState();
}

class _DisablingButtonState extends State<_DisablingButton> {
  bool enabled = true;
  @override
  Widget build(BuildContext context) => Button(
    label: 'Go',
    onPressed: enabled
        ? () {
            widget.onPressed();
            setState(() => enabled = false);
          }
        : null,
  );
}
