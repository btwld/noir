import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/widgets/overlay.dart'
    show RootOverlay, rawOverlayPortal;

import '../helpers/test_element_host.dart';

/// Assertions-disabled probe for overlay and menu validation.
void main() {
  _expectState('missing-host', () {
    final host = TestElementHost();
    try {
      host.mount(
        OverlayPortal(
          controller: OverlayPortalController(),
          overlayChildBuilder: (context) => const Text('overlay'),
          child: const Text('child'),
        ),
      );
    } finally {
      _disposeQuietly(host);
    }
  });

  _expectState('duplicate-portal-controller', () {
    final controller = OverlayPortalController();
    final host = TestElementHost();
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
    } finally {
      _disposeQuietly(host);
    }
  });

  _expectState('malformed-entry', () {
    final host = TestElementHost();
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
    } finally {
      _disposeQuietly(host);
    }
  });

  _expectState('duplicate-menu-controller', () {
    final controller = MenuController();
    final host = TestElementHost();
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
    } finally {
      _disposeQuietly(host);
    }
  });

  _expectState('detached-menu-open', () {
    MenuController().open();
  });

  _expectArgument('negative-reserved-padding', () {
    final host = TestElementHost();
    try {
      host.mount(
        RootOverlay(
          child: MenuAnchor(
            reservedPadding: EdgeInsets(left: 0 - 1),
            menuChildren: const [Text('item')],
            child: const Text('Open'),
          ),
        ),
      );
    } finally {
      _disposeQuietly(host);
    }
  });
}

void _expectState(String label, void Function() body) {
  var threw = false;
  try {
    body();
  } catch (error) {
    if (error is! StateError) {
      rethrow;
    }
    threw = true;
  }
  if (!threw) {
    throw StateError('UNEXPECTED_SUCCESS:$label');
  }
  print('PASS:$label');
}

void _expectArgument(String label, void Function() body) {
  var threw = false;
  try {
    body();
  } catch (error) {
    if (error is! ArgumentError) {
      rethrow;
    }
    threw = true;
  }
  if (!threw) {
    throw StateError('UNEXPECTED_SUCCESS:$label');
  }
  print('PASS:$label');
}

void _disposeQuietly(TestElementHost host) {
  try {
    host.dispose();
  } catch (_) {}
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
