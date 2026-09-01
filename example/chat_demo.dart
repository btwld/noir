// ignore_for_file: cascade_invocations
// Replay: dart run example/chat_demo.dart

import 'dart:async';

import 'package:noir/noir.dart';

import 'src/agent_chat_protocol.dart';
import 'src/agent_session_controller.dart';

export 'src/agent_chat_protocol.dart';
export 'src/agent_session_controller.dart';

void main() {
  runTuiApp(const ChatDemoApp(), enableMouse: true).enableKittyKeyboard();
}

/// Minimal C-family source highlighter for the agent transcript.
///
/// [CodeView] and [MarkdownView] default to [PlainTextCodeHighlighter], so a
/// fenced block renders as unstyled text until an application supplies a
/// highlighter.
///
/// The highlighter separates the two parts of the problem. Comment, string,
/// and number syntax is the same across the C family, so [_lexedLanguages]
/// gets it. Reserved words are not shared, so each language declares its own
/// set in [_keywords]. A lexed language with no set still gets comments,
/// strings, and numbers.
///
/// Painting a word that the language does not reserve is worse than leaving
/// it plain, so a word joins a set only when that language treats it as a
/// keyword and readers rarely write it as an ordinary name there. That test
/// keeps `get`, `set`, and `of` out of JavaScript, and `any`, `number`,
/// `string`, and `type` out of TypeScript.
///
/// The result is always sorted and non-overlapping, and it is empty for a
/// language the highlighter does not lex.
final class AgentCodeHighlighter implements CodeHighlighter {
  /// Creates the highlighter with the default transcript token colors.
  const AgentCodeHighlighter({
    this.comment = const TextStyle(color: Color(0.6, 0.6, 0.6)),
    this.string = const TextStyle(color: Color.error),
    this.number = const TextStyle(color: Color.warning),
    this.keyword = const TextStyle(color: Color.info),
  });

  /// Style for line and block comments.
  final TextStyle comment;

  /// Style for single- and double-quoted strings.
  final TextStyle string;

  /// Style for numeric literals.
  final TextStyle number;

  /// Style for reserved words.
  final TextStyle keyword;

  /// Languages whose comment, string, and number syntax this lexer reads.
  ///
  /// Rust is absent on purpose. A Rust lifetime such as `&'a str` opens with
  /// a single quote, so this lexer would read the rest of the line as a
  /// string.
  static const Set<String> _lexedLanguages = {
    'c',
    'cpp',
    'dart',
    'go',
    'java',
    'javascript',
    'js',
    'kotlin',
    'swift',
    'ts',
    'typescript',
  };

  /// Reserved words per language.
  ///
  /// Add an entry to give a lexed language reserved-word highlighting. Every
  /// other language keeps its comments, strings, and numbers.
  /// Reserved words per language.
  ///
  /// Add an entry to give a lexed language reserved-word highlighting. Every
  /// other language keeps its comments, strings, and numbers.
  static const Map<String, Set<String>> _keywords = {
    'dart': _dartKeywords,
    'javascript': _javaScriptKeywords,
    'js': _javaScriptKeywords,
    'ts': _javaScriptKeywords,
    'typescript': _javaScriptKeywords,
  };

  static const Set<String> _dartKeywords = {
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'base',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'get',
    'if',
    'implements',
    'import',
    'in',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'new',
    'null',
    'operator',
    'part',
    'required',
    'rethrow',
    'return',
    'sealed',
    'set',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };

  /// Serves TypeScript too. TypeScript's own additions, such as `keyof`,
  /// `satisfies`, and `readonly`, are contextual: each one is a legal name
  /// outside a type position, so none of them meets the test above.
  static const Set<String> _javaScriptKeywords = {
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'debugger',
    'default',
    'delete',
    'do',
    'else',
    'enum',
    'export',
    'extends',
    'false',
    'finally',
    'for',
    'function',
    'if',
    'implements',
    'import',
    'in',
    'instanceof',
    'interface',
    'let',
    'new',
    'null',
    'package',
    'private',
    'protected',
    'public',
    'return',
    'static',
    'super',
    'switch',
    'this',
    'throw',
    'true',
    'try',
    'typeof',
    'var',
    'void',
    'while',
    'with',
    'yield',
  };

  @override
  List<StyledTextRange> highlight(String source, {String? language}) {
    final name = language?.toLowerCase();
    if (name == null || !_lexedLanguages.contains(name)) return const [];
    final reserved = _keywords[name] ?? const <String>{};
    final ranges = <StyledTextRange>[];
    var index = 0;
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code == 0x2f && index + 1 < source.length) {
        final next = source.codeUnitAt(index + 1);
        if (next == 0x2f) {
          final end = _lineEnd(source, index);
          ranges.add(_range(index, end, comment));
          index = end;
          continue;
        }
        if (next == 0x2a) {
          final close = source.indexOf('*/', index + 2);
          final end = close < 0 ? source.length : close + 2;
          ranges.add(_range(index, end, comment));
          index = end;
          continue;
        }
      }
      if (code == 0x27 || code == 0x22) {
        final end = _stringEnd(source, index, code);
        ranges.add(_range(index, end, string));
        index = end;
        continue;
      }
      if (_isDigit(code)) {
        var end = index + 1;
        while (end < source.length && _isNumberPart(source.codeUnitAt(end))) {
          end++;
        }
        ranges.add(_range(index, end, number));
        index = end;
        continue;
      }
      if (_isWordStart(code)) {
        var end = index + 1;
        while (end < source.length && _isWordPart(source.codeUnitAt(end))) {
          end++;
        }
        if (reserved.contains(source.substring(index, end))) {
          ranges.add(_range(index, end, keyword));
        }
        index = end;
        continue;
      }
      index++;
    }
    return ranges;
  }

  static StyledTextRange _range(int start, int end, TextStyle style) =>
      StyledTextRange(start: start, end: end, style: style);

  static int _lineEnd(String source, int start) {
    final newline = source.indexOf('\n', start);
    return newline < 0 ? source.length : newline;
  }

  static int _stringEnd(String source, int start, int quote) {
    var index = start + 1;
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code == 0x0a) return index;
      if (code == 0x5c) {
        index += 2;
        continue;
      }
      index++;
      if (code == quote) return index;
    }
    return source.length;
  }

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

  static bool _isNumberPart(int code) =>
      _isDigit(code) || code == 0x2e || code == 0x5f;

  static bool _isWordStart(int code) =>
      (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      code == 0x5f ||
      code == 0x24;

  static bool _isWordPart(int code) => _isWordStart(code) || _isDigit(code);
}

