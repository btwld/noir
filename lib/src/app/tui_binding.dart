// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';

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
)..runApp(app);

/// Owns the app lifecycle graph for an OpenTUI widget tree.
final class TuiBinding {
  /// Builds the lifecycle graph; an injected [renderer] remains borrowed,
  /// including when this advanced binding is headless.
  TuiBinding({
    int width = 80,
    int height = 24,
    bool headless = false,
    InputManager? inputManager,
    Renderer? renderer,
  }) : this._(
         width: width,
         height: height,
         headless: headless,
         inputManager: inputManager,
         renderer: renderer,
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
  }) {
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
        scheduleFrame: scheduler.scheduleFrame,
        onExitSignal: dispose,
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
  Element? _root;
  int _frameCount = 0;
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
  void enableMouse({bool enableMovement = false}) {
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

    final renderer = _session.renderer;
    _owner.handleBeginFrame(timestamp);
    _owner.buildScope();

    if (renderer == null) {
      _renderView.updateTerminalSize(_session.width, _session.height);
      _owner.pipelineOwner.flushLayout(
        _renderView,
        _renderView.terminalConstraints,
      );
      return;
    }

    final buf = renderer.nextBuffer;

    _renderView.updateTerminalSize(buf.width, buf.height);
    _owner.pipelineOwner.flushLayout(
      _renderView,
      _renderView.terminalConstraints,
    );

    final painted = _owner.pipelineOwner.flushPaint(_renderView, (root) {
      buf.clear(Color.black);
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

    if (painted) {
      renderer.render(force: true);
      _frameCount++;

      if (io.Platform.environment['TERMINAL_TUI_DEBUG_LOG'] == '1') {
        io.stderr.writeln('tuibinding: frame rendered');
      }
    }
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
