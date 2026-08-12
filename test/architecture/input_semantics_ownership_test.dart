import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('built-in widgets do not parse key events directly', () {
    final files = [
      File('lib/src/widgets/select.dart'),
      File('lib/src/widgets/input.dart'),
      File('lib/src/widgets/text_area.dart'),
      File('lib/src/widgets/scroll_box.dart'),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('event.key')), reason: file.path);
      expect(
        source,
        isNot(contains('switch (event.logicalKey)')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('onKeyEvent: _handleKeyEvent')),
        reason: file.path,
      );
    }
  });

  test('FocusManager owns semantic routing without raw key globals', () {
    final source = File(
      'lib/src/framework/focus_manager.dart',
    ).readAsStringSync();

    for (final forbidden in [
      "event.key == 'Tab'",
      'RawKeyEventHandler',
      '_globalKeyHandlers',
      'registerGlobalKeyHandler',
      'unregisterGlobalKeyHandler',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }

    expect(source, contains('Shortcuts.handleKeyEvent'));
    expect(source, contains('FocusTraversalPolicy'));
    expect(source, contains('KeyEventResult'));
  });

  test('InputDispatcher stays below shortcuts and intents', () {
    final source = File('lib/src/core/input.dart').readAsStringSync();
    final body = _classBody(source, 'InputDispatcher');

    for (final forbidden in [
      'Shortcuts',
      'Actions',
      'Intent',
      'FocusTraversalPolicy',
      'TextInputConnection',
    ]) {
      expect(body, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('text-editing widgets use TextInputConnection', () {
    final textInput = File('lib/src/widgets/input.dart').readAsStringSync();
    final textArea = File('lib/src/widgets/text_area.dart').readAsStringSync();
    final connection = File(
      'lib/src/widgets/text_input_connection.dart',
    ).readAsStringSync();

    expect(connection, contains('class TextInputConnection'));
    expect(textInput, contains('TextInputConnection'));
    expect(textArea, contains('TextInputConnection'));
    expect(textInput, isNot(contains('_handleKeyEvent')));
    expect(textArea, isNot(contains('_handleKeyEvent')));
  });
}

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex < 0) {
    throw StateError('Class $className not found');
  }
  final start = source.indexOf('{', classIndex);
  if (start < 0) {
    throw StateError('Class $className has no body');
  }
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 0x7b) depth++;
    if (code == 0x7d) {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('Class $className body is unterminated');
}
