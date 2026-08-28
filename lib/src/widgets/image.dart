import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../core/terminal_image.dart';
import '../framework/build_context.dart';
import '../framework/widget.dart';
import '../rendering/image.dart';
import '../rendering/object.dart';
import 'sized_box.dart';

/// Builds placeholder content while an image loads.
typedef ImageLoadingBuilder = Widget Function(BuildContext context);

/// Builds fallback content after an image source fails.
typedef ImageErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

/// Stable image-source loading failure categories.
enum ImageLoadErrorCode {
  /// A file could not be opened or read.
  fileRead,

  /// An HTTP request or response body failed.
  network,

  /// An HTTP response returned a non-success status.
  httpStatus,

  /// A network URI did not use HTTP or HTTPS.
  unsupportedUrlScheme,
}

/// Typed failure while acquiring encoded image bytes.
final class ImageLoadException implements Exception {
  /// Creates a typed source-loading error.
  const ImageLoadException({
    required this.code,
    required this.source,
    required this.message,
    this.status,
    this.cause,
  });

  /// Stable failure category.
  final ImageLoadErrorCode code;

  /// File path or URI that failed.
  final String source;

  /// Human-readable description.
  final String message;

  /// HTTP status for [ImageLoadErrorCode.httpStatus].
  final int? status;

  /// Underlying platform failure, when available.
  final Object? cause;

  @override
  String toString() => 'ImageLoadException(${code.name}, $source): $message';
}

/// Network load timeout used by [Image.network]. Tests may shorten this.
@visibleForTesting
Duration debugNetworkImageTimeout = const Duration(seconds: 15);

/// Displays a decoded image through terminal-native protocols or block cells.
class Image extends StatefulWidget {
  /// Displays a borrowed decoded [image]. The widget never disposes it.
  Image({
    required TerminalImage image,
    this.width,
    this.height,
    this.fit = ImageFit.fit,
    this.protocol = ImageProtocol.auto,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
    this.onError,
    super.key,
  }) : _source = _BorrowedImageSource(image);

  /// Decodes a snapshot of encoded image [bytes].
  Image.memory(
    Uint8List bytes, {
    this.width,
    this.height,
    this.fit = ImageFit.fit,
    this.protocol = ImageProtocol.auto,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
    this.onError,
    super.key,
  }) : _source = _MemoryImageSource(_snapshotEncoded(bytes));

  /// Copies a snapshot of straight-alpha RGBA [pixels].
  Image.rgba(
    Uint8List pixels, {
    required int pixelWidth,
    required int pixelHeight,
    required int rowStride,
    this.width,
    this.height,
    this.fit = ImageFit.fit,
    this.protocol = ImageProtocol.auto,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
    this.onError,
    super.key,
  }) : _source = _RgbaImageSource(
         Uint8List.fromList(pixels),
         pixelWidth,
         pixelHeight,
         rowStride,
       );

  /// Streams and decodes an image from [path].
  Image.file(
    String path, {
    this.width,
    this.height,
    this.fit = ImageFit.fit,
    this.protocol = ImageProtocol.auto,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
    this.onError,
    super.key,
  }) : _source = _FileImageSource(path);

  /// Fetches and decodes an HTTP(S) image.
  Image.network(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
    this.width,
    this.height,
    this.fit = ImageFit.fit,
    this.protocol = ImageProtocol.auto,
    this.loadingBuilder,
    this.errorBuilder,
    this.onLoad,
    this.onError,
    super.key,
  }) : _source = _NetworkImageSource(uri, headers);

  final _ImageSource _source;

  /// Optional terminal-cell width.
  final int? width;

  /// Optional terminal-cell height.
  final int? height;

  /// Sizing and cropping mode.
  final ImageFit fit;

  /// Requested terminal graphics protocol.
  final ImageProtocol protocol;

  /// Placeholder used only before any image has loaded successfully.
  final ImageLoadingBuilder? loadingBuilder;

  /// Fallback used only when no image has loaded successfully.
  final ImageErrorBuilder? errorBuilder;

  /// Called after the current source loads successfully.
  final void Function(TerminalImage image)? onLoad;

  /// Called when the current source fails.
  final void Function(Object error, StackTrace stackTrace)? onError;

  @override
  State<Image> createState() => _ImageState();
}

final class _ImageState extends State<Image> {
  TerminalImage? _current;
  bool _ownsCurrent = false;
  Object? _error;
  StackTrace? _errorStack;
  bool _loading = false;
  int _generation = 0;
  _ImageLoadToken? _token;

  @override
  void initState() {
    super.initState();
    _load(widget._source, notify: false);
  }

