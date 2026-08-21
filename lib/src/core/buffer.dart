import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import 'color.dart';
import 'grapheme_metrics.dart';
import 'terminal_image.dart';
import 'terminal_style.dart';

const _rgbaChannelsPerCell = 4;

void _checkUnsignedAbi(int value, int maximum, String name) {
  if (value < 0 || value > maximum) {
    throw RangeError.range(value, 0, maximum, name);
  }
}

void _checkSigned32Abi(int value, String name) {
  if (value < -0x80000000 || value > 0x7FFFFFFF) {
    throw RangeError.range(value, -0x80000000, 0x7FFFFFFF, name);
  }
}

int _rgbaOffset(int cellIndex) => cellIndex * _rgbaChannelsPerCell;

Color _readRgba(Uint16List values, int cellIndex) {
  final offset = _rgbaOffset(cellIndex);
  return Color(
    (values[offset] & 0xFF) / 255,
    (values[offset + 1] & 0xFF) / 255,
    (values[offset + 2] & 0xFF) / 255,
    (values[offset + 3] & 0xFF) / 255,
  );
}

void _writeRgba(Uint16List values, int cellIndex, Color color) {
  validateColorChannels(color);
  final offset = _rgbaOffset(cellIndex);
  values[offset] = (color.r * 255).round();
  values[offset + 1] = (color.g * 255).round();
  values[offset + 2] = (color.b * 255).round();
  values[offset + 3] = (color.a * 255).round();
}

/// Shared validity flag for a [Buffer] and every view ([Buffer.clipped]) of
/// it. Renderer-driven invalidation (after `render`, `resize`, or `dispose`)
/// flips this once and every consumer fails on the next access.
class _BufferValidity {
  bool isValid = true;
  int directAccessGeneration = 0;
}

/// Creates a buffer wrapper for a native frame owned by the renderer.
@internal
Buffer createBufferFromNative(
  OptimizedBufferHandle pointer,
  OpenTuiBindings bindings,
  bool Function() ownerIsDisposed, {
  bool materializeImagesAsBlocks = false,
}) => Buffer._(
  pointer,
  bindings,
  ownerIsDisposed,
  materializeImagesAsBlocks: materializeImagesAsBlocks,
);

/// Resolves native grapheme-table cells for framework capture tests.
@internal
@visibleForTesting
String debugResolveBufferCharacters(
  Buffer buffer, {
  bool addLineBreaks = false,
}) {
  buffer._checkValid();
  return buffer._bindings.bufferResolvedCharacters(
    buffer._ptr,
    addLineBreaks: addLineBreaks,
  );
}

/// Resolves exactly one native cell without re-segmenting adjacent cell text.
///
/// Plain Unicode scalar cells can be decoded directly. Packed grapheme and
/// image cells are resolved by temporarily hiding every other character word
/// from OpenTUI's debug serializer, with the original frame restored even if
/// resolution fails. This test-only path preserves native cell boundaries for
/// separately drawn clusters that Dart's whole-string segmentation could
/// otherwise merge.
@internal
@visibleForTesting
String debugResolveBufferCell(Buffer buffer, int cellIndex) {
  buffer._checkValid();
  final direct = buffer.getDirectAccess();
  if (cellIndex < 0 || cellIndex >= direct.length) {
    throw RangeError.range(cellIndex, 0, direct.length - 1, 'cellIndex');
  }

  final character = direct._chars[cellIndex];
  final kind = character & 0xC0000000;
  if (kind == 0xC0000000) return '';
  if (kind == 0) {
    return character == 0 || character > 0x10FFFF
        ? ' '
        : String.fromCharCode(character);
  }

  final original = Uint32List.fromList(direct._chars);
  try {
    direct._chars
      ..fillRange(0, direct._chars.length, 0xC0000000)
      ..[cellIndex] = character;
    return debugResolveBufferCharacters(buffer);
  } finally {
    direct._chars.setAll(0, original);
  }
}

