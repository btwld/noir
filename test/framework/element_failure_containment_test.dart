// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

void main() {
  test('TuiBinding preserves a later mount failure while rolling back every '
      'initialized State', () {
    final firstKey = GlobalKey<_ProbeState>();
    final failingKey = GlobalKey<_ProbeState>();
    final states = <_ProbeState>[];
    final log = <String>[];
    final mountFailure = StateError('later build failed');
    final mountStack = StackTrace.fromString('later-build-stack');
    final disposeFailure = StateError('earlier dispose failed');
    final disposeStack = StackTrace.fromString('earlier-dispose-stack');

    final caught = _catchSync(
      () => runTuiAppForTesting(
        Row(
          children: [
            _Probe(
              key: firstKey,
              label: 'first',
              states: states,
              log: log,
              disposeFailure: disposeFailure,
              disposeStack: disposeStack,
            ),
            _Probe(
              key: failingKey,
              label: 'failing',
              states: states,
              log: log,
              buildFailure: mountFailure,
              buildStack: mountStack,
            ),
          ],
        ),
        headless: true,
      ),
    );

    expect(caught.error, same(mountFailure));
    expect(caught.stackTrace.toString(), mountStack.toString());
    expect(states, hasLength(2));
    expect(states.every((state) => !state.mounted), isTrue);
    expect(states.map((state) => state.disposeCount), everyElement(1));
    expect(firstKey.currentContext, isNull);
    expect(failingKey.currentContext, isNull);
    expect(log, containsAll(<String>['dispose:failing', 'dispose:first']));
  });

  test('multi-child mount publishes each prior success before a later '
      'failure', () {
    final firstKey = GlobalKey<_ProbeState>();
    final failingKey = GlobalKey<_ProbeState>();
    final states = <_ProbeState>[];
    final log = <String>[];
    final failure = StateError('second build failed');
    final failureStack = StackTrace.fromString('second-build-stack');
    final owner = BuildOwner();
    final element = Row(
      children: [
        _Probe(key: firstKey, label: 'first', states: states, log: log),
        _Probe(
          key: failingKey,
          label: 'failing',
          states: states,
          log: log,
          buildFailure: failure,
          buildStack: failureStack,
        ),
      ],
    ).createElement();

    final caught = _catchSync(() => element.mount(null, owner));

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(element.children, hasLength(1));
    expect(firstKey.currentState?.mounted, isTrue);
    expect(failingKey.currentContext, isNull);

    element.unmount();

    expect(states.map((state) => state.disposeCount), everyElement(1));
    expect(states.every((state) => !state.mounted), isTrue);
    expect(firstKey.currentContext, isNull);
    owner.dispose();
  });

  test('multi-child update publishes each fresh success before a later '
      'failure', () {
    final firstKey = GlobalKey<_ProbeState>();
    final failingKey = GlobalKey<_ProbeState>();
    final states = <_ProbeState>[];
    final log = <String>[];
    final failure = StateError('second update build failed');
    final failureStack = StackTrace.fromString('second-update-build-stack');
    final owner = BuildOwner();
    final element = const Row().createElement()..mount(null, owner);
    final retainedChildren = element.children;

    final caught = _catchSync(
      () => element.update(
        Row(
          children: [
            _Probe(key: firstKey, label: 'first', states: states, log: log),
            _Probe(
              key: failingKey,
              label: 'failing',
              states: states,
              log: log,
              buildFailure: failure,
              buildStack: failureStack,
            ),
          ],
        ),
      ),
    );

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(states, hasLength(2));
    expect(failingKey.currentContext, isNull);
    final firstElement = firstKey.currentContext!.element;
    expect(firstKey.currentState?.mounted, isTrue);
    expect(element.children, same(retainedChildren));
    expect(element.children, [same(firstElement)]);
    expect(retainedChildren, [same(firstElement)]);

    element.unmount();

    expect(states.map((state) => state.disposeCount), everyElement(1));
    expect(states.every((state) => !state.mounted), isTrue);
    expect(firstKey.currentContext, isNull);
    final lifecycleCounts = [
      for (final state in states) (state.deactivateCount, state.disposeCount),
    ];
    owner.dispose();
    expect([
      for (final state in states) (state.deactivateCount, state.disposeCount),
    ], lifecycleCounts);
  });

  test('throwing descendant deactivation cannot truncate its subtree', () {
    final states = <_ProbeState>[];
    final log = <String>[];
    final failure = StateError('first deactivate failed');
    final failureStack = StackTrace.fromString('first-deactivate-stack');
    final owner = BuildOwner();
    final element = Align(
      child: Row(
        children: [
          _Probe(
            label: 'first',
            states: states,
            log: log,
            deactivateFailure: failure,
            deactivateStack: failureStack,
          ),
          _Probe(label: 'later', states: states, log: log),
        ],
      ),
    ).createElement()..mount(null, owner);
    final subtreeRoot = element.children.single;
    final [first, later] = states;

    final caught = _catchSync(() => element.update(const Align()));

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(
      (
        ownerChildren: element.children.length,
        rootActive: subtreeRoot.active,
        firstActive: first.context.element.active,
        laterActive: later.context.element.active,
      ),
      (
        ownerChildren: 0,
        rootActive: false,
        firstActive: false,
        laterActive: false,
      ),
    );
    expect((first.deactivateCount, later.deactivateCount), (1, 1));

    owner.finalizeTree();

    expect(
      states.map((state) => (state.disposeCount, state.mounted)),
      everyElement((1, false)),
    );
    owner.finalizeTree();
    expect(states.map((state) => state.disposeCount), everyElement(1));
    element.unmount();
    owner.dispose();
  });

  test('throwing sibling disposal cannot truncate later sibling or parent '
      'cleanup', () {
    final parentKey = GlobalKey<_TreeState>();
    final firstKey = GlobalKey<_ProbeState>();
    final laterKey = GlobalKey<_ProbeState>();
    final parentStates = <_TreeState>[];
    final childStates = <_ProbeState>[];
    final log = <String>[];
    final failure = StateError('first child dispose failed');
    final failureStack = StackTrace.fromString('first-dispose-stack');
    final owner = BuildOwner();
    final element = _Tree(
      key: parentKey,
      states: parentStates,
      children: [
        _Probe(
          key: firstKey,
          label: 'first',
          states: childStates,
          log: log,
          disposeFailure: failure,
          disposeStack: failureStack,
        ),
        _Probe(key: laterKey, label: 'later', states: childStates, log: log),
      ],
    ).createElement()..mount(null, owner);
    final renderObjects = <RenderObject>[];
    _collectRenderObjects(element, renderObjects);

    final caught = _catchSync(element.unmount);

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(parentStates.single.disposeCount, 1);
    expect(parentStates.single.mounted, isFalse);
    expect(childStates.map((state) => state.disposeCount), everyElement(1));
    expect(childStates.every((state) => !state.mounted), isTrue);
    expect(
      childStates.map((state) => state.activeDuringDeactivate),
      everyElement(isTrue),
      reason:
          'State.deactivate must observe the active element before terminal '
          'publication.',
    );
    expect(parentKey.currentContext, isNull);
    expect(firstKey.currentContext, isNull);
    expect(laterKey.currentContext, isNull);
    expect(
      renderObjects.map((render) => render.pipelineOwner),
      everyElement(isNull),
    );
    expect(element.mounted, isFalse);

    final hookCounts = <int>[
      parentStates.single.deactivateCount,
      parentStates.single.disposeCount,
      ...childStates.expand(
        (state) => <int>[state.deactivateCount, state.disposeCount],
      ),
    ];
    element.unmount();
    expect(<int>[
      parentStates.single.deactivateCount,
      parentStates.single.disposeCount,
      ...childStates.expand(
        (state) => <int>[state.deactivateCount, state.disposeCount],
      ),
    ], hookCounts);
    owner.dispose();
  });

  test(
    'finalizeTree attempts every inactive root once and drains failures',
    () {
      final owner = BuildOwner();
      final failures = List<StateError>.generate(
        3,
        (index) => StateError('inactive root $index failed'),
      );
      final failureStacks = List<StackTrace>.generate(
        3,
        (index) => StackTrace.fromString('inactive-root-$index-stack'),
      );
      final elements = <_FinalizeElement>[
        for (var index = 0; index < failures.length; index++)
          _FinalizeWidget(
                failure: failures[index],
                stackTrace: failureStacks[index],
              ).createElement()
              as _FinalizeElement,
      ];
      for (final element in elements) {
        element.mount(null, owner);
        owner.deactivateChild(element);
      }

      final caught = _catchSync(owner.finalizeTree);

      final observedIndex = failures.indexWhere(
        (failure) => identical(failure, caught.error),
      );
      expect(observedIndex, isNonNegative);
      expect(
        caught.stackTrace.toString(),
        failureStacks[observedIndex].toString(),
      );
      expect(elements.map((element) => element.unmountCount), everyElement(1));
      owner.finalizeTree();
      expect(elements.map((element) => element.unmountCount), everyElement(1));
      owner.dispose();
    },
  );

  test('root teardown still detaches after child-edge scheduling fails', () {
    final owner = BuildOwner();
    final root = RenderProxyBox(RenderProxyBox());
    owner.attachRootRenderObject(root);
    owner.pipelineOwner.flushLayout(
      root,
      const BoxConstraints.tight(width: 2, height: 1),
    );
    owner.pipelineOwner.flushPaint(root, (_) {});
    final failure = StateError('frame callback failed');
    final failureStack = StackTrace.fromString('frame-callback-stack');
    owner.setFrameCallback(
      () => Error.throwWithStackTrace(failure, failureStack),
    );

    final caught = _catchSync(owner.dispose);

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(root.child, isNull);
    expect(root.pipelineOwner, isNull);
    owner.dispose();
  });

  test('owner teardown releases its ticker scheduler frame callback', () {
    final owner = BuildOwner();
    var frameRequests = 0;
    owner.setFrameCallback(() {
      frameRequests++;
    });

    owner.dispose();
    final ticker = owner.tickerScheduler.createTicker((_) {});
    ticker.start();

    expect(frameRequests, 0);
    ticker.dispose();
  });

  test('BuildOwner.dispose completes owned cleanup and is terminal after a '
      'finalization failure', () {
    final inputManager = InputManager();
    final owner = BuildOwner(inputManager: inputManager);
    final pointerRoot = _PointerRoot();
    owner.attachRootRenderObject(pointerRoot);
    final key = GlobalKey<_ProbeState>();
    final failure = StateError('raw unmount failed');
    final failureStack = StackTrace.fromString('raw-unmount-stack');
    final rawElement =
        _FinalizeWidget(
                key: key,
                failure: failure,
                stackTrace: failureStack,
                callSuper: false,
              ).createElement()
              as _FinalizeElement
          ..mount(null, owner);
    var focusEvents = 0;
    final focusNode = FocusNode(
      onKeyEvent: (node, event) {
        focusEvents++;
        return KeyEventResult.handled;
      },
    );
    focusNode.attach(rawElement.buildContext);
    focusNode.requestFocus();

    inputManager.dispatchKey(_keyEvent());
    inputManager.dispatchMouse(_mouseEvent());
    expect(focusEvents, 1);
    expect(pointerRoot.events, 1);
    expect(key.currentContext, isNotNull);
    owner.deactivateChild(rawElement);

    final caught = _catchSync(owner.dispose);

    expect(caught.error, same(failure));
    expect(caught.stackTrace.toString(), failureStack.toString());
    expect(rawElement.unmountCount, 1);
    expect(key.currentContext, isNull);
    expect(pointerRoot.pipelineOwner, isNull);
    expect(owner.pipelineOwner.debugNeedsLayout, isFalse);
    expect(owner.pipelineOwner.debugNeedsPaint, isFalse);

    inputManager.dispatchKey(_keyEvent());
    inputManager.dispatchMouse(_mouseEvent());
    expect(focusEvents, 1);
    expect(pointerRoot.events, 1);

    owner.dispose();
    expect(rawElement.unmountCount, 1);
    focusNode.dispose();
  });
}