  @override
  void didUpdateWidget(covariant Image oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget._source != widget._source) _load(widget._source);
  }

  void _load(_ImageSource source, {bool notify = true}) {
    _token?.cancel();
    final generation = ++_generation;
    final token = _ImageLoadToken();
    _token = token;
    _error = null;
    _errorStack = null;

    if (source case _BorrowedImageSource(:final image)) {
      _replaceCurrent(image, owns: false);
      _loading = false;
      if (notify && mounted) setState(() {});
      scheduleMicrotask(() {
        if (mounted && generation == _generation) widget.onLoad?.call(image);
      });
      return;
    }

    try {
      final image = source.loadSync();
      if (image != null) {
        _replaceCurrent(image, owns: true);
        _loading = false;
        if (notify && mounted) setState(() {});
        scheduleMicrotask(() {
          if (mounted && generation == _generation) widget.onLoad?.call(image);
        });
        return;
      }
    } on Object catch (error, stackTrace) {
      _loading = false;
      _error = error;
      _errorStack = stackTrace;
      if (notify && mounted) setState(() {});
      scheduleMicrotask(() {
        if (mounted && generation == _generation) {
          widget.onError?.call(error, stackTrace);
        }
      });
      return;
    }

    _loading = true;
    if (notify && mounted) setState(() {});
    source
        .load(token)
        .then(
          (image) {
            if (!mounted || token.isCancelled || generation != _generation) {
              image.dispose();
              return;
            }
            setState(() {
              _replaceCurrent(image, owns: true);
              _loading = false;
            });
            widget.onLoad?.call(image);
          },
          onError: (Object error, StackTrace stackTrace) {
            if (error is _ImageLoadCancelled ||
                !mounted ||
                token.isCancelled ||
                generation != _generation) {
              return;
            }
            setState(() {
              _loading = false;
              _error = error;
              _errorStack = stackTrace;
            });
            widget.onError?.call(error, stackTrace);
          },
        );
  }

  void _replaceCurrent(TerminalImage image, {required bool owns}) {
    final old = _current;
    final disposeOld = _ownsCurrent && old != null && !identical(old, image);
    _current = image;
    _ownsCurrent = owns;
    if (disposeOld) old.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _current;
    if (image != null) {
      return _RenderImageWidget(
        image: image,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        protocol: widget.protocol,
      );
    }
    final error = _error;
    if (error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(
        context,
        error,
        _errorStack ?? StackTrace.empty,
      );
    }
    if (_loading && widget.loadingBuilder != null) {
      return widget.loadingBuilder!(context);
    }
    return SizedBox(width: widget.width ?? 0, height: widget.height ?? 0);
  }

  @override
  void dispose() {
    _generation++;
    _token?.cancel();
    if (_ownsCurrent) _current?.dispose();
    _current = null;
    super.dispose();
  }
}

final class _RenderImageWidget extends RenderObjectWidget {
  const _RenderImageWidget({
    required this.image,
    required this.fit,
    required this.protocol,
    required this.width,
    required this.height,
  });

  final TerminalImage image;
  final ImageFit fit;
  final ImageProtocol protocol;
  final int? width;
  final int? height;

  @override
  @internal
  RenderObject createRenderObject(BuildContext context) => RenderImage(
    image: image,
    fit: fit,
    protocol: protocol,
    width: width,
    height: height,
  );

  @override
  @internal
  void updateRenderObject(BuildContext context, RenderImage renderObject) {
    renderObject
      ..explicitWidth = width
      ..explicitHeight = height
      ..image = image
      ..fit = fit
      ..protocol = protocol;
  }
}

sealed class _ImageSource {
  const _ImageSource();

  Future<TerminalImage> load(_ImageLoadToken token);

  TerminalImage? loadSync() => null;
}

@immutable
final class _BorrowedImageSource extends _ImageSource {
  const _BorrowedImageSource(this.image);

  final TerminalImage image;

  @override
  Future<TerminalImage> load(_ImageLoadToken token) => Future.value(image);

  @override
  bool operator ==(Object other) =>
      other is _BorrowedImageSource && identical(other.image, image);

  @override
  int get hashCode => identityHashCode(image);
}

@immutable
final class _MemoryImageSource extends _ImageSource {
  _MemoryImageSource(this.bytes) : _hash = Object.hashAll(bytes);

  final Uint8List bytes;
  final int _hash;

  @override
  Future<TerminalImage> load(_ImageLoadToken token) async {
    token.throwIfCancelled();
    return TerminalImage.decode(bytes);
  }

  @override
  TerminalImage loadSync() => TerminalImage.decode(bytes);

  @override
  bool operator ==(Object other) =>
      other is _MemoryImageSource && _bytesEqual(bytes, other.bytes);

  @override
  int get hashCode => _hash;
}

@immutable
final class _RgbaImageSource extends _ImageSource {
  _RgbaImageSource(this.pixels, this.width, this.height, this.stride)
    : _hash = Object.hash(Object.hashAll(pixels), width, height, stride);

  final Uint8List pixels;
  final int width;
  final int height;
  final int stride;
  final int _hash;

  @override
  Future<TerminalImage> load(_ImageLoadToken token) async {
    token.throwIfCancelled();
    return TerminalImage.fromRgba(
      pixels,
      pixelWidth: width,
      pixelHeight: height,
      rowStride: stride,
    );
  }

  @override
  TerminalImage loadSync() => TerminalImage.fromRgba(
    pixels,
    pixelWidth: width,
    pixelHeight: height,
    rowStride: stride,
  );

