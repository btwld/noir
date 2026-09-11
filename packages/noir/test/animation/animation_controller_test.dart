import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('AnimationController', () {
    test('forward and reverse complete with expected values', () async {
      final owner = BuildOwner();
      owner.setFrameCallback(() {});

      final key = GlobalKey<_AnimationHostState>();
      final host = _AnimationHost(key: key);
      final element = host.createElement();

      element.mount(null, owner);
      final state = key.currentState!;
      final controller = state.controller;

      final values = <double>[];
      final statuses = <AnimationStatus>[];
      controller
        ..addListener(() => values.add(controller.value))
        ..addStatusListener(statuses.add);

      final forwardFuture = controller.forward(from: 0);
      owner.handleBeginFrame(Duration.zero);
      owner.handleBeginFrame(const Duration(milliseconds: 50));
      owner.handleBeginFrame(const Duration(milliseconds: 100));

      await forwardFuture;
      expect(controller.status, AnimationStatus.completed);
      expect(controller.value, closeTo(1.0, 1e-6));

      final reverseFuture = controller.reverse();
      owner.handleBeginFrame(Duration.zero);
      owner.handleBeginFrame(const Duration(milliseconds: 50));
      owner.handleBeginFrame(const Duration(milliseconds: 100));

      await reverseFuture;
      expect(controller.status, AnimationStatus.dismissed);
      expect(controller.value, closeTo(0.0, 1e-6));

      expect(values, isNotEmpty);
      expect(statuses.contains(AnimationStatus.forward), isTrue);
      expect(statuses.contains(AnimationStatus.completed), isTrue);
      expect(statuses.contains(AnimationStatus.reverse), isTrue);
      expect(statuses.contains(AnimationStatus.dismissed), isTrue);

      element.unmount();
    });
  });
}

class _AnimationHost extends StatefulWidget {
  const _AnimationHost({super.key});

  @override
  State<_AnimationHost> createState() => _AnimationHostState();
}

class _AnimationHostState extends State<_AnimationHost>
    with SingleTickerProviderStateMixin<_AnimationHost> {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container();
}
