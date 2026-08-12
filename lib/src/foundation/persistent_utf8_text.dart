import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'disposable.dart';

/// Reusable native UTF-8 storage for passing stable, nul-terminated text bytes
/// to OpenTUI across frames.
final class PersistentUtf8Text implements Disposable {
  /// Creates storage initialized with [text].
  PersistentUtf8Text([String text = '']) {
    update(text);
  }

  static final Finalizer<Pointer<Void>> _finalizer = Finalizer<Pointer<Void>>((
    pointer,
  ) {
    if (pointer != nullptr) {
      calloc.free(pointer);
    }
  });

  Pointer<Uint8> _pointer = nullptr;
  int _length = 0;
  int _capacity = 0;
  bool _disposed = false;
  final Object _finalizerKey = Object();

  /// Pointer to a nul-terminated UTF-8 buffer.
  Pointer<Uint8> get pointer => _pointer;

  /// Number of bytes excluding the terminating nul.
  int get length => _length;

  /// Allocated byte capacity excluding the terminating nul.
  int get capacity => _capacity;

  /// Replaces the stored text, reusing the native allocation when it fits.
  void update(String text, {int? maxBytes}) {
    if (_disposed) throw StateError('PersistentUtf8Text is disposed');
    final bytes = utf8.encode(text);
    if (maxBytes != null && bytes.length > maxBytes) {
      throw RangeError.range(
        bytes.length,
        0,
        maxBytes,
        'text',
        'encoded UTF-8 byte length exceeds maxBytes',
      );
    }
    if (_pointer == nullptr || bytes.length > _capacity) {
      _replaceStorage(bytes.length);
    }
    _length = bytes.length;
    for (var i = 0; i < bytes.length; i++) {
      _pointer[i] = bytes[i];
    }
    _pointer[_length] = 0;
  }

  /// Releases native storage.
  @override
  void dispose() {
    if (_disposed) return;
    _finalizer.detach(_finalizerKey);
    calloc.free(_pointer);
    _pointer = nullptr;
    _length = 0;
    _capacity = 0;
    _disposed = true;
  }

  void _replaceStorage(int capacity) {
    _finalizer.detach(_finalizerKey);
    calloc.free(_pointer);
    _pointer = calloc<Uint8>(capacity + 1);
    _capacity = capacity;
    _finalizer.attach(this, _pointer.cast<Void>(), detach: _finalizerKey);
  }
}
