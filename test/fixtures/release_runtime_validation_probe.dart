import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/animation/ticker.dart';

import '../helpers/test_element_host.dart';

void main() {
  final renderer = Renderer.create(2, 1, testing: true);
  try {
    final buffer = renderer.nextBuffer;
    final belowRange = -0.1;
    final notFinite = double.nan;
    _expect<ArgumentError>('ffi-color-range', () {
      buffer.clear(Color(belowRange, 0, 0));
    });
    _expect<ArgumentError>('direct-color-finite', () {
      buffer.getDirectAccess().setForeground(0, 0, Color(notFinite, 0, 0));
    });
  } finally {
    renderer.dispose();
  }

  _expect<ArgumentError>('animation-bounds', () {
    AnimationController(vsync: _TickerProvider(), lowerBound: 2);
  });
  _expect<ArgumentError>('animation-value', () {
    AnimationController(vsync: _TickerProvider(), value: double.nan);
  });
  _expect<ArgumentError>('animation-set-value', () {
    AnimationController(vsync: _TickerProvider()).value = double.nan;
  });
  _expect<ArgumentError>('animation-duration', () {
    AnimationController(
      vsync: _TickerProvider(),
      duration: const Duration(microseconds: -1),
    );
  });
  _expect<ArgumentError>('animation-reverse-duration', () {
    AnimationController(
      vsync: _TickerProvider(),
      reverseDuration: const Duration(microseconds: -1),
    );
  });
  _expect<ArgumentError>('animation-duration-setter', () {
    AnimationController(vsync: _TickerProvider()).duration = const Duration(
      microseconds: -1,
    );
  });
  _expect<ArgumentError>('animation-reverse-duration-setter', () {
    AnimationController(vsync: _TickerProvider()).reverseDuration =
        const Duration(microseconds: -1);
  });
  _expect<ArgumentError>('box-options-border-chars', () {
    BoxOptions(borderChars: const <int>[0x2500]);
  });
  _expect<ArgumentError>('border-border-chars', () {
    Border.all(borderChars: const <int>[0x2500]);
  });
  _expect<ArgumentError>('container-color-decoration', () {
    final host = TestElementHost();
    final color = Color.red;
    final decoration = const BoxDecoration(color: Color.blue);
    try {
      host.mount(Container(color: color, decoration: decoration));
    } finally {
      try {
        host.dispose();
      } on Object {
        // The expected build failure can leave the host partly mounted.
      }
    }
  });
}

final class _TickerProvider implements TickerProvider {
  final TickerScheduler _scheduler = TickerScheduler();

  @override
  Ticker createTicker(TickerCallback onTick, {String? debugLabel}) =>
      _scheduler.createTicker(onTick, debugLabel: debugLabel);
}

void _expect<T extends Object>(String label, void Function() body) {
  try {
    body();
  } on T {
    print('PASS:$label');
    return;
  }
  throw StateError('unexpected success: $label');
}