/// Product-neutral agent transcript composed only from Noir's public widgets.
///
/// A supplied [controller] is borrowed. When it is omitted, this widget owns a
/// session controller around [backend], or around a local replay backend when
/// both are omitted.
class ChatDemoApp extends StatefulWidget {
  const ChatDemoApp({
    super.key,
    this.controller,
    this.backend,
    this.pathSuggestions = _defaultPathSuggestions,
    this.enableReplayControls = true,
    this.autofocusComposer = true,
    this.enableAnimation = true,
  }) : assert(
         controller == null || backend == null,
         'ChatDemoApp accepts either controller or backend, not both.',
       );

  final AgentSessionController? controller;
  final AgentBackend? backend;
  final List<String> pathSuggestions;
  final bool enableReplayControls;
  final bool autofocusComposer;
  final bool enableAnimation;

  @override
  State<ChatDemoApp> createState() => _ChatDemoAppState();
}

const _defaultPathSuggestions = <String>[
  'lib/noir.dart',
  'lib/src/widgets/text_area.dart',
  'example/chat_demo.dart',
  'test/example/chat_demo_test.dart',
  'README.md',
];

const _commands = <({String value, String description})>[
  (value: '/review', description: 'Inspect the focused change'),
  (value: '/permission', description: 'Preview a permission decision'),
  (value: '/question', description: 'Preview a user question'),
  (value: '/error', description: 'Replay a failed request'),
  (value: '/help', description: 'Show the local replay commands'),
];

const _demoEditDiff =
    'diff --git a/example/chat_demo.dart b/example/chat_demo.dart\n'
    '--- a/example/chat_demo.dart\n'
    '+++ b/example/chat_demo.dart\n'
    '@@ -1,3 +1,4 @@\n'
    ' void main() {\n'
    '-  runTuiApp(const ChatDemoApp());\n'
    '+  // Keep the replay deterministic.\n'
    '+  runTuiApp(const ChatDemoApp());\n'
    ' }';

enum _ModalSurface { permission, question, model, sessions }

final class _Suggestion {
  const _Suggestion({
    required this.value,
    required this.description,
    required this.start,
    required this.end,
  });

  final String value;
  final String description;
  final int start;
  final int end;
}

final class _SessionTreeValue {
  const _SessionTreeValue(this.label, [this.sessionId]);

  final String label;
  final String? sessionId;
}

class _ChatDemoAppState extends State<ChatDemoApp> {
  final _composerController = TextEditingController();
  final _questionController = TextEditingController();
  final _composerFocus = FocusNode(debugLabel: 'agent-composer');
  final _transcriptFocus = FocusNode(debugLabel: 'agent-transcript');
  final _permissionDenyFocus = FocusNode(debugLabel: 'agent-permission-deny');
  final _permissionAllowFocus = FocusNode(debugLabel: 'agent-permission-allow');
  final _questionChoicesFocus = FocusNode(debugLabel: 'agent-question-choices');
  final _questionAnswerFocus = FocusNode(debugLabel: 'agent-question-answer');
  final _questionSubmitFocus = FocusNode(debugLabel: 'agent-question-submit');
  final _modelPickerFocus = FocusNode(debugLabel: 'agent-model-picker');
  final _modelCancelFocus = FocusNode(debugLabel: 'agent-model-cancel');
  final _sessionPickerFocus = FocusNode(debugLabel: 'agent-session-picker');
  final _sessionCancelFocus = FocusNode(debugLabel: 'agent-session-cancel');
  final _transcriptController = ScrollController(followTail: true);
  final _modalController = ModalController();
  final _history = <String>[];

  late AgentSessionController _session;
  TreeViewController<_SessionTreeValue>? _sessionTree;
  _ModalSurface? _surface;
  List<_Suggestion> _suggestions = const [];
  int _suggestionIndex = 0;
  int? _historyIndex;
  String _historyScratch = '';
  bool _ownsSession = false;
  bool _settingDraft = false;
  bool _suggestionsSuppressed = false;
  int _modalRequest = 0;

  @override
  void initState() {
    super.initState();
    _validateConfiguration();
    _composerController.addListener(_handleDraftValueChanged);
    _transcriptController.addListener(_handleTranscriptChanged);
    _composerFocus.addListener(_handleRegionFocusChanged);
    _transcriptFocus.addListener(_handleRegionFocusChanged);
    _attachSession();
  }

  @override
  void didUpdateWidget(ChatDemoApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _validateConfiguration();
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    final backendChanged =
        oldWidget.controller == null &&
        widget.controller == null &&
        !identical(oldWidget.backend, widget.backend);
    if (controllerChanged || backendChanged) {
      _modalRequest++;
      _modalController.close();
      _surface = null;
      _disposeSessionTree();
      _detachSession();
      _attachSession();
    }
  }

  void _validateConfiguration() {
    if (widget.controller != null && widget.backend != null) {
      throw ArgumentError(
        'ChatDemoApp accepts either controller or backend, not both.',
      );
    }
  }

  void _attachSession() {
    final supplied = widget.controller;
    _ownsSession = supplied == null;
    _session =
        supplied ??
        AgentSessionController(
          backend: widget.backend ?? _createReplayBackend(),
        );
    _session.addListener(_handleSessionChanged);
    if (_session.permissionRequest != null) {
      _surface = _ModalSurface.permission;
      _scheduleModalOpen();
    } else if (_session.questionRequest != null) {
      _surface = _ModalSurface.question;
      _scheduleModalOpen();
    }
    unawaited(_session.start());
  }

  void _detachSession() {
    _session.removeListener(_handleSessionChanged);
    if (_ownsSession) unawaited(_session.close());
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final decisionSurface = _session.permissionRequest != null
        ? _ModalSurface.permission
        : _session.questionRequest != null
        ? _ModalSurface.question
        : null;
    final currentIsDecision =
        _surface == _ModalSurface.permission ||
        _surface == _ModalSurface.question;
    var openDecision = false;
    var closeDecision = false;
    setState(() {
      if (decisionSurface != null && _surface != decisionSurface) {
        _disposeSessionTree();
        _surface = decisionSurface;
        _questionController.clear();
        openDecision = true;
      } else if (decisionSurface == null && currentIsDecision) {
        _surface = null;
        closeDecision = true;
      }
    });
    if (openDecision) _scheduleModalOpen();
    if (closeDecision) _closeModalAndRestoreComposer();
  }

