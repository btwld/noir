import 'dart:async';

import 'package:ack/ack.dart';
import 'package:muse/muse.dart';
import 'package:noir/noir.dart';

import 'component_binding.dart';
import 'question_control.dart';

/// Stable id for the reduced, terminal-native Muse catalog.
const String museNoirCatalogId =
    'https://github.com/leoafarias/noir/catalogs/muse-noir/v2';

/// The eleven trusted bindings that define the v2 Noir catalog.
final List<MuseNoirComponentBinding> museNoirComponentBindings =
    List<MuseNoirComponentBinding>.unmodifiable(<MuseNoirComponentBinding>[
      _binding(
        'Column',
        'Vertical terminal-cell layout.',
        _buildColumn,
        properties: _flowProperties,
        children: MuseChildren.list,
      ),
      _binding(
        'Row',
        'Horizontal terminal-cell layout.',
        _buildRow,
        properties: _flowProperties,
        children: MuseChildren.list,
      ),
      _binding(
        'Panel',
        'One indented terminal section with an optional visible title.',
        _buildPanel,
        properties: <String, MuseProperty>{
          'title': _text(
            'Optional panel title.',
            optional: true,
            maxLength: 128,
          ),
        },
        children: MuseChildren.list,
      ),
      _binding(
        'Text',
        'Bounded terminal text using trusted semantic styles.',
        _buildText,
        properties: <String, MuseProperty>{
          'text': _text('Text to display.'),
          'variant': _token('Trusted semantic text style.', <String>[
            'body',
            'caption',
            'title',
            'warning',
            'success',
            'code',
          ]),
          'maxLines': MuseProperty.literal(
            Ack.integer().min(1).max(64).optional(),
            'Optional maximum rendered line count.',
          ),
          'softWrap': MuseProperty.bindable(
            Ack.boolean().optional(),
            'Whether long text may wrap.',
          ),
        },
      ),
      _binding(
        'Badge',
        'Short passive terminal status tag.',
        _buildBadge,
        properties: <String, MuseProperty>{
          'label': _text('Short badge label.', maxLength: 128),
          'variant': _token('Trusted badge tone.', <String>[
            'neutral',
            'success',
            'warning',
            'danger',
            'info',
          ]),
        },
      ),
      _binding(
        'Callout',
        'Indented terminal message with a trusted semantic tone.',
        _buildCallout,
        properties: <String, MuseProperty>{
          'title': _text(
            'Optional callout title.',
            optional: true,
            maxLength: 128,
          ),
          'text': _text('Callout body text.'),
          'tone': _token('Trusted callout tone.', <String>[
            'info',
            'success',
            'warning',
            'danger',
          ]),
        },
      ),
      _binding(
        'Divider',
        'One horizontal terminal-cell divider.',
        _buildDivider,
      ),
      _binding(
        'Progress',
        'Normalized progress rendered in terminal cells.',
        _buildProgress,
        properties: <String, MuseProperty>{
          'label': _text(
            'Optional progress label.',
            optional: true,
            maxLength: 128,
          ),
          'value': MuseProperty.bindable(
            Ack.number().min(0).max(1),
            'Progress from zero to one.',
          ),
          'width': MuseProperty.literal(
            Ack.integer().min(4).max(80).optional(),
            'Optional terminal-cell width.',
          ),
        },
      ),
      _binding(
        'Spinner',
        'One activity glyph with an optional visible label.',
        _buildSpinner,
        properties: <String, MuseProperty>{
          'label': _text(
            'Optional activity label.',
            optional: true,
            maxLength: 128,
          ),
        },
      ),
      _binding(
        'Button',
        'One trusted push action with a provider-authored visible label.',
        _buildButton,
        properties: <String, MuseProperty>{
          'label': _text('Visible button label.', maxLength: 128),
          'variant': _token('Trusted button presentation.', <String>[
            'primary',
            'secondary',
            'danger',
            'subtle',
          ]),
          'enabled': MuseProperty.bindable(
            Ack.boolean().optional(),
            'Whether the user may activate the button.',
          ),
        },
        checkable: true,
      ),
      museNoirQuestionBinding,
    ]);

