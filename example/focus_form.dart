// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

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
  Widget build(BuildContext context) => FocusScope(
    node: _scopeNode,
    onKeyEvent: _handleScopeKey,
    child: DemoScaffold(
      title: 'Focus & Pointer Demo',
      hint: 'Use keyboard or mouse to interact with the fields below.',
      child: Column(
        spacing: 1,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildField(
            label: 'Name',
            focusNode: _nameFocus,
            value: _name,
            autofocus: true,
            placeholder: 'Enter name',
            onChanged: (value) => setState(() => _name = value),
          ),
          _buildField(
            label: 'Email',
            focusNode: _emailFocus,
            value: _email,
            placeholder: 'Enter email',
            onChanged: (value) => setState(() => _email = value),
            onSubmit: _submit,
          ),
          DemoPanel(width: 54, height: 3, child: Text(_status)),
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
  }) => DemoPanel(
    title: label,
    focused: focusNode.hasFocus,
    width: 54,
    height: 4,
    child: TextInput(
      focusNode: focusNode,
      autofocus: autofocus,
      value: value,
      placeholder: placeholder,
      maxLength: 40,
      onChanged: onChanged,
      onSubmit: onSubmit,
    ),
  );
}
