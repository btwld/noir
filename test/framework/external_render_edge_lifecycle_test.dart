import 'dart:collection';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('direct removal detaches the external edge before publication', () {
    final probe = _mountProbe();
    try {
      final dual = _findDual(probe.host.root!);
      final overlay = dual.overlayRenderObject!;
      expect(identical(overlay.parent, probe.externalHost), isTrue);

      probe.host.update(
        Column(
          children: [
            _ExternalHost(key: probe.hostKey),
            const SizedBox(width: 4, height: 2, child: Text('after')),
          ],
        ),
      );
      probe.host.pumpBuild();

      expect(overlay.parent, isNull);
      expect(overlay.pipelineOwner, isNull);
      expect(
        probe.externalHost.children.any(
          (candidate) => identical(candidate, overlay),
        ),
        isFalse,
      );
      expect(dual.detachParentWasReadable, isTrue);
      expect(dual.disposeCount, 1);
      expect(probe.focusNode.isAttached, isFalse);
      expect(probe.focusNode.hasPrimaryFocus, isFalse);
    } finally {
      probe.host.dispose();
    }
  });

  test('ancestor removal detaches the overlay edge owned below the first '
      'render object', () {
    final probe = _mountProbe();
    try {
      final dual = _findDual(probe.host.root!);
      final overlay = dual.overlayRenderObject!;
      expect(identical(overlay.parent, probe.externalHost), isTrue);

      probe.host.update(
        Column(
          children: [
            _ExternalHost(key: probe.hostKey),
            const Text('gone'),
          ],
        ),
      );
      probe.host.pumpBuild();

      expect(overlay.parent, isNull);
      expect(overlay.pipelineOwner, isNull);
      expect(
        probe.externalHost.children.any(
          (candidate) => identical(candidate, overlay),
        ),
        isFalse,
      );
      expect(dual.detachParentWasReadable, isTrue);
      expect(dual.disposeCount, 1);
      expect(probe.focusNode.isAttached, isFalse);
      expect(probe.focusNode.hasPrimaryFocus, isFalse);
    } finally {
      probe.host.dispose();
    }
  });

  test('incompatible replacement destroys overlay state once', () {
    final probe = _mountProbe();
    try {
      final dual = _findDual(probe.host.root!);
      final overlay = dual.overlayRenderObject!;

      probe.host.update(
        Column(
          children: [
            _ExternalHost(key: probe.hostKey),
            const SizedBox(width: 1, height: 1),
          ],
        ),
      );
      probe.host.pumpBuild();

      expect(overlay.parent, isNull);
      expect(dual.disposeCount, 1);
    } finally {
      probe.host.dispose();
    }
  });

  test('mount rollback drops a published external edge', () {
    final hostKey = GlobalKey();
    final host = TestElementHost()
      ..mount(Column(children: [_ExternalHost(key: hostKey)]));

    Object? error;
    try {
      host.update(
        Column(
          children: [
            _ExternalHost(key: hostKey),
            _DualEdgeProbe(
              hostKey: hostKey,
              throwAfterAttach: true,
              ordinary: const SizedBox(width: 1, height: 1),
              overlay: const SizedBox(width: 1, height: 1),
            ),
          ],
        ),
      );
    } on Object catch (caught) {
      error = caught;
    }

    try {
      expect(error, isA<StateError>());
      expect('$error', contains('mount failed'));
      final renderObject = hostKey.currentContext!.findRenderObject();
      expect(renderObject, isA<_HostBox>());
      expect((renderObject! as _HostBox).children, isEmpty);
    } finally {
      host.dispose();
    }
  });

  test(
    'throwing detach still detaches later edges and keeps the first error',
    () {
      final probe = _mountProbe();
      try {
        final dual = _findDual(probe.host.root!);
        final overlay = dual.overlayRenderObject!;
        final detachError = StateError('detach hook failed');
        dual.detachError = detachError;

        Object? caught;
        try {
          probe.host.update(
            Column(
              children: [
                _ExternalHost(key: probe.hostKey),
                const Text('gone'),
              ],
            ),
          );
        } on Object catch (error) {
          caught = error;
        }
        try {
          probe.host.pumpBuild();
        } on Object catch (error) {
          caught ??= error;
        }

        expect(caught, same(detachError));
        expect(overlay.parent, isNull);
        expect(overlay.pipelineOwner, isNull);
        expect(dual.disposeCount, 1);
      } finally {
        probe.host.dispose();
      }
    },
  );

  test('a failed detach still attempts every later external edge', () {
    final probe = _mountProbe(includeTrailingExternal: true);
    try {
      final dual = _findDual(probe.host.root!);
      final overlay = dual.overlayRenderObject!;
      final trailing = dual.trailingRenderObject!;
      final detachError = StateError('detach failed before removal');
      dual.detachBeforeDropError = detachError;

      Object? caught;
      try {
        probe.host.update(
          Column(
            children: [
              _ExternalHost(key: probe.hostKey),
              const Text('gone'),
            ],
          ),
        );
      } on Object catch (error) {
        caught = error;
      }

      expect(caught, same(detachError));
      expect(overlay.parent, same(probe.externalHost));
      expect(trailing.parent, isNull);
      expect(trailing.pipelineOwner, isNull);
      expect(dual.parent, isNotNull);
    } finally {
      final dual = _findDual(probe.host.root!);
      dual.detachBeforeDropError = null;
      probe.host.dispose();
    }
  });

  test('throwing State.deactivate still disposes overlay state once', () {
    final probe = _mountProbe(throwOnDeactivate: true);
    try {
      final dual = _findDual(probe.host.root!);
      final overlay = dual.overlayRenderObject!;

      Object? caught;
      try {
        probe.host.update(
          Column(
            children: [
              _ExternalHost(key: probe.hostKey),
              const Text('gone'),
            ],
          ),
        );
      } on Object catch (error) {
        caught = error;
      }
      try {
        probe.host.pumpBuild();
      } on Object catch (error) {
        caught ??= error;
      }

      expect(caught, isA<StateError>());
      expect('$caught', contains('deactivate failed'));
      expect(overlay.parent, isNull);
      expect(dual.disposeCount, 1);
    } finally {
      probe.host.dispose();
    }
  });
}

