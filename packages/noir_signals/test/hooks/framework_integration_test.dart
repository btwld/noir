import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

void main() {
  test('active animation controller stops before ticker-provider teardown', () {
    final host = TestElementHost();
    late AnimationController controller;

    host.mount(
      SignalBuilder(
        builder: (context) {
          controller = useAnimationController(
            duration: const Duration(seconds: 1),
          );
          return const Container();
        },
      ),
    );

    unawaited(controller.forward());
    expect(controller.isAnimating, isTrue);

    expect(host.dispose, returnsNormally);
    expect(controller.isAnimating, isFalse);
    expect(() => controller.addListener(() {}), throwsA(isA<StateError>()));
  });
}
