// ignore_for_file: avoid_positional_boolean_parameters, use_setters_to_change_properties
import 'dart:ffi';
import 'dart:io';

import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import 'buffer.dart';
import 'color.dart';

/// Manages frame buffers, terminal rendering, and output flushing.
class Renderer {
  Renderer._(this._bindings, this._ptr) {
    _finalizer.attach(this, _ptr.cast<Void>(), detach: _finalizerKey);
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
    final ptr = bindings.createRenderer(width, height, testing: testing);
    if (ptr == nullptr) {
      throw StateError('OpenTUI returned a null renderer handle.');
    }
    return Renderer._(bindings, ptr);
  }

  /// Finalizer for best-effort cleanup if dispose() is not called.
  /// This releases native resources when users forget to dispose the renderer.
  static final Finalizer<Pointer<Void>> _finalizer = Finalizer<Pointer<Void>>((
    pointer,
  ) {
    if (pointer == nullptr) {
      return;
    }
    final bindings = OpenTuiBindings();
    // Use default dispose settings in finalizer (no alternate screen cleanup)
    bindings.destroyRenderer(pointer.cast<RendererHandle>());
  });

  final OpenTuiBindings _bindings;
  final Pointer<RendererHandle> _ptr;
  Buffer? _nextBuffer;
  bool _disposed = false;
  bool _autoFlush = true;
  final Object _finalizerKey = Object();

  void _checkNotDisposed() {
    if (_disposed) throw StateError('Renderer is disposed');
  }

  /// Initialize terminal session (enter alt screen, set modes)
  void setupTerminal({bool useAlternateScreen = true}) {
    _checkNotDisposed();
    _bindings.setupTerminal(_ptr, useAlternateScreen);
  }

  /// Resize the renderer (and its underlying buffer) to new dimensions.
  /// Invalidates any cached `nextBuffer` reference.
  ///
  /// Throws [ArgumentError] when [width] or [height] is non-positive.
  void resize(int width, int height) {
    _checkNotDisposed();
    validateRendererDimensions(width, height);
    _bindings.resizeRenderer(_ptr, width, height);
    _nextBuffer?.invalidate();
    _nextBuffer = null;
  }

  /// The buffer for the next frame, created lazily and invalidated after each [render] call.
  Buffer get nextBuffer {
    _checkNotDisposed();
    _nextBuffer ??= createBufferFromNative(
      _bindings.getNextBuffer(_ptr),
      _bindings,
    );
    return _nextBuffer!;
  }

  /// Current rendered buffer, exposed for integration tests.
  @visibleForTesting
  @internal
  Buffer get debugCurrentBuffer {
    _checkNotDisposed();
    return createBufferFromNative(_bindings.getCurrentBuffer(_ptr), _bindings);
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
    _bindings.render(_ptr, force);
    final shouldFlush = autoFlush ?? _autoFlush;
    if (shouldFlush) {
      stdout.flush();
    }
    _nextBuffer?.invalidate();
    _nextBuffer = null;
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
    _bindings.setBackgroundColor(_ptr, color);
  }

  /// Clears the terminal screen.
  void clearTerminal() {
    _checkNotDisposed();
    _bindings.clearTerminal(_ptr);
  }

  /// Registers a low-level native/debug hit-grid region.
  ///
  /// Built-in widgets use render-tree hit testing for pointer routing.
  void addToHitGrid(int x, int y, int width, int height, int id) {
    _checkNotDisposed();
    _bindings.addToHitGrid(_ptr, x, y, width, height, id);
  }

  /// Queries the low-level native/debug hit grid.
  ///
  /// Built-in widgets use render-tree hit testing for pointer routing.
  int checkHit(int x, int y) {
    _checkNotDisposed();
    return _bindings.checkHit(_ptr, x, y);
  }

  /// Releases all native renderer resources and detaches the finalizer.
  void dispose({bool useAlternateScreen = false, int splitHeight = 0}) {
    if (_disposed) return;
    validateUnsigned32Abi(splitHeight, 'splitHeight');
    _disposed = true;
    // Detach from finalizer before manual destruction (prevent double-free)
    _finalizer.detach(_finalizerKey);
    // Invalidate before destroying native handle so any stragglers (clipped
    // views, etc.) fail fast instead of touching freed memory.
    _nextBuffer?.invalidate();
    _bindings.destroyRenderer(
      _ptr,
      useAlternateScreen: useAlternateScreen,
      splitHeight: splitHeight,
    );
    _nextBuffer = null;
  }

  /// Internal: raw native renderer handle. Used by `CursorManagement`,
  /// `MouseSupport`, and `KeyboardSupport` extensions in the same package
  /// and by tests that need to drive the FFI directly. Not for user code.
  @internal
  Pointer<RendererHandle> get handle {
    _checkNotDisposed();
    return _ptr;
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
  renderer._bindings.processCapabilityResponse(renderer._ptr, response);
}