/// High-level wrapper for OpenTUI's optimized buffer operations.
///
/// The Buffer class provides a convenient Dart interface for all OpenTUI
/// drawing operations, including text rendering, shape drawing, and advanced
/// compositing. Buffers represent 2D grids of terminal cells, each containing
/// a character, foreground color, background color, and text attributes.
///
/// **Lifecycle**: Buffer instances obtained from [Renderer.nextBuffer] are only
/// valid until the next call to [Renderer.render()]. After render, the buffer
/// is invalidated and all operations will throw [StateError].
///
/// Use Buffer when:
/// - Building terminal-based user interfaces
/// - Creating text-mode games and graphics
/// - Implementing off-screen rendering for complex layouts
/// - Building layered rendering systems with multiple buffers
///
/// Example:
/// ```dart
/// final buffer = renderer.nextBuffer;
///
/// // Clear to dark background
/// buffer.clear(Color.rgb(0.1, 0.13, 0.17));
///
/// // Draw a bordered panel
/// buffer.drawBox(5, 2, 30, 15,
///     BoxOptions(title: 'Settings'),
///     Color.cyan, Color.darkGray);
///
/// // Add content text
/// buffer.drawText('Welcome to OpenTUI!', 10, 5, Color.white);
///
/// // Create a progress bar
/// buffer.fillRect(10, 8, 20, 1, Color.green);
/// ```
class Buffer {
  Buffer._(
    this._ptr,
    this._bindings,
    this._ownerIsDisposed, {
    bool materializeImagesAsBlocks = false,
  }) : _materializeImagesAsBlocks = materializeImagesAsBlocks,
       _validity = _BufferValidity();

  Buffer._withValidity(
    this._ptr,
    this._bindings,
    this._ownerIsDisposed,
    this._validity, {
    required bool materializeImagesAsBlocks,
  }) : _materializeImagesAsBlocks = materializeImagesAsBlocks;
  final OpenTuiBindings _bindings;
  final OptimizedBufferHandle _ptr;
  final bool Function() _ownerIsDisposed;
  final _BufferValidity _validity;
  final bool _materializeImagesAsBlocks;

  /// Returns a [Buffer] view that silently drops draw calls outside the
  /// rectangle `(clipX, clipY, clipWidth, clipHeight)`. The view shares the
  /// underlying FFI buffer and validity state; invalidating the parent
  /// also invalidates every clipped view. Used by scrolling/clipping
  /// containers (e.g. `ScrollBox`).
  Buffer clipped({
    required int clipX,
    required int clipY,
    required int clipWidth,
    required int clipHeight,
  }) => _ClippedBufferView(
    _ptr,
    _bindings,
    _ownerIsDisposed,
    _validity,
    materializeImagesAsBlocks: _materializeImagesAsBlocks,
    clipX: clipX,
    clipY: clipY,
    clipWidth: clipWidth,
    clipHeight: clipHeight,
  );

  void _checkValid() {
    if (!_validity.isValid || _ownerIsDisposed()) {
      throw StateError(
        'Buffer has been invalidated. Get a fresh buffer from renderer.nextBuffer.',
      );
    }
  }

  void _checkDirectAccessGeneration(int generation) {
    _checkValid();
    if (generation != _validity.directAccessGeneration) {
      throw StateError(
        'Buffer has been invalidated by resize. '
        'Get fresh direct access from buffer.getDirectAccess().',
      );
    }
  }

  /// Invalidate this buffer (and every view created from it via
  /// [clipped]). Called by Renderer after `render`, `resize`, or
  /// `dispose`.
  @internal
  void invalidate() {
    _validity.isValid = false;
  }

  /// Whether this buffer has been invalidated.
  bool get isInvalidated => !_validity.isValid || _ownerIsDisposed();

  /// Packs a semantic [uri] into [attributes] for a visible text run.
  @internal
  int attributesWithLink(int attributes, Uri uri) {
    _checkValid();
    final linkId = _bindings.linkAlloc(uri);
    return linkId == 0
        ? attributes
        : _bindings.attributesWithLink(attributes, linkId);
  }

  /// Resolves the semantic URL encoded in a cell attribute word.
  @internal
  String? linkForAttributes(int attributes) {
    _checkValid();
    final linkId = _bindings.attributesGetLinkId(attributes);
    return _bindings.linkGetUrl(linkId);
  }

  /// Whether a complete text cluster would be painted at this location.
  ///
  /// The compositor checks this before allocating hyperlink attributes.
  /// OpenTUI link slots begin without cell references, so allocating for a
  /// cluster that clipping later drops would leave the slot unreclaimable.
  @internal
  bool acceptsTextCluster(int x, int y, int clusterWidth) =>
      clusterWidth > 0 &&
      x >= 0 &&
      x + clusterWidth <= width &&
      y >= 0 &&
      y < height;

