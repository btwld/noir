// ignore_for_file: cascade_invocations
// Run with: dart run example/chat_demo.dart

import 'dart:async';

import 'package:noir/noir.dart';

typedef ChatResponder = FutureOr<String> Function(String prompt);

void main() {
  runTuiApp(const ChatDemoApp(), enableMouse: true).enableKittyKeyboard();
}

enum ChatRole { user, assistant }

final class ChatMessage {
  const ChatMessage.user(this.text) : role = ChatRole.user;

  const ChatMessage.assistant(this.text) : role = ChatRole.assistant;

  final ChatRole role;
  final String text;
}

class ChatDemoApp extends StatefulWidget {
  const ChatDemoApp({
    super.key,
    this.responder,
    this.responseDelay = const Duration(milliseconds: 900),
    this.initialMessages = _defaultMessages,
    this.initialThinking = false,
    this.enableAnimation = true,
    this.autofocusInput = true,
  });

  final ChatResponder? responder;
  final Duration responseDelay;
  final List<ChatMessage> initialMessages;
  final bool initialThinking;
  final bool enableAnimation;
  final bool autofocusInput;

  @override
  State<ChatDemoApp> createState() => _ChatDemoAppState();
}

const _defaultMessages = <ChatMessage>[
  ChatMessage.assistant('Ready when you are.'),
];

class _ChatDemoAppState extends State<ChatDemoApp> {
  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  late final List<ChatMessage> _messages;
  late final ScrollController _transcriptController;

  var _thinking = false;
  var _turn = 0;

  @override
  void initState() {
    super.initState();
    _messages = List<ChatMessage>.of(widget.initialMessages);
    _thinking = widget.initialThinking;
    _inputController = TextEditingController();
    _transcriptController = ScrollController();
    _inputFocus = FocusNode();
  }

  @override
  void dispose() {
    _inputFocus.dispose();
    _inputController.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  KeyEventResult _handleRootKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      _transcriptController.pageUp();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      _transcriptController.pageDown();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submitPrompt() {
    final prompt = _inputController.text.trim();
    if (prompt.isEmpty || _thinking) {
      return;
    }

    _inputController.clear();
    final turn = ++_turn;
    setState(() {
      _thinking = true;
      _messages.add(ChatMessage.user(prompt));
    });
    _scrollToLatest();
    unawaited(_completeAssistantTurn(turn, prompt));
  }

  Future<void> _completeAssistantTurn(int turn, String prompt) async {
    late final String reply;
    try {
      reply = await _resolveResponse(prompt);
    } on Exception catch (error) {
      reply = 'Responder failed: $error';
    }

    if (!mounted || turn != _turn) {
      return;
    }

    setState(() {
      _thinking = false;
      _messages.add(ChatMessage.assistant(reply));
    });
    _scrollToLatest();
  }

  void _scrollToLatest() {
    _transcriptController.jumpTo(0);
  }

  FutureOr<String> _resolveResponse(String prompt) {
    final responder = widget.responder;
    if (responder != null) {
      return responder(prompt);
    }
    return Future<String>.delayed(
      widget.responseDelay,
      () => _defaultReply(prompt),
    );
  }

  String _defaultReply(String prompt) {
    final normalized = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return 'I need a message before I can respond.';
    }
    return 'I received "$normalized". This simulated reply keeps the demo '
        'local while exercising async UI updates.';
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: _handleRootKey,
    child: Container(
      color: Theme.of(context).surface,
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(thinking: _thinking, messageCount: _messages.length),
          const SizedBox(height: 1),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).surfaceVariant,
                border: Border.all(color: Theme.of(context).border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: ScrollBox(
                controller: _transcriptController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Newest-first keeps the active turn visible while the
                    // ScrollBox still exposes older history.
                    if (_thinking)
                      _ThinkingBlock(animated: widget.enableAnimation),
                    for (var i = _messages.length - 1; i >= 0; i--)
                      _MessageBlock(
                        key: ValueKey('message-$i'),
                        message: _messages[i],
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 1),
          _PromptBox(
            controller: _inputController,
            focusNode: _inputFocus,
            thinking: _thinking,
            autofocus: widget.autofocusInput,
            onSubmit: _submitPrompt,
          ),
        ],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.thinking, required this.messageCount});

  final bool thinking;
  final int messageCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        border: Border.all(color: theme.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: [
          Text(
            'Noir Chat',
            style: TextStyle(color: theme.text, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 2),
          Text(
            thinking ? 'Thinking' : 'Ready',
            style: TextStyle(color: thinking ? theme.warning : theme.success),
          ),
          const SizedBox(width: 2),
          Text(
            '$messageCount messages',
            style: TextStyle(color: theme.textMuted),
          ),
        ],
      ),
    );
  }
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final label = switch (message.role) {
      ChatRole.user => 'You',
      ChatRole.assistant => 'Noir',
    };
    final accent = switch (message.role) {
      ChatRole.user => const Color(0.42, 0.85, 1),
      ChatRole.assistant => const Color(0.62, 0.95, 0.68),
    };

    return Container(
      margin: const EdgeInsets.only(top: 1),
      child: Text(
        '$label: ${message.text}',
        style: TextStyle(color: accent, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  const _ThinkingBlock({required this.animated});

  final bool animated;

  @override
  Widget build(BuildContext context) {
    final warning = Theme.of(context).warning;
    return Container(
      margin: const EdgeInsets.only(top: 1),
      child: Row(
        spacing: 1,
        children: [
          Text(
            'Noir is thinking',
            style: TextStyle(color: warning, fontWeight: FontWeight.bold),
          ),
          if (animated)
            Spinner(color: warning)
          else
            Text(SpinnerFrames.dots.first, style: TextStyle(color: warning)),
        ],
      ),
    );
  }
}

class _PromptBox extends StatelessWidget {
  const _PromptBox({
    required this.controller,
    required this.focusNode,
    required this.thinking,
    required this.autofocus,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool thinking;
  final bool autofocus;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = thinking ? theme.warning : theme.accent;
    return Container(
      height: 3,
      decoration: BoxDecoration(
        color: theme.surfaceVariant,
        border: Border.all(color: accent),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Row(
        children: [
          Text(
            thinking ? '...' : '>',
            style: TextStyle(color: accent, fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 1),
          Expanded(
            child: TextInput(
              key: const ValueKey<String>('composer'),
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              placeholder: thinking ? 'Waiting for Noir' : 'Message Noir',
              cursorColor: theme.accent,
              color: theme.text,
              onSubmit: onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}
