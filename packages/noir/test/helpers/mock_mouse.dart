import 'dart:convert';

import 'package:noir/noir.dart';
import 'package:noir/src/core/stdin_input_driver.dart';

enum ScrollDirection { up, down, left, right }

class MockMouse {
  MockMouse(this._driver);

  final StdinInputDriver _driver;
  MouseButton? _pressedButton;

  void click(int x, int y, {MouseButton button = MouseButton.left}) {
    pressDown(x, y, button);
    release(x, y, button);
  }

  void pressDown(int x, int y, [MouseButton button = MouseButton.left]) {
    _pressedButton = button;
    _emit(x, y, _buttonCode(button), press: true);
  }

  void release(int x, int y, [MouseButton button = MouseButton.left]) {
    _pressedButton = null;
    _emit(x, y, _buttonCode(button), press: false);
  }

  void drag(
    int fromX,
    int fromY,
    int toX,
    int toY, [
    MouseButton button = MouseButton.left,
  ]) {
    pressDown(fromX, fromY, button);
    // Preserves the historical emission byte-for-byte: the move report ends
    // with the SGR release terminator 'm', which the parser accepts.
    _emit(toX, toY, _buttonCode(_pressedButton ?? button) | 0x20, press: false);
    release(toX, toY, button);
  }

  void scroll(
    int x,
    int y,
    ScrollDirection direction, {
    bool shift = false,
    bool alt = false,
    bool control = false,
  }) {
    final code = switch (direction) {
      ScrollDirection.up => 64,
      ScrollDirection.down => 65,
      ScrollDirection.left => 66,
      ScrollDirection.right => 67,
    };
    final modifiedCode =
        code | (shift ? 0x04 : 0) | (alt ? 0x08 : 0) | (control ? 0x10 : 0);
    _emit(x, y, modifiedCode, press: true);
  }

  int _buttonCode(MouseButton button) => switch (button) {
    MouseButton.left => 0,
    MouseButton.middle => 1,
    MouseButton.right => 2,
  };

  void _emit(int x, int y, int buttonCode, {required bool press}) {
    final finalByte = press ? 'M' : 'm';
    _driver.debugFeedBytes(
      utf8.encode('\x1b[<$buttonCode;${x + 1};${y + 1}$finalByte'),
    );
  }
}
