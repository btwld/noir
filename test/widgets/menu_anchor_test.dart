import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/rendering/overlay.dart';
import 'package:noir/src/widgets/overlay.dart' show RootOverlay;
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('open throws when the controller is not attached', () {
    expect(
      () => MenuController().open(),
      throwsA(
        isA<StateError>().having(
          (error) => '$error',
          'message',
          contains('before the controller was attached'),
        ),
      ),
    );
  });

  test('close while detached is a no-op', () {
    expect(MenuController().close, returnsNormally);
  });

  test('closed to open fires onOpen once and already-open open does not', () {
    var opens = 0;
    var closes = 0;
    final controller = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            controller: controller,
            onOpen: () => opens++,
            onClose: () => closes++,
            menuChildren: const [Text('item')],
            child: const Text('Open'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      controller.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(controller.isOpen, isTrue);
      expect(opens, 1);

      controller.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(opens, 1);
      expect(closes, 0);

      controller.close();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(controller.isOpen, isFalse);
      expect(closes, 1);
    } finally {
      host.dispose();
    }
  });

  test('throwing transition callbacks do not interrupt menu state cleanup', () {
    final openError = StateError('open callback failed');
    final closeError = StateError('close callback failed');
    final controller = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            controller: controller,
            onOpen: () {
              expect(controller.isOpen, isTrue);
              throw openError;
            },
            onClose: () {
              expect(controller.isOpen, isFalse);
              throw closeError;
            },
            menuChildren: const [Text('item')],
            child: const Text('Open'),
          ),
        ),
      );

    try {
      expect(controller.open, throwsA(same(openError)));
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(controller.isOpen, isTrue);
      expect(_findText(host.root!, 'item'), isTrue);

      expect(controller.close, throwsA(same(closeError)));
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(controller.isOpen, isFalse);
      expect(_findText(host.root!, 'item'), isFalse);
    } finally {
      host.dispose();
    }
  });

  test('controller replace preserves open state without callbacks', () {
    var opens = 0;
    var closes = 0;
    final first = MenuController();
    final second = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            controller: first,
            onOpen: () => opens++,
            onClose: () => closes++,
            menuChildren: const [Text('item')],
            child: const Text('Open'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      first.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(opens, 1);

      host
        ..update(
          RootOverlay(
            child: MenuAnchor(
              controller: second,
              onOpen: () => opens++,
              onClose: () => closes++,
              menuChildren: const [Text('item')],
              child: const Text('Open'),
            ),
          ),
        )
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 40, height: 12),
        );

      expect(first.isOpen, isFalse);
      expect(second.isOpen, isTrue);
      expect(opens, 1);
      expect(closes, 0);
      expect(_findText(host.root!, 'item'), isTrue);
    } finally {
      host.dispose();
    }
  });

  test('teardown while open skips onClose', () {
    var closes = 0;
    final controller = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            controller: controller,
            onClose: () => closes++,
            menuChildren: const [Text('item')],
            child: const Text('Open'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      controller.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
    } finally {
      host.dispose();
    }

    expect(closes, 0);
    expect(controller.isOpen, isFalse);
  });

  test(
    'internal controller opens below the launcher and closes on Escape',
    () async {
      final driver = KeyDriver(
        MenuAnchor(
          menuChildren: const [Text('item-a')],
          builder: (context, controller, child) => Button(
            label: 'Open',
            autofocus: true,
            onPressed: () => controller.open(),
          ),
        ),
        paintFrames: true,
        width: 40,
        height: 12,
      );
      try {
        await driver.ready();
        await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
        await driver.ready();
        driver.app.debugFlushFrame();
        expect(
          CapturedBuffer.fromBuffer(
            driver.app.renderer!.debugCurrentBuffer,
          ).toText(),
          contains('item-a'),
        );
        await driver.sendLogicalKey(LogicalKeyboardKey.escape);
        await driver.ready();
        driver.app.debugFlushFrame();
        expect(
          CapturedBuffer.fromBuffer(
            driver.app.renderer!.debugCurrentBuffer,
          ).toText(),
          isNot(contains('item-a')),
        );
      } finally {
        driver.dispose();
      }
    },
  );

  test('Tab closes an open menu without advancing focus', () async {
    final launcher = FocusNode(debugLabel: 'launcher');
    final after = FocusNode(debugLabel: 'after');
    final controller = MenuController();
    final driver = KeyDriver(
      Column(
        children: [
          MenuAnchor(
            controller: controller,
            childFocusNode: launcher,
            menuChildren: const [Text('item-a')],
            child: Button(
              label: 'Open',
              focusNode: launcher,
              autofocus: true,
              onPressed: controller.open,
            ),
          ),
          Button(label: 'Next', focusNode: after, onPressed: () {}),
        ],
      ),
    );
    try {
      await driver.ready();
      controller.open();
      await driver.ready();
      driver.app.debugFlushFrame();
      expect(controller.isOpen, isTrue);

      await driver.sendLogicalKey(LogicalKeyboardKey.tab);
      await driver.ready();
      expect(controller.isOpen, isFalse);
      expect(launcher.hasFocus, isTrue);
      expect(after.hasFocus, isFalse);

      controller.open();
      await driver.ready();
      await driver.sendLogicalKey(
        LogicalKeyboardKey.tab,
        modifiers: KeyModifiers.shift,
      );
      await driver.ready();
      expect(controller.isOpen, isFalse);
      expect(launcher.hasFocus, isTrue);
      expect(after.hasFocus, isFalse);
    } finally {
      driver.dispose();
      launcher.dispose();
      after.dispose();
    }
  });

  test('independent anchors do not form a group', () {
    final first = MenuController();
    final second = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: Column(
            children: [
              MenuAnchor(
                controller: first,
                menuChildren: const [Text('one')],
                child: const Text('a'),
              ),
              MenuAnchor(
                controller: second,
                menuChildren: const [Text('two')],
                child: const Text('b'),
              ),
            ],
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      first.open();
      second.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(first.isOpen, isTrue);
      expect(second.isOpen, isTrue);
    } finally {
      host.dispose();
    }
  });

  test('outside left-down closes only the topmost open menu', () {
    final first = MenuController();
    final second = MenuController();
    final app = createTuiTestApp(
      Column(
        children: [
          MenuAnchor(
            controller: first,
            menuChildren: const [Text('first-menu')],
            child: const Text('first-child'),
          ),
          MenuAnchor(
            controller: second,
            menuChildren: const [Text('second-menu')],
            child: const Text('second-child'),
          ),
        ],
      ),
      width: 30,
      height: 8,
    );

    try {
      app.pumpFrame();
      first.open();
      second.open();
      app.pumpFrame();

      app.mockMouse.pressDown(20, 7);
      app.pumpFrame();
      expect(first.isOpen, isTrue);
      expect(second.isOpen, isFalse);

      app.mockMouse.pressDown(20, 7);
      app.pumpFrame();
      expect(first.isOpen, isFalse);
    } finally {
      app.dispose();
    }
  });

  test('MenuController.maybeOf does not register a dependency', () {
    MenuController? found;
    Element? lookupElement;
    var builds = 0;
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            menuChildren: const [Text('item')],
            builder: (context, controller, child) {
              builds++;
              lookupElement = context.element;
              found = MenuController.maybeOf(context);
              return const Text('launcher');
            },
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
    try {
      expect(found, isNotNull);
      expect(builds, 1);
      var ancestor = lookupElement!.parent;
      while (ancestor != null) {
        if (ancestor is InheritedElement) ancestor.notifyDependents();
        ancestor = ancestor.parent;
      }
      host.pumpBuild();
      expect(builds, 1);
    } finally {
      host.dispose();
    }
  });

  test('menu opens below the launcher and follows a same-frame resize', () {
    final controller = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: Align(
            alignment: Alignment.topRight,
            child: MenuAnchor(
              controller: controller,
              menuChildren: const [
                SizedBox(width: 3, height: 2, child: Text('m')),
              ],
              child: const SizedBox(width: 4, height: 1, child: Text('Open')),
            ),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      controller.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      final first = _menuOrigin(host.root!);
      expect(first, const Offset(36, 1));

      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 8),
      );
      final second = _menuOrigin(host.root!);
      expect(second, const Offset(16, 1));
      expect(controller.isOpen, isTrue);
    } finally {
      host.dispose();
    }
  });

  test('paint and hit testing share the anchored menu origin', () {
    final controller = MenuController();
    final app = createTuiTestApp(
      MenuAnchor(
        controller: controller,
        menuChildren: const [Text('item-a')],
        child: const SizedBox(width: 4, height: 1, child: Text('Open')),
      ),
      width: 20,
      height: 6,
    );

    try {
      app.pumpFrame();
      controller.open();
      app.pumpFrame();

      final menu = app.captureFrame().findText('item-a').single;
      expect(menu, const BufferPosition(0, 1));

      app.mockMouse.pressDown(menu.x, menu.y);
      app.pumpFrame();
      expect(controller.isOpen, isTrue);
    } finally {
      app.dispose();
    }
  });

  test('explicit open position ignores alignmentOffset', () {
    final controller = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: MenuAnchor(
            controller: controller,
            alignmentOffset: const Offset(8, 3),
            menuChildren: const [
              SizedBox(width: 2, height: 1, child: Text('m')),
            ],
            child: const SizedBox(width: 4, height: 1, child: Text('Open')),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );

    try {
      controller.open(position: Offset.zero);
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 40, height: 12),
      );
      expect(_menuOrigin(host.root!), Offset.zero);
    } finally {
      host.dispose();
    }
  });

  test(
    'outside left-down closes; other outside pointer events do not',
    () async {
      final controller = MenuController();
      var underlying = 0;
      final observed = <MouseEventType>[];
      final driver = KeyDriver(
        Stack(
          children: [
            PointerListener(
              onPointerDown: (event) => underlying++,
              child: const SizedBox(width: 40, height: 12),
            ),
            MenuAnchor(
              controller: controller,
              menuChildren: const [Text('item-a')],
              child: const SizedBox(width: 4, height: 1, child: Text('Open')),
            ),
          ],
        ),
        paintFrames: true,
        width: 40,
        height: 12,
      );
      final subscription = driver.app.inputManager.onMouse((event) {
        observed.add(event.type);
      }, priority: InputPriority.app);
      try {
        await driver.ready();
        controller.open();
        await driver.ready();
        driver.app.debugFlushFrame();
        expect(controller.isOpen, isTrue);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.move,
            button: MouseButton.left,
            x: 20,
            y: 10,
          ),
        );
        expect(controller.isOpen, isTrue);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.right,
            x: 20,
            y: 10,
          ),
        );
        expect(controller.isOpen, isTrue);
        expect(underlying, 0);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.middle,
            x: 20,
            y: 10,
          ),
        );
        expect(controller.isOpen, isTrue);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.up,
            button: MouseButton.left,
            x: 20,
            y: 10,
          ),
        );
        expect(controller.isOpen, isTrue);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.scroll,
            button: MouseButton.middle,
            x: 20,
            y: 10,
            scroll: MouseScroll(direction: MouseScrollDirection.down),
          ),
        );
        expect(controller.isOpen, isTrue);
        expect(underlying, 0);

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 20,
            y: 10,
          ),
        );
        await driver.ready();
        expect(controller.isOpen, isFalse);
        expect(underlying, 0);
        expect(observed, isNotEmpty);
      } finally {
        subscription.cancel();
        driver.dispose();
      }
    },
  );

  test('duplicate MenuController attachment throws before changing either', () {
    final controller = MenuController();
    final host = TestElementHost();
    Object? error;
    try {
      host.mount(
        RootOverlay(
          child: Column(
            children: [
              MenuAnchor(
                controller: controller,
                menuChildren: const [Text('one')],
                child: const Text('a'),
              ),
              MenuAnchor(
                controller: controller,
                menuChildren: const [Text('two')],
                child: const Text('b'),
              ),
            ],
          ),
        ),
      );
    } on Object catch (caught) {
      error = caught;
    }
    try {
      expect(error, isA<StateError>());
      expect('$error', contains('already attached'));
    } finally {
      host.dispose();
    }
  });

  test('failed controller replacement preserves both live attachments', () {
    final first = MenuController();
    final occupied = MenuController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: Column(
            children: [
              MenuAnchor(
                controller: first,
                menuChildren: const [Text('first-menu')],
                child: const Text('first-child'),
              ),
              MenuAnchor(
                controller: occupied,
                menuChildren: const [Text('second-menu')],
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
                MenuAnchor(
                  controller: occupied,
                  menuChildren: const [Text('invalid')],
                  child: const Text('first-child'),
                ),
                MenuAnchor(
                  controller: occupied,
                  menuChildren: const [Text('second-menu')],
                  child: const Text('second-child'),
                ),
              ],
            ),
          ),
        ),
        throwsStateError,
      );

      first.open();
      occupied.open();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 30, height: 8),
      );

      expect(first.isOpen, isTrue);
      expect(occupied.isOpen, isTrue);
      expect(_findText(host.root!, 'first-menu'), isTrue);
      expect(_findText(host.root!, 'second-menu'), isTrue);
    } finally {
      host.dispose();
    }
  });
}

Offset _menuOrigin(Element root) {
  RenderOverlayEntry? entry;
  void visit(Element element) {
    if (element is RenderObjectElement &&
        element.renderObject is RenderOverlayEntry) {
      entry = element.renderObject! as RenderOverlayEntry;
    }
    element.visitChildren(visit);
  }

  visit(root);
  expect(entry, isNotNull);
  final child = entry!.child;
  expect(child, isA<RenderBox>());
  final box = child! as RenderBox;
  return Offset(box.x, box.y);
}

bool _findText(Element root, String value) {
  var found = false;
  void visit(Element element) {
    final widget = element.widget;
    if (widget is Text && widget.data == value) {
      found = true;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found;
}
