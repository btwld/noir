import 'dart:async';

import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';
import '../session/mcp_session.dart';
import 'console_pane.dart';
import 'detail_pane.dart';
import 'elicitation_modal.dart';
import 'header.dart';
import 'primitives_pane.dart';
import 'protocol_pane.dart';

/// The inspector palette: one accent, otherwise the shipped dark tokens.
final inspectorTheme = ThemeData.dark.copyWith(
  accent: const Color(0.45, 0.78, 0.55),
  accentForeground: const Color(0.02, 0.09, 0.05),
  selectedBackground: const Color(0.10, 0.22, 0.14),
  selectedForeground: const Color(0.62, 0.92, 0.72),
  border: const Color(0.18, 0.26, 0.21),
);

/// Moves the active tab to the index this intent carries.
final class SelectTabIntent extends Intent {
  /// Creates an intent that selects the tab at [index].
  const SelectTabIntent(this.index);

  /// Zero-based position in [InspectorTab.values].
  final int index;
}

/// Moves the active tab one step in the direction this intent carries.
final class StepTabIntent extends Intent {
  /// Creates an intent that steps the tab by [delta].
  const StepTabIntent(this.delta);

  /// How far to move, normally minus one or plus one.
  final int delta;
}

/// Sends the request the active tab and selection describe.
final class RunRequestIntent extends Intent {
  /// Creates a run intent.
  const RunRequestIntent();
}

/// Swaps the detail pane between the generated form and the raw schema.
final class ToggleSchemaIntent extends Intent {
  /// Creates the intent.
  const ToggleSchemaIntent();
}

/// Ends the application through the supported [TuiApp.exit] path.
final class ExitInspectorIntent extends Intent {
  /// Creates an exit intent.
  const ExitInspectorIntent();
}

/// The MCP inspector screen.
///
/// The widget owns the [InspectorController], the modal, the focus nodes, and
/// the console scroll position. It never touches `package:mcp_dart`: the
/// session boundary supplies value types this package owns.
class InspectorApp extends StatefulWidget {
  /// Creates the screen over [session], which it connects and closes.
  const InspectorApp({required this.session, super.key});

  /// The boundary this screen drives.
  final McpSession session;

  @override
  State<InspectorApp> createState() => _InspectorAppState();
}

class _InspectorAppState extends State<InspectorApp> {
  late final InspectorController _controller;
  final ModalController _modal = ModalController();
  final ScrollController _consoleScroll = ScrollController(followTail: true);
  final FocusNode _tabsFocus = FocusNode(debugLabel: 'tabs');
  final FocusNode _listFocus = FocusNode(debugLabel: 'primitives');
  final FocusNode _runFocus = FocusNode(debugLabel: 'run');
  final FocusNode _schemaFocus = FocusNode(debugLabel: 'schema');
  final FocusNode _resultFocus = FocusNode(debugLabel: 'result');
  final FocusNode _messageFocus = FocusNode(debugLabel: 'message');
  final FocusNode _consoleFocus = FocusNode(debugLabel: 'console');
  final Map<String, FocusNode> _fieldNodes = <String, FocusNode>{};
  InspectorTab _focusedTab = InspectorTab.tools;

