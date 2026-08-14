// ignore_for_file: cascade_invocations
// Run with: dart run example/chat_demo.dart

import 'dart:async';
import 'dart:io' as io;

import 'package:noir/noir.dart';

typedef ChatResponder = FutureOr<String> Function(String prompt);

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(ChatDemoApp(onQuit: quit));
  app.enableMouse();
  app.enableKittyKeyboard();
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
    this.onQuit,
    this.responder,
    this.responseDelay = const Duration(milliseconds: 900),
    this.initialMessages = _defaultMessages,
    this.initialThinking = false,
    this.enableAnimation = true,
    this.autofocusInput = true,
  });

  final VoidCallback? onQuit;
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

class _ChatDemoAppState extends State<ChatDemoApp>
    with SingleTickerProviderStateMixin<ChatDemoApp> {
  static const _spinnerFrames = ['|', '/', '-', r'\'];

  late final TextEditingController _inputController;
  late final FocusNode _inputFocus;
  late final AnimationController _spinner;
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
    _spinner =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 640),
            debugLabel: 'chat loading spinner',
          )
          ..addListener(_handleSpinnerTick)
          ..addStatusListener(_handleSpinnerStatus);
    if (_thinking && widget.enableAnimation) {
      _spinner.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _spinner
      ..removeListener(_handleSpinnerTick)
      ..removeStatusListener(_handleSpinnerStatus)
      ..dispose();
    _inputFocus.dispose();
    _inputController.dispose();
    _transcriptController.dispose();
    super.dispose();
  }

  void _handleSpinnerTick() {
    if (mounted && _thinking) {
      setState(() {});
    }
  }

  void _handleSpinnerStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed &&
        _thinking &&
        widget.enableAnimation) {
      _spinner.forward(from: 0);
    }
  }

  KeyEventResult _handleRootKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onQuit?.call();
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
    if (widget.enableAnimation) {
      _spinner.forward(from: 0);
    }
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
    _spinner.stop();
    _spinner.reset();
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

  String get _spinnerGlyph {
    if (!widget.enableAnimation) {
      return _spinnerFrames.first;
    }
    final index =
        (_spinner.value * _spinnerFrames.length).floor() %
        _spinnerFrames.length;
    return _spinnerFrames[index];
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: widget.autofocusInput,
    onKeyEvent: _handleRootKey,
    child: Container(
      color: const Color(0.04, 0.05, 0.08),
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(thinking: _thinking, messageCount: _messages.length),
          const SizedBox(height: 1),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0.07, 0.08, 0.11),
                border: Border.all(color: const Color(0.22, 0.28, 0.36)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: ScrollBox(
                controller: _transcriptController,
                scrollbarColor: const Color(0.45, 0.74, 0.92),
                trackColor: const Color(0.13, 0.15, 0.20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Newest-first keeps the active turn visible while the
                    // ScrollBox still exposes older history.
                    if (_thinking) _ThinkingBlock(frame: _spinnerGlyph),
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
  Widget build(BuildContext context) => Container(
    height: 3,
    decoration: BoxDecoration(
      color: const Color(0.10, 0.13, 0.18),
      border: Border.all(color: const Color(0.30, 0.40, 0.55)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Row(
      children: [
        const Text(
          'OpenTUI Chat',
          style: TextStyle(
            color: Color(0.78, 0.90, 1),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          thinking ? 'Thinking' : 'Ready',
          style: TextStyle(
            color: thinking
                ? const Color(1, 0.78, 0.35)
                : const Color(0.45, 0.92, 0.65),
          ),
        ),
        const SizedBox(width: 2),
        Text(
          '$messageCount messages',
          style: const TextStyle(color: Color(0.56, 0.62, 0.70)),
        ),
      ],
    ),
  );
}

class _MessageBlock extends StatelessWidget {
  const _MessageBlock({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final label = switch (message.role) {
      ChatRole.user => 'You',
      ChatRole.assistant => 'OpenTUI',
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
  const _ThinkingBlock({required this.frame});

  final String frame;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 1),
    child: Text(
      'OpenTUI is thinking $frame',
      style: const TextStyle(
        color: Color(1, 0.78, 0.35),
        fontWeight: FontWeight.bold,
      ),
    ),
  );
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
  Widget build(BuildContext context) => Container(
    height: 3,
    decoration: BoxDecoration(
      color: const Color(0.09, 0.10, 0.13),
      border: Border.all(
        color: thinking
            ? const Color(1, 0.78, 0.35)
            : const Color(0.42, 0.85, 1),
      ),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 1),
    child: Row(
      children: [
        Text(
          thinking ? '...' : '>',
          style: TextStyle(
            color: thinking
                ? const Color(1, 0.78, 0.35)
                : const Color(0.42, 0.85, 1),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 1),
        Expanded(
          child: TextInput(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            placeholder: thinking ? 'Waiting for OpenTUI' : 'Message OpenTUI',
            cursorColor: const Color(0.42, 0.85, 1),
            color: const Color(0.94, 0.96, 1),
            onSubmit: onSubmit,
          ),
        ),
      ],
    ),
  );
}
