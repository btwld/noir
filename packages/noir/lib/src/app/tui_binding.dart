// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';

import 'package:meta/meta.dart';

import '../core/buffer.dart';
import '../core/color.dart';
import '../core/input.dart';
import '../core/renderer.dart';
import '../foundation/first_error.dart';
import '../framework/diagnostics.dart';
import '../framework/element.dart';
import '../framework/owner.dart';
import '../framework/widget.dart';
import '../painting/tui_canvas.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';
import '../rendering/render_view.dart';
import '../scheduler/scheduler_binding.dart';
import 'terminal_session.dart';

/// Builds a [TuiBinding] with injectable terminal seams, without mounting.
///
/// Separate from [runTuiAppForTesting] because a harness that wraps the root
/// widget — the app-scope wrapper `runTuiApp` installs, for instance — needs
/// the binding before it can build the widget it mounts.
@visibleForTesting
TuiBinding createTuiBindingForTesting({
  int width = 80,
  int height = 24,
  bool headless = false,
  InputManager? inputManager,
  Renderer? renderer,
  TerminalPlatform? terminalPlatform,
  RendererFactory? rendererFactory,
  TerminalInputDriverFactory? inputDriverFactory,
  void Function(int exitCode)? exitProcess,
  void Function(int exitCode)? onExitRequested,
}) => TuiBinding._(
  width: width,
  height: height,
  headless: headless,
  inputManager: inputManager,
  renderer: renderer,
  terminalPlatform: terminalPlatform,
  rendererFactory: rendererFactory,
  inputDriverFactory: inputDriverFactory,
  exitProcess: exitProcess,
  onExitRequested: onExitRequested,
);

/// Runs [app] through a [TuiBinding] with injectable terminal seams for tests.
@visibleForTesting
TuiBinding runTuiAppForTesting(
  Widget app, {
  int width = 80,
  int height = 24,
  bool headless = false,
  InputManager? inputManager,
  Renderer? renderer,
  TerminalPlatform? terminalPlatform,
  RendererFactory? rendererFactory,
  TerminalInputDriverFactory? inputDriverFactory,
  void Function(int exitCode)? exitProcess,
  void Function(int exitCode)? onExitRequested,
}) => createTuiBindingForTesting(
  width: width,
  height: height,
  headless: headless,
  inputManager: inputManager,
  renderer: renderer,
  terminalPlatform: terminalPlatform,
  rendererFactory: rendererFactory,
  inputDriverFactory: inputDriverFactory,
  exitProcess: exitProcess,
  onExitRequested: onExitRequested,
)..runApp(app);

/// Builds the headless, one-row binding an inline host paints through.
///
/// The host takes part in every frame at its two ends, where nothing of the
/// frame is in flight, so either callback may resize or dispose the binding
/// and its renderer:
///
/// - [beginFrame] runs first, before the tickers and before the tree is
///   built. A size the host sets here is the size this frame is laid out at.
/// - [endFrame] runs last, in place of a native render, in every frame that
///   completed. It receives the frame when one was painted and null
///   otherwise, and must stop using the frame once it has resized or disposed
///   anything.
///
/// The borrowed [renderer] therefore only lends its cell buffer: it never
/// serializes a frame, so it writes nothing anywhere, and its non-terminal
/// sink, which keeps every byte until the renderer is destroyed, stays empty
/// however long the host runs.
///
/// Frames are cleared to transparent rather than black, which lets the host
/// tell a cell no widget painted behind from one a widget painted black.
@internal
TuiBinding createInlineTuiBinding({
  required int width,
  required Renderer renderer,
  required void Function() beginFrame,
  required void Function(Buffer? painted) endFrame,
}) => TuiBinding._(
  width: width,
  height: 1,
  headless: true,
  renderer: renderer,
  beginFrame: beginFrame,
  endFrame: endFrame,
  clearColor: Color.transparent,
);

