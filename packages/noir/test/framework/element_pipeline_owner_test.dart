import 'package:noir/noir.dart' show BoxConstraints, BuildContext, Size;
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:test/test.dart';

void main() {
  test('RenderObjectElement attaches render object to BuildOwner pipeline', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
    final element = const _ProbeWidget(label: 'a').createElement();

    element.mount(null, owner);

    final renderElement = Element.findRenderObjectElement(element)!;
    final renderObject = renderElement.renderObject! as _ProbeRenderBox;

    expect(renderObject.pipelineOwner, same(pipelineOwner));
    expect(renderObject.debugNeedsLayout, isTrue);
    expect(renderObject.debugNeedsPaint, isTrue);
    expect(pipelineOwner.debugNeedsLayout, isTrue);
    expect(pipelineOwner.debugNeedsPaint, isTrue);
    expect(visualUpdates, 1);
  });

  test(
    'layout-owning render setter schedules layout through Element update',
    () {
      var visualUpdates = 0;
      final owner = BuildOwner.test(
        pipelineOwner: PipelineOwner(onNeedVisualUpdate: () => visualUpdates++),
      );
      final element = const _ProbeWidget(label: 'a').createElement();
      const constraints = BoxConstraints.tight(width: 10, height: 4);

      element.mount(null, owner);
      final renderObject =
          Element.findRenderObjectElement(element)!.renderObject!
              as _ProbeRenderBox;
      owner.pipelineOwner.flushLayout(renderObject, constraints);
      owner.pipelineOwner.flushPaint(renderObject, (_) {});
      visualUpdates = 0;

      element.update(const _ProbeWidget(label: 'b'));

      expect(renderObject.label, 'b');
      expect(renderObject.debugNeedsLayout, isTrue);
      expect(renderObject.debugNeedsPaint, isTrue);
      expect(owner.pipelineOwner.debugNeedsLayout, isTrue);
      expect(owner.pipelineOwner.debugNeedsPaint, isTrue);
      expect(visualUpdates, 1);
    },
  );

  test(
    'paint-owning render setter stays paint-only through Element update',
    () {
      var visualUpdates = 0;
      final pipelineOwner = PipelineOwner(
        onNeedVisualUpdate: () => visualUpdates++,
      );
      final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
      final element = const _PaintProbeWidget(color: 1).createElement();
      const constraints = BoxConstraints.tight(width: 10, height: 4);

      element.mount(null, owner);
      final renderObject =
          Element.findRenderObjectElement(element)!.renderObject!
              as _PaintProbeRenderBox;
      pipelineOwner.flushLayout(renderObject, constraints);
      pipelineOwner.flushPaint(renderObject, (_) {});
      visualUpdates = 0;

      element.update(const _PaintProbeWidget(color: 2));

      expect(renderObject.color, 2);
      expect(renderObject.debugNeedsLayout, isFalse);
      expect(renderObject.debugNeedsPaint, isTrue);
      expect(pipelineOwner.debugNeedsLayout, isFalse);
      expect(pipelineOwner.debugNeedsPaint, isTrue);
      expect(visualUpdates, 1);
    },
  );

  test('callback-only Element update schedules no pipeline work', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
    void first() {}
    void second() {}
    final element = _CallbackProbeWidget(first).createElement();
    const constraints = BoxConstraints.tight(width: 10, height: 4);

    element.mount(null, owner);
    final renderObject =
        Element.findRenderObjectElement(element)!.renderObject!
            as _CallbackProbeRenderBox;
    pipelineOwner.flushLayout(renderObject, constraints);
    pipelineOwner.flushPaint(renderObject, (_) {});
    visualUpdates = 0;

    element.update(_CallbackProbeWidget(second));

    expect(renderObject.callback, same(second));
    expect(renderObject.debugNeedsLayout, isFalse);
    expect(renderObject.debugNeedsPaint, isFalse);
    expect(pipelineOwner.debugNeedsLayout, isFalse);
    expect(pipelineOwner.debugNeedsPaint, isFalse);
    expect(visualUpdates, 0);
  });

  test('unmounted render object cannot schedule on its former owner', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
    final element = const _ProbeWidget(label: 'retained').createElement();
    const constraints = BoxConstraints.tight(width: 10, height: 4);
    element.mount(null, owner);
    final renderObject =
        Element.findRenderObjectElement(element)!.renderObject!
            as _ProbeRenderBox;
    pipelineOwner.flushLayout(renderObject, constraints);
    pipelineOwner.flushPaint(renderObject, (_) {});

    element.unmount();
    final updatesAfterUnmount = visualUpdates;
    renderObject.markNeedsLayout();
    renderObject.markNeedsPaint();

    expect(renderObject.pipelineOwner, isNull);
    expect(pipelineOwner.debugNeedsLayout, isFalse);
    expect(pipelineOwner.debugNeedsPaint, isFalse);
    expect(visualUpdates, updatesAfterUnmount);
  });
}

class _ProbeWidget extends RenderObjectWidget {
  const _ProbeWidget({required this.label});

  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _ProbeRenderBox(label);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _ProbeRenderBox).label = label;
  }
}

class _ProbeRenderBox extends RenderBox {
  _ProbeRenderBox(this._label);

  String _label;

  String get label => _label;

  set label(String value) {
    if (_label == value) return;
    _label = value;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}

class _PaintProbeWidget extends RenderObjectWidget {
  const _PaintProbeWidget({required this.color});

  final int color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _PaintProbeRenderBox(color);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _PaintProbeRenderBox).color = color;
  }
}

class _PaintProbeRenderBox extends _ProbeRenderBox {
  _PaintProbeRenderBox(this._color) : super('paint');

  int _color;

  int get color => _color;

  set color(int value) {
    if (_color == value) return;
    _color = value;
    markNeedsPaint();
  }
}

class _CallbackProbeWidget extends RenderObjectWidget {
  const _CallbackProbeWidget(this.callback);

  final void Function() callback;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _CallbackProbeRenderBox(callback);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _CallbackProbeRenderBox).callback = callback;
  }
}

class _CallbackProbeRenderBox extends _ProbeRenderBox {
  _CallbackProbeRenderBox(this.callback) : super('callback');

  void Function() callback;
}
