# Noir reference: state, lifecycle & animation

How noir manages mutable state and time. The model is Flutter-like:
`StatefulWidget` + `State` + `setState`, observable `ChangeNotifier`s,
`TextEditingController` for editable text, `AnimationController` for time-based
value animation, and `InheritedWidget` for passing data down the tree. Noir's
controller deliberately uses the simpler run-ended `Future<void>` contract
described below rather than Flutter's cancellation-aware `TickerFuture`.

## Contents

- [StatefulWidget lifecycle](#statefulwidget-lifecycle)
- [setState and the `mounted` guard](#setstate-and-the-mounted-guard)
- [ChangeNotifier / ValueNotifier](#changenotifier--valuenotifier)
- [TextEditingController](#texteditingcontroller)
- [AnimationController + tickers](#animationcontroller--tickers)
- [InheritedWidget](#inheritedwidget)

---

## StatefulWidget lifecycle

```dart
class MyWidget extends StatefulWidget {
  const MyWidget({super.key});
  @override
  State<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  void initState() {
    super.initState();
    // Create controllers / focus nodes / listeners here. Runs once on mount.
  }

  @override
  void didUpdateWidget(covariant MyWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilt with new config. Reconcile against oldWidget here —
    // e.g. re-sync a FocusNode if widget.focusNode changed.
  }

  @override
  void dispose() {
    // Dispose everything you created in initState (controllers, focus nodes,
    // listeners). Skipping this retains native resources. Dispose, then super.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('…');
}
```

The element holding this `State` persists across rebuilds — that's why state
survives. The `widget` getter always points at the current configuration.

## setState and the `mounted` guard

`setState(fn)` mutates state and schedules a rebuild + repaint. Two rules:

1. Keep the closure to synchronous state mutation; do real work outside it.
2. In any async or delayed callback, **guard on `mounted`** — the widget may have
   been disposed before the callback ran:

```dart
Future.delayed(const Duration(milliseconds: 50), () {
  if (!mounted) return;          // critical: don't setState after dispose
  setState(() => _count++);
});
```

## ChangeNotifier / ValueNotifier

For state that lives outside a single widget or is shared, use a notifier and
listen to it.

```dart
ChangeNotifier()
//   .addListener(VoidCallback) / .removeListener(...) / .notifyListeners() / .dispose()

ValueNotifier<T>(T value)
//   .value (get/set — notifies listeners when the value changes by ==)
```

```dart
final _count = ValueNotifier<int>(0);
// In initState: _count.addListener(() { if (mounted) setState(() {}); });
// Mutate from anywhere: _count.value++;
// In dispose: _count.dispose();
```

## TextEditingController

Owns editable text and a selection/cursor for `TextInput`/`TextArea`. **Use this
rather than reimplementing cursor math** — it's the required path for text
editing in this repo.

```dart
TextEditingController({ String text = '' })

ctrl.text            // get/set (setting clears selection)
ctrl.selection       // TextSelection
ctrl.lines           // List<String>
ctrl.line, ctrl.col  // cursor position
ctrl.isEmpty
ctrl.clear();
ctrl.setCursor(line, col);

ctrl.insert(String replacement, { bool allowNewline = true });  // false for single-line fields
ctrl.newline(); ctrl.deleteBack(); ctrl.deleteForward();
ctrl.moveCursorLeft(); ctrl.moveCursorRight(); ctrl.moveCursorUp(); ctrl.moveCursorDown();
ctrl.moveLineStart(); ctrl.moveLineEnd(); ctrl.moveDocumentStart(); ctrl.moveDocumentEnd();
```

For single-line inputs, pass `allowNewline: false` to `insert(...)` so pasted
newlines are rejected.

```dart
final _controller = TextEditingController(text: 'hello');
// ... TextInput(controller: _controller, ...)
@override void dispose() { _controller.dispose(); super.dispose(); }
```

## AnimationController + tickers

`AnimationController` drives a `double` from `lowerBound` to `upperBound` over a
`Duration`, ticking once per frame. It needs a `vsync` (`TickerProvider`) — mix
`SingleTickerProviderStateMixin` into your `State` (or
`TickerProviderStateMixin` for several controllers) and pass `vsync: this`.

```dart
AnimationController({
  required TickerProvider vsync,
  Duration duration = const Duration(milliseconds: 300),
  Duration? reverseDuration,
  double lowerBound = 0.0,
  double upperBound = 1.0,
  double value = 0.0,
  String? debugLabel,
})
//   .value (get/set) · .status · .isAnimating
//   .forward({double? from}) · .reverse({double? from}) · .stop() · .reset()
//   .addListener(VoidCallback) / .removeListener(...)
//   .addStatusListener(AnimationStatusListener) / .removeStatusListener(...)
//   .dispose()
```

`forward()` and `reverse()` each return a `Future<void>` that completes when
that run ends, whether it reaches its target or is superseded, stopped, reset,
or disposed. The Future is not cancellation-aware and does not retain why the
run ended. After an `await`, `status` is the controller's current state and may
already describe a replacement run. Register a status listener before
starting the run when its status transitions matter.

Canonical ping-pong loop — listen for ticks to repaint, and flip direction on
status:

```dart
class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin<Pulse> {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..addListener(_onTick);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _controller.reverse();
      else if (status == AnimationStatus.dismissed) _controller.forward();
    });
    _controller.forward(from: 0);
  }

  void _onTick() { if (mounted) setState(() {}); }

  @override
  void dispose() { _controller..removeListener(_onTick)..dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final v = _controller.value;     // 0.0 → 1.0 → 0.0 …
    return Container(width: 8 + (v * 12).round(), height: 2 + (v * 4).round(), color: Color.rgb(0.2 + v * 0.6, 0.3, 0.6));
  }
}
```

Note the integer rounding: animated `value` is a `double`, but widths/heights are
cells, so `.round()` when you feed them into layout.

## InheritedWidget

Pass data down to descendants without threading it through constructors.
Subclass noir's `InheritedWidget`, expose a static `of(context)` that calls
`context.dependOnInheritedWidgetOfExactType<T>()`, and implement
`updateShouldNotify`. See `example/inherited_example.dart` for a complete,
runnable pattern using noir's current dependency contract.
