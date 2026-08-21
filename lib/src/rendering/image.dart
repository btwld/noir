import 'dart:math' as math;

import '../core/terminal_image.dart';
import '../render/geometry.dart';
import 'box.dart';
import 'object.dart';

/// Render box for one decoded terminal image.
class RenderImage extends RenderBox {
  /// Creates an image render box.
  RenderImage({
    required TerminalImage image,
    required ImageFit fit,
    ImageProtocol protocol = ImageProtocol.auto,
    int? width,
    int? height,
  }) : _image = image,
       _fit = fit,
       _protocol = protocol,
       _width = _validateExtent(width, 'width'),
       _height = _validateExtent(height, 'height');

  TerminalImage _image;
  ImageFit _fit;
  ImageProtocol _protocol;
  int? _width;
  int? _height;
  TerminalCellMetrics _metrics = const TerminalCellMetrics(columns: 0, rows: 0);

  /// Decoded image to paint.
  TerminalImage get image => _image;

  set image(TerminalImage value) {
    if (identical(value, _image)) return;
    _image = value;
    markNeedsLayout();
  }

  /// Sizing/cropping mode.
  ImageFit get fit => _fit;

  set fit(ImageFit value) {
    if (value == _fit) return;
    _fit = value;
    markNeedsPaint();
  }

  /// Requested terminal image protocol.
  ImageProtocol get protocol => _protocol;

  set protocol(ImageProtocol value) {
    if (value == _protocol) return;
    _protocol = value;
    markNeedsPaint();
  }

  /// Optional explicit terminal-cell width.
  int? get explicitWidth => _width;

  set explicitWidth(int? value) {
    _validateExtent(value, 'width');
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  /// Optional explicit terminal-cell height.
  int? get explicitHeight => _height;

  set explicitHeight(int? value) {
    _validateExtent(value, 'height');
    if (value == _height) return;
    _height = value;
    markNeedsLayout();
  }

  @override
  void performBoxLayout(BoxConstraints constraints) {
    final natural = _naturalSize(_metrics);
    var desiredWidth = _width;
    var desiredHeight = _height;
    if (desiredWidth == null && desiredHeight == null) {
      desiredWidth = natural.width;
      desiredHeight = natural.height;
    } else if (desiredWidth == null) {
      desiredWidth = natural.height == 0
          ? 0
          : math.max(
              1,
              (natural.width * desiredHeight! / natural.height).round(),
            );
    } else {
      desiredHeight ??= natural.width == 0
          ? 0
          : math.max(
              1,
              (natural.height * desiredWidth / natural.width).round(),
            );
    }
    size = Size(
      constraints.constrainWidth(desiredWidth),
      constraints.constrainHeight(desiredHeight ?? natural.height),
    );
  }

  Size _naturalSize(TerminalCellMetrics metrics) {
    final info = _image.info;
    final (cellPixelWidth, cellPixelHeight) = _cellPixelSize(metrics);
    return Size(
      math.max(1, (info.pixelWidth / cellPixelWidth).ceil()),
      math.max(1, (info.pixelHeight / cellPixelHeight).ceil()),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_metrics != context.cellMetrics) {
      _metrics = context.cellMetrics;
      if (_width == null || _height == null) markNeedsLayout();
    }
    if (size.width <= 0 || size.height <= 0) return;
    final geometry = _geometry(context.cellMetrics);
    final origin = offset + Offset(x, y);
    context.canvas.drawImage(
      _image,
      Rect.fromLTWH(
        origin.dx + geometry.destination.left,
        origin.dy + geometry.destination.top,
        geometry.destination.width,
        geometry.destination.height,
      ),
      pixelWidth: geometry.pixelWidth,
      pixelHeight: geometry.pixelHeight,
      sourceRect: geometry.source,
      protocol: _protocol,
    );
  }

  _ImageGeometry _geometry(TerminalCellMetrics metrics) {
    final info = _image.info;
    final (cellPixelWidth, cellPixelHeight) = _cellPixelSize(metrics);
    final measured =
        metrics.pixelsPerCellX != null && metrics.pixelsPerCellY != null;
    if (_fit == ImageFit.fill) {
      return _ImageGeometry(
        destination: Rect.fromLTWH(0, 0, size.width, size.height),
        source: null,
        pixelWidth: measured ? (size.width * cellPixelWidth).round() : 0,
        pixelHeight: measured ? (size.height * cellPixelHeight).round() : 0,
      );
    }

    final naturalWidth = info.pixelWidth / cellPixelWidth;
    final naturalHeight = info.pixelHeight / cellPixelHeight;
    if (_fit == ImageFit.fit) {
      final scale = math.min(
        size.width / naturalWidth,
        size.height / naturalHeight,
      );
      final width = math.max(
        1,
        math.min(size.width, (naturalWidth * scale).round()),
      );
      final height = math.max(
        1,
        math.min(size.height, (naturalHeight * scale).round()),
      );
      return _ImageGeometry(
        destination: Rect.fromLTWH(
          (size.width - width) ~/ 2,
          (size.height - height) ~/ 2,
          width,
          height,
        ),
        source: null,
        pixelWidth: measured ? (width * cellPixelWidth).round() : 0,
        pixelHeight: measured ? (height * cellPixelHeight).round() : 0,
      );
    }

    final targetAspect =
        (size.width * cellPixelWidth) / (size.height * cellPixelHeight);
    final imageAspect = info.pixelWidth / info.pixelHeight;
    Rect source;
    if (imageAspect > targetAspect) {
      final width = math.max(1, (info.pixelHeight * targetAspect).round());
      source = Rect.fromLTWH(
        (info.pixelWidth - width) ~/ 2,
        0,
        width,
        info.pixelHeight,
      );
    } else {
      final height = math.max(1, (info.pixelWidth / targetAspect).round());
      source = Rect.fromLTWH(
        0,
        (info.pixelHeight - height) ~/ 2,
        info.pixelWidth,
        height,
      );
    }
    return _ImageGeometry(
      destination: Rect.fromLTWH(0, 0, size.width, size.height),
      source: source,
      pixelWidth: measured ? (size.width * cellPixelWidth).round() : 0,
      pixelHeight: measured ? (size.height * cellPixelHeight).round() : 0,
    );
  }

  static int? _validateExtent(int? value, String name) {
    if (value != null && value < 0) {
      throw ArgumentError.value(value, name, 'must be non-negative');
    }
    return value;
  }
}

(double, double) _cellPixelSize(TerminalCellMetrics metrics) {
  const nominalWidth = 1.0;
  return (
    metrics.pixelsPerCellX ?? nominalWidth,
    metrics.pixelsPerCellY ?? nominalWidth / metrics.nominalCellAspectRatio,
  );
}

final class _ImageGeometry {
  const _ImageGeometry({
    required this.destination,
    required this.source,
    required this.pixelWidth,
    required this.pixelHeight,
  });

  final Rect destination;
  final Rect? source;
  final int pixelWidth;
  final int pixelHeight;
}
