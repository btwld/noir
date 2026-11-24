import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('a ticker callback may dispose the binding during its own frame', () {
    late final TuiTestApp app;
    // Disposes the binding and then the renderer it borrowed, as a host that
    // owns both does when an animation callback ends the session.
    app = createTuiTestApp(_CallsOnTick(() => app.dispose()));
    addTearDown(app.dispose);

    expect(app.pumpFrame, returnsNormally);
    expect(app.binding.debugHasScheduledFrame, isFalse);
  });
}

/// Runs [onTick] once, from a ticker, which is inside a frame.
final class _CallsOnTick extends StatefulWidget {
  const _CallsOnTick(this.onTick);

  final void Function() onTick;

  @override
  State<_CallsOnTick> createState() => _CallsOnTickState();
}

final class _CallsOnTickState extends State<_CallsOnTick>
    with SingleTickerProviderStateMixin<_CallsOnTick> {
  late final Ticker _ticker;
  var _called = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (_called) return;
      _called = true;
      widget.onTick();
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('ticking');
}
