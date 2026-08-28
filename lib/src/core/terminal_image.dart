import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import '../foundation/disposable.dart';

/// Maximum encoded input accepted by Noir image sources (64 MiB).
const int maxTerminalImageEncodedBytes = 64 * 1024 * 1024;

/// Encoded or raw format reported by OpenTUI.
enum ImageFormat {
  /// Portable Network Graphics.
  png,

  /// Unencoded straight-alpha RGBA bytes.
  rawRgba,

  /// Joint Photographic Experts Group image.
  jpeg,

  /// WebP image.
  webp,

  /// Graphics Interchange Format image.
  gif,
}

/// Color-profile interpretation reported by OpenTUI.
enum ImageColorStatus {
  /// No explicit profile was present, so sRGB is assumed.
  assumedSrgb,

  /// The source explicitly identifies sRGB color.
  explicitSrgb,
}

/// Terminal image transport requested for a draw operation.
enum ImageProtocol {
  /// Let OpenTUI select Kitty, Sixel, or block cells from capabilities.
  auto,

  /// Request Kitty graphics directly.
  ///
  /// Forced Kitty graphics through tmux are unsupported for the alpha.3
  /// release boundary because initial placement may be incorrect until a
  /// resize. Prefer [ImageProtocol.auto], which selects block cells under
  /// tmux.
  kitty,

  /// Request Sixel graphics.
  sixel,

  /// Render deterministic colored block cells.
  blocks,
}

/// How an image is mapped into its terminal-cell box.
enum ImageFit {
  /// Preserve aspect ratio and center the complete image.
  fit,

  /// Preserve aspect ratio, center, and crop to cover the box.
  cover,

  /// Stretch the complete image to fill the box.
  fill,
}

/// Stable native image failure categories.
enum TerminalImageErrorCode {
  /// The native image handle is invalid.
  invalidHandle,

  /// The encoded format is unsupported.
  unsupportedFormat,

  /// The image color space is unsupported.
  unsupportedColorSpace,

  /// The encoded bytes are malformed.
  malformedData,

  /// Pixel dimensions exceed native limits.
  dimensionLimit,

  /// Decoded or encoded memory exceeds native limits.
  memoryLimit,

  /// An argument is outside the native contract.
  invalidArgument,

  /// Native allocation failed.
  outOfMemory,

  /// A caller-provided output buffer is too small.
  outputTooSmall,

  /// An unexpected native failure occurred.
  internalError,

  /// A valid image feature is not implemented.
  unsupportedFeature,
}

/// A typed failure from native image decoding or allocation.
final class TerminalImageException implements Exception {
  /// Creates an exception from the canonical OpenTUI image [status].
  factory TerminalImageException.fromStatus(int status) {
    final (code, message) = switch (status) {
      1 => (TerminalImageErrorCode.invalidHandle, 'invalid image handle'),
      2 => (
        TerminalImageErrorCode.unsupportedFormat,
        'unsupported image format',
      ),
      3 => (
        TerminalImageErrorCode.unsupportedColorSpace,
        'unsupported image color space',
      ),
      4 => (TerminalImageErrorCode.malformedData, 'malformed image data'),
      5 => (
        TerminalImageErrorCode.dimensionLimit,
        'image dimensions exceed limits',
      ),
      6 => (TerminalImageErrorCode.memoryLimit, 'image memory limit exceeded'),
      7 => (TerminalImageErrorCode.invalidArgument, 'invalid image argument'),
      8 => (TerminalImageErrorCode.outOfMemory, 'out of memory'),
      9 => (
        TerminalImageErrorCode.outputTooSmall,
        'image output buffer is too small',
      ),
      11 => (
        TerminalImageErrorCode.unsupportedFeature,
        'unsupported image feature',
      ),
      _ => (TerminalImageErrorCode.internalError, 'internal image error'),
    };
    return TerminalImageException._(status, code, message);
  }

  const TerminalImageException._(this.status, this.code, this.message);

  /// Numeric OpenTUI status.
  final int status;

  /// Stable Dart category.
  final TerminalImageErrorCode code;

  /// Human-readable failure description.
  final String message;

  @override
  String toString() => 'TerminalImageException($status): $message';
}

/// Immutable decoded-image metadata.
@immutable
final class TerminalImageInfo {
  /// Creates decoded image metadata.
  const TerminalImageInfo({
    required this.pixelWidth,
    required this.pixelHeight,
    required this.sourcePixelWidth,
    required this.sourcePixelHeight,
    required this.format,
    required this.colorStatus,
    required this.orientation,
    required this.hasAlpha,
  });

  /// Display-oriented pixel width.
  final int pixelWidth;

  /// Display-oriented pixel height.
  final int pixelHeight;

  /// Source pixel width before orientation is applied.
  final int sourcePixelWidth;

  /// Source pixel height before orientation is applied.
  final int sourcePixelHeight;

  /// Source format.
  final ImageFormat format;

  /// Color-profile interpretation.
  final ImageColorStatus colorStatus;

  /// EXIF orientation value.
  final int orientation;

