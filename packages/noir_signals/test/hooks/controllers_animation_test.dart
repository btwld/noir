import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

void main() {
  test('text editing controller is retained and disposed', () {
    final host = TestElementHost();
    late TextEditingController controller;
    TextEditingController? firstController;
    var initialText = 'first';

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        controller = useTextEditingController(text: initialText);
        firstController ??= controller;
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(controller.text, 'first');

    controller.text = 'edited';
    initialText = 'second';
    host.update(buildRoot());

    expect(controller, same(firstController));
    expect(controller.text, 'edited');

    host.dispose();
    expect(() => controller.addListener(() {}), throwsA(isA<StateError>()));
  });

  test('focus node updates mutable fields and keys creation-only fields', () {
    final host = TestElementHost();
    KeyEventResult firstHandler(FocusNode _, KeyEvent _) =>
        KeyEventResult.ignored;
    KeyEventResult secondHandler(FocusNode _, KeyEvent _) =>
        KeyEventResult.handled;

    var currentHandler = firstHandler;
    var canRequestFocus = true;
    var debugLabel = 'first';
    var key = 0;
    late FocusNode node;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        node = useFocusNode(
          debugLabel: debugLabel,
          onKeyEvent: currentHandler,
          canRequestFocus: canRequestFocus,
          keys: <Object?>[key],
        );
        return const Container();
      },
    );

    host.mount(buildRoot());
    final firstNode = node;

    currentHandler = secondHandler;
    canRequestFocus = false;
    debugLabel = 'second';
    host.update(buildRoot());

    expect(node, same(firstNode));
    expect(node.debugLabel, 'first');
    expect(node.onKeyEvent, same(secondHandler));
    expect(node.canRequestFocus, isFalse);

    key = 1;
    host.update(buildRoot());

    expect(node, isNot(same(firstNode)));
    expect(node.debugLabel, 'second');
    expect(() => firstNode.addListener(() {}), throwsA(isA<StateError>()));

    host.dispose();
  });

  test('scroll controller uses initial offset only when created', () {
    final host = TestElementHost();
    var initialOffset = 4.0;
    final keys = <Object?>[0];
    late ScrollController controller;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        controller = useScrollController(
          initialOffset: initialOffset,
          keys: keys,
        );
        return const Container();
      },
    );

    host.mount(buildRoot());
    final firstController = controller;
    expect(controller.offset, 4.0);

    initialOffset = 8.0;
    host.update(buildRoot());
    expect(controller, same(firstController));
    expect(controller.offset, 4.0);

    keys[0] = 1;
    host.update(buildRoot());
    expect(controller, isNot(same(firstController)));
    expect(controller.offset, 8.0);

    host.dispose();
  });

  test('viewport controller is owned and keyed', () {
    final host = TestElementHost();
    var key = 0;
    late ViewportController controller;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        controller = useViewportController(
          initialContentExtent: 100,
          initialViewportExtent: 10,
          initialScrollOffset: 20,
          keys: <Object?>[key],
        );
        return const Container();
      },
    );

    host.mount(buildRoot());
    final firstController = controller;
    expect(controller.scrollOffset, 20);

    key = 1;
    host.update(buildRoot());
    expect(controller, isNot(same(firstController)));

    host.dispose();
    expect(() => controller.addListener(() {}), throwsA(isA<StateError>()));
  });

  test(
    'animation controller updates duration and keys creation-only fields',
    () {
      final host = TestElementHost();
      var duration = const Duration(milliseconds: 100);
      var lowerBound = 0.0;
      var initialValue = 0.0;
      var debugLabel = 'first';
      var key = 0;
      late AnimationController controller;
      late double animatedValue;
      var builds = 0;

      Widget buildRoot() => HookBuilder(
        builder: (context) {
          builds++;
          controller = useAnimationController(
            duration: duration,
            lowerBound: lowerBound,
            initialValue: initialValue,
            debugLabel: debugLabel,
            keys: <Object?>[key],
          );
          animatedValue = useAnimation<double>(controller);
          return const Container();
        },
      );

      host.mount(buildRoot());
      final firstController = controller;

      controller.value = 0.5;
      host.pumpBuild();
      expect(builds, 2);
      expect(animatedValue, 0.5);

      duration = const Duration(milliseconds: 250);
      lowerBound = -1.0;
      initialValue = -0.5;
      debugLabel = 'second';
      host.update(buildRoot());

      expect(controller, same(firstController));
      expect(controller.duration, duration);
      expect(controller.lowerBound, 0.0);
      expect(controller.debugLabel, 'first');
      expect(controller.value, 0.5);

      key = 1;
      host.update(buildRoot());
      expect(controller, isNot(same(firstController)));
      expect(controller.lowerBound, -1.0);
      expect(controller.debugLabel, 'second');
      expect(controller.value, -0.5);
      expect(
        () => firstController.addListener(() {}),
        throwsA(isA<StateError>()),
      );

      host.dispose();
    },
  );

  test('useAnimationStatus rebuilds for status transitions', () async {
    final host = TestElementHost();
    addTearDown(host.dispose);
    late AnimationController controller;
    late AnimationStatus status;

    host.mount(
      HookBuilder(
        builder: (context) {
          controller = useAnimationController(duration: Duration.zero);
          status = useAnimationStatus<double>(controller);
          return const Container();
        },
      ),
    );

    expect(status, AnimationStatus.dismissed);
    await controller.forward();
    host.pumpBuild();
    expect(status, AnimationStatus.completed);
  });

  test('useTickerProvider returns one stable shared provider', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    late TickerProvider provider;
    TickerProvider? firstProvider;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        provider = useTickerProvider();
        firstProvider ??= provider;
        return const Container();
      },
    );

    host.mount(buildRoot());
    host.update(buildRoot());

    expect(provider, same(firstProvider));
  });
}
