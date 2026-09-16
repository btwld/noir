import 'dart:async';

import 'package:noir/noir.dart';

/// Repaints well after the driver's default settle window.
///
/// A key press schedules its `setState` on a timer instead of applying it
/// immediately, which is what an app doing async work on input looks like from
/// the driver's side: the RPC returns, and the frame that proves the input
/// landed arrives much later.
const Duration repaintDelay = Duration(milliseconds: 700);

void main() => runTuiApp(const _Probe());

class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  var _count = 0;
  Timer? _pending;

  @override
  void dispose() {
    _pending?.cancel();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (!event.isPress || event.logicalKey != LogicalKeyboardKey.arrowUp) {
      return KeyEventResult.ignored;
    }
    _pending?.cancel();
    _pending = Timer(repaintDelay, () {
      if (!mounted) return;
      setState(() => _count++);
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _handleKey,
    child: Text('COUNT $_count'),
  );
}
