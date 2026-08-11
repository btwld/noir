// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart' show Element;
import 'package:test/test.dart';

void main() {
  group('GlobalKey cross-parent placement', () {
    _testCrossParentRejection(
      description:
          'source-first rejects before mutating the destination child edge',
      sourceSlot: 0,
      hostDepth: 1,
    );
    _testCrossParentRejection(
      description:
          'destination-first rejects before mutating the destination child edge',
      sourceSlot: 1,
      hostDepth: 1,
    );
    _testCrossParentRejection(
      description:
          'nested source-first rejects before mutating the destination child edge',
      sourceSlot: 0,
      hostDepth: 3,
    );
    _testCrossParentRejection(
      description:
          'nested destination-first rejects before mutating the destination child edge',
      sourceSlot: 1,
      hostDepth: 3,
    );

    test(
      'incompatible same-parent reuse rejects before widget or child mutation',
      () {
        final lifecycle = <String>[];
        final key = GlobalKey();
        final owner = BuildOwner();
        final originalWidget = Row(
          children: [
            _Counter(key: key, lifecycle: lifecycle),
            const _Placeholder(),
          ],
        );
        final root = originalWidget.createElement();
        root.mount(null, owner);
        owner.buildScope();

        final originalElement = key.currentContext!.element;
        final originalState = key.currentState;
        final originalRender = Element.findDescendantRenderObject(
          originalElement,
        );
        final originalRenderParent = originalRender!.parent;
        lifecycle.clear();

        expect(
          () => root.update(
            Row(
              children: [
                _AlternateCounter(key: key, lifecycle: lifecycle),
                const _Placeholder(),
              ],
            ),
          ),
          throwsA(_unsupportedPlacementError),
        );

        expect(root.widget, same(originalWidget));
        expect(root.children.first, same(originalElement));
        expect(key.currentContext!.element, same(originalElement));
        expect(key.currentState, same(originalState));
        expect(
          Element.findDescendantRenderObject(originalElement),
          same(originalRender),
        );
        expect(originalRender.parent, same(originalRenderParent));
        expect(originalElement.active, isTrue);
        expect(lifecycle, isEmpty);

        root.unmount();
        owner.dispose();
      },
    );

    test('duplicate placement in unrelated live branches never initializes a '
        'second State and preserves the first binding', () {
      final lifecycle = <String>[];
      final key = GlobalKey<_CounterState>();
      final owner = BuildOwner();
      final root = Row(
        children: [
          _Host(_Counter(key: key, lifecycle: lifecycle)),
          _Host(_Counter(key: key, lifecycle: lifecycle)),
        ],
      ).createElement();

      expect(() => root.mount(null, owner), throwsA(_duplicatePlacementError));

      final firstElement = key.currentContext!.element;
      expect(lifecycle.where((entry) => entry == 'initState'), hasLength(1));
      expect(key.currentState, isNotNull);
      expect(key.currentContext!.element, same(firstElement));

      root.unmount();
      owner.dispose();
      expect(key.currentContext, isNull);
    });

    test(
      'one key cannot bind live children owned by different BuildOwners',
      () {
        final lifecycle = <String>[];
        final key = GlobalKey<_CounterState>();
        final firstOwner = BuildOwner();
        final secondOwner = BuildOwner();
        final firstRoot = _Host(
          _Counter(key: key, lifecycle: lifecycle),
        ).createElement();
        final secondRoot = _Host(
          _Counter(key: key, lifecycle: lifecycle),
        ).createElement();

        firstRoot.mount(null, firstOwner);
        final firstElement = key.currentContext!.element;
        final firstState = key.currentState;
        lifecycle.clear();

        expect(
          () => secondRoot.mount(null, secondOwner),
          throwsA(_unsupportedPlacementError),
        );

        expect(key.currentContext!.element, same(firstElement));
        expect(key.currentState, same(firstState));
        expect(lifecycle, isEmpty);
        expect(secondRoot.children, isEmpty);

        secondRoot.unmount();
        secondOwner.dispose();
        firstRoot.unmount();
        firstOwner.dispose();
        expect(key.currentContext, isNull);
      },
    );

    test(
      'direct root conflict preserves the first binding through partial-root '
      'cleanup',
      () {
        final firstLifecycle = <String>[];
        final secondLifecycle = <String>[];
        final key = GlobalKey<_CounterState>();
        final firstOwner = BuildOwner();
        final secondOwner = BuildOwner();
        final firstRoot = _Counter(
          key: key,
          lifecycle: firstLifecycle,
        ).createElement();
        final secondRoot = _Counter(
          key: key,
          lifecycle: secondLifecycle,
        ).createElement();

        firstRoot.mount(null, firstOwner);
        final firstContext = key.currentContext;
        final firstState = key.currentState;
        expect(firstLifecycle, ['initState']);

        expect(
          () => secondRoot.mount(null, secondOwner),
          throwsA(_unsupportedPlacementError),
        );

        expect(key.currentContext, same(firstContext));
        expect(key.currentState, same(firstState));
        expect(secondLifecycle, isNot(contains('initState')));
        expect(secondRoot.mounted, isTrue);

        // Direct Element.mount bypasses inflateWidget's rollback wrapper. Its
        // rejected low-level partial root is therefore cleaned up explicitly.
        secondRoot.unmount();
        expect(secondRoot.mounted, isFalse);
        expect(secondLifecycle, isNot(contains('initState')));
        expect(key.currentContext, same(firstContext));
        expect(key.currentState, same(firstState));

        secondOwner.dispose();
        expect(key.currentContext, same(firstContext));
        expect(key.currentState, same(firstState));

        firstRoot.unmount();
        expect(key.currentContext, isNull);
        expect(key.currentState, isNull);
        expect(key.currentWidget, isNull);
        firstOwner.dispose();
      },
    );
  });

  group('GlobalKey lookup and update', () {
    test('direct rebind to an already claimed key rejects before widget or '
        'binding mutation', () {
      final lifecycle = <String>[];
      final keyA = GlobalKey<_CounterState>();
      final keyB = GlobalKey<_CounterState>();
      final owner = BuildOwner();
      final root = Row(
        children: [
          _Counter(key: keyA, lifecycle: lifecycle),
          _Counter(key: keyB, lifecycle: lifecycle),
        ],
      ).createElement();
      root.mount(null, owner);
      owner.buildScope();

      final elementA = keyA.currentContext!.element;
      final stateA = keyA.currentState;
      final widgetA = elementA.widget;
      final elementB = keyB.currentContext!.element;
      final stateB = keyB.currentState;
      lifecycle.clear();

      expect(
        () => elementA.update(_Counter(key: keyB, lifecycle: lifecycle)),
        throwsA(_unsupportedPlacementError),
      );

      expect(elementA.widget, same(widgetA));
      expect(keyA.currentContext!.element, same(elementA));
      expect(keyA.currentState, same(stateA));
      expect(keyB.currentContext!.element, same(elementB));
      expect(keyB.currentState, same(stateB));
      expect(lifecycle, isEmpty);

      root.unmount();
      owner.dispose();
    });

    test(
      'current getters resolve while bound and clear after permanent teardown',
      () {
        final lifecycle = <String>[];
        final key = GlobalKey<_CounterState>();
        final owner = BuildOwner();
        final widget = _Counter(key: key, lifecycle: lifecycle);
        final element = widget.createElement();

        expect(key.currentContext, isNull);
        expect(key.currentState, isNull);
        expect(key.currentWidget, isNull);

        element.mount(null, owner);

        expect(key.currentContext!.element, same(element));
        expect(key.currentState, isNotNull);
        expect(key.currentWidget, same(widget));

        element.unmount();

        expect(key.currentContext, isNull);
        expect(key.currentState, isNull);
        expect(key.currentWidget, isNull);
        owner.dispose();
      },
    );
  });

  group('BuildOwner active guard', () {
    test(
      'a dirty child deactivated mid-batch by its parent is not ghost-rebuilt',
      () {
        final log = <String>[];
        final owner = BuildOwner();
        final parentKey = GlobalKey<_RemovableParentState>();
        final counterKey = GlobalKey<_LoggingCounterState>();

        final element = _RemovableParent(
          key: parentKey,
          counterKey: counterKey,
          log: log,
        ).createElement();
        element.mount(null, owner);
        owner.buildScope();

        expect(log, ['build:counter']);
        log.clear();

        counterKey.currentState!.setState(() {});
        parentKey.currentState!.hideCounter();
        owner.buildScope();

        expect(log, ['dispose:counter']);

        element.unmount();
        owner.dispose();
      },
    );
  });
}