  /// Width of the buffer in terminal columns.
  int get width {
    _checkValid();
    return _bindings.getBufferWidth(_ptr);
  }

  /// Height of the buffer in terminal rows.
  int get height {
    _checkValid();
    return _bindings.getBufferHeight(_ptr);
  }

  /// Clears the entire buffer to a uniform background color.
  ///
  /// This efficiently resets all cells in the buffer, setting their
  /// background colors and clearing any existing characters and formatting.
  ///
  /// Example:
  /// ```dart
  /// buffer.clear(Color.black); // Clear to black background
  /// buffer.clear(Color.transparent); // Clear to transparent
  /// ```
  void clear(Color bg) {
    _checkValid();
    _bindings.bufferClear(_ptr, bg);
  }

  /// Draws text at the specified position with styling options.
  ///
  /// This is the primary method for text rendering. Text extends horizontally
  /// from the given position and will be clipped at buffer boundaries.
  ///
  /// Example:
  /// ```dart
  /// // Simple text
  /// buffer.drawText('Hello', 0, 0, Color.white);
  ///
  /// // Styled text with background
  /// buffer.drawText('Error!', 10, 5, Color.red,
  ///     bg: Color.yellow, attributes: Attr.bold);
  /// ```
  ///
  /// [x] and [y] must fit unsigned 32-bit values and [attributes] an unsigned
  /// 32-bit value; violations throw a pre-invocation [RangeError] after the
  /// lifecycle check.
  void drawText(
    String text,
    int x,
    int y,
    Color fg, {
    Color? bg,
    int attributes = 0,
  }) {
    _checkValid();
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    _bindings.bufferDrawText(_ptr, text, x, y, fg, bg, attributes);
  }

  /// Fills a rectangular region with solid background color.
  ///
  /// This is very efficient for drawing solid areas, panels, and backgrounds.
  /// Use this instead of multiple setCell calls for better performance.
  ///
  /// Example:
  /// ```dart
  /// // Fill a 20x10 panel background
  /// buffer.fillRect(5, 2, 20, 10, Color.darkGray);
  ///
  /// // Create a progress bar
  /// final progress = 0.7; // 70%
  /// buffer.fillRect(10, 8, (progress * 30).round(), 1, Color.green);
  /// ```
  ///
  /// [x], [y], [width], and [height] must fit unsigned 32-bit values;
  /// violations throw a pre-invocation [RangeError] after the lifecycle
  /// check.
  void fillRect(int x, int y, int width, int height, Color color) {
    _checkValid();
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _bindings.bufferFillRect(_ptr, x, y, width, height, color);
  }

  /// Draws a bordered box with extensive customization options.
  ///
  /// This creates bordered rectangles with optional titles, custom border
  /// characters, selective sides, and interior fills. Perfect for UI panels,
  /// dialogs, and structured layouts.
  ///
  /// Example:
  /// ```dart
  /// // Simple bordered box
  /// buffer.drawBox(10, 5, 25, 12,
  ///     BoxOptions(),
  ///     Color.white, Color.transparent);
  ///
  /// // Dialog with title
  /// buffer.drawBox(15, 8, 35, 18,
  ///     BoxOptions(
  ///         title: 'Confirm Action',
  ///         titleAlignment: TextAlign.center,
  ///         fill: true
  ///     ), Color.cyan, Color.blue);
  /// ```
  ///
  /// [x] and [y] must fit signed 32-bit values and [width] and [height]
  /// unsigned 32-bit values; violations throw a pre-invocation [RangeError]
  /// after the lifecycle check.
  void drawBox(
    int x,
    int y,
    int width,
    int height,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) {
    _checkValid();
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _bindings.bufferDrawBox(
      _ptr,
      x,
      y,
      width,
      height,
      options,
      borderColor,
      backgroundColor,
    );
  }

  /// Sets a single cell at (x, y) using alpha blending.
  ///
  /// [attributes] must fit an unsigned 32-bit value; a violation throws a
  /// pre-invocation [RangeError] after the lifecycle, character, and bounds
  /// checks.
  void setCell(int x, int y, String char, Color fg, Color bg, int attributes) {
    setCellWithAlphaBlending(x, y, char, fg, bg, attributes);
  }