/// Owns the app lifecycle graph for an OpenTUI widget tree.
final class TuiBinding {
  /// Builds the lifecycle graph; an injected [renderer] remains borrowed,
  /// including when this advanced binding is headless.
  ///
  /// With [onExitRequested], the first termination signal or unhandled Ctrl+C
  /// reports its exit code instead of disposing or exiting. The caller must
  /// finish its asynchronous cleanup, call [dispose], and set its exit code.
  /// The callback is invoked synchronously; Noir does not await asynchronous work
  /// it starts. If it throws synchronously, Noir attempts best-effort cleanup and
  /// propagates the original error. A headless binding acquires no input or signal
  /// handlers.
  TuiBinding({
    int width = 80,
    int height = 24,
    bool headless = false,
    InputManager? inputManager,
    Renderer? renderer,
    void Function(int exitCode)? onExitRequested,
  }) : this._(
         width: width,
         height: height,
         headless: headless,
         inputManager: inputManager,
         renderer: renderer,
         onExitRequested: onExitRequested,
       );

  TuiBinding._({
    int width = 80,
    int height = 24,
    bool headless = false,
    InputManager? inputManager,
    Renderer? renderer,
    TerminalPlatform? terminalPlatform,
    RendererFactory? rendererFactory,
    TerminalInputDriverFactory? inputDriverFactory,
    void Function(int exitCode)? exitProcess,
    void Function(int exitCode)? onExitRequested,
    void Function()? beginFrame,
    void Function(Buffer? painted)? endFrame,
    Color clearColor = Color.black,
  }) : _beginFrame = beginFrame,
       _endFrame = endFrame,
       _clearColor = clearColor {
    SchedulerBinding? scheduler;
    BuildOwner? owner;
    InputDispatcher? inputDispatcher;
    RenderView? renderView;
    TerminalSession? session;

    try {
      scheduler = SchedulerBinding();
      _scheduler = scheduler;
      _inputManager = inputManager ?? InputManager();
      inputDispatcher = _inputManager.dispatcher;
      _inputDispatcher = inputDispatcher;
      owner = BuildOwner(inputManager: _inputManager);
      _owner = owner;
      renderView = RenderView(width: width, height: height);
      _renderView = renderView;
      owner.attachRootRenderObject(renderView);
      _scheduler.setFrameCallback(_drawFrame);
      _owner.setFrameCallback(_scheduler.scheduleFrame);
      _inputDispatcher.setEventDispatch(_scheduler.scheduleFrame);

      session = TerminalSession(
        width: width,
        height: height,
        headless: headless,
        inputDispatcher: inputDispatcher,
        renderer: renderer,
        // Session changes can affect paint metrics without changing widgets.
        // Render invalidation also schedules the frame through PipelineOwner.
        scheduleFrame: renderView.markNeedsPaint,
        onExitSignal: dispose,
        onExitRequested: onExitRequested,
        platform: terminalPlatform,
        rendererFactory: rendererFactory,
        inputDriverFactory: inputDriverFactory,
        exitProcess: exitProcess,
      );
      _session = session;

      final sessionRenderer = session.renderer;
      if (sessionRenderer != null) {
        owner.setRenderer(sessionRenderer);
      }
    } on Object catch (error, stackTrace) {
      void rollback(void Function() action) {
        try {
          action();
        } on Object {
          // The construction failure remains primary after rollback.
        }
      }

      if (scheduler != null) {
        rollback(scheduler.dispose);
      }
      if (owner != null && renderView != null) {
        rollback(() => owner!.clearRootRenderObject(renderView!));
      }
      if (inputDispatcher != null) {
        rollback(() => inputDispatcher!.setEventDispatch(null));
      }
      if (owner != null) {
        rollback(owner.clearRenderer);
        rollback(owner.dispose);
      }
      if (session != null) {
        rollback(session.close);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  late final SchedulerBinding _scheduler;
  late final TerminalSession _session;
  late final BuildOwner _owner;
  late final InputManager _inputManager;
  late final InputDispatcher _inputDispatcher;
  late final RenderView _renderView;
  final void Function()? _beginFrame;
  final void Function(Buffer? painted)? _endFrame;
  final Color _clearColor;
  Element? _root;
  int _frameCount = 0;
  bool _walkingTree = false;
  bool _disposing = false;
  bool _disposed = false;

  /// The input manager used by this binding.
  InputManager get inputManager => _inputManager;

  /// The renderer used by this binding, if one exists.
  Renderer? get renderer => _session.renderer;

  /// Whether this binding runs without an owned terminal renderer.
  bool get isHeadless => _session.isHeadless;

  /// The [BuildOwner] driving widget build/layout/paint for this binding.
  BuildOwner get buildOwner => _owner;

  /// Whether a frame is building, laying out, or painting the tree right now.
  ///
  /// The tree cannot be resized or torn down under that walk, so a host
  /// refuses the calls that would do either while this is true. It is false
  /// in the rest of a frame: while tickers run, and at its two ends.
  /// [BuildOwner.isBuilding] is not the same question. It does not cover the
  /// layout or the paint of a render object, and it does cover the first
  /// mount, which is not part of any frame.
  @internal
  bool get isWalkingTree => _walkingTree;

  /// Mount [app] as this binding's root widget and schedule the first frame.
  void runApp(Widget app) {
    if (_disposed || _disposing) {
      throw StateError('Cannot mount a widget after TuiBinding.dispose().');
    }
    if (_root != null) {
      throw StateError('TuiBinding already has a mounted root widget.');
    }

    try {
      final root = app.createElement();
      _root = root;
      root.mount(null, _owner);
      _owner.finalizeTree();
      WidgetInspectorService.instance.registerRoot(root);
      _scheduler.scheduleFrame();
    } on Object catch (error, stackTrace) {
      try {
        dispose();
      } on Object {
        // The mount failure remains primary after rollback is attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Enable mouse reporting through the terminal renderer.
  void enableMouse({bool enableMovement = true}) {
    _session.enableMouse(enableMovement: enableMovement);
  }

  /// Disable mouse reporting through the terminal renderer.
  void disableMouse() {
    _session.disableMouse();
  }

  /// Enable Kitty keyboard reporting through the terminal renderer.
  void enableKittyKeyboard({int flags = KittyFlags.disambiguateEscapeCodes}) {
    _session.enableKittyKeyboard(flags: flags);
  }

  /// Disable Kitty keyboard reporting through the terminal renderer.
  void disableKittyKeyboard() {
    _session.disableKittyKeyboard();
  }

  void _drawFrame(Duration timestamp) {
    final root = _root;
    if (root == null) return;

    // Nothing of this frame is in flight yet, so the host may resize this
    // binding here, or dispose it.
    _beginFrame?.call();
    if (_disposed) return;

    final renderer = _session.renderer;
    _owner.handleBeginFrame(timestamp);
    // A ticker or animation callback may have disposed this binding. There
    // is then nothing left to build or paint, and a renderer the caller owns
    // may already be gone.
    if (_disposed) return;

    final Buffer? painted;
    final wasWalkingTree = _walkingTree;
    _walkingTree = true;
    try {
      painted = _buildLayoutPaint(renderer);
    } finally {
      // Restored rather than cleared: a test may flush a frame from inside
      // another one's walk, and that walk is still on the stack afterwards.
      _walkingTree = wasWalkingTree;
    }

    // Presenting is the last step of a frame: nothing reads the frame or the
    // renderer after it, so the host may resize or dispose both from here.
    final endFrame = _endFrame;
    if (endFrame != null) {
      endFrame(painted);
    } else if (painted != null) {
      renderer?.render(force: true);
    }
    if (painted != null) {
      _frameCount++;
    }
  }

  /// Builds, lays out, and paints the tree for one frame.
  ///
  /// Returns the frame when anything was painted into it.
  Buffer? _buildLayoutPaint(Renderer? renderer) {
    _owner.buildScope();

    if (renderer == null) {
      _renderView.updateTerminalSize(_session.width, _session.height);
      _owner.pipelineOwner.flushLayout(
        _renderView,
        _renderView.terminalConstraints,
      );
      _session.updateMouseCursor(_owner.mouseCursor);
      return null;
    }

    final buf = renderer.nextBuffer;

    _renderView.updateTerminalSize(buf.width, buf.height);
    _owner.pipelineOwner.flushLayout(
      _renderView,
      _renderView.terminalConstraints,
    );

    _session.updateMouseCursor(_owner.mouseCursor);

    final painted = _owner.pipelineOwner.flushPaint(_renderView, (root) {
      buf.clear(_clearColor);
      final canvas = createTuiCanvas();
      final resolution = _session.pixelResolution;
      root.paint(
        PaintingContext(
          canvas,
          cellMetrics: TerminalCellMetrics(
            columns: buf.width,
            rows: buf.height,
            pixelWidth: resolution?.width,
            pixelHeight: resolution?.height,
          ),
        ),
        Offset.zero,
      );
      commitTuiCanvas(buf, canvas);
    });

    return painted ? buf : null;
  }

  /// Flush one frame synchronously in integration tests.
  @visibleForTesting
  void debugFlushFrame([Duration timestamp = Duration.zero]) {
    _scheduler.debugFlushFrame(timestamp);
  }

  /// Whether the scheduler has a pending frame in integration tests.
  @visibleForTesting
  bool get debugHasScheduledFrame => _scheduler.hasScheduledFrame;

  /// Frames this binding has painted and rendered since construction.
  ///
  /// Deliberate: a headless renderer paints without any observable side
  /// effect, so drive mode and integration tests need a repaint signal that
  /// does not depend on diffing two captured frames.
  @visibleForTesting
  int get debugFrameCount => _frameCount;

  /// Dispose this binding and every owned lifecycle object.
  void dispose() {
    if (_disposed || _disposing) {
      return;
    }
    _disposing = true;
    final failures = FirstErrorRecorder();
    final root = _root;
    try {
      failures.attempt(_scheduler.dispose);
      if (root != null) {
        failures.attempt(
          () => WidgetInspectorService.instance.unregisterRoot(root),
        );
        failures.attempt(root.unmount);
      }
      failures.attempt(() => _owner.clearRootRenderObject(_renderView));
      failures.attempt(() => _inputDispatcher.setEventDispatch(null));
      failures.attempt(_owner.clearRenderer);
      failures.attempt(_owner.dispose);
      failures.attempt(_session.close);
    } finally {
      _root = null;
      _disposed = true;
      _disposing = false;
    }

    failures.rethrowFirst();
  }

  /// Resize the renderer and schedule a frame if dimensions changed.
  void handleResize(int width, int height) {
    if (_disposed || _disposing) {
      return;
    }
    if (_session.resize(width, height)) {
      // The renderer dropped its frame along with the old size. A second
      // resize can restore the size the tree was last laid out at before any
      // frame runs, and then nothing in the tree is dirty, so ask for the
      // paint here rather than leaving it to layout.
      _renderView.markNeedsPaint();
      _scheduler.scheduleFrame();
    }
  }

  /// Rebuild the mounted tree and force a full layout and paint pass.
  ///
  /// Call this once a hot-reload `reloadSources` request has succeeded. Only
  /// the existing element and render graphs are re-run: the renderer, terminal
  /// session, input drivers, and every native handle stay exactly as they are.
  ///
  /// A failing `State.reassemble()` never costs the reload its rebuild or its
  /// repaint: it is reported to the zone this call began in, the same way a
  /// failing ticker tick or change-notifier listener is. Rethrowing here would
  /// abort the repaint and would be indistinguishable, at the hot-reload
  /// service extension, from the disposal race that reports "not reassembled".
  void reassemble() {
    if (_disposed || _disposing) {
      return;
    }
    final reportingZone = Zone.current;
    try {
      _owner.reassemble();
    } on Object catch (error, stackTrace) {
      reportingZone.handleUncaughtError(error, stackTrace);
    }
    // Not redundant with the rebuild above. A reloaded `performLayout` or
    // `paint` body changes no widget configuration, so every value-equality
    // render setter declines to mark anything dirty and the frame would paint
    // nothing new. One mark on the render root is enough: `flushLayout` and
    // `flushPaint` re-walk the whole tree from there.
    _renderView.markNeedsLayout();
  }
}
