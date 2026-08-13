// ignore_for_file: avoid_positional_boolean_parameters, use_setters_to_change_properties
import 'dart:io';

import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import 'buffer.dart';
import 'color.dart';

/// Creates a renderer around injected bindings for failure-path tests.
@internal
@visibleForTesting
Renderer createRendererForTesting(
  OpenTuiBindings bindings,
  RendererHandle handle,
) => Renderer._(bindings, handle);

/// Manages frame buffers, terminal rendering, and output flushing.
class Renderer {
  Renderer._(this._bindings, this._handle) {
    _finalizer.attach(this, _handle, detach: _finalizerKey);
  }

  /// Opens guarded bindings and allocates a native renderer.
  ///
  /// Set [testing] to true to use OpenTUI's non-terminal testing sink. This is
  /// useful in harnesses that capture render state through direct buffer access
  /// instead of terminal output.
  ///
  /// Throws [ArgumentError] when [width] or [height] is non-positive.
  factory Renderer.create(int width, int height, {bool testing = false}) {
    validateRendererDimensions(width, height);
    final bindings = OpenTuiBindings();
    final handle = bindings.createRenderer(width, height, testing: testing);
    return Renderer._(bindings, handle);
  }

  /// Finalizer for best-effort cleanup if dispose() is not called.
  /// This releases native resources when users forget to dispose the renderer.
  static final Finalizer<RendererHandle> _finalizer = Finalizer<RendererHandle>(
    (handle) {
      final bindings = OpenTuiBindings();
      bindings.destroyRenderer(handle);
    },
  );

  final OpenTuiBindings _bindings;
  final RendererHandle _handle;
  Buffer? _nextBuffer;
  Buffer? _currentBuffer;
  bool _disposed = false;
  bool _autoFlush = true;
  final Object _finalizerKey = Object();

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Renderer is disposed');
  }

  /// Initialize terminal session (enter alt screen, set modes)
  void setupTerminal({bool useAlternateScreen = true}) {
    _checkNotDisposed();
    _bindings.setupTerminal(_handle, useAlternateScreen);
  }

  /// Resize the renderer (and its underlying buffer) to new dimensions.
  /// Invalidates any cached `nextBuffer` reference.
  ///
  /// Throws [ArgumentError] when [width] or [height] is non-positive.
  void resize(int width, int height) {
    _checkNotDisposed();
    validateRendererDimensions(width, height);
    try {
      _bindings.resizeRenderer(_handle, width, height);
    } finally {
      _invalidateBorrowedBuffers();
    }
  }

  /// The buffer for the next frame, created lazily and invalidated after each [render] call.
  Buffer get nextBuffer {
    _checkNotDisposed();
    _nextBuffer ??= createBufferFromNative(
      _bindings.getNextBuffer(_handle),
      _bindings,
      () => _disposed,
    );
    return _nextBuffer!;
  }

  /// Current rendered buffer, exposed for integration tests.
  @visibleForTesting
  @internal
  Buffer get debugCurrentBuffer {
    _checkNotDisposed();
    _currentBuffer ??= createBufferFromNative(
      _bindings.getCurrentBuffer(_handle),
      _bindings,
      () => _disposed,
    );
    return _currentBuffer!;
  }

  /// Renders the current buffer to the terminal.
  ///
  /// Automatically calls stdout.flush() to ensure output is visible immediately
  /// in TTY environments. This prevents buffering issues where ANSI sequences
  /// might not be displayed until program exit.
  ///
  /// Set [autoFlush] to false for high-performance scenarios where you want
  /// to control flushing manually.
  ///
  /// **Note**: After calling render(), the current buffer is invalidated.
  /// Any subsequent operations on the old buffer will throw [StateError].
  /// Get a fresh buffer via [nextBuffer].
  void render({bool force = false, bool? autoFlush}) {
    _checkNotDisposed();
    try {
      _bindings.render(_handle, force);
      final shouldFlush = autoFlush ?? _autoFlush;
      if (shouldFlush) {
        stdout.flush();
      }
    } finally {
      // OpenTUI may have cleared or otherwise mutated the frame before it
      // reports failure. Never let callers reuse a potentially stale native
      // view, including when rendering or flushing throws.
      _invalidateBorrowedBuffers();
    }
  }

  /// Sets the default auto-flush behavior for this renderer.
  ///
  /// When [enabled] is true (default), stdout.flush() is called automatically
  /// after each render() call. This ensures immediate output visibility in TTY
  /// environments but may impact performance in high-frequency rendering.
  ///
  /// Set to false when the caller owns the output-flush schedule.
  void setAutoFlush(bool enabled) {
    _autoFlush = enabled;
  }

  /// Gets the current auto-flush setting.
  bool get autoFlush => _autoFlush;

  /// Sets the terminal background color to [color].
  void setBackgroundColor(Color color) {
    _checkNotDisposed();
    _bindings.setBackgroundColor(_handle, color);
  }

  /// Clears the terminal screen.
  void clearTerminal() {
    _checkNotDisposed();
    _bindings.clearTerminal(_handle);
  }

  /// Registers a low-level native/debug hit-grid region.
  ///
  /// Built-in widgets use render-tree hit testing for pointer routing.
  void addToHitGrid(int x, int y, int width, int height, int id) {
    _checkNotDisposed();
    _bindings.addToHitGrid(_handle, x, y, width, height, id);
  }

  /// Queries the low-level native/debug hit grid.
  ///
  /// Built-in widgets use render-tree hit testing for pointer routing.
  int checkHit(int x, int y) {
    _checkNotDisposed();
    return _bindings.checkHit(_handle, x, y);
  }

  /// Releases all native renderer resources and detaches the finalizer.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Detach from finalizer before manual destruction (prevent double-free)
    _finalizer.detach(_finalizerKey);
    // Invalidate before destroying native handle so any stragglers (clipped
    // views, etc.) fail fast instead of touching freed memory.
    _invalidateBorrowedBuffers();
    _bindings.destroyRenderer(_handle);
  }

  void _invalidateBorrowedBuffers() {
    _nextBuffer?.invalidate();
    _currentBuffer?.invalidate();
    _nextBuffer = null;
    _currentBuffer = null;
  }

  /// Internal: raw native renderer handle. Used by `CursorManagement`,
  /// `MouseSupport`, and `KeyboardSupport` extensions in the same package
  /// and by tests that need to drive the FFI directly. Not for user code.
  @internal
  RendererHandle get handle {
    _checkNotDisposed();
    return _handle;
  }

  /// Internal: shared FFI bindings. Same caveats as [handle].
  @internal
  OpenTuiBindings get bindings {
    _checkNotDisposed();
    return _bindings;
  }
}

/// Routes one raw terminal capability response through its renderer owner.
///
/// Internal app/session code uses this bridge instead of reaching through the
/// renderer to its FFI bindings or native handle.
@internal
void processRendererCapabilityResponse(Renderer renderer, String response) {
  renderer._checkNotDisposed();
  renderer._bindings.processCapabilityResponse(renderer._handle, response);
}
