import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/terminal_session.dart'
    show TerminalInputDriverFactory, TerminalPlatform;
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:noir/src/core/input.dart' show InputManagerKernelAccess;
import 'package:noir/src/core/stdin_input_driver.dart';

import 'buffer_capture.dart';
import 'mock_input.dart';
import 'mock_mouse.dart';

export 'mock_input.dart' show ArrowDirection, MockInput;
export 'mock_mouse.dart' show MockMouse, ScrollDirection;

TuiTestApp createTuiTestApp(
  Widget app, {
  int width = 80,
  int height = 24,
  bool headless = true,
  bool kittyKeyboard = false,
  TerminalPlatform? terminalPlatform,
  TerminalInputDriverFactory? inputDriverFactory,
  void Function(int exitCode)? exitProcess,
}) {
  final renderer = Renderer.create(width, height, testing: true)
    ..setAutoFlush(false);
  final binding = runTuiAppForTesting(
    app,
    width: width,
    height: height,
    headless: headless,
    renderer: renderer,
    terminalPlatform: terminalPlatform,
    inputDriverFactory: inputDriverFactory,
    exitProcess: exitProcess,
  );
  if (kittyKeyboard) {
    binding.enableKittyKeyboard();
  }
  final driver = StdinInputDriver(binding.inputManager.dispatcher);
  return TuiTestApp._(
    binding: binding,
    renderer: renderer,
    inputDriver: driver,
  );
}

class TuiTestApp {
  TuiTestApp._({
    required this.binding,
    required this.renderer,
    required StdinInputDriver inputDriver,
  }) : mockInput = MockInput(inputDriver),
       mockMouse = MockMouse(inputDriver);

  final TuiBinding binding;
  final Renderer renderer;
  final MockInput mockInput;
  final MockMouse mockMouse;
  bool _disposed = false;

  void pumpFrame([Duration timestamp = Duration.zero]) {
    binding.debugFlushFrame(timestamp);
  }

  CapturedBuffer captureFrame() => CapturedBuffer.fromBuffer(
    renderer.debugCurrentBuffer,
    cursor: CapturedCursor.fromController(binding.buildOwner.cursorController),
  );

  void resize(int width, int height) {
    binding.handleResize(width, height);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    binding.dispose();
    renderer.dispose();
  }
}