  /// Sets a cell at (x, y) with full alpha-blending support.
  ///
  /// [attributes] must fit an unsigned 32-bit value; a violation throws a
  /// pre-invocation [RangeError] after the lifecycle, character, and bounds
  /// checks.
  void setCellWithAlphaBlending(
    int x,
    int y,
    String char,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkValid();
    if (char.isEmpty) throw ArgumentError('Character cannot be empty');
    _setCellCodeWithAlphaBlending(x, y, char.runes.first, fg, bg, attributes);
  }

  /// Shared write funnel for public cell writes and the clipped-view
  /// compositing seam: lifecycle, then bounds, then the single unsigned
  /// 32-bit [attributes] domain check. [charCode] is a Unicode scalar or a
  /// native-encoded cell word, both unsigned 32-bit by construction.
  void _setCellCodeWithAlphaBlending(
    int x,
    int y,
    int charCode,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkValid();
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError(
        'Coordinates ($x, $y) out of bounds for ${width}x$height buffer',
      );
    }
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');

    _bindings.bufferSetCellWithAlphaBlending(
      _ptr,
      x,
      y,
      charCode,
      fg,
      bg,
      attributes,
    );
  }

  /// Draw another buffer onto this buffer (compositing).
  ///
  /// The source rectangle (`srcX, srcY, srcWidth, srcHeight`) is copied to
  /// (`destX, destY`) on this buffer. Both buffers must be valid (not yet
  /// invalidated by their renderer); zero source values select the native
  /// full-extent default. After both lifecycle checks, [srcX], [srcY],
  /// [srcWidth], and [srcHeight] must fit unsigned 32-bit values and [destX]
  /// and [destY] signed 32-bit values; violations throw a pre-invocation
  /// [RangeError].
  void drawFrameBuffer(
    Buffer sourceBuffer,
    int srcX,
    int srcY,
    int srcWidth,
    int srcHeight,
    int destX,
    int destY,
  ) {
    _checkValid();
    sourceBuffer._checkValid();
    _checkUnsignedAbi(srcX, 0xFFFFFFFF, 'srcX');
    _checkUnsignedAbi(srcY, 0xFFFFFFFF, 'srcY');
    _checkUnsignedAbi(srcWidth, 0xFFFFFFFF, 'srcWidth');
    _checkUnsignedAbi(srcHeight, 0xFFFFFFFF, 'srcHeight');
    _checkSigned32Abi(destX, 'destX');
    _checkSigned32Abi(destY, 'destY');
    _bindings.drawFrameBuffer(
      _ptr,
      destX,
      destY,
      sourceBuffer._ptr,
      srcX,
      srcY,
      srcWidth,
      srcHeight,
    );
  }

  /// Draws [image] into a terminal-cell rectangle.
  ///
  /// Pixel dimensions of zero let OpenTUI use its fallback cell aspect. The
  /// optional clip is pushed onto the native scissor stack so OpenTUI adjusts
  /// both the destination and proportional source crop as one operation.
  bool drawImage(
    TerminalImage image, {
    required int x,
    required int y,
    required int width,
    required int height,
    int pixelWidth = 0,
    int pixelHeight = 0,
    int sourceX = 0,
    int sourceY = 0,
    int? sourceWidth,
    int? sourceHeight,
    ImageProtocol protocol = ImageProtocol.auto,
    int? clipX,
    int? clipY,
    int? clipWidth,
    int? clipHeight,
  }) {
    _checkValid();
    final info = image.info;
    final resolvedSourceWidth = sourceWidth ?? info.pixelWidth;
    final resolvedSourceHeight = sourceHeight ?? info.pixelHeight;
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    for (final (name, value) in <(String, int)>[
      ('width', width),
      ('height', height),
      ('pixelWidth', pixelWidth),
      ('pixelHeight', pixelHeight),
      ('sourceX', sourceX),
      ('sourceY', sourceY),
      ('sourceWidth', resolvedSourceWidth),
      ('sourceHeight', resolvedSourceHeight),
    ]) {
      final maximum = switch (name) {
        'width' || 'height' || 'pixelWidth' || 'pixelHeight' => 0x7FFFFFFF,
        _ => 0xFFFFFFFF,
      };
      _checkUnsignedAbi(value, maximum, name);
    }
    if (width <= 0 || height <= 0) {
      throw ArgumentError('image width and height must be positive');
    }
    if (x + width > 0x7FFFFFFF || y + height > 0x7FFFFFFF) {
      throw RangeError('image destination exceeds signed 32-bit bounds');
    }
    if (resolvedSourceWidth <= 0 || resolvedSourceHeight <= 0) {
      throw ArgumentError('image source width and height must be positive');
    }
    final hasClip =
        clipX != null ||
        clipY != null ||
        clipWidth != null ||
        clipHeight != null;
    if (hasClip &&
        (clipX == null ||
            clipY == null ||
            clipWidth == null ||
            clipHeight == null)) {
      throw ArgumentError(
        'clipX, clipY, clipWidth, and clipHeight must be supplied together',
      );
    }
    if (hasClip) {
      _checkSigned32Abi(clipX!, 'clipX');
      _checkSigned32Abi(clipY!, 'clipY');
      _checkUnsignedAbi(clipWidth!, 0xFFFFFFFF, 'clipWidth');
      _checkUnsignedAbi(clipHeight!, 0xFFFFFFFF, 'clipHeight');
    }
    if (_materializeImagesAsBlocks) {
      final left = hasClip ? math.max(x, clipX!) : x;
      final top = hasClip ? math.max(y, clipY!) : y;
      final right = hasClip
          ? math.min(x + width, clipX! + clipWidth!)
          : x + width;
      final bottom = hasClip
          ? math.min(y + height, clipY! + clipHeight!)
          : y + height;
      for (
        var row = math.max(0, top);
        row < math.min(this.height, bottom);
        row++
      ) {
        for (
          var column = math.max(0, left);
          column < math.min(this.width, right);
          column++
        ) {
          setCell(column, row, '▀', Color.white, Color.black, 0);
        }
      }
      return true;
    }
    if (hasClip) {
      _bindings.bufferPushScissorRect(
        _ptr,
        clipX!,
        clipY!,
        clipWidth!,
        clipHeight!,
      );
    }
    try {
      return _bindings.bufferDrawImage(
        _ptr,
        image.handle,
        x: x,
        y: y,
        width: width,
        height: height,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        sourceX: sourceX,
        sourceY: sourceY,
        sourceWidth: resolvedSourceWidth,
        sourceHeight: resolvedSourceHeight,
        protocol: protocol.index,
      );
    } finally {
      if (hasClip) _bindings.bufferPopScissorRect(_ptr);
    }
  }

  /// Resizes the buffer to [newWidth] by [newHeight] terminal cells.
  ///
  /// [newWidth] and [newHeight] must fit unsigned 32-bit values; violations
  /// throw a pre-invocation [RangeError] before the positive-dimensions
  /// [ArgumentError].
  void resize(int newWidth, int newHeight) {
    _checkValid();
    _checkUnsignedAbi(newWidth, 0xFFFFFFFF, 'newWidth');
    _checkUnsignedAbi(newHeight, 0xFFFFFFFF, 'newHeight');
    if (newWidth <= 0 || newHeight <= 0) {
      throw ArgumentError(
        'Invalid dimensions: width and height must be greater than 0',
      );
    }
    try {
      _bindings.bufferResize(_ptr, newWidth, newHeight);
    } finally {
      // OpenTUI reallocates every cell array during resize. Existing typed
      // list views must fail before their next read even if native resizing
      // reports an error after partially mutating storage.
      _validity.directAccessGeneration++;
    }
  }

  /// Get direct access to internal arrays for performance-critical operations.
  ///
  /// The returned object performs a lifecycle check before every native-memory
  /// read or write. It becomes unusable when this buffer is invalidated (for
  /// example by the next `Renderer.render()` call).
  DirectBufferAccess getDirectAccess() {
    _checkValid();
    final w = _bindings.getBufferWidth(_ptr);
    final h = _bindings.getBufferHeight(_ptr);
    final len = w * h;

    if (len == 0) {
      throw StateError('Buffer has zero size');
    }

    final charPtr = _bindings.bufferGetCharPtr(_ptr);
    final fgPtr = _bindings.bufferGetFgPtr(_ptr);
    final bgPtr = _bindings.bufferGetBgPtr(_ptr);
    final attrPtr = _bindings.bufferGetAttributesPtr(_ptr);

    return DirectBufferAccess._(
      owner: this,
      generation: _validity.directAccessGeneration,
      chars: charPtr.asTypedList(len),
      foregrounds: fgPtr.asTypedList(len * 4), // 4 u16 values per Color
      backgrounds: bgPtr.asTypedList(len * 4),
      attributes: attrPtr.asTypedList(len),
      width: w,
      height: h,
    );
  }

  /// Internal: raw native handle. Subject to invalidation; do not retain
  /// across frames or pass to user code. Validity-checked on read.
  @internal
  OptimizedBufferHandle get handle {
    _checkValid();
    return _ptr;
  }
}

