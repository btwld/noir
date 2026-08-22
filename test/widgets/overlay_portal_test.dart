import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/rendering/overlay.dart';
import 'package:noir/src/widgets/overlay.dart'
    show RootOverlay, rawOverlayPortal;
import 'package:test/test.dart';

import '../helpers/key_driver.dart';
import '../helpers/test_element_host.dart';

void main() {
  test('hidden overlay builder is not invoked', () {
    var builds = 0;
    final controller = OverlayPortalController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: OverlayPortal(
            controller: controller,
            overlayChildBuilder: (context) {
              builds++;
              return const Text('overlay');
            },
            child: const Text('child'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      expect(builds, 0);
      expect(controller.isShowing, isFalse);
    } finally {
      host.dispose();
    }
  });

  test('show builds a fresh overlay; hide destroys it; show rebuilds', () {
    final states = <_ProbeState>[];
    final controller = OverlayPortalController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: OverlayPortal(
            controller: controller,
            overlayChildBuilder: (context) => _Probe(states: states),
            child: const Text('child'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      controller.show();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      expect(controller.isShowing, isTrue);
      expect(states, hasLength(1));
      expect(states.single.mounted, isTrue);
      final first = states.single;

      controller.hide();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      expect(controller.isShowing, isFalse);
      expect(first.mounted, isFalse);
      expect(first.disposeCount, 1);

      controller.show();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      expect(states, hasLength(2));
      expect(states.last.mounted, isTrue);
      expect(identical(states.first, states.last), isFalse);
    } finally {
      host.dispose();
    }
  });

  test('overlay child is a logical descendant of the portal', () {
    BuildContext? overlayContext;
    Element? portalElement;
    final controller = OverlayPortalController()..show();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: OverlayPortal(
            controller: controller,
            overlayChildBuilder: (context) {
              overlayContext = context;
              return const Text('overlay');
            },
            child: const Text('child'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      void visit(Element element) {
        if (element.widget is OverlayPortal) {
          portalElement = element;
        }
        element.visitChildren(visit);
      }

      visit(host.root!);
      expect(portalElement, isNotNull);
      expect(overlayContext, isNotNull);
      var ancestor = overlayContext!.element.parent;
      var foundPortal = false;
      while (ancestor != null) {
        if (identical(ancestor, portalElement)) {
          foundPortal = true;
          break;
        }
        ancestor = ancestor.parent;
      }
      expect(foundPortal, isTrue);
    } finally {
      host.dispose();
    }
  });

  test(
    'overlay resolves Theme, Actions, and focus ancestry through the portal',
    () {
      Color? resolved;
      Action<Intent>? action;
      final outerFocus = FocusNode(debugLabel: 'outer');
      final overlayFocus = FocusNode(debugLabel: 'overlay');
      final activate = CallbackAction<ActivateIntent>(
        (intent, context) => KeyEventResult.handled,
      );
      final controller = OverlayPortalController()..show();
      final host = TestElementHost()
        ..mount(
          RootOverlay(
            child: Theme(
              data: ThemeData.dark.copyWith(text: Color.red),
              child: Actions(
                actions: <Type, Action<Intent>>{ActivateIntent: activate},
                child: Focus(
                  focusNode: outerFocus,
                  child: OverlayPortal(
                    controller: controller,
                    overlayChildBuilder: (context) {
                      resolved = Theme.of(context).text;
                      action = Actions.maybeFind(context, ActivateIntent);
                      return Focus(
                        focusNode: overlayFocus,
                        child: const Text('overlay'),
                      );
                    },
                    child: const Text('child'),
                  ),
                ),
              ),
            ),
          ),
        )
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 20, height: 6),
        );

      try {
        expect(resolved, Color.red);
        expect(action, same(activate));
        expect(overlayFocus.parent, same(outerFocus));
      } finally {
        host.dispose();
        outerFocus.dispose();
        overlayFocus.dispose();
      }
    },
  );

  test('unattached show is pending until the next valid attachment', () {
    final controller = OverlayPortalController()..show();
    expect(controller.isShowing, isTrue);
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: OverlayPortal(
            controller: controller,
            overlayChildBuilder: (context) => const Text('overlay'),
            child: const Text('child'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
    try {
      expect(controller.isShowing, isTrue);
      expect(_findText(host.root!, 'overlay'), isTrue);
    } finally {
      host.dispose();
    }
  });

  test('duplicate controller attachment throws before changing either', () {
    final controller = OverlayPortalController();
    final host = TestElementHost();
    Object? error;
    try {
      host.mount(
        RootOverlay(
          child: Column(
            children: [
              OverlayPortal(
                controller: controller,
                overlayChildBuilder: (context) => const Text('a'),
                child: const Text('one'),
              ),
              OverlayPortal(
                controller: controller,
                overlayChildBuilder: (context) => const Text('b'),
                child: const Text('two'),
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
      expect(controller.isShowing, isFalse);
    } finally {
      host.dispose();
    }
  });

  test('mounting OverlayPortal without the root overlay throws', () {
    final host = TestElementHost();
    Object? error;
    try {
      host.mount(
        OverlayPortal(
          controller: OverlayPortalController(),
          overlayChildBuilder: (context) => const Text('overlay'),
          child: const Text('child'),
        ),
      );
    } on Object catch (caught) {
      error = caught;
    }
    try {
      expect(error, isA<StateError>());
      expect('$error', contains('root overlay'));
    } finally {
      host.dispose();
    }
  });

  test('show on an already-shown portal moves that identity to the top', () {
    final first = OverlayPortalController();
    final second = OverlayPortalController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: Column(
            children: [
              OverlayPortal(
                controller: first,
                overlayChildBuilder: (context) => const Text('first'),
                child: const Text('a'),
              ),
              OverlayPortal(
                controller: second,
                overlayChildBuilder: (context) => const Text('second'),
                child: const Text('b'),
              ),
            ],
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      first.show();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      final overlay = _findOverlay(host.root!);
      final firstEntry = overlay.entries.single;

      second.show();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      expect(overlay.entries.first, same(firstEntry));
      final secondEntry = overlay.entries.last;

      first.show();
      host.pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );
      expect(overlay.entries, [same(secondEntry), same(firstEntry)]);
    } finally {
      host.dispose();
    }
  });

  test('rebuilds do not reorder shown entries', () {
    final first = OverlayPortalController()..show();
    final second = OverlayPortalController()..show();
    final host = TestElementHost()
      ..mount(_LabeledPortals(label: 'one', first: first, second: second))
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      final overlay = _findOverlay(host.root!);
      final snapshot = List<RenderBox>.from(overlay.entries);
      expect(snapshot, hasLength(2));

      host
        ..update(_LabeledPortals(label: 'two', first: first, second: second))
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 20, height: 6),
        );

      expect(overlay.entries, [same(snapshot[0]), same(snapshot[1])]);
    } finally {
      host.dispose();
    }
  });

  test('replacing the controller does not transfer visibility', () {
    final states = <_ProbeState>[];
    final first = OverlayPortalController()..show();
    final second = OverlayPortalController();
    final host = TestElementHost()
      ..mount(
        RootOverlay(
          child: OverlayPortal(
            controller: first,
            overlayChildBuilder: (context) => _Probe(states: states),
            child: const Text('child'),
          ),
        ),
      )
      ..pumpFrame(
        constraints: const BoxConstraints.tight(width: 20, height: 6),
      );

    try {
      expect(states, hasLength(1));
      host
        ..update(
          RootOverlay(
            child: OverlayPortal(
              controller: second,
              overlayChildBuilder: (context) => _Probe(states: states),
              child: const Text('child'),
            ),
          ),
        )
        ..pumpFrame(
          constraints: const BoxConstraints.tight(width: 20, height: 6),
        );

      expect(first.isShowing, isFalse);
      expect(second.isShowing, isFalse);
      expect(states.single.disposeCount, 1);
      expect(_findText(host.root!, 'probe'), isFalse);
    } finally {
      host.dispose();
    }
  });

  test('a malformed overlay entry root is rejected before adoption', () {
    final host = TestElementHost();
    Object? error;
    try {
      host.mount(
        RootOverlay(
          child: rawOverlayPortal(
            controller: OverlayPortalController()..show(),
            overlayChildBuilder: (context) => const _NonBoxLeaf(),
            child: const Text('child'),
          ),
        ),
      );
    } on Object catch (caught) {
      error = caught;
    }
    try {
      expect(error, isA<StateError>());
      expect('$error', contains('RenderBox wrapper'));
    } finally {
      host.dispose();
    }
  });

  test('KeyDriver OverlayPortal still has the runTuiApp host', () async {
    final controller = OverlayPortalController()..show();
    final driver = KeyDriver(
      OverlayPortal(
        controller: controller,
        overlayChildBuilder: (context) => const Text('hosted'),
        child: const Text('child'),
      ),
    );
    await driver.ready();
    try {
      expect(controller.isShowing, isTrue);
    } finally {
      driver.dispose();
    }
  });
}

RenderOverlay _findOverlay(Element root) {
  RenderOverlay? overlay;
  void visit(Element element) {
    if (element is RenderObjectElement &&
        element.renderObject is RenderOverlay) {
      overlay = element.renderObject! as RenderOverlay;
    }
    element.visitChildren(visit);
  }

  visit(root);
  expect(overlay, isNotNull);
  return overlay!;
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

class _LabeledPortals extends StatelessWidget {
  const _LabeledPortals({
    required this.label,
    required this.first,
    required this.second,
  });

  final String label;
  final OverlayPortalController first;
  final OverlayPortalController second;

  @override
  Widget build(BuildContext context) => RootOverlay(
    child: Column(
      children: [
        Text(label),
        OverlayPortal(
          controller: first,
          overlayChildBuilder: (context) => const Text('first'),
          child: const Text('a'),
        ),
        OverlayPortal(
          controller: second,
          overlayChildBuilder: (context) => const Text('second'),
          child: const Text('b'),
        ),
      ],
    ),
  );
}

class _Probe extends StatefulWidget {
  const _Probe({required this.states});

  final List<_ProbeState> states;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int disposeCount = 0;

  @override
  void initState() {
    super.initState();
    widget.states.add(this);
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('probe');
}

class _NonBoxLeaf extends RenderObjectWidget {
  const _NonBoxLeaf();

  @override
  RenderObject createRenderObject(BuildContext context) => _BareRenderObject();
}

final class _BareRenderObject extends RenderObject {
  @override
  void performLayout(Constraints constraints) {
    width = constraints.maxWidth ?? 0;
    height = constraints.maxHeight ?? 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}
