import 'dart:async';

import 'package:ack/ack.dart';
import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

import 'component_binding.dart';

final AckSchema<Object, Object> _questionAnswerSchema =
    Ack.object(<String, AckSchema<Object, Object>>{
      'selectedValues': Ack.list(
        Ack.string().notEmpty().maxLength(128),
      ).maxLength(12).withDefault(const <String>[]),
      'freeText': Ack.string().maxLength(2048).withDefault(''),
    }).strict();

final AckSchema<Object, Object> _questionOptionsSchema =
    Ack.list(
          Ack.object(<String, AckSchema<Object, Object>>{
            'value': Ack.string().notEmpty().maxLength(128),
            'label': Ack.string().notEmpty().maxLength(256),
            'description': Ack.string().notEmpty().maxLength(512).optional(),
          }).strict(),
        )
        .maxLength(12)
        .refine((options) {
          final values = <String>{};
          for (final option in options) {
            if (!values.add(option['value']! as String)) return false;
          }
          return true;
        }, message: 'Question option values must be unique.')
        .withDefault(const <JsonMap>[]);

/// Terminal-native Question declaration and trusted builder.
final MuseNoirComponentBinding museNoirQuestionBinding =
    MuseNoirComponentBinding(
      name: 'Question',
      description:
          'One bounded terminal question with single-choice, multiple-choice, '
          'and optional free-text answers.',
      properties: <String, MuseProperty>{
        'questionId': MuseProperty.literal(
          Ack.string().notEmpty().maxLength(128),
          'Stable literal question identifier.',
        ),
        'prompt': MuseProperty.bindable(
          Ack.string().notEmpty().maxLength(2048),
          'Visible question prompt.',
        ),
        'mode': MuseProperty.literal(
          Ack.enumString(const <String>['single', 'multiple']),
          'Whether one or multiple options may be selected.',
        ),
        'options': MuseProperty.literal(
          _questionOptionsSchema,
          'Bounded unique answer options.',
        ),
        'allowFreeText': MuseProperty.literal(
          Ack.boolean().withDefault(false),
          'Whether the user may enter an answer not in the options.',
        ),
        'freeTextPlaceholder': MuseProperty.bindable(
          Ack.string().notEmpty().maxLength(128).withDefault('Other answer'),
          'Placeholder for the optional free-text input.',
        ),
        'submitLabel': MuseProperty.bindable(
          Ack.string().notEmpty().maxLength(128).withDefault('Answer'),
          'Visible explicit-submit button label.',
        ),
        'enabled': MuseProperty.bindable(
          Ack.boolean().withDefault(true),
          'Whether the question accepts input.',
        ),
        'autofocus': MuseProperty.literal(
          Ack.boolean().withDefault(false),
          'Whether the first input requests focus.',
        ),
        'answer': MuseProperty.bindable(
          _questionAnswerSchema,
          'Local draft answer submitted through the declared action.',
        ),
      },
      checkable: true,
      builder: _buildMuseNoirQuestion,
    );

Widget _buildMuseNoirQuestion(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  final answer = properties['answer'];
  return _MuseNoirQuestion(
    questionId: properties['questionId']! as String,
    prompt: properties['prompt']! as String,
    mode: properties['mode']! as String,
    options: _questionOptions(properties['options']),
    allowFreeText: properties['allowFreeText'] as bool? ?? false,
    freeTextPlaceholder:
        properties['freeTextPlaceholder'] as String? ?? 'Other answer',
    submitLabel: properties['submitLabel'] as String? ?? 'Answer',
    enabled: properties['enabled'] as bool? ?? true,
    autofocus: properties['autofocus'] as bool? ?? false,
    answer: answer is Map<String, Object?>
        ? answer
        : const <String, Object?>{'selectedValues': <String>[], 'freeText': ''},
    errorText: node.errorText,
    onEdit: (value) => node.edit('answer', value),
    activate: node.activate,
  );
}

List<_QuestionOption> _questionOptions(Object? value) {
  if (value is! List<Object?>) return const <_QuestionOption>[];
  return List<_QuestionOption>.unmodifiable(<_QuestionOption>[
    for (final item in value)
      if (item is Map<String, Object?>)
        _QuestionOption(
          value: item['value']! as String,
          label: item['label']! as String,
          description: item['description'] as String?,
        ),
  ]);
}

