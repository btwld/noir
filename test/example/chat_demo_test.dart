import 'dart:async';
import 'dart:io' as io;

import 'package:test/test.dart';

import '../../example/chat_demo.dart';
import '../helpers/tui_test_app.dart';

void main() {
  group('chat demo example', () {
    test(
      'submits typed text and renders the controlled assistant reply',
      () async {
        final reply = Completer<String>();
        final prompts = <String>[];
        final app = createTuiTestApp(
          ChatDemoApp(
            responder: (prompt) {
              prompts.add(prompt);
              return reply.future;
            },
          ),
          width: 64,
          height: 16,
        );

        try {
          await _settleAutofocus(app);
          app.mockInput
            ..typeText('hello OpenTUI')
            ..pressEnter();
          app
            ..pumpFrame(const Duration(milliseconds: 16))
            ..pumpFrame(const Duration(milliseconds: 32));

          var text = app.captureFrame().toText();
          expect(prompts, ['hello OpenTUI']);
          expect(text, contains('You'));
          expect(text, contains('hello OpenTUI'));
          expect(text, contains('OpenTUI is thinking'));

          reply.complete('Echo: hello OpenTUI');
          await Future<void>.delayed(Duration.zero);
          app.pumpFrame(const Duration(milliseconds: 40));

          text = app.captureFrame().toText();
          expect(text, contains('OpenTUI'));
          expect(text, contains('Echo: hello OpenTUI'));
          expect(text, isNot(contains('OpenTUI is thinking')));
        } finally {
          app.dispose();
        }
      },
    );

    test('loading animation advances across frame timestamps', () async {
      final app = createTuiTestApp(
        ChatDemoApp(responder: (_) => Completer<String>().future),
        width: 64,
        height: 16,
      );

      try {
        await _settleAutofocus(app);
        app.mockInput
          ..typeText('spin')
          ..pressEnter();

        app
          ..pumpFrame(const Duration(milliseconds: 16))
          ..pumpFrame(const Duration(milliseconds: 32));
        final first = app.captureFrame().toText();
        app.pumpFrame(const Duration(milliseconds: 280));
        final second = app.captureFrame().toText();

        expect(first, contains('OpenTUI is thinking'));
        expect(second, contains('OpenTUI is thinking'));
        expect(first, isNot(second));
      } finally {
        app.dispose();
      }
    });

    test('keeps the newest message visible after transcript growth', () async {
      final initialMessages = List<ChatMessage>.generate(
        12,
        (index) => ChatMessage.assistant('Seed response ${index + 100}'),
      );
      final app = createTuiTestApp(
        ChatDemoApp(
          initialMessages: initialMessages,
          responder: (prompt) => 'Reply for $prompt',
        ),
        width: 56,
        height: 18,
      );

      try {
        await _settleAutofocus(app);
        app.mockInput
          ..typeText('latest request')
          ..pressEnter();
        await Future<void>.delayed(Duration.zero);
        app
          ..pumpFrame(const Duration(milliseconds: 16))
          ..pumpFrame(const Duration(milliseconds: 32))
          ..pumpFrame(const Duration(milliseconds: 48));

        final text = app.captureFrame().toText();
        expect(text, contains('latest request'));
        expect(text, contains('Reply for latest request'));
        expect(text, isNot(contains('Seed response 100')));
      } finally {
        app.dispose();
      }
    });

    test('PageDown scrolls transcript while the prompt keeps focus', () async {
      final initialMessages = List<ChatMessage>.generate(
        24,
        (index) => ChatMessage.assistant(
          'History item ${index.toString().padLeft(2, '0')}',
        ),
      );
      final app = createTuiTestApp(
        ChatDemoApp(initialMessages: initialMessages, enableAnimation: false),
        width: 56,
        height: 16,
      );

      try {
        await _settleAutofocus(app);
        final before = app.captureFrame().toText();
        expect(before, contains('History item 23'));
        expect(before, isNot(contains('History item 00')));

        app.mockInput.pressPageDown();
        await Future<void>.delayed(Duration.zero);
        app.pumpFrame(const Duration(milliseconds: 16));

        final after = app.captureFrame().toText();
        expect(after, isNot(before));
        expect(after, contains('History item 21'));
      } finally {
        app.dispose();
      }
    });

    test('Escape invokes the documented quit callback', () async {
      var quits = 0;
      final app = createTuiTestApp(
        ChatDemoApp(onQuit: () => quits++, enableAnimation: false),
      );

      try {
        await _settleAutofocus(app);
        app.mockInput.pressEscape();

        expect(quits, 1);
      } finally {
        app.dispose();
      }
    });

    test('real terminal entrypoint enables Kitty keyboard reporting', () {
      final source = io.File('example/chat_demo.dart').readAsStringSync();

      expect(source, contains('app.enableKittyKeyboard();'));
    });
  });
}

Future<void> _settleAutofocus(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
