import 'package:noir/src/core/color.dart';
import 'package:noir/src/core/cursor.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/constrained_box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/padding.dart';
import 'package:noir/src/widgets/input.dart';
import 'package:noir/src/widgets/select.dart';
import 'package:noir/src/widgets/text_area.dart';

void main() {
  final constrained = RenderConstrainedBox(
    additionalConstraints: const BoxConstraints(maxWidth: 8),
  );
  _rejectsWithoutWork(
    'constraints',
    constrained,
    () => constrained.additionalConstraints = _InvalidConstraints(),
    () => constrained.additionalConstraints = const BoxConstraints(maxWidth: 8),
  );

  final padding = RenderPadding(padding: const EdgeInsets.all(1));
  _rejectsWithoutWork(
    'padding',
    padding,
    () => padding.padding = _InvalidInsets(),
    () => padding.padding = const EdgeInsets.all(1),
  );

  final select = RenderSelect<String>(
    options: const [SelectOption(name: 'a', value: 'a')],
    highlighted: 0,
    scrollOffset: 0,
    visibleRows: 2,
    showScrollIndicator: false,
    color: Color.white,
    backgroundColor: Color.black,
    selectedBackgroundColor: Color.black,
    selectedTextColor: Color.white,
    descriptionColor: Color.white,
  );
  _rejectsWithoutWork(
    'select-rows',
    select,
    () => select.visibleRows = -1,
    () => select.visibleRows = 2,
  );

  final area = _textArea();
  _rejectsWithoutWork(
    'textarea-height',
    area,
    () => area.heightLines = -1,
    () => area.heightLines = 2,
  );
  final widthArea = _textArea();
  _rejectsWithoutWork(
    'textarea-width',
    widthArea,
    () => widthArea.explicitWidth = -1,
    () => widthArea.explicitWidth = 8,
  );

  final input = RenderTextInput(
    cursorController: CursorController(),
    value: 'secret',
    color: Color.white,
    cursorColor: Color.white,
    cursorStyle: CursorStyle.block,
    cursorPosition: 0,
    focused: false,
    obscureText: true,
    obscuringCharacter: '*',
  );
  _rejectsWithoutWork(
    'obscuring-character',
    input,
    () => input.obscuringCharacter = '界',
    () => input.obscuringCharacter = '*',
  );
}

RenderTextArea _textArea() => RenderTextArea(
  cursorController: CursorController(),
  lines: const ['a'],
  cursorLine: 0,
  cursorColumn: 0,
  placeholder: null,
  heightLines: 2,
  explicitWidth: 8,
  color: Color.white,
  backgroundColor: Color.black,
  cursorColor: Color.white,
  cursorStyle: CursorStyle.block,
  focused: false,
  scrollLine: 0,
  scrollCell: 0,
);

void _rejectsWithoutWork(
  String label,
  RenderBox renderObject,
  void Function() reject,
  void Function() restoreOriginal,
) {
  var visualUpdates = 0;
  final owner = PipelineOwner(onNeedVisualUpdate: () => visualUpdates++);
  renderObject.attach(owner);
  owner
    ..flushLayout(
      renderObject,
      const BoxConstraints.tight(width: 12, height: 6),
    )
    ..flushPaint(renderObject, (_) {});
  visualUpdates = 0;

  Object? error;
  try {
    reject();
  } catch (caught) {
    error = caught;
  }
  if (error is! ArgumentError) {
    throw StateError('$label did not throw ArgumentError: $error');
  }
  _requireClean(label, renderObject, owner, visualUpdates);

  restoreOriginal();
  _requireClean('$label retained value', renderObject, owner, visualUpdates);
  print('PASS:$label');
}

void _requireClean(
  String label,
  RenderObject renderObject,
  PipelineOwner owner,
  int visualUpdates,
) {
  if (renderObject.debugNeedsLayout ||
      renderObject.debugNeedsPaint ||
      owner.debugNeedsLayout ||
      owner.debugNeedsPaint ||
      visualUpdates != 0) {
    throw StateError(
      '$label changed state: '
      'renderLayout=${renderObject.debugNeedsLayout} '
      'renderPaint=${renderObject.debugNeedsPaint} '
      'ownerLayout=${owner.debugNeedsLayout} '
      'ownerPaint=${owner.debugNeedsPaint} updates=$visualUpdates',
    );
  }
}

final class _InvalidConstraints extends BoxConstraints {
  _InvalidConstraints() : super(maxWidth: 2);

  @override
  int get minWidth => 3;
}

final class _InvalidInsets extends EdgeInsets {
  _InvalidInsets() : super(left: 0);

  @override
  int get left => -1;
}
