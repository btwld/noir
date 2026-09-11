import 'package:meta/meta.dart';

/// Strongly typed OpenTUI v0.5.1 handle value.
@immutable
sealed class OpenTuiHandle {
  const OpenTuiHandle._(this.value);

  /// Nonzero unsigned 32-bit value issued by OpenTUI.
  final int value;

  /// Validates and returns a canonical nonzero `u32` handle value.
  static int checked(int value, String name) {
    if (value <= 0 || value > 0xFFFFFFFF) {
      throw RangeError.range(value, 1, 0xFFFFFFFF, name);
    }
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other.runtimeType == runtimeType &&
      other is OpenTuiHandle &&
      other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

/// Native renderer handle.
final class RendererHandle extends OpenTuiHandle {
  /// Creates a renderer handle from its canonical native value.
  RendererHandle.fromNative(int value)
    : super._(OpenTuiHandle.checked(value, 'rendererHandle'));
}

/// Native optimized-buffer handle borrowed from a renderer.
final class OptimizedBufferHandle extends OpenTuiHandle {
  /// Creates a buffer handle from its canonical native value.
  OptimizedBufferHandle.fromNative(int value)
    : super._(OpenTuiHandle.checked(value, 'bufferHandle'));
}

/// Native decoded-image handle.
final class TerminalImageHandle extends OpenTuiHandle {
  /// Creates an image handle from its canonical native value.
  TerminalImageHandle.fromNative(int value)
    : super._(OpenTuiHandle.checked(value, 'imageHandle'));
}
