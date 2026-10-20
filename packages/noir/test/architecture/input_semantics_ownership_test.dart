import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('built-in widgets do not parse key events directly', () {
    final files = [
      File('lib/src/widgets/select.dart'),
      File('lib/src/widgets/text_input.dart'),
      File('lib/src/widgets/text_area.dart'),
      File('lib/src/widgets/scroll_box.dart'),
      File('lib/src/widgets/document_view.dart'),
      File('lib/src/widgets/slider.dart'),
      File('lib/src/widgets/tab_select.dart'),
    ];

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('event.key')), reason: file.path);
      expect(source, isNot(contains('event.logicalKey')), reason: file.path);
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

  test('text-editing widgets use TextInputConnection', () {
    final textInput = File(
      'lib/src/widgets/text_input.dart',
    ).readAsStringSync();
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
