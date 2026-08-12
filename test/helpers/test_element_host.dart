import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:noir/src/rendering/render_view.dart';

/// Shared element-mounting plumbing for the [WidgetTester] and
/// [BufferCapture] harnesses.
///
/// The mount / unmount + BuildOwner / root-RenderObject lookup boilerplate
/// is identical across those two harnesses; this class hosts it in one place
/// while each harness keeps its own public API. [KeyDriver] does not use it:
/// that harness mounts through the real [TuiBinding]. Some tests also
/// construct a [TestElementHost] directly for raw mount/layout machinery.
///
/// Lifecycle:
///   1. construct with optional [InputManager] / [Renderer]
///   2. [mount] a widget — owns the [BuildOwner] and root [Element]
///   3. [pumpFrame] runs build + pipeline layout/paint
///   4. [dispose] tears everything down
class TestElementHost {
  TestElementHost({InputManager? inputManager, Renderer? renderer})
    : _externalInputManager = inputManager,
      _externalRenderer = renderer;

  final InputManager? _externalInputManager;
  final Renderer? _externalRenderer;

  BuildOwner? _owner;
  Element? _root;
  RenderView? _renderView;

  BuildOwner get owner {
    final owner = _owner;
    if (owner == null) {
      throw StateError('TestElementHost has no owner; call mount() first');
    }
    return owner;
  }

  Element? get root => _root;

  /// First descendant [RenderObject] under the mounted element, or null if
  /// the tree has none yet.
  RenderObject? get renderObject {
    final root = _root;
    if (root == null) return null;
    return _findFirstRenderObject(root);
  }

  /// Mount a widget. Creates a fresh [BuildOwner] (or reuses one bound to
  /// the supplied [InputManager]) and attaches the renderer if one was
  /// provided at construction time.
  void mount(Widget widget) {
    if (_owner != null) {
      throw StateError(
        'TestElementHost is already hosting a widget; call dispose() first',
      );
    }
    final owner = BuildOwner(inputManager: _externalInputManager);
    final renderer = _externalRenderer;
    if (renderer != null) {
      owner.setRenderer(renderer);
    }
    final renderView = RenderView();
    owner.attachRootRenderObject(renderView);
    final element = widget.createElement()..mount(null, owner);
    _owner = owner;
    _root = element;
    _renderView = renderView;
  }

  /// Run a single frame through the same pipeline boundary as `TuiBinding`.
  void pumpFrame({Buffer? buffer, BoxConstraints? constraints}) {
    final root = _root;
    if (root == null) {
      throw StateError('TestElementHost is not mounted');
    }
    final renderView = _renderView;
    if (renderView == null) {
      throw StateError('TestElementHost has no render view');
    }
    owner.buildScope();

    final layoutConstraints =
        constraints ??
        (buffer != null
            ? BoxConstraints(maxWidth: buffer.width, maxHeight: buffer.height)
            : const BoxConstraints());
    renderView.updateTerminalSize(
      layoutConstraints.maxWidth ?? layoutConstraints.minWidth,
      layoutConstraints.maxHeight ?? layoutConstraints.minHeight,
    );
    owner.pipelineOwner.flushLayout(renderView, layoutConstraints);
    if (buffer != null) {
      owner.pipelineOwner.flushPaint(renderView, (root) {
        final canvas = createTuiCanvas();
        root.paint(PaintingContext(canvas), Offset.zero);
        commitTuiCanvas(buffer, canvas);
      });
    }
  }

  /// Unmount and release references. The supplied renderer / input manager
  /// are NOT disposed here — they are owned by the caller.
  void dispose() {
    final owner = _owner;
    if (owner != null && _externalRenderer != null) {
      owner.clearRenderer();
    }
    _root?.unmount();
    final renderView = _renderView;
    if (owner != null && renderView != null) {
      owner.clearRootRenderObject(renderView);
    }
    owner?.dispose();
    _root = null;
    _renderView = null;
    _owner = null;
  }
}

RenderObject? _findFirstRenderObject(Element element) {
  if (element is RenderObjectElement) {
    return element.renderObject;
  }
  for (final child in element.children) {
    final found = _findFirstRenderObject(child);
    if (found != null) {
      return found;
    }
  }
  return null;
}
