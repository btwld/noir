// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart'
    show
        BuildContext,
        Container,
        GlobalKey,
        ProxyWidget,
        State,
        StatefulWidget,
        Widget;
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:noir/src/framework/widget.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/render_view.dart';
import 'package:test/test.dart';

void main() {
  test(
    'root render object under non-render widgets attaches to owner RenderView',
    () {
      final owner = BuildOwner();
      final view = RenderView(width: 10, height: 4);
      owner.attachRootRenderObject(view);
      final element = const _Proxy(child: _Leaf('root')).createElement();

      element.mount(null, owner);

      expect(view.child, isA<_LeafRenderBox>());
      expect((view.child! as _LeafRenderBox).label, 'root');
      expect(view.child!.parent, same(view));

      element.unmount();
      owner.clearRootRenderObject(view);
      owner.dispose();
    },
  );

  test(
    'root render object replacement updates RenderView child after build',
    () {
      final owner = BuildOwner();
      owner.setFrameCallback(() {});
      final view = RenderView(width: 10, height: 4);
      owner.attachRootRenderObject(view);
      final key = _SwitchingRoot.keyHandle;
      final element = _SwitchingRoot(key: key).createElement();

      element.mount(null, owner);
      expect(view.child, isA<_LeafRenderBox>());
      expect((view.child! as _LeafRenderBox).label, 'a');

      key.currentState!.showSecond();
      owner.buildScope();

      expect(view.child, isA<_LeafRenderBox>());
      expect((view.child! as _LeafRenderBox).label, 'b');
      expect(view.child!.parent, same(view));
      expect(Element.findDescendantRenderObject(element), same(view.child));

      element.unmount();
      owner.clearRootRenderObject(view);
      owner.dispose();
    },
  );

  test('cleared RenderView and child cannot schedule on the former owner', () {
    var visualUpdates = 0;
    final pipelineOwner = PipelineOwner(
      onNeedVisualUpdate: () => visualUpdates++,
    );
    final owner = BuildOwner.test(pipelineOwner: pipelineOwner);
    final view = RenderView(width: 10, height: 4);
    final child = _LeafRenderBox('old');
    owner.attachRootRenderObject(view);
    view.setChild(child);
    pipelineOwner.flushLayout(view, view.terminalConstraints);
    pipelineOwner.flushPaint(view, (_) {});

    owner.clearRootRenderObject(view);
    final afterClear = visualUpdates;
    view.markNeedsLayout();
    child.markNeedsPaint();

    expect(view.pipelineOwner, isNull);
    expect(child.pipelineOwner, isNull);
    expect(pipelineOwner.debugNeedsLayout, isFalse);
    expect(pipelineOwner.debugNeedsPaint, isFalse);
    expect(visualUpdates, afterClear);

    final replacement = RenderView(width: 10, height: 4);
    owner.attachRootRenderObject(replacement);
    replacement.markNeedsLayout();
    expect(replacement.pipelineOwner, same(pipelineOwner));
    expect(pipelineOwner.debugNeedsLayout, isTrue);
  });

  test(
    'foreign RenderView rejection leaves BuildOwner root and pointer state empty',
    () {
      final ownerA = PipelineOwner();
      final ownerBPipeline = PipelineOwner();
      final ownerB = BuildOwner.test(pipelineOwner: ownerBPipeline);
      final foreign = RenderView(width: 10, height: 4)..attach(ownerA);
      final rejectedChild = _LeafRenderBox('rejected');

      expect(() => ownerB.attachRootRenderObject(foreign), throwsStateError);
      ownerB.insertRootRenderObjectChild(rejectedChild);

      expect(foreign.pipelineOwner, same(ownerA));
      expect(foreign.child, isNull);
      expect(rejectedChild.parent, isNull);
      expect(rejectedChild.pipelineOwner, isNull);
      expect(ownerBPipeline.debugNeedsLayout, isFalse);
      expect(ownerBPipeline.debugNeedsPaint, isFalse);
    },
  );

  test('valid RenderView installs after rejected foreign root', () {
    final ownerA = PipelineOwner();
    final ownerBPipeline = PipelineOwner();
    final ownerB = BuildOwner.test(pipelineOwner: ownerBPipeline);
    final foreign = RenderView(width: 10, height: 4)..attach(ownerA);
    expect(() => ownerB.attachRootRenderObject(foreign), throwsStateError);

    final valid = RenderView(width: 10, height: 4);
    final child = _LeafRenderBox('valid');
    ownerB.attachRootRenderObject(valid);
    ownerB.insertRootRenderObjectChild(child);

    expect(valid.pipelineOwner, same(ownerBPipeline));
    expect(valid.child, same(child));
    expect(child.parent, same(valid));
    expect(child.pipelineOwner, same(ownerBPipeline));
  });
}

class _Proxy extends ProxyWidget {
  const _Proxy({required super.child});
}

class _SwitchingRoot extends StatefulWidget {
  const _SwitchingRoot({super.key});

  static final keyHandle = GlobalKey<_SwitchingRootState>();

  @override
  State<StatefulWidget> createState() => _SwitchingRootState();
}

class _SwitchingRootState extends State<_SwitchingRoot> {
  bool second = false;

  void showSecond() {
    setState(() {
      second = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (second) {
      return const _Proxy(child: Container(child: _Leaf('b')));
    }
    return const _Proxy(child: _Leaf('a'));
  }
}

class _Leaf extends RenderObjectWidget {
  const _Leaf(this.label);

  final String label;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _LeafRenderBox(label);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _LeafRenderBox).label = label;
  }
}

class _LeafRenderBox extends RenderBox {
  _LeafRenderBox(this.label);

  String label;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }
}
