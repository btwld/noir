import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

void main() {
  group('InheritedWidget', () {
    test(
      'dependOnInheritedWidgetOfExactType registers dependency and rebuilds',
      () {
        final log = <String>[];
        final probes = <_ProbeSnapshot>[];
        final owner = BuildOwner();
        final harness = _Harness(
          child: TestData(
            value: 'alpha',
            child: _TestConsumer(log: log, probes: probes),
          ),
        );

        final element = harness.createElement();
        element.mount(null, owner);
        owner.buildScope();

        expect(log, ['didChangeDependencies:alpha', 'build:alpha']);
        expect(probes, hasLength(1));
        expect(probes.first.inheritedValue, 'alpha');
        expect(probes.first.ancestorWidgetValue, 'alpha');
        expect(probes.first.hasAncestorWidget, isTrue);
        expect(probes.first.hasAncestorState, isTrue);

        final updated = _Harness(
          child: TestData(
            value: 'beta',
            child: _TestConsumer(log: log, probes: probes),
          ),
        );

        element.update(updated);
        owner.buildScope();

        // Flutter order: one didChangeDependencies immediately followed by
        // one build with the new value — no stale-value build, no duplicate
        // build for the same inherited change.
        expect(log, [
          'didChangeDependencies:alpha',
          'build:alpha',
          'didChangeDependencies:beta',
          'build:beta',
        ]);
        expect(probes, hasLength(2));
        expect(probes.map((p) => p.inheritedValue), ['alpha', 'beta']);
        expect(probes[1].ancestorWidgetValue, 'beta');
        expect(probes[1].hasAncestorWidget, isTrue);
        expect(probes[1].hasAncestorState, isTrue);

        element.unmount();
      },
    );

    test(
      'getElementForInheritedWidgetOfExactType does not register dependency',
      () {
        final log = <String>[];
        final owner = BuildOwner();
        final child = _LookupWidget(log: log);

        final widget = TestData(value: 'one', child: child);

        final element = widget.createElement();
        element.mount(null, owner);

        expect(log, ['build:one']);

        final updated = TestData(value: 'two', child: child);

        element.update(updated);
        owner.buildScope();

        expect(log, ['build:one', 'build:two']);

        element.unmount();
      },
    );

    test('dependencies are dropped when widget stops listening', () {
      final log = <String>[];
      final owner = BuildOwner();
      final consumer = _ConditionalConsumer(log: log, listen: true);

      final element = TestData(value: 'alpha', child: consumer).createElement();

      element.mount(null, owner);
      owner.buildScope();
      expect(log, ['build:alpha']);

      log.clear();
      element.update(
        TestData(
          value: 'alpha',
          child: _ConditionalConsumer(log: log, listen: false),
        ),
      );
      owner.buildScope();
      expect(log, ['build:no-listen']);

      log.clear();
      element.update(
        TestData(
          value: 'beta',
          child: _ConditionalConsumer(log: log, listen: false),
        ),
      );
      owner.buildScope();
      expect(log, ['build:no-listen']);

      element.unmount();
    });

    test('null-aspect dependency removal calls didLoseDependency', () {
      final log = <String>[];
      final owner = BuildOwner();
      final element = TestData(
        value: 'alpha',
        child: _DependencyProbe(log: log, listen: true),
      ).createElement();

      element.mount(null, owner);
      owner.buildScope();
      expect(log, ['build:alpha']);

      log.clear();
      element.update(
        TestData(
          value: 'alpha',
          child: _DependencyProbe(log: log, listen: false),
        ),
      );
      owner.buildScope();

      expect(log, ['build:no-listen', 'lost:alpha']);

      element.unmount();
    });
  });

  group('InheritedElement.notifyDependents liveness guard', () {
    test('a dependent deactivated earlier in the same rebuild is not '
        'notified again, and is cleanly dropped once finalizeTree disposes '
        'it', () {
      final log = <String>[];
      final owner = BuildOwner();

      Widget buildTree({
        required String value,
        required bool includeConsumer,
      }) => TestData(
        value: value,
        child: includeConsumer ? _NotifyProbe(log: log) : const _Placeholder(),
      );

      final element = buildTree(
        value: 'alpha',
        includeConsumer: true,
      ).createElement();
      element.mount(null, owner);
      owner.buildScope();

      expect(log, ['didChangeDependencies:alpha']);
      log.clear();

      // The same update both changes the inherited value (so
      // updateShouldNotify becomes true) and removes the consumer via a
      // non-GlobalKey type swap, so the consumer is deactivated by the time
      // InheritedElement.update reaches notifyDependents.
      element.update(buildTree(value: 'beta', includeConsumer: false));
      owner.buildScope();

      expect(
        log,
        isNot(contains('didChangeDependencies:beta')),
        reason:
            'the consumer was deactivated earlier in this same rebuild; '
            'notifyDependents must not notify an inactive dependent',
      );
      expect(log, ['dispose']);

      element.unmount();
    });
  });
}

