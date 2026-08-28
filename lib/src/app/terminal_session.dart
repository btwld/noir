import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';

import '../core/input.dart';
import '../core/renderer.dart';
import '../core/stdin_input_driver.dart';
import '../foundation/first_error.dart';

/// Terminal signal kinds watched by [TerminalSession].
@visibleForTesting
enum TerminalSignal {
  /// SIGINT.
  interrupt,

  /// SIGTERM.
  terminate,

  /// SIGHUP.
  hangup,

  /// SIGWINCH.
  resize,
}

/// Measured terminal viewport size in physical pixels.
@immutable
final class TerminalPixelResolution {
  /// Creates a positive physical-pixel measurement.
  const TerminalPixelResolution(this.width, this.height);

  /// Pixel width of the terminal viewport.
  final int width;

  /// Pixel height of the terminal viewport.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is TerminalPixelResolution &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// Minimal input driver interface used by [TerminalSession].
@visibleForTesting
abstract interface class TerminalInputDriver {
  /// Starts the driver and reports whether terminal stdin was acquired.
  bool start();

  /// Stops the driver.
  void stop();
}

/// Platform adapter used by [TerminalSession].
@visibleForTesting
abstract interface class TerminalPlatform {
  /// Whether stdout is attached to a terminal.
  bool get stdoutHasTerminal;

  /// Whether the current platform is Windows.
  bool get isWindows;

  /// Current terminal columns.
  int get terminalColumns;

  /// Current terminal lines.
  int get terminalLines;

  /// Writes raw data to stdout.
  void stdoutWrite(String data);

  /// Flushes stdout.
  void stdoutFlush();

