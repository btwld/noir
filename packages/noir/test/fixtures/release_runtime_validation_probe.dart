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
  _expect<StateError>('ticker-single-cardinality', () {
    final key = GlobalKey<_SingleTickerProbeState>();
    final host = TestElementHost()..mount(_SingleTickerProbe(key: key));
    try {
      final state = key.currentState!;
      state.createTicker((_) {});
      state.createTicker((_) {});
    } finally {
      host.dispose();
    }
  });
  _expect<StateError>('ticker-active-at-dispose', () {
    final key = GlobalKey<_MultiTickerProbeState>();
    final host = TestElementHost()..mount(_MultiTickerProbe(key: key));
    key.currentState!.createTicker((_) {}).start();
    host.dispose();
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

class _SingleTickerProbe extends StatefulWidget {
  const _SingleTickerProbe({super.key});

  @override
  State<_SingleTickerProbe> createState() => _SingleTickerProbeState();
}

class _SingleTickerProbeState extends State<_SingleTickerProbe>
    with SingleTickerProviderStateMixin<_SingleTickerProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}

class _MultiTickerProbe extends StatefulWidget {
  const _MultiTickerProbe({super.key});

  @override
  State<_MultiTickerProbe> createState() => _MultiTickerProbeState();
}

class _MultiTickerProbeState extends State<_MultiTickerProbe>
    with TickerProviderStateMixin<_MultiTickerProbe> {
  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
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