/// Direct access to Buffer internal arrays for advanced operations.
class DirectBufferAccess {
  DirectBufferAccess._({
    required Buffer owner,
    required int generation,
    required Uint32List chars,
    required Uint16List foregrounds,
    required Uint16List backgrounds,
    required Uint32List attributes,
    required int width,
    required int height,
  }) : _owner = owner,
       _generation = generation,
       _chars = chars,
       _foregrounds = foregrounds,
       _backgrounds = backgrounds,
       _attributes = attributes,
       _width = width,
       _height = height;

  final Buffer _owner;
  final int _generation;
  final Uint32List _chars;
  final Uint16List _foregrounds;
  final Uint16List _backgrounds;
  final Uint32List _attributes;
  final int _width;
  final int _height;

  /// Width of the buffer in cells.
  int get width {
    _checkValid();
    return _width;
  }

  /// Height of the buffer in cells.
  int get height {
    _checkValid();
    return _height;
  }

  /// Get buffer length (width * height).
  int get length {
    _checkValid();
    return _width * _height;
  }

  /// Reads one native encoded cell word by row-major [cellIndex].
  ///
  /// A word may be a direct Unicode scalar or a native packed-grapheme value.
  int getEncodedCellAt(int cellIndex) {
    _checkCellIndex(cellIndex);
    return _chars[cellIndex];
  }

