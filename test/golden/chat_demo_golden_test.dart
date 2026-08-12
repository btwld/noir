import 'dart:io';

import 'package:test/test.dart';

import '../../example/chat_demo.dart';
import '../helpers/golden_testing.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Chat demo golden', () {
    late GoldenTester tester;

    setUpAll(() {
      tester = GoldenTester();
    });

    tearDownAll(() {
      tester.dispose();
    });

    test('chat_demo visual state', () async {
      await tester.expectGolden(
        const ChatDemoApp(
          enableAnimation: false,
          autofocusInput: false,
          initialThinking: true,
          initialMessages: [
            ChatMessage.assistant('I can help inspect a terminal UI.'),
            ChatMessage.user('Show the latest validation state.'),
          ],
        ),
        'chat_demo',
        updateGoldens: _updateGoldens,
      );
    });
  });
}
