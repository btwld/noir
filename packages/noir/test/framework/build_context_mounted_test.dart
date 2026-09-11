import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('BuildContext.mounted', () {
    test('is true while built and false once the element is unmounted', () {
      final owner = BuildOwner();
      final probe = _ContextProbeWidget();
      final element = probe.createElement();

      element.mount(null, owner);
      final context = probe.capturedContext!;

      expect(context.mounted, isTrue);

      element.unmount();

      expect(
        context.mounted,
        isFalse,
        reason: 'a captured context reports that its element is gone',
      );
      expect(
        probe.mountedDuringDispose,
        isFalse,
        reason:
            'the element leaves the tree before dispose() runs; State.mounted '
            'is the one that stays true for the whole call',
      );
    });

    test('reports a deactivated-but-not-finalized element as mounted', () {
      final owner = BuildOwner();
      final probe = _ContextProbeWidget();
      final root = _SwapRootWidget(child: probe).createElement();

      root.mount(null, owner);
      final context = probe.capturedContext!;
      expect(context.mounted, isTrue);

      // Reconciliation removes the probe; it is inactive but still mounted
      // until the build pass finalizes.
      root.update(const _SwapRootWidget(child: SizedBox(width: 1, height: 1)));
      expect(context.element.active, isFalse);
      expect(context.mounted, isTrue);

      owner.buildScope();

      expect(context.mounted, isFalse);
      root.unmount();
    });
  });
}

class _SwapRootWidget extends StatelessWidget {
  const _SwapRootWidget({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _ContextProbeWidget extends StatefulWidget {
  _ContextProbeWidget();

  BuildContext? capturedContext;
  bool? mountedDuringDispose;

  @override
  State<_ContextProbeWidget> createState() => _ContextProbeState();
}

class _ContextProbeState extends State<_ContextProbeWidget> {
  @override
  Widget build(BuildContext context) {
    widget.capturedContext = context;
    return const SizedBox(width: 1, height: 1);
  }

  @override
  void dispose() {
    widget.mountedDuringDispose = context.mounted;
    super.dispose();
  }
}
