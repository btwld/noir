// ignore_for_file: cascade_invocations
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/render_view.dart';
import 'package:test/test.dart';

void main() {
  test('RenderView attaches to PipelineOwner and schedules initial work', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final view = RenderView(width: 12, height: 5);

    view.attach(pipelineOwner);

    expect(view.pipelineOwner, same(pipelineOwner));
    expect(view.debugNeedsLayout, isTrue);
    expect(view.debugNeedsPaint, isTrue);
    expect(pipelineOwner.debugNeedsLayout, isTrue);
    expect(pipelineOwner.debugNeedsPaint, isTrue);
    expect(visualUpdates, 1);
  });

  test('setChild adopts, drops, and reassigns idempotently', () {
    final view = RenderView();
    final first = _ProbeRenderBox();
    final second = _ProbeRenderBox();

    view.setChild(first);
    view.setChild(first);

    expect(view.child, same(first));
    expect(first.parent, same(view));
    expect(view.children, [same(first)]);

    view.setChild(second);

    expect(view.child, same(second));
    expect(first.parent, isNull);
    expect(second.parent, same(view));
    expect(view.children, [same(second)]);

    view.setChild(null);

    expect(view.child, isNull);
    expect(second.parent, isNull);
    expect(view.children, isEmpty);
  });

  test(
    'flushLayout gives child tight terminal constraints and positions origin',
    () {
      final pipelineOwner = PipelineOwner();
      final view = RenderView(width: 20, height: 7)..attach(pipelineOwner);
      final child = _ProbeRenderBox();

      view.setChild(child);
      pipelineOwner.flushLayout(view, view.terminalConstraints);

      expect(view.size, const Size(20, 7));
      expect(child.lastConstraints, isA<BoxConstraints>());
      final constraints = child.lastConstraints! as BoxConstraints;
      expect(constraints.minWidth, 20);
      expect(constraints.maxWidth, 20);
      expect(constraints.minHeight, 7);
      expect(constraints.maxHeight, 7);
      expect(child.size, const Size(20, 7));
      expect(child.x, 0);
      expect(child.y, 0);
    },
  );

  test('updateTerminalSize schedules layout only when dimensions change', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final view = RenderView(width: 8, height: 3)..attach(pipelineOwner);

    pipelineOwner.flushLayout(view, view.terminalConstraints);
    pipelineOwner.flushPaint(view, (_) {});
    visualUpdates = 0;

    view.updateTerminalSize(8, 3);

    expect(view.debugNeedsLayout, isFalse);
    expect(pipelineOwner.debugNeedsLayout, isFalse);
    expect(visualUpdates, 0);

    view.updateTerminalSize(9, 4);

    expect(view.terminalConstraints.maxWidth, 9);
    expect(view.terminalConstraints.maxHeight, 4);
    expect(view.debugNeedsLayout, isTrue);
    expect(pipelineOwner.debugNeedsLayout, isTrue);
    expect(visualUpdates, 1);
  });
}

class _ProbeRenderBox extends RenderBox {
  Constraints? lastConstraints;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    lastConstraints = constraints;
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
