import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';

void main() {
  test('runTuiApp installs the root overlay host', () async {
    final controller = OverlayPortalController()..show();
    final driver = KeyDriver(
      OverlayPortal(
        controller: controller,
        overlayChildBuilder: (context) => const Text('hosted'),
        child: const Text('child'),
      ),
    );
    try {
      await driver.ready();
      expect(controller.isShowing, isTrue);
    } finally {
      driver.dispose();
    }
  });

  test('bare TuiBinding.runApp does not install a root overlay', () {
    final binding = TuiBinding(headless: true);
    Object? error;
    try {
      binding.runApp(
        OverlayPortal(
          controller: OverlayPortalController()..show(),
          overlayChildBuilder: (context) => const Text('hosted'),
          child: const Text('child'),
        ),
      );
    } on Object catch (caught) {
      error = caught;
    } finally {
      binding.dispose();
    }
    expect(error, isA<StateError>());
    expect('$error', contains('root overlay'));
  });

  test('non-box custom roots remain valid beneath runTuiApp', () async {
    final driver = KeyDriver(const _NonBoxRoot());
    try {
      await driver.ready();
    } finally {
      driver.dispose();
    }
  });
}

class _NonBoxRoot extends RenderObjectWidget {
  const _NonBoxRoot();

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
