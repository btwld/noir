import 'dart:convert';

import 'package:noir/noir.dart';

import '../session/mcp_session.dart';

/// The coerced arguments of one generated form, with any problems found.
final class FormArguments {
  /// Creates an argument set.
  const FormArguments({
    required this.values,
    required this.missing,
    required this.invalid,
  });

  /// The coerced values, ready to send as MCP arguments.
  final Map<String, Object?> values;

  /// Names of required fields the user left empty.
  final List<String> missing;

  /// Names of fields whose text could not be coerced, mapped to the reason.
  final Map<String, String> invalid;

  /// Whether every required field is present and every value coerced.
  bool get isValid => missing.isEmpty && invalid.isEmpty;

  /// Every value rendered as a string, for the prompt argument map.
  Map<String, String> get asStrings => <String, String>{
    for (final entry in values.entries) entry.key: '${entry.value}',
  };

  /// A one-line report of what the user must fix, empty when [isValid].
  String get problem {
    final parts = <String>[
      if (missing.isNotEmpty) 'Missing required: ${missing.join(', ')}',
      for (final entry in invalid.entries) '${entry.key}: ${entry.value}',
    ];
    return parts.join('. ');
  }
}

/// The editable state of one generated form.
///
/// The model owns a [TextEditingController] for every field a person types
/// into, so the screen wires controls without holding a second copy of the
/// text. The owner disposes the model when the selection changes.
final class FormModel implements Disposable {
  /// Builds an editable form over [spec].
  FormModel(this.spec) {
    for (final field in spec.fields) {
      if (field.kind == FormFieldKind.boolean) {
        _flags[field.name] = field.initialFlag;
      } else {
        _controllers[field.name] = TextEditingController(
          text: _initialTextOf(field),
        );
      }
    }
  }

  /// The fields this form presents.
  final FormSpec spec;

  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, bool> _flags = <String, bool>{};
  bool _disposed = false;

  /// The controller for [name], or null for a boolean field.
  TextEditingController? controllerFor(String name) => _controllers[name];

  /// The current text of [name], or the empty string for a boolean field.
  String textOf(String name) => _controllers[name]?.text ?? '';

  /// The current state of the boolean field [name].
  bool flagOf(String name) => _flags[name] ?? false;

  /// Sets the boolean field [name] to [value].
  void setFlag(String name, {required bool value}) => _flags[name] = value;

  /// Sets the text of [name], replacing the whole value.
  void setText(String name, String value) {
    final controller = _controllers[name];
    if (controller != null) controller.text = value;
  }

  /// Coerces every field into MCP arguments and reports what is unusable.
  FormArguments toArguments() {
    final values = <String, Object?>{};
    final missing = <String>[];
    final invalid = <String, String>{};
    for (final field in spec.fields) {
      if (field.kind == FormFieldKind.boolean) {
        values[field.name] = flagOf(field.name);
        continue;
      }
      final text = textOf(field.name).trim();
      if (text.isEmpty) {
        if (field.isRequired) missing.add(field.name);
        continue;
      }
      switch (field.kind) {
        case FormFieldKind.text:
        case FormFieldKind.select:
          values[field.name] = text;
        case FormFieldKind.number:
          final value = num.tryParse(text);
          if (value == null) {
            invalid[field.name] = 'not a number';
          } else {
            values[field.name] = value;
          }
        case FormFieldKind.integer:
          final value = int.tryParse(text);
          if (value == null) {
            invalid[field.name] = 'not an integer';
          } else {
            values[field.name] = value;
          }
        case FormFieldKind.json:
          try {
            values[field.name] = jsonDecode(text);
          } on FormatException catch (error) {
            invalid[field.name] = 'not valid JSON (${error.message})';
          }
        case FormFieldKind.boolean:
          break;
      }
    }
    return FormArguments(values: values, missing: missing, invalid: invalid);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _flags.clear();
  }

  static String _initialTextOf(FormFieldSpec field) {
    if (field.kind != FormFieldKind.select) return field.initialText;
    if (field.options.contains(field.initialText)) return field.initialText;
    return field.options.isEmpty ? '' : field.options.first;
  }
}
