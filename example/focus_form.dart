// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

void main() {
  final app = runTuiApp(const FocusFormApp());
  app.enableMouse();
  app.enableKittyKeyboard();
}

class FocusFormApp extends StatefulWidget {
  const FocusFormApp({super.key});

  @override
  State<FocusFormApp> createState() => _FocusFormAppState();
}

class _FocusFormAppState extends State<FocusFormApp> {
  final FocusScopeNode _scopeNode = FocusScopeNode();
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();

  String _name = '';
  String _email = '';
  String _status = 'Tab moves focus. Enter on Email saves.';

  @override
  void initState() {
    super.initState();
    _nameFocus.addListener(_handleFocusChanged);
    _emailFocus.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _nameFocus.removeListener(_handleFocusChanged);
    _emailFocus.removeListener(_handleFocusChanged);
    _nameFocus.dispose();
    _emailFocus.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  KeyEventResult _handleScopeKey(FocusNode node, KeyEvent event) {
    if (!event.isPress) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.tab) {
      if (_emailFocus.hasFocus) {
        _nameFocus.requestFocus();
      } else {
        _emailFocus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter && _emailFocus.hasFocus) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submit() {
    setState(() {
      _status = 'Saved: $_name - $_email';
    });
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Color.rgb(0.05, 0.05, 0.12),
      border: Border.all(color: Color.rgb(0.2, 0.25, 0.35)),
    ),
    padding: const EdgeInsets.all(1),
    child: FocusScope(
      node: _scopeNode,
      onKeyEvent: _handleScopeKey,
      child: Column(
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Focus & Pointer Demo',
            style: TextStyle(color: Color(0.7, 0.9, 1)),
          ),
          const Text(
            'Use keyboard or mouse to interact with the fields below.',
          ),
          _buildField(
            label: 'Name',
            focusNode: _nameFocus,
            value: _name,
            autofocus: true,
            placeholder: 'Jane Doe',
            onChanged: (value) => setState(() => _name = value),
          ),
          _buildField(
            label: 'Email',
            focusNode: _emailFocus,
            value: _email,
            placeholder: 'jane@example.com',
            onChanged: (value) => setState(() => _email = value),
            onSubmit: _submit,
          ),
          Container(
            width: 72,
            height: 3,
            padding: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: Color.rgb(0.07, 0.12, 0.18),
              border: Border.all(color: Color.rgb(0.2, 0.25, 0.35)),
            ),
            child: Text(
              _status,
              style: const TextStyle(color: Color(0.85, 0.9, 0.95)),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _buildField({
    required String label,
    required FocusNode focusNode,
    required String value,
    required ValueChanged<String> onChanged,
    required String placeholder,
    VoidCallback? onSubmit,
    bool autofocus = false,
  }) {
    final focused = focusNode.hasFocus;
    final border = focused ? Color.cyan : Color.rgb(0.25, 0.3, 0.4);
    final background = focused
        ? Color.rgb(0.1, 0.17, 0.28)
        : Color.rgb(0.06, 0.08, 0.12);

    return Container(
      width: 54,
      height: 5,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Column(
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0.7, 0.85, 1))),
          TextInput(
            focusNode: focusNode,
            autofocus: autofocus,
            value: value,
            placeholder: placeholder,
            cursorColor: Color.cyan,
            maxLength: 40,
            onChanged: onChanged,
            onSubmit: onSubmit,
          ),
        ],
      ),
    );
  }
}