final class _QuestionOption {
  const _QuestionOption({
    required this.value,
    required this.label,
    this.description,
  });

  final String value;
  final String label;
  final String? description;
}

final class _MuseNoirQuestion extends StatefulWidget {
  const _MuseNoirQuestion({
    required this.questionId,
    required this.prompt,
    required this.mode,
    required this.options,
    required this.allowFreeText,
    required this.freeTextPlaceholder,
    required this.submitLabel,
    required this.enabled,
    required this.autofocus,
    required this.answer,
    required this.errorText,
    required this.onEdit,
    required this.activate,
  });

  final String questionId;
  final String prompt;
  final String mode;
  final List<_QuestionOption> options;
  final bool allowFreeText;
  final String freeTextPlaceholder;
  final String submitLabel;
  final bool enabled;
  final bool autofocus;
  final Map<String, Object?> answer;
  final String? errorText;
  final void Function(Map<String, Object?> value) onEdit;
  final Future<MuseActionResult> Function()? activate;

  @override
  State<_MuseNoirQuestion> createState() => _MuseNoirQuestionState();
}

final class _MuseNoirQuestionState extends State<_MuseNoirQuestion> {
  late final TextEditingController _freeTextController;
  final Set<String> _selectedValues = <String>{};
  var _highlightedIndex = 0;
  var _busy = false;
  var _generation = 0;
  String? _interactionError;
  var _synchronizing = false;

  bool get _isMultiple => widget.mode == 'multiple';
  bool get _showsAnswerButton => _isMultiple || widget.allowFreeText;

  String? get _configurationError =>
      widget.options.isEmpty && !widget.allowFreeText
      ? 'Question needs options or a free-text answer.'
      : null;

  bool get _canInteract =>
      widget.enabled &&
      !_busy &&
      _configurationError == null &&
      widget.activate != null;

  @override
  void initState() {
    super.initState();
    _freeTextController = TextEditingController();
    _syncAnswer();
  }