  /// Writes one native encoded cell word by row-major [cellIndex].
  void setEncodedCellAt(int cellIndex, int value) {
    _checkCellIndex(cellIndex);
    _checkUnsignedAbi(value, 0xFFFFFFFF, 'value');
    _chars[cellIndex] = value;
  }

  void _checkCellIndex(int cellIndex) {
    _checkValid();
    if (cellIndex < 0 || cellIndex >= _chars.length) {
      throw RangeError.range(cellIndex, 0, _chars.length - 1, 'cellIndex');
    }
  }

  /// Convert 2D coordinates to flat index.
  int _getIndex(int x, int y) {
    _checkValid();
    if (x < 0 || x >= _width || y < 0 || y >= _height) {
      throw RangeError(
        'Coordinates ($x, $y) out of bounds for ${_width}x$_height buffer',
      );
    }
    return y * _width + x;
  }

  void _checkValid() {
    _owner._checkDirectAccessGeneration(_generation);
  }

  /// Decodes a direct Unicode-scalar cell at the specified coordinates.
  ///
  /// Do not call this for a native packed-grapheme cell; use
  /// [getEncodedCellAt] when working with encoded cell words.
  String getChar(int x, int y) {
    final index = _getIndex(x, y);
    return String.fromCharCode(_chars[index]);
  }

  /// Stores the first Unicode scalar from a non-empty [char].
  void setChar(int x, int y, String char) {
    final index = _getIndex(x, y);
    if (char.isEmpty) throw ArgumentError('Character cannot be empty');

    _chars[index] = char.runes.first;
  }

  /// Get foreground color at the specified coordinates.
  Color getForeground(int x, int y) {
    final index = _getIndex(x, y);
    return _readRgba(_foregrounds, index);
  }

  /// Set foreground color at the specified coordinates.
  void setForeground(int x, int y, Color color) {
    final index = _getIndex(x, y);
    _writeRgba(_foregrounds, index, color);
  }

  /// Get background color at the specified coordinates.
  Color getBackground(int x, int y) {
    final index = _getIndex(x, y);
    return _readRgba(_backgrounds, index);
  }

  /// Set background color at the specified coordinates.
  void setBackground(int x, int y, Color color) {
    final index = _getIndex(x, y);
    _writeRgba(_backgrounds, index, color);
  }

  /// Get text attributes at the specified coordinates.
  int getAttributes(int x, int y) {
    final index = _getIndex(x, y);
    return _attributes[index];
  }

  /// Set text attributes at the specified coordinates.
  ///
  /// [attr] must fit an unsigned 32-bit value; violations throw [RangeError]
  /// before the native-memory store instead of silently truncating.
  void setAttributes(int x, int y, int attr) {
    final index = _getIndex(x, y);
    _checkUnsignedAbi(attr, 0xFFFFFFFF, 'attr');
    _attributes[index] = attr;
  }
}

