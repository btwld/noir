import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test(
    'isWalkingTree is true only while a frame builds, lays out, and paints',
    () {
      final seen = <String, bool>{};
      final rebuild = ValueNotifier<int>(0);
      addTearDown(rebuild.dispose);
      TuiTestApp? mounted;
      void record(String where) {
        // The first mount builds before there is an app to ask.
        final binding = mounted?.binding;
        if (binding != null) {
          seen[where] = binding.isWalkingTree;
        }
      }

      final app = mounted = createTuiTestApp(
        _Probes(record, rebuild),
        width: 20,
        height: 3,
      );
      addTearDown(app.dispose);
      expect(app.binding.isWalkingTree, isFalse);

      app.pumpFrame();
      rebuild.value = 1;
      app.pumpFrame(const Duration(milliseconds: 16));

      expect(seen, <String, bool>{
        'ticker': false,
        'build': true,
        'layout builder': true,
        'layout': true,
        'paint': true,
      });
      expect(app.binding.isWalkingTree, isFalse);
    },
  );

  test('isWalkingTree is false again after a walk that threw', () {
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);
    final failure = StateError('build failed');
    final app = createTuiTestApp(
      _CallsWhenRebuilt(rebuild, () => throw failure),
    );
    addTearDown(app.dispose);
    app.pumpFrame();

    rebuild.value = 1;
    expect(
      () => app.pumpFrame(const Duration(milliseconds: 16)),
      throwsA(same(failure)),
    );

    expect(app.binding.isWalkingTree, isFalse);
  });

  test('a frame flushed from inside a build leaves the outer walk marked', () {
    final rebuild = ValueNotifier<int>(0);
    addTearDown(rebuild.dispose);
    TuiTestApp? mounted;
    bool? walkingAfterInnerFrame;
    final app = mounted = createTuiTestApp(
      _CallsWhenRebuilt(rebuild, () {
        final app = mounted!;
        // The build owner refuses a second build pass, which ends the inner
        // frame. The outer one is still walking the tree.
        expect(app.pumpFrame, throwsStateError);
        walkingAfterInnerFrame = app.binding.isWalkingTree;
      }),
    );
    addTearDown(app.dispose);
    app.pumpFrame();

    rebuild.value = 1;
    app.pumpFrame(const Duration(milliseconds: 16));

    expect(walkingAfterInnerFrame, isTrue);
  });
}

/// Calls [record] from each part of a frame that runs a widget's own code.
final class _Probes extends StatefulWidget {
  const _Probes(this.record, this.rebuild);

  final void Function(String where) record;

  /// Rebuilds this widget when it changes, so `build` runs inside a frame.
  final ValueNotifier<int> rebuild;

  @override
  State<_Probes> createState() => _ProbesState();
}

final class _ProbesState extends State<_Probes>
    with SingleTickerProviderStateMixin<_Probes> {
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    widget.rebuild.addListener(_rebuild);
    _ticker = createTicker((_) => widget.record('ticker'))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.rebuild.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    widget.record('build');
    return Column(
      children: <Widget>[
        LayoutBuilder(
          builder: (context, constraints) {
            widget.record('layout builder');
            return Text('built ${widget.rebuild.value}');
          },
        ),
        _RenderProbe(widget.record, child: const Text('painted')),
      ],
    );
  }
}

final class _RenderProbe extends SingleChildRenderObjectWidget {
  const _RenderProbe(this.record, {super.child});

  final void Function(String where) record;

  @override
  _RenderProbeBox createRenderObject(BuildContext context) =>
      _RenderProbeBox(record);
}

final class _RenderProbeBox extends RenderProxyBox {
  _RenderProbeBox(this.record);

  final void Function(String where) record;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    record('layout');
    super.performBoxLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    record('paint');
    super.paint(context, offset);
  }
}

/// Builds normally at first, and runs [onRebuild] from `build` each time
/// [rebuild] has changed.
final class _CallsWhenRebuilt extends StatefulWidget {
  const _CallsWhenRebuilt(this.rebuild, this.onRebuild);

  final ValueNotifier<int> rebuild;
  final void Function() onRebuild;

  @override
  State<_CallsWhenRebuilt> createState() => _CallsWhenRebuiltState();
}

final class _CallsWhenRebuiltState extends State<_CallsWhenRebuilt> {
  @override
  void initState() {
    super.initState();
    widget.rebuild.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.rebuild.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (widget.rebuild.value != 0) {
      widget.onRebuild();
    }
    return const Text('ready');
  }
}
