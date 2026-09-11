// ignore_for_file: invalid_use_of_visible_for_testing_member, invalid_use_of_internal_member
import 'package:noir/noir.dart';
import 'package:noir/src/core/input.dart'
    show InputManagerKernelAccess, InputPriority;
import 'package:test/test.dart';
import '../helpers/key_driver.dart';

MouseEvent move(int x) =>
    MouseEvent(type: MouseEventType.move, button: MouseButton.left, x: x, y: 0);

void main() {
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