void _testCrossParentRejection({
  required String description,
  required int sourceSlot,
  required int hostDepth,
}) {
  test(description, () {
    final lifecycle = <String>[];
    final key = GlobalKey<_CounterState>();
    final owner = BuildOwner();
    final destinationSlot = 1 - sourceSlot;

    Widget buildTree(int occupiedSlot) => Row(
      children: [
        _nestedHost(
          occupiedSlot == 0
              ? _Counter(key: key, lifecycle: lifecycle)
              : const _Placeholder(),
          hostDepth,
        ),
        _nestedHost(
          occupiedSlot == 1
              ? _Counter(key: key, lifecycle: lifecycle)
              : const _Placeholder(),
          hostDepth,
        ),
      ],
    );

    final root = buildTree(sourceSlot).createElement();
    root.mount(null, owner);
    owner.buildScope();

    final sourceElement = key.currentContext!.element;
    final sourceState = key.currentState;
    final sourceParent = sourceElement.parent;
    final destinationPlaceholder = _findWidgetElement<_Placeholder>(
      root.children[destinationSlot],
    );
    final destinationParent = destinationPlaceholder.parent;
    final destinationRender = Element.findDescendantRenderObject(
      destinationPlaceholder,
    )!;
    final destinationRenderParent = destinationRender.parent;
    lifecycle.clear();

    expect(
      () => root.update(buildTree(destinationSlot)),
      throwsA(_unsupportedPlacementError),
    );

    expect(destinationPlaceholder.parent, same(destinationParent));
    expect(destinationPlaceholder.active, isTrue);
    expect(destinationRender.parent, same(destinationRenderParent));
    expect(key.currentContext!.element, same(sourceElement));
    expect(key.currentState, same(sourceState));
    expect(lifecycle, isNot(contains('initState')));
    expect(lifecycle, isNot(contains('dispose')));

    if (sourceSlot == 0) {
      expect(sourceElement.parent, isNull);
      expect(sourceElement.active, isFalse);

      owner.finalizeTree();

      expect(lifecycle.where((entry) => entry == 'dispose'), hasLength(1));
      expect(key.currentContext, isNull);
      expect(key.currentState, isNull);
      expect(key.currentWidget, isNull);
    } else {
      expect(sourceElement.parent, same(sourceParent));
      expect(sourceElement.active, isTrue);
      expect(key.currentContext!.element, same(sourceElement));
    }

    root.unmount();
    owner.dispose();
    expect(lifecycle.where((entry) => entry == 'dispose'), hasLength(1));
    expect(key.currentContext, isNull);
  });
}