  @override
  void initState() {
    super.initState();
    _controller = InspectorController(session: widget.session)
      ..addListener(_handleControllerChanged);
    unawaited(_controller.connect());
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    for (final node in _fieldNodes.values) {
      node.dispose();
    }
    _fieldNodes.clear();
    _tabsFocus.dispose();
    _listFocus.dispose();
    _runFocus.dispose();
    _schemaFocus.dispose();
    _resultFocus.dispose();
    _messageFocus.dispose();
    _consoleFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: inspectorTheme,
    child: Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        for (var index = 0; index < InspectorTab.values.length; index++)
          SingleActivator(_digitKeys[index], control: true): SelectTabIntent(
            index,
          ),
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            const RunRequestIntent(),
        const SingleActivator(LogicalKeyboardKey.keyR, control: true):
            const RunRequestIntent(),
        // Ctrl+N and Ctrl+P step the tab strip from anywhere, including a
        // focused field. `[` and `]` are scoped to regions that never accept
        // typing, and terminals do not agree on Ctrl with a digit.
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            const StepTabIntent(1),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true):
            const StepTabIntent(-1),
        // Ctrl+O reads as "open the schema". A bare letter would hijack a
        // focused field, and Ctrl+Enter and Ctrl with a digit never arrive
        // without the Kitty keyboard protocol.
        const SingleActivator(LogicalKeyboardKey.keyO, control: true):
            const ToggleSchemaIntent(),
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true):
            const ExitInspectorIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SelectTabIntent: CallbackAction<SelectTabIntent>((intent, context) {
            _controller.selectTab(InspectorTab.values[intent.index]);
            return KeyEventResult.handled;
          }),
          StepTabIntent: CallbackAction<StepTabIntent>((intent, context) {
            final next = _controller.activeTab.index + intent.delta;
            if (next < 0 || next >= InspectorTab.values.length) {
              return KeyEventResult.handled;
            }
            _controller.selectTab(InspectorTab.values[next]);
            return KeyEventResult.handled;
          }),
          RunRequestIntent: CallbackAction<RunRequestIntent>((intent, context) {
            unawaited(_controller.run());
            return KeyEventResult.handled;
          }),
          ToggleSchemaIntent: CallbackAction<ToggleSchemaIntent>((
            intent,
            context,
          ) {
            final wasVisible = _controller.visibleSchema != null;
            _controller.toggleSchema();
            // Swapping either view out removes whatever owned focus, and
            // `Shortcuts` are looked up from the focused element, so an
            // unfocused tree would stop answering every binding. Opening is
            // covered by the schema view's `autofocus`; closing has nothing
            // that autofocuses, so hand focus to Run, which stays mounted.
            if (wasVisible && _controller.visibleSchema == null) {
              _runFocus.requestFocus();
            }
            return KeyEventResult.handled;
          }),
          ExitInspectorIntent: CallbackAction<ExitInspectorIntent>((
            intent,
            context,
          ) {
            TuiApp.exit(context);
            return KeyEventResult.handled;
          }),
        },
        child: Modal(
          controller: _modal,
          dismissOnEscape: false,
          initialFocusNode: _firstElicitationNode(),
          modalBuilder: _buildModal,
          child: _buildPage(context),
        ),
      ),
    ),
  );

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.surface,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InspectorHeader(controller: _controller),
          TabSelect<InspectorTab>(
            key: const ValueKey<String>('tabs'),
            options: _tabOptions,
            selectedIndex: _controller.activeTab.index,
            focusNode: _tabsFocus,
            tabWidth: 15,
            showDescription: false,
            onChanged: (index, option) =>
                _controller.selectTab(InspectorTab.values[index]),
            onSelect: (index, option) =>
                _controller.selectTab(InspectorTab.values[index]),
          ),
          Expanded(child: _buildBody()),
          SizedBox(
            height: 1,
            child: Text(
              _footer,
              style: TextStyle(color: theme.textMuted),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.activeTab == InspectorTab.console) {
      return _withTabKeys(
        ConsolePane(
          controller: _controller,
          scrollController: _consoleScroll,
          focusNode: _consoleFocus,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 1,
      children: <Widget>[
        _withTabKeys(
          PrimitivesPane(
            controller: _controller,
            focusNode: _listFocus,
            onActivate: _activateRow,
          ),
        ),
        Expanded(
          child: _controller.activeTab == InspectorTab.protocol
              ? ProtocolPane(controller: _controller, focusNode: _messageFocus)
              : DetailPane(
                  controller: _controller,
                  focusNodeFor: _detailFieldNode,
                  runFocusNode: _runFocus,
                  schemaFocusNode: _schemaFocus,
                  resultFocusNode: _resultFocus,
                  onChanged: _rebuild,
                ),
        ),
      ],
    );
  }

  /// Adds `[` and `]` tab stepping to a region that never accepts typing.
  ///
  /// The activators stay out of the form on purpose: `Shortcuts` outranks the
  /// printable-character stage, so a bare `[` bound above a `TextInput` would
  /// make that character untypable.
  Widget _withTabKeys(Widget child) => Shortcuts(
    shortcuts: const <ShortcutActivator, Intent>{
      CharacterActivator('['): StepTabIntent(-1),
      CharacterActivator(']'): StepTabIntent(1),
    },
    child: child,
  );

  Widget _buildModal(BuildContext context) {
    final pending = _controller.pendingElicitation;
    if (pending == null) return const SizedBox();
    return ElicitationModal(
      pending: pending,
      focusNodeFor: _elicitationFieldNode,
      onChanged: _rebuild,
      onResolve: _controller.resolveElicitation,
    );
  }

  void _activateRow(int index) {
    _controller.select(index);
    // The schema view replaces the form, so its field nodes are detached and
    // focusing one throws. Selecting the row is the whole action here.
    if (_controller.visibleSchema != null) return;
    final target = _firstFieldAwaitingInput();
    if (target == null) {
      // Nothing to fill in: a resource read, or a form the defaults complete.
      if (_controller.activeTab != InspectorTab.protocol) {
        unawaited(_controller.run());
      }
      return;
    }
    _fieldNodes['field:$target']?.requestFocus();
  }

  /// The field Enter should move to: the first one still awaiting a value,
  /// or the first field when every value is already present.
  String? _firstFieldAwaitingInput() {
    final form = _controller.form;
    if (form == null || form.spec.isEmpty) return null;
    for (final field in form.spec.fields) {
      if (field.kind == FormFieldKind.boolean) continue;
      if (form.textOf(field.name).isEmpty) return field.name;
    }
    return form.spec.fields.first.name;
  }

  void _handleControllerChanged() {
    _syncFieldNodes();
    _syncTabFocus();
    _syncModal();
    if (mounted) setState(() {});
  }

  /// Keeps one node focused across a tab change.
  ///
  /// A tab change can remove the region that owns focus, and `Shortcuts` are
  /// looked up from the focused element, so an unfocused tree would stop
  /// answering every binding. The list and the console own their tab's focus;
  /// each takes it back through `autofocus` when its region remounts.
  void _syncTabFocus() {
    final tab = _controller.activeTab;
    final previous = _focusedTab;
    if (tab == previous) return;
    _focusedTab = tab;
    if (tab == InspectorTab.console || previous == InspectorTab.console) {
      return;
    }
    if (!_listFocus.hasFocus) _listFocus.requestFocus();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _syncModal() {
    final pending = _controller.pendingElicitation;
    if (pending != null && !_modal.isOpen) {
      _modal.open();
    } else if (pending == null && _modal.isOpen) {
      _modal.close();
    }
  }

  /// Keeps one focus node per generated field for the life of this state.
  ///
  /// Nodes are never disposed while the tree still references them: disposing
  /// an attached node throws `FocusNode is not attached to a FocusManager` on
  /// the next dispatch. A field that disappears only surrenders focus here;
  /// [dispose] releases every node at teardown.
  void _syncFieldNodes() {
    final wanted = <String>{
      for (final field
          in _controller.form?.spec.fields ?? const <FormFieldSpec>[])
        'field:${field.name}',
      for (final field
          in _controller.pendingElicitation?.form.spec.fields ??
              const <FormFieldSpec>[])
        'elicit:field:${field.name}',
    };
    for (final entry in _fieldNodes.entries) {
      if (entry.value.hasFocus && !wanted.contains(entry.key)) {
        entry.value.unfocus();
      }
    }
    for (final key in wanted) {
      _fieldNodes.putIfAbsent(key, () => FocusNode(debugLabel: key));
    }
  }

  FocusNode _detailFieldNode(String name) => _node('field:$name');

  FocusNode _elicitationFieldNode(String name) => _node('elicit:field:$name');

  FocusNode? _firstElicitationNode() {
    final first = _controller.pendingElicitation?.form.spec.fields.firstOrNull;
    return first == null ? null : _fieldNodes['elicit:field:${first.name}'];
  }

  FocusNode _node(String key) =>
      _fieldNodes.putIfAbsent(key, () => FocusNode(debugLabel: key));

  String get _footer => switch (_controller.connectionState) {
    InspectorConnectionState.failed =>
      _controller.errorMessage ?? 'The session failed.',
    _ => 'Tab focus  Ctrl+R run  Ctrl+O schema  Ctrl+N/P tabs  Ctrl+Q quit',
  };

  List<SelectOption<InspectorTab>> get _tabOptions =>
      <SelectOption<InspectorTab>>[
        SelectOption<InspectorTab>(
          name: 'Tools (${_controller.tools.length})',
          value: InspectorTab.tools,
        ),
        SelectOption<InspectorTab>(
          name: 'Resources (${_controller.resources.length})',
          value: InspectorTab.resources,
        ),
        SelectOption<InspectorTab>(
          name: 'Prompts (${_controller.prompts.length})',
          value: InspectorTab.prompts,
        ),
        SelectOption<InspectorTab>(
          name: 'Protocol (${_controller.protocolEntries.length})',
          value: InspectorTab.protocol,
        ),
        SelectOption<InspectorTab>(
          name: 'Console (${_controller.consoleLines.length})',
          value: InspectorTab.console,
        ),
      ];
}

const _digitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
];