  @override
  bool operator ==(Object other) =>
      other is _RgbaImageSource &&
      other.width == width &&
      other.height == height &&
      other.stride == stride &&
      _bytesEqual(other.pixels, pixels);

  @override
  int get hashCode => _hash;
}

@immutable
final class _FileImageSource extends _ImageSource {
  const _FileImageSource(this.path);

  final String path;

  @override
  Future<TerminalImage> load(_ImageLoadToken token) async {
    try {
      final file = io.File(path);
      final length = await file.length();
      token.throwIfCancelled();
      if (length > maxTerminalImageEncodedBytes) {
        throw TerminalImageException.fromStatus(6);
      }
      final bytes = await _readBytes(file.openRead(), token);
      token.throwIfCancelled();
      return TerminalImage.decode(bytes);
    } on TerminalImageException {
      rethrow;
    } on _ImageLoadCancelled {
      rethrow;
    } on Object catch (error) {
      throw ImageLoadException(
        code: ImageLoadErrorCode.fileRead,
        source: path,
        message: 'Failed to read image file',
        cause: error,
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _FileImageSource && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

@immutable
final class _NetworkImageSource extends _ImageSource {
  _NetworkImageSource(this.uri, Map<String, String> headers)
    : headers = Map<String, String>.unmodifiable(
        Map<String, String>.of(headers),
      ),
      _hash = Object.hash(uri, _mapHash(headers));

  final Uri uri;
  final Map<String, String> headers;
  final int _hash;

  @override
  Future<TerminalImage> load(_ImageLoadToken token) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw ImageLoadException(
        code: ImageLoadErrorCode.unsupportedUrlScheme,
        source: uri.toString(),
        message: 'Only HTTP and HTTPS image URIs are supported',
      );
    }
    final timeout = debugNetworkImageTimeout;
    final client = io.HttpClient()..connectionTimeout = timeout;
    void cancelRequest() => client.close(force: true);
    token.addCancelCallback(cancelRequest);
    try {
      token.throwIfCancelled();
      final request = await client.getUrl(uri).timeout(timeout);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.drain<void>();
        throw ImageLoadException(
          code: ImageLoadErrorCode.httpStatus,
          source: uri.toString(),
          status: response.statusCode,
          message: 'Image request returned HTTP ${response.statusCode}',
        );
      }
      if (response.contentLength > maxTerminalImageEncodedBytes) {
        throw TerminalImageException.fromStatus(6);
      }
      final bytes = await _readBytes(response, token);
      token.throwIfCancelled();
      return TerminalImage.decode(bytes);
    } on ImageLoadException {
      rethrow;
    } on TerminalImageException {
      rethrow;
    } on _ImageLoadCancelled {
      rethrow;
    } on Object catch (error) {
      throw ImageLoadException(
        code: ImageLoadErrorCode.network,
        source: uri.toString(),
        message: 'Failed to fetch image',
        cause: error,
      );
    } finally {
      token.removeCancelCallback(cancelRequest);
      client.close(force: token.isCancelled);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is _NetworkImageSource &&
      other.uri == uri &&
      _mapEqual(other.headers, headers);

  @override
  int get hashCode => _hash;
}

Future<Uint8List> _readBytes(
  Stream<List<int>> stream,
  _ImageLoadToken token,
) async {
  final builder = BytesBuilder(copy: false);
  final iterator = StreamIterator<List<int>>(stream);
  void cancelRead() => unawaited(iterator.cancel());
  token.addCancelCallback(cancelRead);
  var length = 0;
  try {
    while (await iterator.moveNext()) {
      token.throwIfCancelled();
      final chunk = iterator.current;
      if (chunk.length > maxTerminalImageEncodedBytes - length) {
        throw TerminalImageException.fromStatus(6);
      }
      builder.add(chunk);
      length += chunk.length;
    }
    return builder.takeBytes();
  } finally {
    token.removeCancelCallback(cancelRead);
  }
}

final class _ImageLoadToken {
  bool _cancelled = false;
  final List<void Function()> _cancelCallbacks = <void Function()>[];

  bool get isCancelled => _cancelled;

  void addCancelCallback(void Function() callback) {
    if (_cancelled) {
      callback();
      return;
    }
    _cancelCallbacks.add(callback);
  }

  void removeCancelCallback(void Function() callback) {
    _cancelCallbacks.remove(callback);
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final callback in List<void Function()>.of(_cancelCallbacks)) {
      callback();
    }
    _cancelCallbacks.clear();
  }

  void throwIfCancelled() {
    if (_cancelled) throw const _ImageLoadCancelled();
  }
}

final class _ImageLoadCancelled implements Exception {
  const _ImageLoadCancelled();
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

Uint8List _snapshotEncoded(Uint8List bytes) {
  if (bytes.length > maxTerminalImageEncodedBytes) {
    throw TerminalImageException.fromStatus(6);
  }
  return Uint8List.fromList(bytes);
}

bool _mapEqual(Map<String, String> a, Map<String, String> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

int _mapHash(Map<String, String> map) => Object.hashAllUnordered(
  map.entries.map((entry) => Object.hash(entry.key, entry.value)),
);