  void _handleDraftValueChanged() {
    if (_settingDraft || !mounted) return;
    _historyIndex = null;
    _historyScratch = '';
    _suggestionsSuppressed = false;
    _refreshSuggestions();
  }

  void _handleTranscriptChanged() {
    if (mounted) setState(() {});
  }

  void _handleRegionFocusChanged() {
    if (mounted) setState(() {});
  }

  void _refreshSuggestions() {
    final next = _suggestionsSuppressed
        ? const <_Suggestion>[]
        : _suggestionsForDraft();
    setState(() {
      _suggestions = next;
      _suggestionIndex = next.isEmpty
          ? 0
          : _suggestionIndex.clamp(0, next.length - 1);
    });
  }

  List<_Suggestion> _suggestionsForDraft() {
    final text = _composerController.text;
    final selection = _composerController.selection;
    if (!selection.isCollapsed || !selection.isValid) return const [];
    final caret = selection.extentOffset.clamp(0, text.length);
    final beforeCaret = text.substring(0, caret);
    if (widget.enableReplayControls &&
        beforeCaret.startsWith('/') &&
        !beforeCaret.contains(RegExp(r'\s'))) {
      final query = beforeCaret.toLowerCase();
      return [
        for (final command in _commands)
          if (command.value.startsWith(query))
            _Suggestion(
              value: command.value,
              description: command.description,
              start: 0,
              end: caret,
            ),
      ];
    }

    final mentionStart = beforeCaret.lastIndexOf('@');
    if (mentionStart < 0 ||
        (mentionStart > 0 &&
            !RegExp(r'\s').hasMatch(beforeCaret[mentionStart - 1]))) {
      return const [];
    }
    final query = beforeCaret.substring(mentionStart + 1);
    if (query.contains(RegExp(r'\s'))) return const [];
    final normalized = query.toLowerCase();
    return [
      for (final path in widget.pathSuggestions)
        if (path.toLowerCase().contains(normalized))
          _Suggestion(
            value: '@$path',
            description: 'Project path',
            start: mentionStart,
            end: caret,
          ),
    ];
  }

