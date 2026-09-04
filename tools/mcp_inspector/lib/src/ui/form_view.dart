import 'package:noir/noir.dart';

import '../model/form_model.dart';
import '../session/mcp_session.dart';

/// Width in cells of the label column beside every generated control.
const formLabelWidth = 12;

/// Renders one [FormModel] as labelled controls, one field per schema entry.
///
/// The same view serves a tool's input schema, a prompt's arguments, and a
/// server-initiated elicitation. [keyPrefix] separates the detail form's
/// `field:` keys from the modal's `elicit:field:` keys.
class FormView extends StatelessWidget {
  /// Creates a view over [model].
  const FormView({
    required this.model,
    required this.focusNodeFor,
    required this.onChanged,
    super.key,
    this.keyPrefix = 'field',
  });

  /// The editable form this view presents.
  final FormModel model;

  /// Supplies the focus node for the field named by its argument.
  final FocusNode Function(String name) focusNodeFor;

  /// Called after any control changes a value, so the owner can rebuild.
  final VoidCallback onChanged;

  /// Key namespace for the generated controls.
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (model.spec.isEmpty) {
      return Text('No arguments', style: TextStyle(color: theme.textMuted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final field in model.spec.fields) ...<Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 1,
            children: <Widget>[
              SizedBox(
                width: formLabelWidth,
                child: Text(
                  field.isRequired ? '${field.label}*' : field.label,
                  style: TextStyle(color: theme.textMuted),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(child: _control(field)),
            ],
          ),
          // The hint sits under the control, indented past the label column,
          // so a field the schema documents costs one extra row and a field
          // it does not costs none.
          if (field.hint case final hint?)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: <Widget>[
                const SizedBox(width: formLabelWidth),
                Expanded(
                  child: Text(
                    hint,
                    style: TextStyle(color: theme.textMuted),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _control(FormFieldSpec field) {
    final key = ValueKey<String>('$keyPrefix:${field.name}');
    final node = focusNodeFor(field.name);
    switch (field.kind) {
      case FormFieldKind.boolean:
        return Checkbox(
          key: key,
          value: model.flagOf(field.name),
          focusNode: node,
          onChanged: (value) {
            model.setFlag(field.name, value: value);
            onChanged();
          },
        );
      case FormFieldKind.select:
        final options = <SelectOption<String>>[
          for (final option in field.options)
            SelectOption<String>(name: option, value: option),
        ];
        final current = field.options.indexOf(model.textOf(field.name));
        return Select<String>(
          key: key,
          options: options,
          selectedIndex: current < 0 ? 0 : current,
          height: options.length < 4 ? options.length : 4,
          focusNode: node,
          onChanged: (index, option) {
            model.setText(field.name, option.value ?? option.name);
            onChanged();
          },
        );
      case FormFieldKind.json:
        return TextArea(
          key: key,
          controller: model.controllerFor(field.name),
          focusNode: node,
          height: 3,
          placeholder: 'raw JSON',
          onChanged: (_) => onChanged(),
        );
      case FormFieldKind.text:
      case FormFieldKind.number:
      case FormFieldKind.integer:
        return TextInput(
          key: key,
          controller: model.controllerFor(field.name),
          focusNode: node,
          placeholder: _placeholderFor(field.kind),
          onChanged: (_) => onChanged(),
        );
    }
  }

  static String? _placeholderFor(FormFieldKind kind) => switch (kind) {
    FormFieldKind.number => 'number',
    FormFieldKind.integer => 'integer',
    _ => null,
  };
}