/// Default renderer implementing every declaration in [museNoirCatalog].
final MuseNoirRenderer museNoirRenderer = MuseNoirRenderer(
  museNoirComponentBindings,
);

/// Canonical reduced catalog, derived from [museNoirComponentBindings].
final MuseCatalog museNoirCatalog = museNoirRenderer.catalog(
  id: museNoirCatalogId,
  guidance:
      'Use Button and Question for actions; all other components are passive.',
);

/// Reusable composition constraints for intents using the default catalog.
final List<MuseConstraint> museNoirConstraints =
    List<MuseConstraint>.unmodifiable(<MuseConstraint>[
      MuseConstraint.count(componentTypes: <String>{'Question'}, maximum: 4),
      MuseConstraint.count(
        componentTypes: <String>{'Question'},
        propertyEquals: const <String, Object?>{'autofocus': true},
        maximum: 1,
      ),
    ]);

MuseNoirComponentBinding _binding(
  String name,
  String description,
  MuseNoirComponentBuilder builder, {
  Map<String, MuseProperty> properties = const <String, MuseProperty>{},
  MuseChildren children = MuseChildren.none,
  bool checkable = false,
}) => MuseNoirComponentBinding(
  name: name,
  description: description,
  properties: properties,
  children: children,
  checkable: checkable,
  builder: builder,
);

final Map<String, MuseProperty> _flowProperties = <String, MuseProperty>{
  'align': _token('Cross-axis alignment.', <String>[
    'start',
    'center',
    'end',
    'stretch',
  ]),
  'justify': _token('Main-axis alignment.', <String>[
    'start',
    'center',
    'end',
    'spaceAround',
    'spaceBetween',
    'spaceEvenly',
  ]),
  'spacing': _token('Spacing between children.', <String>[
    'none',
    'xs',
    'sm',
    'md',
    'lg',
  ]),
};

MuseProperty _text(
  String description, {
  bool optional = false,
  int maxLength = 2048,
}) {
  final schema = Ack.string().notEmpty().maxLength(maxLength);
  return MuseProperty.bindable(
    optional ? schema.optional() : schema,
    description,
  );
}

MuseProperty _token(String description, List<String> values) =>
    MuseProperty.literal(Ack.enumString(values).optional(), description);

Widget _buildColumn(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  return Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: _mainAxisAlignment(properties['justify']),
    crossAxisAlignment: _crossAxisAlignment(properties['align']),
    spacing: _spacing(properties['spacing']),
    children: _weightedChildren(node),
  );
}

Widget _buildRow(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  return Row(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: _mainAxisAlignment(properties['justify']),
    crossAxisAlignment: _crossAxisAlignment(properties['align']),
    spacing: _spacing(properties['spacing']),
    children: _weightedChildren(node),
  );
}

Widget _buildPanel(BuildContext context, MuseNoirRenderNode node) {
  final title = _string(node.properties['title']);
  final theme = Theme.of(context);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (title != null)
        Text(
          title,
          style: TextStyle(color: theme.textMuted, fontWeight: FontWeight.bold),
        ),
      Padding(
        padding: const EdgeInsets.only(left: 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 1,
          children: node.children,
        ),
      ),
    ],
  );
}

Widget _buildText(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  final softWrap = properties['softWrap'] as bool? ?? true;
  final configuredMaxLines = properties['maxLines'] as int?;
  return Text(
    _string(properties['text']) ?? '',
    style: _textStyle(context, properties['variant']),
    maxLines: configuredMaxLines ?? (softWrap ? null : 1),
    softWrap: softWrap,
    overflow: TextOverflow.ellipsis,
  );
}

Widget _buildBadge(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  return Badge(
    label: _string(properties['label']) ?? '',
    variant: _badgeVariant(properties['variant']),
  );
}

Widget _buildCallout(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  final tone = properties['tone'];
  final theme = Theme.of(context);
  final toneColor = _toneColor(context, tone);
  final title = _string(properties['title']);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      if (title != null)
        Text(
          '› $title',
          style: TextStyle(color: toneColor, fontWeight: FontWeight.bold),
        ),
      Padding(
        padding: EdgeInsets.only(left: title == null ? 0 : 2),
        child: Text(
          _string(properties['text']) ?? '',
          style: TextStyle(color: theme.text),
        ),
      ),
    ],
  );
}