  /// Whether decoded pixels may contain transparency.
  final bool hasAlpha;
}

/// An explicitly owned decoded image backed by OpenTUI.
///
/// Call [dispose] when the image is no longer needed. Disposal is idempotent;
/// every other member throws [StateError] after disposal.
final class TerminalImage implements Disposable {
  TerminalImage._(this._bindings, this._handle, this._info) {
    _finalizer.attach(
      this,
      _TerminalImageFinalizerPayload(_bindings, _handle),
      detach: _finalizerKey,
    );
  }

  /// Decodes PNG, JPEG, WebP, or the first frame of a GIF synchronously.
  factory TerminalImage.decode(Uint8List data) =>
      TerminalImage._decodeWith(OpenTuiBindings(), data);

  /// Creates an image by copying straight-alpha RGBA bytes synchronously.
  factory TerminalImage.fromRgba(
    Uint8List pixels, {
    required int pixelWidth,
    required int pixelHeight,
    required int rowStride,
  }) => TerminalImage._rgbaWith(
    OpenTuiBindings(),
    pixels,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight,
    rowStride: rowStride,
  );

  static TerminalImage _decodeWith(OpenTuiBindings bindings, Uint8List data) {
    if (data.isEmpty) {
      throw ArgumentError.value(data, 'data', 'must not be empty');
    }
    if (data.length > maxTerminalImageEncodedBytes) {
      throw TerminalImageException.fromStatus(6);
    }
    final result = bindings.imageDecode(data);
    return _finishCreation(bindings, result.status, result.handle);
  }

  static TerminalImage _rgbaWith(
    OpenTuiBindings bindings,
    Uint8List pixels, {
    required int pixelWidth,
    required int pixelHeight,
    required int rowStride,
  }) {
    if (pixelWidth <= 0 || pixelHeight <= 0) {
      throw ArgumentError('pixelWidth and pixelHeight must be positive');
    }
    final minimumStride = pixelWidth * 4;
    if (rowStride < minimumStride) {
      throw ArgumentError.value(
        rowStride,
        'rowStride',
        'must be at least pixelWidth * 4',
      );
    }
    if (pixels.length < rowStride * pixelHeight) {
      throw ArgumentError.value(
        pixels.length,
        'pixels',
        'does not contain every RGBA row',
      );
    }
    final result = bindings.imageCreateFromRgba(
      pixels,
      width: pixelWidth,
      height: pixelHeight,
      stride: rowStride,
    );
    return _finishCreation(bindings, result.status, result.handle);
  }

  // ignore: prefer_constructors_over_static_methods
  static TerminalImage _finishCreation(
    OpenTuiBindings bindings,
    int status,
    TerminalImageHandle? handle,
  ) {
    if (status != 0 || handle == null) {
      if (handle != null) bindings.imageDestroy(handle);
      throw TerminalImageException.fromStatus(status == 0 ? 10 : status);
    }
    final infoResult = bindings.imageGetInfo(handle);
    if (infoResult.status != 0) {
      bindings.imageDestroy(handle);
      throw TerminalImageException.fromStatus(infoResult.status);
    }
    return TerminalImage._(bindings, handle, _decodeInfo(infoResult.fields));
  }

  static TerminalImageInfo _decodeInfo(List<int> fields) {
    final format = switch (fields[4]) {
      1 => ImageFormat.png,
      2 => ImageFormat.rawRgba,
      3 => ImageFormat.jpeg,
      4 => ImageFormat.webp,
      5 => ImageFormat.gif,
      _ => throw TerminalImageException.fromStatus(10),
    };
    return TerminalImageInfo(
      pixelWidth: fields[0],
      pixelHeight: fields[1],
      sourcePixelWidth: fields[2],
      sourcePixelHeight: fields[3],
      format: format,
      colorStatus: fields[5] == 1
          ? ImageColorStatus.explicitSrgb
          : ImageColorStatus.assumedSrgb,
      orientation: fields[6],
      hasAlpha: fields[7] != 0,
    );
  }

  static final Finalizer<_TerminalImageFinalizerPayload> _finalizer =
      Finalizer<_TerminalImageFinalizerPayload>((payload) {
        try {
          payload.bindings.imageDestroy(payload.handle);
        } on Object {
          // Finalizers are best-effort fallback cleanup.
        }
      });

  final OpenTuiBindings _bindings;
  final TerminalImageHandle _handle;
  final TerminalImageInfo _info;
  final Object _finalizerKey = Object();
  bool _disposed = false;

  /// Decoded metadata.
  TerminalImageInfo get info {
    _checkNotDisposed();
    return _info;
  }

  @internal
  /// Live native handle retained by framework painting commands.
  TerminalImageHandle get handle {
    _checkNotDisposed();
    return _handle;
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('TerminalImage is disposed');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _finalizer.detach(_finalizerKey);
    _bindings.imageDestroy(_handle);
  }
}

final class _TerminalImageFinalizerPayload {
  const _TerminalImageFinalizerPayload(this.bindings, this.handle);

  final OpenTuiBindings bindings;
  final TerminalImageHandle handle;
}
