import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

void main() {
  group('State.deferDispose', () {
    test('releases a retired resource only after descendants reconcile', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _ParentWidget(generation: 1, log: log).createElement()
        ..mount(null, owner);

      expect(log, <String>['child-build:generation-1']);

      element.update(_ParentWidget(generation: 2, log: log));

      // The replacement build already ran, but the retired resource is still
      // alive because the pass has not finalized yet.
      expect(log, <String>[
        'child-build:generation-1',
        'child-build:generation-2',
      ]);

      owner.buildScope();

      expect(log, <String>[
        'child-build:generation-1',
        'child-build:generation-2',
        'release:generation-1',
      ]);

      element.unmount();
      owner.dispose();
    });

    test('keeps the resource when the host build fails, then recovers', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _ParentWidget(generation: 1, log: log).createElement()
        ..mount(null, owner);

      expect(
        () => element.update(
          _ParentWidget(generation: 2, log: log, failBuild: true),
        ),
        throwsA(isA<_BuildFailure>()),
      );
      owner.buildScope();

      expect(log, isNot(contains('release:generation-1')));

      element.update(_ParentWidget(generation: 3, log: log));
      owner.buildScope();

      expect(log, contains('release:generation-1'));
      expect(log, contains('release:generation-2'));

      element.unmount();
      owner.dispose();
    });

    test('releases descendant batches before ancestor batches', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _NestedHostWidget(generation: 1, log: log).createElement()
        ..mount(null, owner);

      element.update(_NestedHostWidget(generation: 2, log: log));
      owner.buildScope();

      expect(
        log.where((entry) => entry.startsWith('release:')).toList(),
        <String>['release:inner-1', 'release:outer-1'],
      );

      element.unmount();
      owner.dispose();
    });

    test('releases a deeper host first across separate build batches', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _SplitBatchHostWidget(log).createElement()
        ..mount(null, owner);

      // Both hosts retire outside any reconciliation, ancestor first, so
      // retire order alone would release the ancestor first. Depth decides.
      final ancestor = (element as StatefulElement).state as _SplitBatchState;
      ancestor.retire();
      _SplitBatchInnerState.instance!.retire();
      owner.buildScope();

      expect(log, <String>['release:inner', 'release:outer']);

      element.unmount();
      owner.dispose();
    });

    test('flushes retired resources during unmount before dispose', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _ParentWidget(generation: 1, log: log).createElement()
        ..mount(null, owner);

      element.update(_ParentWidget(generation: 2, log: log));
      element.unmount();

      final released = log.indexOf('release:generation-1');
      final disposed = log.indexOf('dispose:parent');
      expect(released, isNonNegative);
      expect(disposed, isNonNegative);
      expect(released, lessThan(disposed));

      owner.dispose();
    });

    test('flushes after the descendants unmount, not before', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _StatefulChildHostWidget(
        generation: 1,
        log: log,
      ).createElement()..mount(null, owner);

      element.update(_StatefulChildHostWidget(generation: 2, log: log));
      element.unmount();

      expect(log, <String>[
        'dispose:child',
        'release:host-1',
        'dispose:host',
        'release:host-2',
      ]);

      owner.dispose();
    });

    test('runs cleanup synchronously while dispose is executing', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _DisposeTimeWidget(log).createElement()
        ..mount(null, owner);

      element.unmount();

      expect(log, <String>['dispose-start', 'release:dispose-time']);
      owner.dispose();
    });

    test('schedules the required rebuild when called while idle', () {
      final log = <String>[];
      final owner = BuildOwner();
      var frames = 0;
      owner.setFrameCallback(() => frames++);
      final element = _IdleDeferWidget(log).createElement()..mount(null, owner);

      final state = (element as StatefulElement).state as _IdleDeferState;
      state.retire('idle');

      expect(frames, greaterThan(0));
      expect(log, isEmpty);

      owner.buildScope();
      expect(log, <String>['release:idle']);

      element.unmount();
      owner.dispose();
    });

    test('attempts every cleanup and preserves the first failure', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _IdleDeferWidget(log).createElement()..mount(null, owner);
      final state = (element as StatefulElement).state as _IdleDeferState;

      state.retireThrowing('first');
      state.retire('second');
      state.retireThrowing('third');

      // Two distinct failures: the earliest one must escape, not the last.
      expect(
        owner.buildScope,
        throwsA(
          isA<_CleanupFailure>().having(
            (failure) => failure.name,
            'name',
            'first',
          ),
        ),
      );
      expect(log, <String>['release:first', 'release:second', 'release:third']);

      element.unmount();
      owner.dispose();
    });

    test('joins nested registrations to the drain already in flight', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = _IdleDeferWidget(log).createElement()..mount(null, owner);
      final state = (element as StatefulElement).state as _IdleDeferState;

      state.retireNesting('outer', 'nested');
      owner.buildScope();

      expect(log, <String>['release:outer', 'release:nested']);

      element.unmount();
      owner.dispose();
    });

    test('throws when called after the state detaches', () {
      final owner = BuildOwner();
      final element = _IdleDeferWidget(<String>[]).createElement()
        ..mount(null, owner);
      final state = (element as StatefulElement).state as _IdleDeferState;

      element.unmount();
      owner.dispose();

      expect(
        () => state.deferDispose(() {}),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('deferDispose() called after dispose()'),
          ),
        ),
      );
    });
  });
}