final Matcher _unsupportedPlacementError = isA<StateError>().having(
  (error) => error.message,
  'message',
  contains('Cross-parent GlobalKey placement is unsupported'),
);

final Matcher _duplicatePlacementError = isA<StateError>().having(
  (error) => error.message.toLowerCase(),
  'message',
  contains('duplicate'),
);

Widget _nestedHost(Widget child, int depth) {
  var result = child;
  for (var i = 0; i < depth; i++) {
    result = _Host(result);
  }
  return result;
}

Element _findWidgetElement<T extends Widget>(Element root) {
  Element? found;
  void visit(Element element) {
    if (element.widget is T) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  return found!;
}

class _Host extends StatelessWidget {
  const _Host(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 1);
}

class _Counter extends StatefulWidget {
  const _Counter({required this.lifecycle, super.key});

  final List<String> lifecycle;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  @override
  void initState() {
    super.initState();
    widget.lifecycle.add('initState');
  }

  @override
  void dispose() {
    widget.lifecycle.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 1);
}

class _AlternateCounter extends StatefulWidget {
  const _AlternateCounter({required this.lifecycle, super.key});

  final List<String> lifecycle;

  @override
  State<_AlternateCounter> createState() => _AlternateCounterState();
}

class _AlternateCounterState extends State<_AlternateCounter> {
  @override
  void initState() {
    super.initState();
    widget.lifecycle.add('alternate-initState');
  }

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 1);
}

class _RemovableParent extends StatefulWidget {
  const _RemovableParent({
    required this.counterKey,
    required this.log,
    super.key,
  });

  final GlobalKey<_LoggingCounterState> counterKey;
  final List<String> log;

  @override
  State<_RemovableParent> createState() => _RemovableParentState();
}

class _RemovableParentState extends State<_RemovableParent> {
  bool showCounter = true;

  void hideCounter() => setState(() => showCounter = false);

  @override
  Widget build(BuildContext context) => showCounter
      ? _LoggingCounter(key: widget.counterKey, log: widget.log)
      : const _Placeholder();
}

class _LoggingCounter extends StatefulWidget {
  const _LoggingCounter({required this.log, super.key});

  final List<String> log;

  @override
  State<_LoggingCounter> createState() => _LoggingCounterState();
}

class _LoggingCounterState extends State<_LoggingCounter> {
  @override
  void dispose() {
    widget.log.add('dispose:counter');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:counter');
    return Container(width: 1, height: 1);
  }
}
