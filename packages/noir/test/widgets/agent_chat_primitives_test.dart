import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test(
    'public primitives compose a wrapped chronological chat miniature',
    () async {
      final key = GlobalKey<_ChatPrimitiveHarnessState>();
      final app = createTuiTestApp(
        _ChatPrimitiveHarness(key: key),
        width: 20,
        height: 8,
        kittyKeyboard: true,
      );
      addTearDown(app.dispose);

      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();
      expect(key.currentState!.transcript.isFollowingTail, isTrue);

      app.mockInput.typeText('first');
      app.mockInput.pressKittyKey(
        LogicalKeyboardKey.keyJ.keyId,
        modifiers: KeyModifiers.ctrl,
      );
      app.mockInput.typeText('second');
      app.pumpFrame();
      expect(key.currentState!.composer.text, 'first\nsecond');
      expect(app.captureFrame().toText(), contains('second'));

      app.mockInput.pressEnter();
      app.pumpFrame();
      expect(key.currentState!.messages.last, 'You: first\nsecond');
      expect(key.currentState!.composer.text, isEmpty);
      expect(key.currentState!.transcript.isFollowingTail, isTrue);
      expect(app.captureFrame().toText(), contains('second'));

      key.currentState!.transcript.jumpTo(0);
      final detachedOffset = key.currentState!.transcript.offset;
      expect(key.currentState!.transcript.isFollowingTail, isFalse);
      key.currentState!.append('Agent: appended\nwith detail');
      app.pumpFrame();
      expect(key.currentState!.transcript.offset, detachedOffset);
    },
  );
}

class _ChatPrimitiveHarness extends StatefulWidget {
  const _ChatPrimitiveHarness({super.key});

  @override
  State<_ChatPrimitiveHarness> createState() => _ChatPrimitiveHarnessState();
}

class _ChatPrimitiveHarnessState extends State<_ChatPrimitiveHarness> {
  final composer = TextEditingController();
  final composerFocus = FocusNode();
  final transcript = ScrollController(followTail: true);
  final messages = <String>[
    'Agent: oldest\nwith detail',
    'You: inspect',
    'Agent: working\nstep one\nstep two',
  ];

  void append(String message) {
    setState(() => messages.add(message));
  }

  void _submit() {
    final draft = composer.text;
    if (draft.isEmpty) return;
    composer.clear();
    append('You: $draft');
  }

  @override
  void dispose() {
    transcript.dispose();
    composerFocus.dispose();
    composer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: ScrollBox(
          controller: transcript,
          showScrollbar: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [for (final message in messages) Text(message)],
          ),
        ),
      ),
      TextArea(
        controller: composer,
        focusNode: composerFocus,
        autofocus: true,
        height: 1,
        maxHeight: 3,
        softWrap: true,
        submitOnEnter: true,
        onSubmit: _submit,
      ),
    ],
  );
}