final class _Caught {
  const _Caught(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

_Caught _catchSync(void Function() action) {
  try {
    action();
  } on Object catch (error, stackTrace) {
    return _Caught(error, stackTrace);
  }
  throw StateError('Expected action to throw');
}

void _collectRenderObjects(Element element, List<RenderObject> result) {
  if (element case final RenderObjectElement renderElement) {
    final renderObject = renderElement.renderObject;
    if (renderObject != null) {
      result.add(renderObject);
    }
  }
  element.visitChildren((child) => _collectRenderObjects(child, result));
}

KeyEvent _keyEvent() => KeyEvent(
  logicalKey: LogicalKeyboardKey.keyA,
  keyCode: 'a'.codeUnitAt(0),
  character: 'a',
);

MouseEvent _mouseEvent() =>
    MouseEvent(type: MouseEventType.down, button: MouseButton.left, x: 0, y: 0);

final class _Probe extends StatefulWidget {
  const _Probe({
    required this.label,
    required this.states,
    required this.log,
    this.buildFailure,
    this.buildStack,
    this.deactivateFailure,
    this.deactivateStack,
    this.disposeFailure,
    this.disposeStack,
    super.key,
  });

  final String label;
  final List<_ProbeState> states;
  final List<String> log;
  final Object? buildFailure;
  final StackTrace? buildStack;
  final Object? deactivateFailure;
  final StackTrace? deactivateStack;
  final Object? disposeFailure;
  final StackTrace? disposeStack;

  @override
  State<_Probe> createState() => _ProbeState(states);
}

final class _ProbeState extends State<_Probe> {
  _ProbeState(List<_ProbeState> states) {
    states.add(this);
  }

  int deactivateCount = 0;
  int disposeCount = 0;
  bool? activeDuringDeactivate;

  @override
  void deactivate() {
    deactivateCount++;
    activeDuringDeactivate = context.element.active;
    widget.log.add('deactivate:${widget.label}');
    final failure = widget.deactivateFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, widget.deactivateStack!);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    disposeCount++;
    widget.log.add('dispose:${widget.label}');
    final failure = widget.disposeFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, widget.disposeStack!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.buildFailure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, widget.buildStack!);
    }
    return const SizedBox(width: 1, height: 1);
  }
}

