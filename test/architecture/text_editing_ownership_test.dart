import 'dart:io';

import 'package:test/test.dart';

void main() {
  final input = File('lib/src/widgets/input.dart').readAsStringSync();
  final area = File('lib/src/widgets/text_area.dart').readAsStringSync();
  final mixin = File(
    'lib/src/widgets/text_editing_owner_mixin.dart',
  ).readAsStringSync();
  final connection = File(
    'lib/src/widgets/text_input_connection.dart',
  ).readAsStringSync();
  final inputGolden = File(
    'test/golden/text_input_golden_test.dart',
  ).readAsStringSync();
  final areaGolden = File(
    'test/golden/text_area_golden_test.dart',
  ).readAsStringSync();
  final publicBarrel = File('lib/noir.dart').readAsStringSync();
  final lowLevelBarrel = File('lib/noir_low_level.dart').readAsStringSync();

  test('editor widgets do not seed or repair controller selection', () {
    expect(input, isNot(contains('owned.selection =')));
    expect(area, isNot(contains('owned.setCursor(')));
    expect(area, isNot(contains('controller.setCursor(')));
  });

  test('shared owner has one listener and synchronous repair only', () {
    expect(
      RegExp(r'addListener\(handleControllerChanged\)').allMatches(mixin),
      hasLength(1),
    );
    expect(mixin, contains('_repairingActiveSelection'));
    expect(mixin, contains('TextSelection.collapsed'));
    expect(mixin, isNot(contains('Future')));
    expect(mixin, isNot(contains('Timer')));
    expect(mixin, isNot(contains('addPostFrameCallback')));
  });

  test('editor States have one shared reconciliation and rebuild owner', () {
    final stateSources = <String, ({String widgetType, String source})>{
      '_TextInputState': (
        widgetType: 'TextInput',
        source: _slice(input, 'class _TextInputState', 'class _TextInputLeaf'),
      ),
      '_TextAreaState': (
        widgetType: 'TextArea',
        source: _slice(area, 'class _TextAreaState', 'class _TextAreaLeaf'),
      ),
    };

    for (final entry in stateSources.entries) {
      final stateName = entry.key;
      final widgetType = entry.value.widgetType;
      final source = entry.value.source;
      expect(
        source,
        contains('TextEditingOwnerStateMixin<$widgetType>'),
        reason: '$stateName must compose the shared semantic owner',
      );
      expect(
        RegExp(r'\breconcileControllerUpdate\s*\(').allMatches(source),
        isEmpty,
        reason: '$stateName must not reconcile directly; the mixin owns it',
      );
      expect(
        RegExp(r'\bsyncController\s*\(').allMatches(source),
        hasLength(1),
        reason: '$stateName must sync each parent update exactly once',
      );
      expect(
        source,
        isNot(contains('setState(')),
        reason: '$stateName must not add a second rebuild owner',
      );
    }

    expect(
      RegExp(
        r'reconcileControllerUpdate\(controllerChanged: controllerChanged\)',
      ).allMatches(mixin),
      hasLength(1),
      reason: 'the mixin must own the single reconciliation call',
    );
  });

  test('connection exposes no second selection or repaint owner', () {
    expect(connection, isNot(contains('onStateChanged')));
    expect(connection, isNot(contains('ensureActiveSelection')));
    expect(input, isNot(contains('onStateChanged:')));
    expect(area, isNot(contains('onStateChanged:')));
  });

  test('editor cursor goldens retain cursor sidecars', () {
    expect(inputGolden, isNot(contains('captureCursor: false')));
    expect(areaGolden, isNot(contains('captureCursor: false')));
    expect(inputGolden, isNot(contains('but not cursor visibility')));
  });

  test('TextArea consumes one passive render-owned layout-metrics pair', () {
    for (final forbidden in <String>[
      "import '../framework/element.dart';",
      'context.element',
      'RenderObjectElement',
      'visitChildren',
      '_findLeafRenderObject',
    ]) {
      expect(
        area.contains(forbidden),
        isFalse,
        reason: 'TextArea State must not traverse Elements for $forbidden',
      );
    }

    final holder = _slice(
      area,
      'class _TextAreaLayoutMetrics',
      'class _TextAreaState',
    );
    expect(holder, contains('Size? _lastCompletedSize;'));
    expect(holder, contains('Size? get lastCompletedSize'));
    expect(holder, contains('void publish(Size size)'));
    for (final forbidden in <String>[
      'ValueNotifier',
      'ChangeNotifier',
      'addListener',
      'removeListener',
      'notifyListeners',
      'VoidCallback',
      'Function(',
      'callback',
      'setState',
      'addPostFrameCallback',
    ]) {
      expect(
        holder,
        isNot(contains(forbidden)),
        reason: 'layout metrics must remain passive: $forbidden',
      );
    }

    final state = _slice(area, 'class _TextAreaState', 'class _TextAreaLeaf');
    expect(
      RegExp(
        r'final _TextAreaLayoutMetrics _layoutMetrics\s*=\s*'
        r'_TextAreaLayoutMetrics\(\);',
      ).allMatches(state),
      hasLength(1),
      reason: 'State must own exactly one identity-stable metrics holder',
    );
    expect(
      RegExp(r'_TextAreaLayoutMetrics\(\)').allMatches(area),
      hasLength(1),
      reason: 'production must construct only the State-lifetime holder',
    );
    expect(
      RegExp(r'layoutMetrics:\s*_layoutMetrics,').allMatches(state),
      hasLength(1),
      reason: 'State must pass its exact lifetime holder to the leaf',
    );
    final viewport = _slice(
      state,
      '({int width, int height}) get _viewportCells',
      'int _cursorCellCol()',
    );
    expect(viewport, contains('_layoutMetrics.lastCompletedSize'));
    expect(
      viewport,
      matches(
        RegExp(
          r'if \(completedSize != null &&\s*'
          r'completedSize\.width > 0 &&\s*'
          r'completedSize\.height > 0\)',
        ),
      ),
      reason: 'a completed size is consumed only as a both-positive pair',
    );
    expect(
      viewport,
      contains(
        'return (width: completedSize.width, height: completedSize.height);',
      ),
    );
    expect(
      viewport,
      contains('return (width: widget.width ?? 80, height: widget.height);'),
      reason: 'an unusable completed pair must use the whole fallback pair',
    );

    final leaf = _slice(area, 'class _TextAreaLeaf', 'class RenderTextArea');
    expect(leaf, contains('required this.layoutMetrics'));
    expect(leaf, contains('final _TextAreaLayoutMetrics layoutMetrics;'));
    expect(leaf, contains('RenderTextArea._forWidget('));
    expect(leaf, contains('layoutMetrics: layoutMetrics'));

    final render = area.substring(area.indexOf('class RenderTextArea'));
    expect(render, contains('final _TextAreaLayoutMetrics? _layoutMetrics;'));
    final layout = _slice(
      render,
      'void performBoxLayout(BoxConstraints constraints)',
      'void paint(PaintingContext context, Offset offset)',
    );
    final sizeAssignment = layout.indexOf('size = Size(');
    final sizeAssignmentEnd = layout.indexOf(';', sizeAssignment);
    final publication = layout.indexOf('_layoutMetrics?.publish(size);');
    expect(sizeAssignment, isNonNegative);
    expect(sizeAssignmentEnd, greaterThan(sizeAssignment));
    expect(
      publication,
      greaterThan(sizeAssignmentEnd),
      reason: 'metrics publication must follow successful size assignment',
    );
    expect(
      RegExp(r'_layoutMetrics\?\.publish\(size\);').allMatches(area),
      hasLength(1),
      reason: "completed render layout must remain the holder's sole writer",
    );

    final publicConstructor = _slice(render, '  RenderTextArea({', '  })');
    expect(publicConstructor, isNot(contains('layoutMetrics')));
    for (final parameter in <String>[
      'cursorController',
      'lines',
      'cursorLine',
      'cursorColumn',
      'placeholder',
      'heightLines',
      'explicitWidth',
      'color',
      'backgroundColor',
      'cursorColor',
      'cursorStyle',
      'focused',
      'scrollLine',
      'scrollCell',
    ]) {
      expect(
        RegExp('required [^,]+ $parameter,').allMatches(publicConstructor),
        hasLength(1),
        reason: 'public RenderTextArea parameter changed: $parameter',
      );
    }
    expect(
      RegExp('required [^,]+ [a-zA-Z]+,').allMatches(publicConstructor),
      hasLength(14),
      reason: 'public RenderTextArea constructor shape must stay exact',
    );
    expect(
      publicBarrel,
      contains("export 'src/widgets/text_area.dart' show TextArea;"),
    );
    expect(
      RegExp(
        r"export 'src/widgets/text_area\.dart'[^;]*;",
      ).allMatches(publicBarrel),
      hasLength(1),
    );
    expect(
      lowLevelBarrel,
      contains("export 'src/widgets/text_area.dart' show RenderTextArea;"),
    );
    expect(
      RegExp(
        r"export 'src/widgets/text_area\.dart'[^;]*;",
      ).allMatches(lowLevelBarrel),
      hasLength(1),
    );
    expect(publicBarrel, isNot(contains('RenderTextArea')));
    expect(lowLevelBarrel, isNot(contains('_TextAreaLayoutMetrics')));
  });
}

String _slice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  expect(start, isNonNegative, reason: 'missing source marker: $startMarker');
  expect(end, greaterThan(start), reason: 'missing source marker: $endMarker');
  return source.substring(start, end);
}
