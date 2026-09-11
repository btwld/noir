import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/app.dart' show mountTuiAppForTesting;

/// Minimal headless harness for behavioural input tests.
///
/// Mounts a widget under a headless [TuiBinding], runs one frame, then
/// lets a test send synthetic key/mouse events through [InputManager].
///
/// Note: KeyDriver delegates mount/unmount through [TuiBinding], the advanced
/// host behind the public app facade.
/// The other two harnesses (`WidgetTester`, `BufferCapture`) use
/// [TestElementHost] directly because they don't need binding frame
/// scheduler or input-event dispatch wiring.
///
/// Replaces ~6 lines of repeated boilerplate per test:
///
/// ```dart
/// final driver = KeyDriver(MyWidget(...));
/// await driver.ready();
/// await driver.sendCharacter('a');
/// await driver.sendLogicalKey(LogicalKeyboardKey.enter, code: 13);
/// driver.dispose();
/// ```
///
/// The harness does NOT exercise the ANSI byte parser. Use
/// `createTuiTestApp` when a test needs byte-level parser coverage; see
/// `test/helpers/README.md`.
class KeyDriver {
  KeyDriver(
    Widget root, {
    bool paintFrames = false,
    int width = 80,
    int height = 24,
  }) : _renderer = paintFrames
           ? Renderer.create(width, height, testing: true)
           : null {
    _renderer?.setAutoFlush(false);
    app = TuiBinding(
      width: width,
      height: height,
      headless: true,
      renderer: _renderer,
    );
    mountTuiAppForTesting(app, root, exitCodeSink: _exitRequests.add);
  }

  late final TuiBinding app;
  final Renderer? _renderer;
  final List<int> _exitRequests = <int>[];

  /// Exit codes requested through [TuiApp.exit], in order.
  List<int> get exitRequests => List<int>.unmodifiable(_exitRequests);

  /// Yields the microtask queue so initial focus, mount, and first build
  /// settle. Awaits any pending focus-change microtasks.
  Future<void> ready() async {
    // Two pumps: one for autofocus (scheduled microtask), one for any
    // setState reaction triggered by the focus change itself.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  /// Send a synthetic key press through [InputManager] and yield until
  /// downstream `setState` calls have flushed.
  Future<void> sendLogicalKey(
    LogicalKeyboardKey key, {
    int code = 0,
    int modifiers = 0,
  }) async {
    app.inputManager.dispatchKey(
      KeyEvent(logicalKey: key, keyCode: code, modifiers: modifiers),
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// Send a synthetic printable character through [InputManager].
  Future<void> sendCharacter(String character, {int modifiers = 0}) async {
    app.inputManager.dispatchKey(
      KeyEvent(
        logicalKey: LogicalKeyboardKey.forCharacter(character),
        keyCode: character.length == 1 ? character.codeUnitAt(0) : 0,
        character: character,
        modifiers: modifiers,
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// Send a synthetic mouse event and yield.
  Future<void> sendMouse(MouseEvent event) async {
    app.inputManager.dispatchMouse(event);
    await Future<void>.delayed(Duration.zero);
  }

  /// Send a synthetic paste event and yield.
  Future<void> sendPaste(String text) async {
    app.inputManager.dispatchPaste(PasteEvent(text));
    await Future<void>.delayed(Duration.zero);
  }

  void dispose() {
    app.dispose();
    _renderer?.dispose();
  }
}