final class _Tree extends StatefulWidget {
  const _Tree({required this.states, required this.children, super.key});

  final List<_TreeState> states;
  final List<Widget> children;

  @override
  State<_Tree> createState() => _TreeState(states);
}

final class _TreeState extends State<_Tree> {
  _TreeState(List<_TreeState> states) {
    states.add(this);
  }

  int deactivateCount = 0;
  int disposeCount = 0;

  @override
  void deactivate() {
    deactivateCount++;
    super.deactivate();
  }

  @override
  void dispose() {
    disposeCount++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(children: widget.children);
}

final class _FinalizeWidget extends Widget {
  const _FinalizeWidget({
    this.failure,
    this.stackTrace,
    this.callSuper = true,
    super.key,
  });

  final Object? failure;
  final StackTrace? stackTrace;
  final bool callSuper;

  @override
  Element createElement() => _FinalizeElement(this);
}

final class _FinalizeElement extends Element {
  _FinalizeElement(_FinalizeWidget super.widget);

  @override
  _FinalizeWidget get widget => super.widget as _FinalizeWidget;

  int unmountCount = 0;

  @override
  void performRebuild() {}

  @override
  void unmount() {
    unmountCount++;
    if (widget.callSuper) {
      super.unmount();
    }
    final failure = widget.failure;
    if (failure != null) {
      Error.throwWithStackTrace(failure, widget.stackTrace!);
    }
  }
}

final class _PointerRoot extends RenderProxyBox implements HitTestTarget {
  int events = 0;

  @override
  bool hitTest(HitTestResult result, Offset position) {
    result.add(HitTestEntry(this, position));
    return true;
  }

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {
    events++;
  }
}