class _BuildFailure implements Exception {
  const _BuildFailure();
}

class _CleanupFailure implements Exception {
  const _CleanupFailure(this.name);

  final String name;
}

/// Owns one generation-tagged resource that its child still reads while the
/// replacement build runs.
class _ParentWidget extends StatefulWidget {
  const _ParentWidget({
    required this.generation,
    required this.log,
    this.failBuild = false,
  });

  final int generation;
  final List<String> log;
  final bool failBuild;

  @override
  State<_ParentWidget> createState() => _ParentState();
}

class _ParentState extends State<_ParentWidget> {
  late _Resource _resource;

  @override
  void initState() {
    super.initState();
    _resource = _Resource('generation-${widget.generation}', widget.log);
  }

  @override
  void didUpdateWidget(_ParentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generation == widget.generation) {
      return;
    }
    final retired = _resource;
    _resource = _Resource('generation-${widget.generation}', widget.log);
    deferDispose(retired.release);
  }

  @override
  void dispose() {
    widget.log.add('dispose:parent');
    _resource.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.failBuild) {
      throw const _BuildFailure();
    }
    return _ChildWidget(resource: _resource, log: widget.log);
  }
}

/// Reads the borrowed resource on every build, so an early release would be
/// observable as a use-after-release.
class _ChildWidget extends StatelessWidget {
  const _ChildWidget({required this.resource, required this.log});

  final _Resource resource;
  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('child-build:${resource.read()}');
    return const SizedBox();
  }
}

/// Two nested hosts that both retire a resource in the same reconciliation.
class _NestedHostWidget extends StatefulWidget {
  const _NestedHostWidget({required this.generation, required this.log});

  final int generation;
  final List<String> log;

  @override
  State<_NestedHostWidget> createState() => _NestedHostState();
}

class _NestedHostState extends State<_NestedHostWidget> {
  late _Resource _resource;

  @override
  void initState() {
    super.initState();
    _resource = _Resource('outer-${widget.generation}', widget.log);
  }

  @override
  void didUpdateWidget(_NestedHostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final retired = _resource;
    _resource = _Resource('outer-${widget.generation}', widget.log);
    deferDispose(retired.release);
  }

  @override
  void dispose() {
    _resource.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _InnerHostWidget(generation: widget.generation, log: widget.log);
}

class _InnerHostWidget extends StatefulWidget {
  const _InnerHostWidget({required this.generation, required this.log});

  final int generation;
  final List<String> log;

  @override
  State<_InnerHostWidget> createState() => _InnerHostState();
}

class _InnerHostState extends State<_InnerHostWidget> {
  late _Resource _resource;

  @override
  void initState() {
    super.initState();
    _resource = _Resource('inner-${widget.generation}', widget.log);
  }

  @override
  void didUpdateWidget(_InnerHostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final retired = _resource;
    _resource = _Resource('inner-${widget.generation}', widget.log);
    deferDispose(retired.release);
  }

