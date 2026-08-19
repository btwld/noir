import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

void main() {
  test('reassemble rebuilds the tree without setState and keeps State', () {
    final log = <String>[];
    final states = <Object>[];
    final app = createTuiTestApp(
      _StateProbe(log: log, onBuild: states.add),
      width: 20,
      height: 5,
    );
    addTearDown(app.dispose);
    app.pumpFrame();

    expect(log, <String>['init', 'build']);

    app.binding.reassemble();
    app.pumpFrame(const Duration(milliseconds: 16));

    expect(log, <String>[
      'init',
      'build',
      'reassemble',
      'build',
    ], reason: 'reassemble must rebuild once and must not re-run initState');
    expect(states, hasLength(2));
    expect(states.first, same(states.last));
  });

  test('a failing State hook keeps the rebuild, repaint, and the report', () {
    final log = <String>[];
    final errors = <Object>[];
    final app = createTuiTestApp(
      _StateProbe(log: log, onBuild: (_) {}, failReassemble: true),
      width: 20,
      height: 5,
    );
    addTearDown(app.dispose);
    app.pumpFrame();
    final pipeline = app.binding.buildOwner.pipelineOwner;
    log.clear();

    runZonedGuarded(app.binding.reassemble, (error, _) => errors.add(error));

    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(
      pipeline.debugNeedsLayout,
      isTrue,
      reason: 'the repaint mark survives a failing hook',
    );

    app.pumpFrame(const Duration(milliseconds: 16));
    expect(log, <String>['reassemble', 'build']);
  });

  test('reassemble marks the render root dirty for a render-stable tree', () {
    final app = createTuiTestApp(
      _StateProbe(log: <String>[], onBuild: (_) {}),
      width: 20,
      height: 5,
    );
    addTearDown(app.dispose);
    final pipeline = app.binding.buildOwner.pipelineOwner;

    // `_StateProbe` builds a `const SizedBox`, so reconciliation reaches the
    // render layer with value-equal constraints and marks nothing dirty.
    app.pumpFrame();
    expect(
      pipeline.debugNeedsLayout,
      isFalse,
      reason: 'the const-stable subtree must settle before the probe',
    );
    expect(pipeline.debugNeedsPaint, isFalse);

    app.binding.reassemble();

    // Asserted before pumping: only `TuiBinding.reassemble`'s explicit
    // `markNeedsLayout()` on the render root can have set this, so an edited
    // `performLayout`/`paint` body still repaints after a hot reload.
    expect(pipeline.debugNeedsLayout, isTrue);
    expect(pipeline.debugNeedsPaint, isTrue);
  });

  test('reassemble on a binding with no mounted root does not throw', () {
    final binding = TuiBinding(headless: true);
    addTearDown(binding.dispose);

    expect(binding.reassemble, returnsNormally);
    expect(binding.debugFlushFrame, returnsNormally);
  });

  test('reassemble after dispose is a no-op', () {
    final log = <String>[];
    final app = createTuiTestApp(
      _StateProbe(log: log, onBuild: (_) {}),
      width: 20,
      height: 5,
    );
    app.dispose();
    log.clear();

    expect(app.binding.reassemble, returnsNormally);
    expect(log, isEmpty);
  });
}

/// Records lifecycle order and hands out its live [State] identity.
///
/// Its `build` returns a `const` subtree so the render layer sees value-equal
/// configuration on every rebuild.
class _StateProbe extends StatefulWidget {
  const _StateProbe({
    required this.log,
    required this.onBuild,
    this.failReassemble = false,
  });

  final List<String> log;
  final void Function(Object state) onBuild;
  final bool failReassemble;

  @override
  State<_StateProbe> createState() => _StateProbeState();
}

class _StateProbeState extends State<_StateProbe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void reassemble() {
    super.reassemble();
    widget.log.add('reassemble');
    if (widget.failReassemble) {
      throw StateError('reassemble failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build');
    widget.onBuild(this);
    return const SizedBox(width: 4, height: 2);
  }
}
