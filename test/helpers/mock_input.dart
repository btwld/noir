import 'dart:convert';

import 'package:noir/src/core/stdin_input_driver.dart';

enum ArrowDirection { up, down, left, right }

class MockInput {
  MockInput(this._driver);

  final StdinInputDriver _driver;

  void typeText(String text) {
    _feed(utf8.encode(text));
  }

  void pressEnter() {
    _feedString('\r');
  }

  void pressEscape() {
    _feedString('\x1b');
    _driver.debugFlushPendingEscape();
  }

  void pressTab() {
    _feedString('\t');
  }

  void pressShiftTab() {
    _feedString('\x1b[Z');
  }

  void pressBackspace() {
    _feedString('\b');
  }

  void pressPageDown() {
    _feedString('\x1b[6~');
  }

  void pressPageUp() {
    _feedString('\x1b[5~');
  }

  void pressCtrl(String letter) {
    if (letter.length != 1) {
      throw ArgumentError.value(letter, 'letter', 'Expected one character.');
    }
    final code = letter.toLowerCase().codeUnitAt(0);
    if (code < 0x61 || code > 0x7a) {
      throw ArgumentError.value(letter, 'letter', 'Expected a-z.');
    }
    _feed(<int>[code - 0x60]);
  }

  void pressArrow(ArrowDirection direction) {
    _feedString(switch (direction) {
      ArrowDirection.up => '\x1b[A',
      ArrowDirection.down => '\x1b[B',
      ArrowDirection.right => '\x1b[C',
      ArrowDirection.left => '\x1b[D',
    });
  }

  void pressKittyKey(int keyCode, {int modifiers = 0, int? eventType}) {
    final modifierField = modifiers + 1;
    final eventSuffix = eventType == null ? '' : ':$eventType';
    _feedString('\x1b[$keyCode;$modifierField${eventSuffix}u');
  }

  void pressModifyOtherKey(int keyCode, {int modifiers = 0}) {
    final modifierField = modifiers + 1;
    _feedString('\x1b[27;$modifierField;$keyCode~');
  }

  void paste(String text) {
    _feed(<int>[
      ...utf8.encode('\x1b[200~'),
      ...utf8.encode(text),
      ...utf8.encode('\x1b[201~'),
    ]);
  }

  void _feedString(String text) {
    _feed(utf8.encode(text));
  }

  void _feed(List<int> bytes) {
    _driver.debugFeedBytes(bytes);
  }
}