  @override
  void dispose() {
    _resource.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Registers a cleanup from inside `dispose()`.
class _DisposeTimeWidget extends StatefulWidget {
  const _DisposeTimeWidget(this.log);

  final List<String> log;

  @override
  State<_DisposeTimeWidget> createState() => _DisposeTimeState();
}

class _DisposeTimeState extends State<_DisposeTimeWidget> {
  @override
  void dispose() {
    widget.log.add('dispose-start');
    deferDispose(() => widget.log.add('release:dispose-time'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Exposes `deferDispose` to the test outside any reconciliation.
class _IdleDeferWidget extends StatefulWidget {
  const _IdleDeferWidget(this.log);

  final List<String> log;

  @override
  State<_IdleDeferWidget> createState() => _IdleDeferState();
}

class _IdleDeferState extends State<_IdleDeferWidget> {
  void retire(String name) =>
      deferDispose(() => widget.log.add('release:$name'));

  void retireThrowing(String name) => deferDispose(() {
    widget.log.add('release:$name');
    throw _CleanupFailure(name);
  });

  void retireNesting(String outer, String nested) => deferDispose(() {
    widget.log.add('release:$outer');
    deferDispose(() => widget.log.add('release:$nested'));
  });

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// A named resource that records its reads and its single release.
class _Resource {
  _Resource(this.name, this._log);

  final String name;
  final List<String> _log;
  bool _released = false;

  String read() {
    if (_released) {
      throw StateError('Resource $name was read after release.');
    }
    return name;
  }

  void release() {
    if (_released) {
      return;
    }
    _released = true;
    _log.add('release:$name');
  }
}

/// A host whose retired resource must outlive its stateful child's teardown.
class _StatefulChildHostWidget extends StatefulWidget {
  const _StatefulChildHostWidget({required this.generation, required this.log});

  final int generation;
  final List<String> log;

  @override
  State<_StatefulChildHostWidget> createState() => _StatefulChildHostState();
}

class _StatefulChildHostState extends State<_StatefulChildHostWidget> {
  late _Resource _resource;

  @override
  void initState() {
    super.initState();
    _resource = _Resource('host-${widget.generation}', widget.log);
  }

  @override
  void didUpdateWidget(_StatefulChildHostWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final retired = _resource;
    _resource = _Resource('host-${widget.generation}', widget.log);
    deferDispose(retired.release);
  }

  @override
  void dispose() {
    widget.log.add('dispose:host');
    _resource.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _LoggingChildWidget(widget.log);
}

/// Records its own teardown so the flush can be ordered against it.
class _LoggingChildWidget extends StatefulWidget {
  const _LoggingChildWidget(this.log);

  final List<String> log;

  @override
  State<_LoggingChildWidget> createState() => _LoggingChildState();
}

class _LoggingChildState extends State<_LoggingChildWidget> {
  @override
  void dispose() {
    widget.log.add('dispose:child');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

/// Two nested hosts that retire outside any reconciliation of each other.
class _SplitBatchHostWidget extends StatefulWidget {
  const _SplitBatchHostWidget(this.log);

  final List<String> log;

  @override
  State<_SplitBatchHostWidget> createState() => _SplitBatchState();
}

class _SplitBatchState extends State<_SplitBatchHostWidget> {
  void retire() => deferDispose(_Resource('outer', widget.log).release);

  @override
  Widget build(BuildContext context) => _SplitBatchInnerWidget(widget.log);
}

class _SplitBatchInnerWidget extends StatefulWidget {
  const _SplitBatchInnerWidget(this.log);

  final List<String> log;

  @override
  State<_SplitBatchInnerWidget> createState() => _SplitBatchInnerState();
}

class _SplitBatchInnerState extends State<_SplitBatchInnerWidget> {
  /// The single live inner state, so the test can retire it directly.
  static _SplitBatchInnerState? instance;

  void retire() => deferDispose(_Resource('inner', widget.log).release);

  @override
  void initState() {
    super.initState();
    instance = this;
  }

  @override
  void dispose() {
    if (identical(instance, this)) instance = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