  void _setDraft(
    String text, {
    int? selectionOffset,
    bool suppressSuggestions = false,
  }) {
    _settingDraft = true;
    _composerController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: (selectionOffset ?? text.length).clamp(0, text.length),
      ),
    );
    _settingDraft = false;
    _suggestionsSuppressed = suppressSuggestions;
    _refreshSuggestions();
  }

  void _moveSuggestion(int delta) {
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestionIndex =
          (_suggestionIndex + delta + _suggestions.length) %
          _suggestions.length;
    });
  }

  bool _acceptSuggestion() {
    if (_suggestions.isEmpty) return false;
    final suggestion = _suggestions[_suggestionIndex];
    final current = _composerController.text;
    final updated = current.replaceRange(
      suggestion.start,
      suggestion.end,
      suggestion.value,
    );
    _setDraft(
      updated,
      selectionOffset: suggestion.start + suggestion.value.length,
      suppressSuggestions: true,
    );
    return true;
  }

  void _dismissSuggestions() {
    if (_suggestions.isEmpty) return;
    _suggestionsSuppressed = true;
    _refreshSuggestions();
  }

  void _submitPrompt() {
    if (_acceptSuggestion()) return;
    final prompt = _composerController.text.trim();
    if (!_session.submit(prompt)) return;
    if (_history.isEmpty || _history.last != prompt) _history.add(prompt);
    _historyIndex = null;
    _historyScratch = '';
    _setDraft('');
  }

  bool _showPreviousPrompt() {
    if (_history.isEmpty) return false;
    if (_historyIndex == null) {
      _historyScratch = _composerController.text;
      _historyIndex = _history.length - 1;
    } else if (_historyIndex! > 0) {
      _historyIndex = _historyIndex! - 1;
    }
    _setDraft(_history[_historyIndex!], suppressSuggestions: true);
    return true;
  }

  bool _showNextPrompt() {
    final index = _historyIndex;
    if (index == null) return false;
    if (index < _history.length - 1) {
      _historyIndex = index + 1;
      _setDraft(_history[_historyIndex!], suppressSuggestions: true);
    } else {
      _historyIndex = null;
      _setDraft(_historyScratch, suppressSuggestions: true);
      _historyScratch = '';
    }
    return true;
  }

  KeyEventResult _handleRootKey(FocusNode node, KeyEvent event) {
    if (!event.isPress || !_composerFocus.hasFocus) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab &&
        !event.isShiftPressed &&
        _acceptSuggestion()) {
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      if (_suggestions.isNotEmpty) {
        _moveSuggestion(-1);
        return KeyEventResult.handled;
      }
      if (_showPreviousPrompt()) {
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      if (_suggestions.isNotEmpty) {
        _moveSuggestion(1);
        return KeyEventResult.handled;
      }
      if (_showNextPrompt()) {
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _dismissOrInterrupt(
    BuildContext context, {
    required bool dismissSuggestions,
  }) {
    final surface = _surface;
    if (surface == _ModalSurface.permission ||
        surface == _ModalSurface.question) {
      unawaited(_session.interrupt());
      return KeyEventResult.handled;
    }
    if (surface != null) {
      _closeSurface();
      return KeyEventResult.handled;
    }
    if (dismissSuggestions && _suggestions.isNotEmpty) {
      _dismissSuggestions();
      return KeyEventResult.handled;
    }
    if (_session.isBusy) {
      unawaited(_session.interrupt());
      return KeyEventResult.handled;
    }
    TuiApp.exit(context);
    return KeyEventResult.handled;
  }

  KeyEventResult _cycleMode() {
    if (!widget.enableReplayControls || _surface != null) {
      return KeyEventResult.handled;
    }
    unawaited(_session.cyclePermissionMode());
    return KeyEventResult.handled;
  }

  KeyEventResult _focusTranscript() {
    if (_surface != null) return KeyEventResult.handled;
    if (_transcriptFocus.isAttached) _transcriptFocus.requestFocus();
    return KeyEventResult.handled;
  }

  KeyEventResult _pageTranscript({required bool down}) {
    if (_surface != null) return KeyEventResult.handled;
    if (down) {
      _transcriptController.pageDown();
    } else {
      _transcriptController.pageUp();
    }
    return KeyEventResult.handled;
  }

  KeyEventResult _showModelPicker() {
    if (!widget.enableReplayControls ||
        _surface != null ||
        _session.permissionRequest != null ||
        _session.questionRequest != null) {
      return KeyEventResult.handled;
    }
    _openSurface(_ModalSurface.model);
    return KeyEventResult.handled;
  }

  KeyEventResult _showSessionPicker() {
    if (!widget.enableReplayControls || _session.isBusy || _surface != null) {
      return KeyEventResult.handled;
    }
    _createSessionTree();
    _openSurface(_ModalSurface.sessions);
    return KeyEventResult.handled;
  }

  void _openSurface(_ModalSurface surface) {
    setState(() => _surface = surface);
    _scheduleModalOpen();
  }

  void _scheduleModalOpen() {
    final request = ++_modalRequest;
    Timer.run(() {
      if (!mounted || request != _modalRequest || _surface == null) return;
      _modalController.open();
    });
  }

  void _closeSurface() {
    _modalRequest++;
    _modalController.close();
    setState(() {
      _surface = null;
      _disposeSessionTree();
    });
    _restoreComposerFocus();
  }

  void _closeModalAndRestoreComposer() {
    _modalRequest++;
    _modalController.close();
    _restoreComposerFocus();
  }

  void _restoreComposerFocus() {
    if (_composerFocus.isAttached) _composerFocus.requestFocus();
  }

  void _createSessionTree() {
    _disposeSessionTree();
    final main = <TreeNode<_SessionTreeValue>>[];
    final forks = <TreeNode<_SessionTreeValue>>[];
    for (final session in _session.sessions) {
      final node = TreeNode<_SessionTreeValue>.leaf(
        id: 'session:${session.id}',
        value: _SessionTreeValue(
          '${session.title} · ${session.updatedLabel}',
          session.id,
        ),
      );
      (session.parentId == null ? main : forks).add(node);
    }
    final roots = <TreeNode<_SessionTreeValue>>[
      if (main.isNotEmpty)
        TreeNode<_SessionTreeValue>.branch(
          id: 'group:recent',
          value: const _SessionTreeValue('Recent'),
          children: main,
        ),
      if (forks.isNotEmpty)
        TreeNode<_SessionTreeValue>.branch(
          id: 'group:forks',
          value: const _SessionTreeValue('Forks'),
          children: forks,
        ),
    ];
    _sessionTree = TreeViewController<_SessionTreeValue>(
      roots: roots,
      initiallyExpanded: const {'group:recent', 'group:forks'},
      initialSelection: main.isNotEmpty
          ? main.first.id
          : forks.isNotEmpty
          ? forks.first.id
          : null,
    );
  }

  void _disposeSessionTree() {
    _sessionTree?.dispose();
    _sessionTree = null;
  }

  void _respondToPermission({required bool allow}) {
    unawaited(_session.respondToPermission(allow: allow));
  }

  void _answerQuestion(String answer) {
    if (answer.trim().isEmpty) return;
    unawaited(_session.answerQuestion(answer));
  }

  void _answerFreeText() => _answerQuestion(_questionController.text);

  void _selectModel(String model) {
    unawaited(
      _completeSurfaceAction(
        _ModalSurface.model,
        (session) => session.selectModel(model),
      ),
    );
  }

  void _activateSession(TreeNode<_SessionTreeValue> node) {
    final sessionId = node.value.sessionId;
    if (sessionId == null) return;
    unawaited(
      _completeSurfaceAction(
        _ModalSurface.sessions,
        (session) => session.loadSession(sessionId),
      ),
    );
  }

  Future<void> _completeSurfaceAction(
    _ModalSurface surface,
    Future<bool> Function(AgentSessionController session) action,
  ) async {
    final session = _session;
    final request = _modalRequest;
    final succeeded = await action(session);
    if (!succeeded ||
        !mounted ||
        !identical(_session, session) ||
        _surface != surface ||
        _modalRequest != request) {
      return;
    }
    _closeSurface();
  }

  FocusNode? get _modalInitialFocus => switch (_surface) {
    _ModalSurface.permission => _permissionDenyFocus,
    _ModalSurface.question =>
      (_session.questionRequest?.choices.isNotEmpty ?? false)
          ? _questionChoicesFocus
          : (_session.questionRequest?.allowFreeText ?? false)
          ? _questionAnswerFocus
          : null,
    _ModalSurface.model => _modelPickerFocus,
    _ModalSurface.sessions =>
      (_sessionTree?.roots.isNotEmpty ?? false)
          ? _sessionPickerFocus
          : _sessionCancelFocus,
    null => null,
  };

  @override
  Widget build(BuildContext context) => Shortcuts(
    shortcuts: _agentShortcuts,
    child: Actions(
      actions: <Type, Action<Intent>>{
        _DismissAgentIntent: CallbackAction<_DismissAgentIntent>(
          (intent, context) => _dismissOrInterrupt(
            context,
            dismissSuggestions: intent.dismissSuggestions,
          ),
        ),
        _CycleModeIntent: CallbackAction<_CycleModeIntent>(
          (intent, context) => _cycleMode(),
        ),
        _ShowModelIntent: CallbackAction<_ShowModelIntent>(
          (intent, context) => _showModelPicker(),
        ),
        _ShowSessionsIntent: CallbackAction<_ShowSessionsIntent>(
          (intent, context) => _showSessionPicker(),
        ),
        _FocusTranscriptIntent: CallbackAction<_FocusTranscriptIntent>(
          (intent, context) => _focusTranscript(),
        ),
        _PageTranscriptUpIntent: CallbackAction<_PageTranscriptUpIntent>(
          (intent, context) => _pageTranscript(down: false),
        ),
        _PageTranscriptDownIntent: CallbackAction<_PageTranscriptDownIntent>(
          (intent, context) => _pageTranscript(down: true),
        ),
      },
      child: Focus(
        canRequestFocus: false,
        onKeyEvent: _handleRootKey,
        child: Modal(
          controller: _modalController,
          initialFocusNode: _modalInitialFocus,
          dismissOnEscape: false,
          modalBuilder: _buildModal,
          child: _buildScreen(context),
        ),
      ),
    ),
  );

  Widget _buildScreen(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ScrollBox(
            key: const ValueKey<String>('transcript'),
            controller: _transcriptController,
            focusNode: _transcriptFocus,
            showScrollbar: !_transcriptController.isFollowingTail,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 1),
                for (final entry in _session.entries)
                  _buildTranscriptEntry(context, entry),
                if (_isActivePhase(_session.phase)) _buildActivity(context),
                if (_suggestions.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  _buildSuggestions(context),
                ],
                const SizedBox(height: 1),
                Container(
                  key: const ValueKey<String>('composer-panel'),
                  decoration: BoxDecoration(
                    border: Border.symmetric(
                      vertical: false,
                      color: _composerFocus.hasFocus
                          ? theme.accent
                          : theme.border,
                      title: _composerFocus.hasFocus
                          ? '${Icons.chevronRight} ${_session.sessionId}'
                          : _session.sessionId,
                      titleAlignment: TextAlign.right,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _session.isBusy ? '…' : Icons.chevronRight,
                        style: TextStyle(
                          color: _session.isBusy ? theme.warning : theme.accent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 1),
                      Expanded(
                        child: TextArea(
                          key: const ValueKey<String>('composer'),
                          controller: _composerController,
                          focusNode: _composerFocus,
                          autofocus: widget.autofocusComposer,
                          height: 1,
                          maxHeight: 4,
                          softWrap: true,
                          submitOnEnter: true,
                          backgroundColor: Color.transparent,
                          placeholder: _session.isBusy
                              ? 'Agent is working — Esc interrupts'
                              : widget.enableReplayControls
                              ? 'Message the agent, / for commands, @ for paths'
                              : widget.pathSuggestions.isEmpty
                              ? 'Message the agent'
                              : 'Message the agent, @ for paths',
                          onSubmit: _submitPrompt,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildFooter(context),
              ],
            ),
          ),
          if (_transcriptFocus.hasPrimaryFocus &&
              _transcriptController.offset > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                color: theme.surface,
                child: Text(
                  '${Icons.chevronRight} Agent Chat',
                  style: TextStyle(
                    color: theme.accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          spacing: 1,
          children: [
            Text(_transcriptFocus.hasPrimaryFocus ? Icons.chevronRight : ' '),
            Text(
              'Agent Chat',
              style: TextStyle(
                color: theme.accent,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              _phaseLabel(_session.phase),
              style: TextStyle(
                color: _phaseColor(theme),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            widget.enableReplayControls
                ? '${_session.model} · ${_modeLabel(_session.permissionMode)}'
                : _session.model,
            style: TextStyle(color: theme.textMuted),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            _session.sessionId,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    final theme = Theme.of(context);
    final usage = _session.inputTokens + _session.outputTokens;
    final detached = _transcriptController.isFollowingTail ? '' : ' · NEW';
    final controls = widget.enableReplayControls
        ? 'Ctrl+J newline · Enter send · Shift+Tab mode · Ctrl+M model · '
              'Ctrl+R sessions'
        : 'Ctrl+J newline · Enter send · Esc interrupt';
    return Row(
      spacing: 1,
      children: [
        Expanded(
          child: Text(
            controls,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: theme.textMuted),
          ),
        ),
        Text(
          '$usage tok · \$${_session.costUsd.toStringAsFixed(3)}$detached',
          maxLines: 1,
          softWrap: false,
          style: TextStyle(color: theme.textMuted),
        ),
      ],
    );
  }

  Widget _buildActivity(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 1),
      child: _markRow(
        Text(
          _phaseLabel(_session.phase),
          style: TextStyle(color: theme.warning),
        ),
        marker: widget.enableAnimation
            ? Spinner(color: theme.warning)
            : Text(
                SpinnerFrames.dots.first,
                style: TextStyle(color: theme.warning),
              ),
      ),
    );
  }

  Widget _buildTranscriptEntry(
    BuildContext context,
    AgentTranscriptEntry entry,
  ) {
    final theme = Theme.of(context);
    return Container(
      key: ValueKey<String>('entry-${entry.id}'),
      margin: const EdgeInsets.only(top: 1),
      child: switch (entry.kind) {
        AgentEntryKind.user => Container(
          color: theme.surfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Text(
            '${Icons.chevronRight} ${entry.text}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        AgentEntryKind.assistant => _markRow(
          marker: _turnMarker(theme),
          MarkdownView(
            markdown: entry.text,
            embedded: true,
            selectable: false,
            theme: _markdownTheme(theme),
            codeHighlighter: const AgentCodeHighlighter(),
            tableCellPaddingX: 1,
          ),
        ),
        AgentEntryKind.tool => _markRow(
          _buildToolEntry(context, entry),
          marker: _turnMarker(theme),
        ),
        AgentEntryKind.notice => _markRow(
          Text(
            entry.text,
            style: TextStyle(
              color: entry.status == AgentEntryStatus.failed
                  ? theme.danger
                  : theme.textMuted,
            ),
          ),
        ),
        AgentEntryKind.unknown => _markRow(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                entry.title,
                style: TextStyle(
                  color: theme.warning,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(entry.text, style: TextStyle(color: theme.textMuted)),
            ],
          ),
        ),
      },
    );
  }

  /// Prefixes one transcript row with the marker gutter.
  ///
  /// Every row of the page uses this one-column gutter, so wrapped body text
  /// keeps a hanging indent under the body column. Omit [marker] for a
  /// secondary row: the gutter stays aligned, and the row does not claim to
  /// be an agent turn.
  Widget _markRow(Widget body, {Widget? marker}) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      marker ?? const SizedBox(width: 1),
      const SizedBox(width: 1),
      Expanded(child: body),
    ],
  );

  /// The marker that identifies an agent turn.
  Widget _turnMarker(ThemeData theme) =>
      Text(Icons.circle, style: TextStyle(color: theme.textMuted));

  Widget _buildToolEntry(BuildContext context, AgentTranscriptEntry entry) {
    final theme = Theme.of(context);
    final status = switch (entry.status) {
      AgentEntryStatus.running => 'RUN',
      AgentEntryStatus.succeeded => 'DONE',
      AgentEntryStatus.failed => 'FAIL',
      AgentEntryStatus.cancelled => 'STOP',
      _ => 'TOOL',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          spacing: 1,
          children: [
            Text(
              status,
              style: TextStyle(
                color: _entryColor(theme, entry.status),
                fontWeight: FontWeight.bold,
              ),
            ),
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Button(
              key: ValueKey<String>('tool-details-${entry.id}'),
              label: entry.expanded ? 'Hide' : 'Details',
              color: Color.transparent,
              textColor: theme.textMuted,
              onPressed: () => _session.toggleToolExpanded(entry.id),
            ),
          ],
        ),
        if (entry.expanded)
          Container(
            padding: const EdgeInsets.only(left: 2),
            child: _buildToolContent(
              entry.text,
              entry.contentKind,
              plainTextStyle: TextStyle(color: theme.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _buildToolContent(
    String text,
    AgentToolContentKind contentKind, {
    TextStyle? plainTextStyle,
  }) {
    if (contentKind == AgentToolContentKind.unifiedDiff) {
      final document = const UnifiedDiffParser().parse(text);
      if (document.files.any((file) => file.hunks.isNotEmpty)) {
        return SizedBox(
          height: _boundedToolContentHeight(text),
          child: DiffView(
            document: document,
            wrap: true,
            selectable: false,
            canRequestFocus: false,
          ),
        );
      }
    }
    return Text(text, style: plainTextStyle);
  }

  int _boundedToolContentHeight(String text) {
    final rows = text.split('\n').length;
    if (rows < 3) return 3;
    if (rows > 8) return 8;
    return rows;
  }

  Widget _buildSuggestions(BuildContext context) {
    final theme = Theme.of(context);
    var start = _suggestionIndex < 4 ? 0 : _suggestionIndex - 3;
    if (start > _suggestions.length - 4) {
      start = _suggestions.length - 4;
    }
    if (start < 0) start = 0;
    final end = start + 4 < _suggestions.length
        ? start + 4
        : _suggestions.length;
    final visible = _suggestions.sublist(start, end);
    return Container(
      key: const ValueKey<String>('composer-suggestions'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _composerController.text.startsWith('/') ? 'Commands' : 'Paths',
            style: TextStyle(
              color: theme.textMuted,
              fontWeight: FontWeight.bold,
            ),
          ),
          for (var index = 0; index < visible.length; index++)
            Container(
              color: start + index == _suggestionIndex
                  ? theme.selectedBackground
                  : Color.transparent,
              child: Row(
                spacing: 1,
                children: [
                  Text(
                    start + index == _suggestionIndex
                        ? Icons.chevronRight
                        : ' ',
                  ),
                  Text(
                    visible[index].value,
                    style: TextStyle(
                      color: start + index == _suggestionIndex
                          ? theme.selectedForeground
                          : theme.text,
                      fontWeight: start + index == _suggestionIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      visible[index].description,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: theme.textMuted),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModal(BuildContext context) {
    final content = switch (_surface) {
      _ModalSurface.permission => _buildPermissionModal(context),
      _ModalSurface.question => _buildQuestionModal(context),
      _ModalSurface.model => _buildModelModal(context),
      _ModalSurface.sessions => _buildSessionModal(context),
      null => const SizedBox(),
    };
    return Container(
      color: Theme.of(context).surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [content],
      ),
    );
  }

  Widget _buildPermissionModal(BuildContext context) {
    final theme = Theme.of(context);
    final request = _session.permissionRequest;
    if (request == null) return const SizedBox();
    return Panel(
      title: 'Permission required',
      focused: true,
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.toolName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(request.reason),
          if (request.preview case final preview?)
            _buildToolContent(preview, request.previewContentKind),
          if (_session.lastError case final error?)
            Text(error, style: TextStyle(color: theme.danger)),
          Row(
            spacing: 1,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                key: const ValueKey<String>('permission-deny'),
                label: 'Deny',
                focusNode: _permissionDenyFocus,
                color: theme.surfaceVariant,
                textColor: theme.text,
                onPressed: _session.decisionInFlight
                    ? null
                    : () => _respondToPermission(allow: false),
              ),
              Button(
                key: const ValueKey<String>('permission-allow'),
                label: 'Allow',
                focusNode: _permissionAllowFocus,
                onPressed: _session.decisionInFlight
                    ? null
                    : () => _respondToPermission(allow: true),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionModal(BuildContext context) {
    final theme = Theme.of(context);
    final request = _session.questionRequest;
    if (request == null) return const SizedBox();
    final choiceHeight = request.choices.length > 4
        ? 4
        : request.choices.isEmpty
        ? 0
        : request.choices.length;
    return Panel(
      title: 'Agent question',
      focused: true,
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            request.prompt,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (request.choices.isNotEmpty)
            Select<String>(
              key: const ValueKey<String>('question-choices'),
              options: [
                for (final choice in request.choices)
                  SelectOption<String>(name: choice, value: choice),
              ],
              height: choiceHeight,
              focusNode: _questionChoicesFocus,
              onSelect: (index, option) => _answerQuestion(option.value!),
            ),
          if (request.allowFreeText)
            Row(
              spacing: 1,
              children: [
                Expanded(
                  child: TextInput(
                    key: const ValueKey<String>('question-answer'),
                    controller: _questionController,
                    focusNode: _questionAnswerFocus,
                    placeholder: 'Type another answer',
                    onSubmit: _answerFreeText,
                  ),
                ),
                Button(
                  key: const ValueKey<String>('question-submit'),
                  label: 'Answer',
                  focusNode: _questionSubmitFocus,
                  onPressed: _session.decisionInFlight ? null : _answerFreeText,
                ),
              ],
            ),
          if (_session.lastError case final error?)
            Text(error, style: TextStyle(color: theme.danger)),
        ],
      ),
    );
  }

  Widget _buildModelModal(BuildContext context) {
    final models = const ['haiku', 'sonnet', 'opus'];
    final selected = models.indexOf(_session.model);
    return Panel(
      title: 'Choose model',
      focused: true,
      width: 42,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Select<String>(
            key: const ValueKey<String>('model-picker'),
            options: [
              for (final model in models)
                SelectOption<String>(name: model, value: model),
            ],
            selectedIndex: selected < 0 ? 0 : selected,
            height: models.length,
            focusNode: _modelPickerFocus,
            onSelect: (index, option) => _selectModel(option.value!),
          ),
          if (_session.lastError case final error?)
            Text(error, style: TextStyle(color: Theme.of(context).danger)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                key: const ValueKey<String>('model-cancel'),
                label: 'Cancel',
                focusNode: _modelCancelFocus,
                onPressed: _closeSurface,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionModal(BuildContext context) {
    final tree = _sessionTree;
    return Panel(
      title: 'Resume session',
      focused: true,
      width: 58,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tree == null || tree.roots.isEmpty)
            const Text('No replay sessions are available.')
          else
            TreeView<_SessionTreeValue>(
              key: const ValueKey<String>('session-picker'),
              controller: tree,
              focusNode: _sessionPickerFocus,
              showScrollIndicator: true,
              itemBuilder: (context, node, selected) => Text(
                node.value.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              onActivate: _activateSession,
            ),
          if (_session.lastError case final error?)
            Text(error, style: TextStyle(color: Theme.of(context).danger)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Button(
                key: const ValueKey<String>('session-cancel'),
                label: 'Cancel',
                focusNode: _sessionCancelFocus,
                onPressed: _closeSurface,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _phaseColor(ThemeData theme) => switch (_session.phase) {
    AgentRunPhase.idle => theme.success,
    AgentRunPhase.failed => theme.danger,
    AgentRunPhase.cancelled || AgentRunPhase.closed => theme.textMuted,
    _ => theme.warning,
  };

  /// Transcript Markdown palette.
  ///
  /// Headings use the body colour so they do not compete with live status
  /// colour. Heading one and two add an underline. Inline code uses a
  /// distinct foreground instead of a filled background.
  MarkdownThemeData _markdownTheme(ThemeData theme) =>
      MarkdownThemeData.fromTheme(theme).copyWith(
        heading1: TextStyle(
          color: theme.text,
          attributes: Attr.bold | Attr.underline,
        ),
        heading2: TextStyle(
          color: theme.text,
          attributes: Attr.bold | Attr.underline,
        ),
        heading3: TextStyle(color: theme.text, attributes: Attr.bold),
        inlineCode: TextStyle(color: theme.info),
        quote: TextStyle(color: theme.text, attributes: Attr.italic),
      );

  Color _entryColor(ThemeData theme, AgentEntryStatus status) =>
      switch (status) {
        AgentEntryStatus.succeeded => theme.success,
        AgentEntryStatus.failed => theme.danger,
        AgentEntryStatus.cancelled => theme.textMuted,
        _ => theme.warning,
      };

  bool _isActivePhase(AgentRunPhase phase) => switch (phase) {
    AgentRunPhase.starting ||
    AgentRunPhase.running ||
    AgentRunPhase.retrying ||
    AgentRunPhase.loadingSession => true,
    _ => false,
  };

  String _phaseLabel(AgentRunPhase phase) => switch (phase) {
    AgentRunPhase.starting => 'STARTING',
    AgentRunPhase.idle => 'READY',
    AgentRunPhase.running => 'WORKING',
    AgentRunPhase.retrying => 'RETRYING',
    AgentRunPhase.waitingPermission => 'REVIEW',
    AgentRunPhase.waitingQuestion => 'QUESTION',
    AgentRunPhase.loadingSession => 'LOADING',
    AgentRunPhase.failed => 'FAILED',
    AgentRunPhase.cancelled => 'STOPPED',
    AgentRunPhase.closed => 'CLOSED',
  };

  String _modeLabel(AgentPermissionMode mode) => switch (mode) {
    AgentPermissionMode.review => 'review',
    AgentPermissionMode.autoEdit => 'auto-edit',
    AgentPermissionMode.plan => 'plan',
  };

  @override
  void dispose() {
    _modalRequest++;
    _session.removeListener(_handleSessionChanged);
    if (_ownsSession) unawaited(_session.close());
    _disposeSessionTree();
    _composerController
      ..removeListener(_handleDraftValueChanged)
      ..dispose();
    _questionController.dispose();
    _composerFocus
      ..removeListener(_handleRegionFocusChanged)
      ..dispose();
    _transcriptFocus
      ..removeListener(_handleRegionFocusChanged)
      ..dispose();
    for (final node in [
      _permissionDenyFocus,
      _permissionAllowFocus,
      _questionChoicesFocus,
      _questionAnswerFocus,
      _questionSubmitFocus,
      _modelPickerFocus,
      _modelCancelFocus,
      _sessionPickerFocus,
      _sessionCancelFocus,
    ]) {
      node.dispose();
    }
    _transcriptController
      ..removeListener(_handleTranscriptChanged)
      ..dispose();
    super.dispose();
  }
}

ReplayAgentBackend _createReplayBackend() {
  late final ReplayAgentBackend backend;
  return backend = ReplayAgentBackend(
    initialEvents: const [
      AgentSessionEvent(
        id: 'demo-session',
        sessionId: 'local replay',
        model: 'sonnet',
        permissionMode: AgentPermissionMode.review,
      ),
    ],
    scripts: {
      '/review': [
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 100),
          (requestId) => AgentTextDeltaEvent(
            id: '$requestId:text:1',
            requestId: requestId,
            blockId: 'answer',
            delta: 'I inspected the focused change. ',
          ),
        ),
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 120),
          (requestId) => AgentToolStartedEvent(
            id: '$requestId:tool:start',
            requestId: requestId,
            blockId: 'read',
            name: 'Read',
            summary: 'lib/src/widgets/text_area.dart',
          ),
        ),
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 80),
          (requestId) => AgentToolResultEvent(
            id: '$requestId:tool:done',
            requestId: requestId,
            blockId: 'read',
            output: 'The focused guard is present.',
          ),
        ),
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 80),
          (requestId) => AgentTextFinalEvent(
            id: '$requestId:text:final',
            requestId: requestId,
            blockId: 'answer',
            text: 'I inspected the focused change. **No blocker found.**',
          ),
        ),
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 40),
          (requestId) => AgentRequestCompletedEvent(
            id: '$requestId:complete',
            requestId: requestId,
            inputTokens: 42,
            outputTokens: 18,
            costUsd: 0.006,
          ),
        ),
      ],
      '/permission': [
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 100),
          (requestId) => AgentPermissionRequestEvent(
            id: '$requestId:permission',
            requestId: requestId,
            permissionId: 'demo-edit',
            toolName: 'Edit',
            reason: 'Update example/chat_demo.dart',
            preview: _demoEditDiff,
            previewContentKind: AgentToolContentKind.unifiedDiff,
          ),
        ),
      ],
      '/question': [
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 100),
          (requestId) => AgentQuestionRequestEvent(
            id: '$requestId:question',
            requestId: requestId,
            questionId: 'scope',
            prompt: 'Which scope should the replay inspect?',
            choices: const ['Focused files', 'Whole package'],
            allowFreeText: true,
          ),
        ),
      ],
      '/error': [
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 100),
          (requestId) => AgentRequestFailedEvent(
            id: '$requestId:failed',
            requestId: requestId,
            message: 'The deterministic error replay failed as requested.',
          ),
        ),
      ],
      '/help': [
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 80),
          (requestId) => AgentTextFinalEvent(
            id: '$requestId:help',
            requestId: requestId,
            blockId: 'answer',
            text: 'Try `/review`, `/permission`, `/question`, or `/error`.',
          ),
        ),
        AgentReplayStep.forRequest(
          const Duration(milliseconds: 20),
          (requestId) => AgentRequestCompletedEvent(
            id: '$requestId:complete',
            requestId: requestId,
            inputTokens: 8,
            outputTokens: 7,
            costUsd: 0.001,
          ),
        ),
      ],
    },
    fallbackScript: [
      AgentReplayStep.forRequest(
        const Duration(milliseconds: 120),
        (requestId) => AgentTextDeltaEvent(
          id: '$requestId:text:1',
          requestId: requestId,
          blockId: 'answer',
          delta: 'This local replay received the prompt. ',
        ),
      ),
      AgentReplayStep.forRequest(
        const Duration(milliseconds: 100),
        (requestId) => AgentTextFinalEvent(
          id: '$requestId:text:final',
          requestId: requestId,
          blockId: 'answer',
          text:
              'This local replay received the prompt. **No network was used.**',
        ),
      ),
      AgentReplayStep.forRequest(
        const Duration(milliseconds: 40),
        (requestId) => AgentRequestCompletedEvent(
          id: '$requestId:complete',
          requestId: requestId,
          inputTokens: 16,
          outputTokens: 12,
          costUsd: 0.002,
        ),
      ),
    ],
    sessions: const [
      AgentSessionSummary(
        id: 'welcome',
        title: 'Welcome replay',
        updatedLabel: 'just now',
      ),
      AgentSessionSummary(
        id: 'review',
        title: 'Focused review',
        updatedLabel: '5m ago',
        parentId: 'welcome',
      ),
    ],
    snapshots: {
      'welcome': AgentSessionSnapshot(
        sessionId: 'welcome',
        model: 'sonnet',
        permissionMode: AgentPermissionMode.review,
        entries: const [
          AgentSnapshotEntry(
            id: 'welcome-agent',
            kind: AgentSnapshotEntryKind.assistant,
            text: 'Welcome back. This transcript came from a replay snapshot.',
          ),
        ],
      ),
      'review': AgentSessionSnapshot(
        sessionId: 'review',
        model: 'opus',
        permissionMode: AgentPermissionMode.plan,
        entries: const [
          AgentSnapshotEntry(
            id: 'review-user',
            kind: AgentSnapshotEntryKind.user,
            text: 'Review the focused change.',
          ),
          AgentSnapshotEntry(
            id: 'review-agent',
            kind: AgentSnapshotEntryKind.assistant,
            text: 'The replayed review found no blocker.',
          ),
        ],
        inputTokens: 42,
        outputTokens: 18,
        costUsd: 0.006,
      ),
    },
    onCommand: (command) {
      if (command.kind != AgentBackendCommandKind.permission &&
          command.kind != AgentBackendCommandKind.answer) {
        return;
      }
      final requestId = command.requestId;
      if (requestId == null) return;
      Timer.run(() {
        if (backend.isClosed) return;
        final text = switch (command.kind) {
          AgentBackendCommandKind.permission =>
            (command.allowed ?? false)
                ? 'Permission allowed. The replay can continue.'
                : 'Permission denied. No change was made.',
          AgentBackendCommandKind.answer =>
            'Answer recorded: ${command.value ?? ''}',
          _ => throw StateError('unreachable replay decision'),
        };
        backend
          ..emit(
            AgentTextFinalEvent(
              id: '$requestId:decision:text',
              requestId: requestId,
              blockId: 'decision',
              text: text,
            ),
          )
          ..emit(
            AgentRequestCompletedEvent(
              id: '$requestId:decision:complete',
              requestId: requestId,
              inputTokens: 10,
              outputTokens: 6,
              costUsd: 0.001,
            ),
          );
      });
    },
  );
}

const Map<ShortcutActivator, Intent> _agentShortcuts = {
  SingleActivator(LogicalKeyboardKey.escape): _DismissAgentIntent(
    dismissSuggestions: true,
  ),
  SingleActivator(LogicalKeyboardKey.keyC, control: true): _DismissAgentIntent(
    dismissSuggestions: false,
  ),
  SingleActivator(LogicalKeyboardKey.tab, shift: true): _CycleModeIntent(),
  SingleActivator(LogicalKeyboardKey.keyM, control: true): _ShowModelIntent(),
  SingleActivator(LogicalKeyboardKey.keyR, control: true):
      _ShowSessionsIntent(),
  SingleActivator(LogicalKeyboardKey.keyO, control: true):
      _FocusTranscriptIntent(),
  SingleActivator(LogicalKeyboardKey.pageUp): _PageTranscriptUpIntent(),
  SingleActivator(LogicalKeyboardKey.pageDown): _PageTranscriptDownIntent(),
};

class _DismissAgentIntent extends Intent {
  const _DismissAgentIntent({required this.dismissSuggestions});

  final bool dismissSuggestions;
}

class _CycleModeIntent extends Intent {
  const _CycleModeIntent();
}

class _ShowModelIntent extends Intent {
  const _ShowModelIntent();
}

class _ShowSessionsIntent extends Intent {
  const _ShowSessionsIntent();
}

class _FocusTranscriptIntent extends Intent {
  const _FocusTranscriptIntent();
}

class _PageTranscriptUpIntent extends Intent {
  const _PageTranscriptUpIntent();
}

class _PageTranscriptDownIntent extends Intent {
  const _PageTranscriptDownIntent();
}