_Probe _mountProbe({
  bool throwOnDeactivate = false,
  bool includeTrailingExternal = false,
}) {
  final hostKey = GlobalKey();
  final focusNode = FocusNode(debugLabel: 'overlay-focus');
  final host = TestElementHost()
    ..mount(
      Column(
        children: [
          _ExternalHost(key: hostKey),
          SizedBox(
            width: 4,
            height: 2,
            child: _DualEdgeProbe(
              hostKey: hostKey,
              includeTrailingExternal: includeTrailingExternal,
              ordinary: const SizedBox(
                width: 2,
                height: 1,
                child: Text('base'),
              ),
              overlay: _LifecycleChild(
                throwOnDeactivate: throwOnDeactivate,
                child: Focus(
                  focusNode: focusNode,
                  autofocus: true,
                  child: const SizedBox(width: 1, height: 1),
                ),
              ),
            ),
          ),
        ],
      ),
    )
    ..pumpFrame(constraints: const BoxConstraints.tight(width: 20, height: 10));
  return _Probe(host: host, hostKey: hostKey, focusNode: focusNode);
}

_DualEdgeProbeElement _findDual(Element root) {
  _DualEdgeProbeElement? found;
  void visit(Element element) {
    if (element is _DualEdgeProbeElement) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  visit(root);
  expect(found, isNotNull);
  return found!;
}

final class _Probe {
  _Probe({required this.host, required this.hostKey, required this.focusNode});

  final TestElementHost host;
  final GlobalKey hostKey;
  final FocusNode focusNode;

  _HostBox get externalHost {
    final renderObject = hostKey.currentContext!.findRenderObject();
    expect(renderObject, isA<_HostBox>());
    return renderObject! as _HostBox;
  }
}

class _ExternalHost extends RenderObjectWidget {
  const _ExternalHost({super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _HostBox();
}

class _HostBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(1, 1);
    for (final child in children) {
      if (child is RenderBox) {
        child.layout(const BoxConstraints());
        child
          ..x = 0
          ..y = 0;
      }
    }
  }
}

class _DualEdgeProbe extends Widget {
  _DualEdgeProbe({
    required this.hostKey,
    required this.ordinary,
    required this.overlay,
    this.includeTrailingExternal = false,
    this.throwAfterAttach = false,
  });

  final GlobalKey hostKey;
  final Widget ordinary;
  final Widget overlay;
  final bool includeTrailingExternal;
  final bool throwAfterAttach;

  @override
  Element createElement() => _DualEdgeProbeElement(this);
}

class _DualEdgeProbeElement extends Element {
  _DualEdgeProbeElement(_DualEdgeProbe super.widget);

  _DualEdgeProbe get typedWidget => widget as _DualEdgeProbe;

  final _children = <Element>[];
  @override
  late final List<Element> children = UnmodifiableListView(_children);

  Element? _ordinary;
  Element? _overlay;
  RenderObject? overlayRenderObject;
  RenderObject? trailingRenderObject;
  bool detachParentWasReadable = false;
  int disposeCount = 0;
  var _inflatingOverlay = false;
  StateError? detachError;
  StateError? detachBeforeDropError;

  @override
  void performRebuild() {
    _updateSlot(
      current: _ordinary,
      next: typedWidget.ordinary,
      overlay: false,
      assign: (element) => _ordinary = element,
    );
    _updateSlot(
      current: _overlay,
      next: typedWidget.overlay,
      overlay: true,
      assign: (element) => _overlay = element,
    );
    if (typedWidget.includeTrailingExternal && trailingRenderObject == null) {
      final trailing = _HostBox();
      _hostBox().adoptChild(trailing);
      trailingRenderObject = trailing;
    }
    if (typedWidget.throwAfterAttach) {
      throw StateError('mount failed');
    }
  }

  void _updateSlot({
    required Element? current,
    required Widget? next,
    required bool overlay,
    required void Function(Element? element) assign,
  }) {
    if (next == null) {
      if (current != null) {
        owner.deactivateChild(current);
        if (current.parent == null && !current.active) {
          _children.removeWhere((candidate) => identical(candidate, current));
          assign(null);
        }
      }
      return;
    }
    if (current == null) {
      _inflatingOverlay = overlay;
      try {
        final child = Element.inflateWidget(next, this);
        _children.add(child);
        assign(child);
      } finally {
        _inflatingOverlay = false;
      }
      return;
    }
    if (Widget.canUpdate(current.widget, next)) {
      current.update(next);
      return;
    }
    owner.deactivateChild(current);
    if (current.parent == null && !current.active) {
      _children.removeWhere((candidate) => identical(candidate, current));
    }
    _inflatingOverlay = overlay;
    try {
      final child = Element.inflateWidget(next, this);
      _children.add(child);
      assign(child);
    } finally {
      _inflatingOverlay = false;
    }
  }

  @override
  void insertRenderObjectChild(RenderObject child, Element childElement) {
    if (_inflatingOverlay || _isOverlayRenderChild(childElement)) {
      final host = _hostBox();
      if (!identical(child.parent, host)) {
        host.adoptChild(child);
      }
      overlayRenderObject = child;
      return;
    }
    super.insertRenderObjectChild(child, childElement);
  }

  @override
  void removeRenderObjectChild(RenderObject child, Element childElement) {
    if (_isOverlayRenderChild(childElement) ||
        identical(child, overlayRenderObject)) {
      _dropExternal(child);
      return;
    }
    super.removeRenderObjectChild(child, childElement);
  }

  @override
  void collectOwnedExternalRenderEdges(List<ExternalRenderEdge> edges) {
    final child = overlayRenderObject;
    if (child == null || child.parent == null) {
      return;
    }
    final host = child.parent!;
    edges.add(
      ExternalRenderEdge(
        child: child,
        expectedParent: host,
        detach: () {
          detachParentWasReadable = parent != null;
          final beforeDropError = detachBeforeDropError;
          if (beforeDropError != null) {
            throw beforeDropError;
          }
          _dropExternal(child);
          final error = detachError;
          if (error != null) {
            throw error;
          }
        },
      ),
    );
    final trailing = trailingRenderObject;
    if (trailing != null && trailing.parent != null) {
      final host = trailing.parent!;
      edges.add(
        ExternalRenderEdge(
          child: trailing,
          expectedParent: host,
          detach: () => _dropTrailing(trailing),
        ),
      );
    }
  }

  @override
  RenderObject? findRenderObject() => _ordinary?.findRenderObject();

  @override
  void unmount() {
    if (!mounted) {
      return;
    }
    final child = overlayRenderObject;
    if (child != null) {
      _dropExternal(child);
    }
    final trailing = trailingRenderObject;
    if (trailing != null) {
      _dropTrailing(trailing);
    }
    super.unmount();
  }

  bool _isOverlayRenderChild(Element childElement) {
    final overlay = _overlay;
    if (overlay == null) {
      return false;
    }
    var current = childElement as Element?;
    while (current != null) {
      if (identical(current, overlay)) {
        return true;
      }
      if (identical(current, this)) {
        return false;
      }
      current = current.parent;
    }
    return false;
  }

  _HostBox _hostBox() {
    final renderObject = typedWidget.hostKey.currentContext?.findRenderObject();
    if (renderObject is! _HostBox) {
      throw StateError('_DualEdgeProbe host is missing.');
    }
    return renderObject;
  }

  void _dropExternal(RenderObject child) {
    final parent = child.parent;
    if (parent != null) {
      parent.dropChild(child);
    }
    if (identical(overlayRenderObject, child)) {
      overlayRenderObject = null;
    }
  }

  void _dropTrailing(RenderObject child) {
    final parent = child.parent;
    if (parent != null) {
      parent.dropChild(child);
    }
    if (identical(trailingRenderObject, child)) {
      trailingRenderObject = null;
    }
  }
}

class _LifecycleChild extends StatefulWidget {
  const _LifecycleChild({required this.child, this.throwOnDeactivate = false});

  final Widget child;
  final bool throwOnDeactivate;

  @override
  State<_LifecycleChild> createState() => _LifecycleChildState();
}

class _LifecycleChildState extends State<_LifecycleChild> {
  @override
  void deactivate() {
    if (widget.throwOnDeactivate) {
      throw StateError('deactivate failed');
    }
    super.deactivate();
  }

  @override
  void initState() {
    super.initState();
    _owner = _findDualOwner();
  }

  @override
  void dispose() {
    _owner?.disposeCount++;
    super.dispose();
  }

  _DualEdgeProbeElement? _owner;

  _DualEdgeProbeElement? _findDualOwner() {
    var current = context.element.parent;
    while (current != null) {
      if (current is _DualEdgeProbeElement) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