class TestData extends InheritedWidget {
  const TestData({required this.value, required super.child, super.key});

  final String value;

  static TestData? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TestData>();

  @override
  bool updateShouldNotify(TestData oldWidget) => oldWidget.value != value;
}

class _TestConsumer extends StatefulWidget {
  const _TestConsumer({required this.log, required this.probes});

  final List<String> log;
  final List<_ProbeSnapshot> probes;

  @override
  State<StatefulWidget> createState() => __TestConsumerState();
}

class __TestConsumerState extends State<_TestConsumer> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = TestData.of(context);
    widget.log.add('didChangeDependencies:${inherited?.value}');
  }

  @override
  Widget build(BuildContext context) {
    final inherited = TestData.of(context);
    widget.log.add('build:${inherited?.value}');
    final ancestorWidget = context.findAncestorWidgetOfExactType<TestData>();
    final ancestorState = context.findAncestorStateOfType<_HarnessState>();
    widget.probes.add(
      _ProbeSnapshot(
        inheritedValue: inherited?.value,
        ancestorWidgetValue: ancestorWidget?.value,
        hasAncestorWidget: ancestorWidget != null,
        hasAncestorState: ancestorState != null,
      ),
    );
    return Container();
  }
}

class _ProbeSnapshot {
  const _ProbeSnapshot({
    required this.inheritedValue,
    required this.ancestorWidgetValue,
    required this.hasAncestorWidget,
    required this.hasAncestorState,
  });

  final String? inheritedValue;
  final String? ancestorWidgetValue;
  final bool hasAncestorWidget;
  final bool hasAncestorState;
}

class _Harness extends StatefulWidget {
  const _Harness({required this.child});

  final Widget child;

  @override
  State<StatefulWidget> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  @override
  Widget build(BuildContext context) => widget.child;
}

class _LookupWidget extends StatelessWidget {
  const _LookupWidget({required this.log});

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    final inherited =
        context.getElementForInheritedWidgetOfExactType<TestData>()?.widget
            as TestData?;
    log.add('build:${inherited?.value}');
    return Container();
  }
}

class _ConditionalConsumer extends StatefulWidget {
  const _ConditionalConsumer({required this.log, required this.listen});

  final List<String> log;
  final bool listen;

  @override
  State<_ConditionalConsumer> createState() => _ConditionalConsumerState();
}

class _ConditionalConsumerState extends State<_ConditionalConsumer> {
  @override
  Widget build(BuildContext context) {
    if (widget.listen) {
      final inherited = TestData.of(context);
      widget.log.add('build:${inherited?.value}');
    } else {
      widget.log.add('build:no-listen');
    }
    return Container();
  }
}

class _DependencyProbe extends Widget {
  const _DependencyProbe({required this.log, required this.listen});

  final List<String> log;
  final bool listen;

  @override
  Element createElement() => _DependencyProbeElement(this);
}

class _DependencyProbeElement extends Element {
  _DependencyProbeElement(_DependencyProbe super.widget);

  @override
  _DependencyProbe get widget => super.widget as _DependencyProbe;

  @override
  void performRebuild() {
    if (widget.listen) {
      final inherited =
          dependOnInheritedElementOfExactType<TestData>()?.widget as TestData?;
      widget.log.add('build:${inherited?.value}');
    } else {
      widget.log.add('build:no-listen');
    }
  }

  @override
  void didLoseDependency(InheritedElement inherited) {
    widget.log.add('lost:${(inherited.widget as TestData).value}');
    super.didLoseDependency(inherited);
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container();
}

/// Consumer whose `build` re-establishes its `TestData` dependency on every
/// rebuild (like `_TestConsumer` above) so an ordinary reconciliation-driven
/// `update()` (not triggered by `notifyDependents`) does not spuriously drop
/// the dependency via `Element.rebuild`'s "not re-confirmed this pass"
/// cleanup.
class _NotifyProbe extends StatefulWidget {
  const _NotifyProbe({required this.log});
  final List<String> log;

  @override
  State<_NotifyProbe> createState() => _NotifyProbeState();
}

class _NotifyProbeState extends State<_NotifyProbe> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inherited = TestData.of(context);
    widget.log.add('didChangeDependencies:${inherited?.value}');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    TestData.of(context);
    return Container();
  }
}