  @override
  void didUpdateWidget(_MuseNoirQuestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.questionId != widget.questionId) {
      _generation += 1;
      _highlightedIndex = 0;
      _busy = false;
      _interactionError = null;
    }
    _syncAnswer();
    final maximumIndex = widget.options.isEmpty ? 0 : widget.options.length - 1;
    _highlightedIndex = _highlightedIndex.clamp(0, maximumIndex);
  }

  void _syncAnswer() {
    final selected = widget.answer['selectedValues'];
    final declaredValues = <String>{
      for (final option in widget.options) option.value,
    };
    _selectedValues
      ..clear()
      ..addAll(
        selected is List<Object?>
            ? selected.whereType<String>().where(declaredValues.contains)
            : const <String>[],
      );
    final text = widget.allowFreeText
        ? widget.answer['freeText'] as String? ?? ''
        : '';
    if (_freeTextController.text != text) {
      _synchronizing = true;
      _freeTextController.text = text;
      _synchronizing = false;
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _freeTextController.dispose();
    super.dispose();
  }

  Map<String, Object?> _answer({String? freeText}) => <String, Object?>{
    'selectedValues': <String>[
      for (final option in widget.options)
        if (_selectedValues.contains(option.value)) option.value,
    ],
    'freeText': freeText ?? _freeTextController.text,
  };

  void _publishEdit() => widget.onEdit(_answer());

  void _moveHighlight(int index) {
    if (index != _highlightedIndex) setState(() => _highlightedIndex = index);
  }

  void _chooseOption(int index) {
    if (!_canInteract) return;
    final value = widget.options[index].value;
    setState(() {
      _interactionError = null;
      if (_isMultiple) {
        if (!_selectedValues.remove(value)) _selectedValues.add(value);
      } else {
        _selectedValues
          ..clear()
          ..add(value);
        if (_freeTextController.text.isNotEmpty) _freeTextController.clear();
      }
    });
    _publishEdit();
    if (!_isMultiple) unawaited(_submit());
  }

  void _changeFreeText(String value) {
    if (!_canInteract || _synchronizing) return;
    setState(() {
      _interactionError = null;
      if (!_isMultiple && value.trim().isNotEmpty) _selectedValues.clear();
    });
    widget.onEdit(_answer(freeText: value));
  }

  Future<void> _submit() async {
    final activate = widget.activate;
    if (!_canInteract || activate == null) return;
    final freeText = widget.allowFreeText
        ? _freeTextController.text.trim()
        : '';
    if (_selectedValues.isEmpty && freeText.isEmpty) {
      setState(
        () => _interactionError = 'Choose an option or enter an answer.',
      );
      return;
    }
    if (freeText != _freeTextController.text) {
      widget.onEdit(_answer(freeText: freeText));
    }
    final generation = _generation;
    setState(() {
      _busy = true;
      _interactionError = null;
    });
    try {
      final result = await activate();
      if (!mounted || generation != _generation) return;
      final failure = result.failure;
      if (failure != null) {
        setState(() => _interactionError = failure.message);
      }
    } on Object {
      if (mounted && generation == _generation) {
        setState(() => _interactionError = 'Question answer could not submit.');
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configurationError = _configurationError;
    final optionHeight = widget.options.length > 8 ? 8 : widget.options.length;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          widget.prompt,
          style: TextStyle(color: theme.text, fontWeight: FontWeight.bold),
        ),
        if (configurationError == null)
          Text(
            _interactionHint,
            style: TextStyle(
              color: theme.textMuted,
              fontWeight: FontWeight.dim,
            ),
          ),
        if (widget.options.isNotEmpty)
          Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: Select<String>(
              key: ValueKey<String>(
                'muse_question:${widget.questionId}:options',
              ),
              options: <SelectOption<String>>[
                for (final option in widget.options)
                  SelectOption<String>(
                    name: '${_selectionIcon(option.value)} ${option.label}',
                    description: option.description,
                    value: option.value,
                  ),
              ],
              selectedIndex: _highlightedIndex,
              height: optionHeight,
              showScrollIndicator: widget.options.length > 8,
              autofocus: widget.autofocus,
              onChanged: _canInteract
                  ? (index, option) => _moveHighlight(index)
                  : null,
              onSelect: _canInteract
                  ? (index, option) => _chooseOption(index)
                  : null,
            ),
          ),
        if (widget.allowFreeText)
          TextInput(
            key: ValueKey<String>(
              'muse_question:${widget.questionId}:free_text',
            ),
            controller: _freeTextController,
            placeholder: widget.freeTextPlaceholder,
            maxLength: 2048,
            autofocus: widget.autofocus && widget.options.isEmpty,
            onChanged: _canInteract ? _changeFreeText : null,
            onSubmit: _canInteract ? () => unawaited(_submit()) : null,
          ),
        if (_showsAnswerButton)
          Button(
            key: ValueKey<String>('muse_question:${widget.questionId}:answer'),
            label: _busy ? '${widget.submitLabel}…' : widget.submitLabel,
            color: theme.surfaceVariant,
            textColor: theme.text,
            onPressed: _canInteract ? () => unawaited(_submit()) : null,
          ),
        if (configurationError != null)
          Text(configurationError, style: TextStyles.error),
        if (widget.errorText case final error?)
          Text(error, style: TextStyles.error),
        if (_interactionError case final error?)
          Text(error, style: TextStyles.error),
        const SizedBox(height: 1),
      ],
    );
  }

  String get _interactionHint {
    if (widget.options.isEmpty && widget.allowFreeText) {
      return 'Free text · press Enter or use the save button';
    }
    if (_isMultiple && widget.allowFreeText) {
      return 'Choose or type any · Enter or the save button submits all';
    }
    if (_isMultiple) {
      return 'Multiple choice · select any, then use the save button';
    }
    if (widget.allowFreeText) {
      return 'Choice submits now · Enter saves typed text';
    }
    return 'Single choice · selection submits immediately';
  }

  String _selectionIcon(String value) {
    final selected = _selectedValues.contains(value);
    if (_isMultiple) return selected ? Icons.square : Icons.squareOutline;
    return selected ? Icons.circle : Icons.circleOutline;
  }
}
