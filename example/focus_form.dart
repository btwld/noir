// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

import 'src/demo_scaffold.dart';

void main() {
  // Kitty keyboard stays a handle method: only apps that want disambiguated
  // escape codes ask for it.
  runTuiApp(const FocusFormApp(), enableMouse: true).enableKittyKeyboard();
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  String _status = 'Tab moves focus. Enter in a field or Save submits.';
  static final _validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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
    _nameController.dispose();
    _emailController.dispose();
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
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final nameError = name.isEmpty ? 'Enter your name.' : null;
    final emailError = _validEmail.hasMatch(email)
        ? null
        : 'Enter an email like name@example.com.';

    final errors = [
      if (nameError != null) 'Name error: $nameError',
      if (emailError != null) 'Email error: $emailError',
    ];
    final status = errors.isEmpty ? 'Saved: $name - $email' : errors.join('\n');
    setState(() => _status = status);

    FocusNode? invalidFocus;
    if (nameError != null) {
      invalidFocus = _nameFocus;
    } else if (emailError != null) {
      invalidFocus = _emailFocus;
    }
    if (invalidFocus != null && !invalidFocus.hasFocus) {
      invalidFocus.requestFocus();
    }
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
            key: const ValueKey<String>('name'),
            label: 'Name',
            focusNode: _nameFocus,
            controller: _nameController,
            autofocus: true,
            placeholder: 'Enter name',
            onSubmit: _submit,
          ),
          _buildField(
            key: const ValueKey<String>('email'),
            label: 'Email',
            focusNode: _emailFocus,
            controller: _emailController,
            placeholder: 'Enter email',
            onSubmit: _submit,
          ),
          Button(
            key: const ValueKey<String>('save'),
            label: 'Save',
            onPressed: _submit,
          ),
          Panel(
            title: 'Status',
            width: 54,
            height: _status.contains('\n') ? 4 : 3,
            child: Text(_status),
          ),
        ],
      ),
    ),
  );

  Widget _buildField({
    required Key key,
    required String label,
    required FocusNode focusNode,
    required TextEditingController controller,
    required String placeholder,
    VoidCallback? onSubmit,
    bool autofocus = false,
  }) => Panel(
    title: label,
    focused: focusNode.hasFocus,
    width: 54,
    height: 3,
    child: TextInput(
      key: key,
      focusNode: focusNode,
      controller: controller,
      autofocus: autofocus,
      placeholder: placeholder,
      maxLength: 40,
      onSubmit: onSubmit,
    ),
  );
}