Widget _buildDivider(BuildContext context, MuseNoirRenderNode node) =>
    Divider(color: Theme.of(context).surfaceVariant);

Widget _buildProgress(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  final progress = ProgressBar(
    value: (properties['value'] as num?)!.toDouble(),
    width: properties['width'] as int? ?? 20,
  );
  final label = _string(properties['label']);
  if (label == null) return progress;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 1,
    children: <Widget>[Text(label), progress],
  );
}

Widget _buildSpinner(BuildContext context, MuseNoirRenderNode node) {
  final label = _string(node.properties['label']);
  if (label == null) return const Spinner();
  return Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 1,
    children: <Widget>[const Spinner(), Text(label)],
  );
}

Widget _buildButton(BuildContext context, MuseNoirRenderNode node) {
  final properties = node.properties;
  final enabled = properties['enabled'] as bool? ?? true;
  final theme = Theme.of(context);
  final variant = properties['variant'];
  final (color, textColor) = switch (variant) {
    'danger' => (theme.danger, Color.white),
    'secondary' => (theme.surfaceVariant, theme.text),
    'subtle' => (theme.surface, theme.textMuted),
    _ => (theme.accent, theme.accentForeground),
  };
  return Button(
    label: _string(properties['label']) ?? '',
    color: color,
    textColor: textColor,
    onPressed: enabled && node.canActivate
        ? () => unawaited(node.activate!())
        : null,
  );
}

List<Widget> _weightedChildren(MuseNoirRenderNode node) => <Widget>[
  for (var index = 0; index < node.children.length; index += 1)
    switch (node.childWeights[index]) {
      final double value => Flexible(
        flex: (value * 1000).clamp(1, 1 << 20).round(),
        child: node.children[index],
      ),
      _ => node.children[index],
    },
];

MainAxisAlignment _mainAxisAlignment(Object? value) => switch (value) {
  'center' => MainAxisAlignment.center,
  'end' => MainAxisAlignment.end,
  'spaceAround' => MainAxisAlignment.spaceAround,
  'spaceBetween' => MainAxisAlignment.spaceBetween,
  'spaceEvenly' => MainAxisAlignment.spaceEvenly,
  _ => MainAxisAlignment.start,
};

CrossAxisAlignment _crossAxisAlignment(Object? value) => switch (value) {
  'end' => CrossAxisAlignment.end,
  'center' => CrossAxisAlignment.center,
  'stretch' => CrossAxisAlignment.stretch,
  _ => CrossAxisAlignment.start,
};

int _spacing(Object? value) => switch (value) {
  'xs' || 'sm' => 1,
  'md' => 2,
  'lg' => 3,
  _ => 0,
};

TextStyle _textStyle(BuildContext context, Object? value) {
  final theme = Theme.of(context);
  return switch (value) {
    'caption' => TextStyle(color: theme.textMuted, fontWeight: FontWeight.dim),
    'title' => TextStyle(color: theme.text, fontWeight: FontWeight.bold),
    'warning' => TextStyle(color: theme.warning, fontWeight: FontWeight.bold),
    'success' => TextStyle(color: theme.success),
    'code' => TextStyles.code.copyWith(color: theme.text),
    _ => TextStyle(color: theme.text),
  };
}

BadgeVariant _badgeVariant(Object? value) => switch (value) {
  'success' => BadgeVariant.success,
  'warning' => BadgeVariant.warning,
  'danger' => BadgeVariant.danger,
  'info' => BadgeVariant.info,
  _ => BadgeVariant.neutral,
};

Color _toneColor(BuildContext context, Object? value) {
  final theme = Theme.of(context);
  return switch (value) {
    'success' => theme.success,
    'warning' => theme.warning,
    'danger' => theme.danger,
    _ => theme.info,
  };
}

String? _string(Object? value) => value is String ? value : null;
