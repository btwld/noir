// ignore_for_file: cascade_invocations
// Run with: dart run example/framework_primitives.dart
//
// Press Enter or Space, or click Activate, to increment. Press q to quit.

import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(FrameworkPrimitivesApp(onQuit: quit));
  app.enableMouse();
}

final class _IncrementIntent extends Intent {
  const _IncrementIntent();
}

class FrameworkPrimitivesApp extends StatefulWidget {
  const FrameworkPrimitivesApp({required this.onQuit, super.key});

  final VoidCallback onQuit;

  @override
  State<FrameworkPrimitivesApp> createState() => _FrameworkPrimitivesAppState();
}

class _FrameworkPrimitivesAppState extends State<FrameworkPrimitivesApp> {
  final _activationKey = GlobalKey<_ActivationSurfaceState>();
  late final ValueNotifier<int> _count;
  var _lastActivation = 'none';

  @override
  void initState() {
    super.initState();
    _count = ValueNotifier<int>(0)..addListener(_handleCountChanged);
  }

  void _handleCountChanged() {
    if (mounted) setState(() {});
  }

  void _activate(String source) {
    _lastActivation = source;
    _count.value++;
  }

  KeyEventResult _handleQuit(FocusNode node, KeyEvent event) {
    if (event.isPress && event.character == 'q') {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _count
      ..removeListener(_handleCountChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      SingleActivator(LogicalKeyboardKey.enter): _IncrementIntent(),
      SingleActivator(LogicalKeyboardKey.space): _IncrementIntent(),
    },
    child: Actions(
      actions: <Type, Action<Intent>>{
        _IncrementIntent: CallbackAction<_IncrementIntent>((intent, context) {
          _activationKey.currentState?.activate('keyboard');
          return KeyEventResult.handled;
        }),
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleQuit,
        child: DemoScaffold(
          title: 'Framework primitives',
          hint: 'Enter/Space/click increments. q quits.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: [
              RichText(
                text: TextSpan(
                  text: 'Count: ',
                  style: const TextStyle(color: Color.lightGray),
                  children: [
                    TextSpan(
                      text: '${_count.value}',
                      style: const TextStyle(
                        color: Color.yellow,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              _ActivationSurface(key: _activationKey, onActivate: _activate),
              Text('Last activation: $_lastActivation'),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ActivationSurface extends StatefulWidget {
  const _ActivationSurface({required this.onActivate, super.key});

  final void Function(String source) onActivate;

  @override
  State<_ActivationSurface> createState() => _ActivationSurfaceState();
}

class _ActivationSurfaceState extends State<_ActivationSurface> {
  void activate(String source) => widget.onActivate(source);

  void _handlePointerDown(MouseEvent event) {
    if (event.button != MouseButton.left) return;
    activate(
      'pointer local ${event.localPosition.dx},${event.localPosition.dy}',
    );
  }

  @override
  Widget build(BuildContext context) => PointerListener(
    onPointerDown: _handlePointerDown,
    child: Container(
      width: 18,
      height: 1,
      color: Theme.of(context).selectedBackground,
      child: const Text('Activate'),
    ),
  );
}
