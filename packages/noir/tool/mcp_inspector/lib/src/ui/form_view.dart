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
class FormView extends StatefulWidget {
  /// Creates a view over [model].
  const FormView({
    required this.model,
    required this.focusNodeFor,
    required this.onChanged,
    super.key,
    this.keyPrefix = 'field',
    this.autofocusNode,
  });

  /// The editable form this view presents.
  final FormModel model;

  /// Supplies the focus node for the field named by its argument.
  final FocusNode Function(String name) focusNodeFor;

  /// Called after any control changes a value, so the owner can rebuild.
  final VoidCallback onChanged;

  /// Key namespace for the generated controls.
  final String keyPrefix;

  /// A borrowed field node that should take focus when the request changes.
  final FocusNode? autofocusNode;

  @override
  State<FormView> createState() => _FormViewState();
}

class _FormViewState extends State<FormView> {
  final ScrollController _scroll = ScrollController();
  final Map<String, FocusNode> _nodes = <String, FocusNode>{};
  int _viewportExtent = 0;

  @override
  void initState() {
    super.initState();
    _syncNodes();
    _scroll.addListener(_handleViewportChanged);
  }

  @override
  void didUpdateWidget(FormView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNodes();
    if (!identical(oldWidget.model, widget.model)) _scroll.jumpTo(0);
  }

  void _syncNodes() {
    for (final node in _nodes.values) {
      node.removeListener(_revealFocusedField);
    }
    _nodes.clear();
    for (final field in widget.model.spec.fields) {
      final node = widget.focusNodeFor(field.name);
      _nodes[field.name] = node;
      node.addListener(_revealFocusedField);
    }
  }

  void _handleViewportChanged() {
    if (_viewportExtent == _scroll.viewportExtent) return;
    _viewportExtent = _scroll.viewportExtent;
    _revealFocusedField();
  }

  void _revealFocusedField() {
    if (_scroll.viewportExtent <= 0) return;
    var top = 0;
    for (final field in widget.model.spec.fields) {
      final height = _fieldHeight(field);
      if (_nodes[field.name]!.hasFocus) {
        final visibleHeight = height.clamp(1, _scroll.viewportExtent);
        if (top < _scroll.offset) {
          _scroll.jumpTo(top.toDouble());
        } else if (top + visibleHeight >
            _scroll.offset + _scroll.viewportExtent) {
          _scroll.jumpTo(
            (top + visibleHeight - _scroll.viewportExtent).toDouble(),
          );
        }
        return;
      }
      top += height;
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.removeListener(_revealFocusedField);
    }
    _scroll
      ..removeListener(_handleViewportChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = widget.model;
    if (model.spec.isEmpty) {
      return Text('No arguments', style: TextStyle(color: theme.textMuted));
    }
    return SizedBox(
      height: model.spec.fields.fold<int>(
        0,
        (height, field) => height + _fieldHeight(field),
      ),
      child: ScrollBox(
        controller: _scroll,
        canRequestFocus: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
        ),
      ),
    );
  }

  Widget _control(FormFieldSpec field) {
    final model = widget.model;
    final key = ValueKey<String>('${widget.keyPrefix}:${field.name}');
    final node = _nodes[field.name]!;
    switch (field.kind) {
      case FormFieldKind.boolean:
        return Checkbox(
          key: key,
          value: model.flagOf(field.name),
          focusNode: node,
          autofocus: identical(widget.autofocusNode, node),
          onChanged: (value) {
            model.setFlag(field.name, value: value);
            widget.onChanged();
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
          height: _controlHeight(field),
          focusNode: node,
          autofocus: identical(widget.autofocusNode, node),
          onChanged: (index, option) {
            model.setText(field.name, option.value ?? option.name);
            widget.onChanged();
          },
        );
      case FormFieldKind.json:
        return TextArea(
          key: key,
          controller: model.controllerFor(field.name),
          focusNode: node,
          autofocus: identical(widget.autofocusNode, node),
          height: _controlHeight(field),
          placeholder: 'raw JSON',
          onChanged: (_) => widget.onChanged(),
        );
      case FormFieldKind.text:
      case FormFieldKind.number:
      case FormFieldKind.integer:
        return TextInput(
          key: key,
          controller: model.controllerFor(field.name),
          focusNode: node,
          autofocus: identical(widget.autofocusNode, node),
          placeholder: _placeholderFor(field.kind),
          onChanged: (_) => widget.onChanged(),
        );
    }
  }

  // Controls have fixed row counts and hints occupy one row. Use the same
  // extents for construction and focus scrolling; no terminal-size API is needed.
  static int _controlHeight(FormFieldSpec field) => switch (field.kind) {
    FormFieldKind.select => field.options.length.clamp(1, 4),
    FormFieldKind.json => 3,
    _ => 1,
  };

  static int _fieldHeight(FormFieldSpec field) =>
      _controlHeight(field) + (field.hint == null ? 0 : 1);

  static String? _placeholderFor(FormFieldKind kind) => switch (kind) {
    FormFieldKind.number => 'number',
    FormFieldKind.integer => 'integer',
    _ => null,
  };
}