/// A [Buffer] view that silently drops draw calls outside a clip rectangle.
///
/// Internal: created via [Buffer.clipped]. Shares the parent's validity
/// token so that invalidating the parent invalidates every view of it.
/// Coordinates stay in signed logical space and clip silently, while the
/// lifecycle and unsigned 32-bit attribute domains are validated even for
/// calls the clip rectangle drops.
class _ClippedBufferView extends Buffer {
  _ClippedBufferView(
    super.ptr,
    super.bindings,
    super.ownerIsDisposed,
    super.validity, {
    required super.materializeImagesAsBlocks,
    required this.clipX,
    required this.clipY,
    required this.clipWidth,
    required this.clipHeight,
  }) : super._withValidity();

  final int clipX;
  final int clipY;
  final int clipWidth;
  final int clipHeight;

  bool _inClip(int x, int y) =>
      x >= clipX &&
      x < clipX + clipWidth &&
      y >= clipY &&
      y < clipY + clipHeight;

  @override
  bool acceptsTextCluster(int x, int y, int clusterWidth) =>
      super.acceptsTextCluster(x, y, clusterWidth) &&
      _inClip(x, y) &&
      _inClip(x + clusterWidth - 1, y);

  @override
  void setCell(int x, int y, String char, Color fg, Color bg, int attributes) {
    _checkValid();
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    if (!_inClip(x, y)) return;
    super.setCell(x, y, char, fg, bg, attributes);
  }

  @override
  void setCellWithAlphaBlending(
    int x,
    int y,
    String char,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkValid();
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    if (!_inClip(x, y)) return;
    super.setCellWithAlphaBlending(x, y, char, fg, bg, attributes);
  }

  @override
  void fillRect(int x, int y, int w, int h, Color color) {
    _checkValid();
    final x0 = x < clipX ? clipX : x;
    final y0 = y < clipY ? clipY : y;
    final x1 = (x + w) > (clipX + clipWidth) ? clipX + clipWidth : (x + w);
    final y1 = (y + h) > (clipY + clipHeight) ? clipY + clipHeight : (y + h);
    if (x0 >= x1 || y0 >= y1) return;
    super.fillRect(x0, y0, x1 - x0, y1 - y0, color);
  }

  @override
  void drawText(
    String text,
    int x,
    int y,
    Color fg, {
    Color? bg,
    int attributes = 0,
  }) {
    _checkValid();
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    // drawText draws horizontally; clip per-row. The horizontal window is
    // computed in terminal cells over grapheme clusters (never UTF-16 code
    // units), so CJK and astral-plane clusters keep their true columns. A
    // wide cluster straddling either clip edge is dropped whole — the view
    // silently drops content outside the rectangle and never paints half a
    // cluster.
    if (y < clipY || y >= clipY + clipHeight) return;
    if (x >= clipX + clipWidth) return;
    var drawX = x;
    final leading = text.characters.iterator;
    while (drawX < clipX && leading.moveNext()) {
      drawX += terminalCellWidth(leading.current);
    }
    final visible = sliceByCells(
      leading.stringAfter,
      clipX + clipWidth - drawX,
    );
    if (visible.isEmpty) return;
    super.drawText(visible, drawX, y, fg, bg: bg, attributes: attributes);
  }

  /// Native `bufferDrawBox` ignores this view's clip rectangle, so a box that
  /// falls entirely outside the clip would still paint. Reject those here;
  /// everything else is handed to OpenTUI unchanged.
  ///
  /// A box that *straddles* a clip edge is still drawn unclipped. Deliberate:
  /// OpenTUI's own scissor stack does not fix it either, because
  /// `canUseTransparentBorderFastPath` writes border cells through an
  /// unchecked index whenever the box background is transparent — which is
  /// exactly the default `Border` case. Re-rasterizing the box in Dart would
  /// duplicate native glyph, corner, and title placement rules, so the
  /// straddling case stays a recorded limitation until the clip seam moves
  /// onto the native scissor.
  @override
  void drawBox(
    int x,
    int y,
    int width,
    int height,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) {
    _checkValid();
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    if (x + width <= clipX ||
        y + height <= clipY ||
        x >= clipX + clipWidth ||
        y >= clipY + clipHeight) {
      return;
    }
    super.drawBox(x, y, width, height, options, borderColor, backgroundColor);
  }
}