  /// Watches a terminal signal.
  Stream<void> watchSignal(TerminalSignal signal);
}

/// Owns terminal-facing resources for a `TuiBinding` instance.
class TerminalSession {
  /// Acquires terminal resources unless headless; a supplied [renderer] is
  /// borrowed in either mode and is never disposed by this session.
  TerminalSession({
    required int width,
    required int height,
    required bool headless,
    required InputDispatcher inputDispatcher,
    required void Function() scheduleFrame,
    Renderer? renderer,
    void Function()? onExitSignal,
    @visibleForTesting TerminalPlatform? platform,
    @visibleForTesting RendererFactory? rendererFactory,
    @visibleForTesting TerminalInputDriverFactory? inputDriverFactory,
    @visibleForTesting void Function(int exitCode)? exitProcess,
  }) : _width = width,
       _height = height,
       _isHeadless = headless,
       _scheduleFrame = scheduleFrame,
       _onExitSignal = onExitSignal,
       _platform = platform ?? _IoTerminalPlatform(),
       _rendererFactory = rendererFactory ?? Renderer.create,
       _inputDriverFactory =
           inputDriverFactory ?? _StdinTerminalInputDriver.new,
       _exitProcess = exitProcess ?? io.exit {
    if (_isHeadless) {
      _renderer = renderer;
      return;
    }

    try {
      final stdoutHasTerminal = _platform.stdoutHasTerminal;
      if (renderer == null && stdoutHasTerminal) {
        _width = _platform.terminalColumns;
        _height = _platform.terminalLines;
      }

      _renderer = renderer ?? _rendererFactory(_width, _height);
      _ownsRenderer = renderer == null;
      _useTerminalSession = stdoutHasTerminal;

      final inputDriver = _inputDriverFactory(inputDispatcher);
      _inputDriver = inputDriver;
      if (_useTerminalSession) {
        final sessionRenderer = _renderer!;
        _capabilitySubscription = inputDispatcher.onCapabilityResponse((event) {
          if (event.kind == TerminalCapabilityKind.pixelResolutionReport) {
            _applyPixelResolutionReport(event.payload);
          }
          event.consume();
          processRendererCapabilityResponse(sessionRenderer, event.raw);
        }, priority: _capabilityRoutingPriority);
      }
      _interruptKeySubscription = inputDispatcher.onKey(
        _handleInterruptKey,
        priority: _interruptKeyRoutingPriority,
      );

      final inputAcquired = inputDriver.start();
      if (_useTerminalSession && !inputAcquired) {
        throw StateError('Interactive terminal setup requires terminal stdin');
      }
      if (_useTerminalSession) {
        _terminalSetupAttempted = true;
        _renderer!.setupTerminal();
        // OpenTUI requests modifyOtherKeys mode 1. Mode 2 also encodes
        // well-known controls such as Ctrl+C, keeping them in the input stream
        // instead of letting POSIX ISIG intercept them under multiplexers.
        _platform.stdoutWrite(_modifyOtherKeysMode2);
        _platform.stdoutFlush();
        _renderer!.queryPixelResolution();
      }
      _installSignalHandlers();
      _installResizeHandler();
    } on Object catch (error, stackTrace) {
      try {
        close();
      } on Object {
        // The acquisition failure remains primary after rollback is attempted.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static const int _capabilityRoutingPriority = InputPriority.app + 1;
  static const String _modifyOtherKeysMode2 = '\x1b[>4;2m';
  static const String _resetKeyboardProtocols = '\x1b[<u\x1b[>4;0m';
  // Terminal shutdown is the final fallback so app, focus, and widget
  // handlers can consume Ctrl+C first when they intentionally override it.
  static const int _interruptKeyRoutingPriority = InputPriority.widget - 1;

  final bool _isHeadless;
  final void Function() _scheduleFrame;
  final void Function()? _onExitSignal;
  final TerminalPlatform _platform;
  final RendererFactory _rendererFactory;
  final TerminalInputDriverFactory _inputDriverFactory;
  final void Function(int exitCode) _exitProcess;
  final List<StreamSubscription<void>> _signalSubscriptions = [];

  Renderer? _renderer;
  bool _ownsRenderer = false;
  TerminalInputDriver? _inputDriver;
  InputSubscription? _capabilitySubscription;
  InputSubscription? _interruptKeySubscription;
  bool _useTerminalSession = false;
  bool _terminalSetupAttempted = false;
  bool _closing = false;
  bool _closed = false;
  bool _handlingExitSignal = false;
  int _width;
  int _height;
  TerminalPixelResolution? _pixelResolution;

  /// The current session width.
  int get width => _width;

  /// The current session height.
  int get height => _height;

  /// Last valid terminal pixel-resolution report, if measured.
  TerminalPixelResolution? get pixelResolution => _pixelResolution;

  /// Whether this session is headless.
  bool get isHeadless => _isHeadless;

  /// The renderer owned or borrowed by this session.
  Renderer? get renderer => _renderer;

  /// Enables mouse reporting through the renderer.
  void enableMouse({bool enableMovement = false}) {
    _requireRenderer(
      'Mouse support requires a renderer',
    ).enableMouse(enableMovement: enableMovement);
  }

  /// Disables mouse reporting through the renderer.
  void disableMouse() {
    _requireRenderer('Mouse support requires a renderer').disableMouse();
  }

  /// Enables Kitty keyboard reporting through the renderer.
  void enableKittyKeyboard({int flags = KittyFlags.disambiguateEscapeCodes}) {
    _requireRenderer(
      'Keyboard support requires a renderer',
    ).enableKittyKeyboard(flags: flags);
  }

  /// Disables Kitty keyboard reporting through the renderer.
  void disableKittyKeyboard() {
    _requireRenderer(
      'Keyboard support requires a renderer',
    ).disableKittyKeyboard();
  }

  /// Returns the live renderer or throws a [StateError] with [message].
  Renderer _requireRenderer(String message) {
    final renderer = _renderer;
    if (renderer == null) {
      throw StateError(message);
    }
    return renderer;
  }

  /// Applies a different positive size to the session and renderer.
  ///
  /// Returns `true` only after the new size is successfully applied. Invalid
  /// or already-applied dimensions return `false`. Renderer failures escape
  /// before either published session dimension changes.
  bool resize(int width, int height) {
    if (_closed || _closing) {
      return false;
    }
    if (width <= 0 || height <= 0) {
      return false;
    }
    if (width == _width && height == _height) {
      return false;
    }
    _renderer?.resize(width, height);
    _width = width;
    _height = height;
    if (_useTerminalSession) _renderer?.queryPixelResolution();
    return true;
  }

  void _applyPixelResolutionReport(String payload) {
    final fields = payload.split(';');
    if (fields.length != 3 || fields.first != '4') return;
    final height = int.tryParse(fields[1]);
    final width = int.tryParse(fields[2]);
    if (width == null || height == null || width <= 0 || height <= 0) return;
    final resolution = TerminalPixelResolution(width, height);
    if (resolution == _pixelResolution) return;
    _pixelResolution = resolution;
    _scheduleFrame();
  }

  /// Closes terminal resources owned by this session.
  void close() {
    if (_closed || _closing) {
      return;
    }
    _closing = true;
    final failures = FirstErrorRecorder();
    final subscriptions = List<StreamSubscription<void>>.from(
      _signalSubscriptions,
    );
    final inputDriver = _inputDriver;
    final capabilitySubscription = _capabilitySubscription;
    final interruptKeySubscription = _interruptKeySubscription;
    final renderer = _renderer;
    final ownsRenderer = _ownsRenderer;

    try {
      for (final subscription in subscriptions) {
        failures.attempt(() {
          final cancellation = subscription.cancel();
          cancellation.ignore();
        });
      }
      failures.attempt(() => inputDriver?.stop());
      if (capabilitySubscription != null) {
        failures.attempt(capabilitySubscription.cancel);
      }
      if (interruptKeySubscription != null) {
        failures.attempt(interruptKeySubscription.cancel);
      }
      failures.attempt(_restoreTerminalSession);
      if (renderer != null && ownsRenderer) {
        failures.attempt(renderer.dispose);
      }
    } finally {
      _signalSubscriptions.clear();
      _inputDriver = null;
      _capabilitySubscription = null;
      _interruptKeySubscription = null;
      _renderer = null;
      _ownsRenderer = false;
      _useTerminalSession = false;
      _terminalSetupAttempted = false;
      _closed = true;
      _closing = false;
    }

    failures.rethrowFirst();
  }

  void _installResizeHandler() {
    if (_platform.isWindows) {
      return;
    }
    try {
      _signalSubscriptions.add(
        _platform.watchSignal(TerminalSignal.resize).listen((_) {
          final columns = _platform.stdoutHasTerminal
              ? _platform.terminalColumns
              : _width;
          final lines = _platform.stdoutHasTerminal
              ? _platform.terminalLines
              : _height;
          if (resize(columns, lines)) {
            _scheduleFrame();
          }
        }),
      );
    } on Object {
      // Some runtimes cannot watch SIGWINCH.
    }
  }

  void _installSignalHandlers() {
    final signals = <TerminalSignal>[
      TerminalSignal.interrupt,
      if (!_platform.isWindows) TerminalSignal.terminate,
      if (!_platform.isWindows) TerminalSignal.hangup,
    ];

    for (final signal in signals) {
      try {
        _signalSubscriptions.add(
          _platform.watchSignal(signal).listen((_) {
            _handleExitSignal(signal);
          }),
        );
      } on Object {
        // Some runtimes cannot watch every process signal.
      }
    }
  }

  void _handleExitSignal(TerminalSignal signal) {
    if (_handlingExitSignal) {
      return;
    }
    _handlingExitSignal = true;
    try {
      final onExitSignal = _onExitSignal;
      if (onExitSignal == null) {
        close();
      } else {
        onExitSignal();
      }
    } finally {
      // Exit codes follow the 128 + signal-number convention.
      _exitProcess(switch (signal) {
        TerminalSignal.interrupt => 130, // SIGINT (2)
        TerminalSignal.hangup => 129, // SIGHUP (1)
        TerminalSignal.terminate => 143, // SIGTERM (15)
        TerminalSignal.resize => 143, // never an exit signal; defensive default
      });
    }
  }

  void _handleInterruptKey(KeyEvent event) {
    if (!event.isPress ||
        event.logicalKey != LogicalKeyboardKey.keyC ||
        !event.isControlPressed) {
      return;
    }
    event.consume();
    _handleExitSignal(TerminalSignal.interrupt);
  }

  void _restoreTerminalSession() {
    if (!_terminalSetupAttempted) {
      return;
    }

    void attempt(void Function() action) {
      try {
        action();
      } on Object {
        // Terminal restoration is best effort by contract.
      }
    }

    for (final sequence in const [
      '\x1b[?1049l\x1b[?25h\x1b[0m',
      '\x1b[?1000l\x1b[?1006l',
      _resetKeyboardProtocols,
    ]) {
      attempt(() => _platform.stdoutWrite(sequence));
    }
    attempt(_platform.stdoutFlush);
  }
}

/// Creates a renderer for a terminal session.
@visibleForTesting
typedef RendererFactory = Renderer Function(int width, int height);

/// Creates an input driver for a terminal session.
@visibleForTesting
typedef TerminalInputDriverFactory =
    TerminalInputDriver Function(InputDispatcher inputDispatcher);

class _StdinTerminalInputDriver implements TerminalInputDriver {
  _StdinTerminalInputDriver(InputDispatcher inputDispatcher)
    : _driver = StdinInputDriver(inputDispatcher);

  final StdinInputDriver _driver;

  @override
  bool start() => _driver.start();

  @override
  void stop() {
    _driver.stop();
  }
}

class _IoTerminalPlatform implements TerminalPlatform {
  @override
  bool get stdoutHasTerminal => io.stdout.hasTerminal;

  @override
  bool get isWindows => io.Platform.isWindows;

  @override
  int get terminalColumns => io.stdout.terminalColumns;

  @override
  int get terminalLines => io.stdout.terminalLines;

  @override
  void stdoutWrite(String data) {
    io.stdout.write(data);
  }

  @override
  void stdoutFlush() {
    io.stdout.flush();
  }

  @override
  Stream<void> watchSignal(TerminalSignal signal) =>
      _processSignal(signal).watch().map((_) {});

  io.ProcessSignal _processSignal(TerminalSignal signal) => switch (signal) {
    TerminalSignal.interrupt => io.ProcessSignal.sigint,
    TerminalSignal.terminate => io.ProcessSignal.sigterm,
    TerminalSignal.hangup => io.ProcessSignal.sighup,
    TerminalSignal.resize => io.ProcessSignal.sigwinch,
  };
}
