import 'dart:ffi';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import 'color.dart';
import 'grapheme_metrics.dart';
import 'terminal_style.dart';
import 'text_buffer.dart';

const _rgbaChannelsPerCell = 4;
const _textBufferTransparentCell = Color(0.123, 0.234, 0.345, 0.456);
const _packedGraphemeMask = 0xC0000000;
const _packedGraphemeStart = 0x80000000;
const _packedGraphemeContinuation = 0xC0000000;
const _packedRightExtentShift = 28;
const _packedExtentMask = 0x3;
const _packedGraphemeIdMask = 0x03FFFFFF;

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

({Pointer<TextBufferHandle> textBufferHandle, bool hasClipRect})
_validateTextBufferDrawArguments(
  Buffer destination,
  TextBuffer textBuffer,
  int x,
  int y, {
  int? clipX,
  int? clipY,
  int? clipWidth,
  int? clipHeight,
}) {
  destination._checkValid();
  final textBufferHandle = textBuffer.handle;
  _checkSigned32Abi(x, 'x');
  _checkSigned32Abi(y, 'y');
  if (clipX != null) _checkSigned32Abi(clipX, 'clipX');
  if (clipY != null) _checkSigned32Abi(clipY, 'clipY');
  if (clipWidth != null) {
    _checkUnsignedAbi(clipWidth, 0xFFFFFFFF, 'clipWidth');
  }
  if (clipHeight != null) {
    _checkUnsignedAbi(clipHeight, 0xFFFFFFFF, 'clipHeight');
  }
  final hasClipRect =
      clipX != null && clipY != null && clipWidth != null && clipHeight != null;
  return (textBufferHandle: textBufferHandle, hasClipRect: hasClipRect);
}

int _rgbaOffset(int cellIndex) => cellIndex * _rgbaChannelsPerCell;

Color _readRgba(Float32List values, int cellIndex) {
  final offset = _rgbaOffset(cellIndex);
  return Color(
    values[offset],
    values[offset + 1],
    values[offset + 2],
    values[offset + 3],
  );
}

void _writeRgba(Float32List values, int cellIndex, Color color) {
  final offset = _rgbaOffset(cellIndex);
  values[offset] = color.r;
  values[offset + 1] = color.g;
  values[offset + 2] = color.b;
  values[offset + 3] = color.a;
}

bool _isPackedGraphemeStart(int code) =>
    (code & _packedGraphemeMask) == _packedGraphemeStart;

bool _isPackedGraphemeContinuation(int code) =>
    (code & _packedGraphemeMask) == _packedGraphemeContinuation;

int _packedGraphemeId(int code) => code & _packedGraphemeIdMask;

int _packedRightExtent(int code) =>
    (code >> _packedRightExtentShift) & _packedExtentMask;

/// Shared validity flag for a [Buffer] and every view ([Buffer.clipped]) of
/// it. Renderer-driven invalidation (after `render`, `resize`, or `dispose`)
/// flips this once and every consumer fails on the next access.
class _BufferValidity {
  bool isValid = true;
}

/// Creates a buffer wrapper for a native frame owned by the renderer.
@internal
Buffer createBufferFromNative(
  Pointer<OptimizedBufferHandle> pointer,
  OpenTuiBindings bindings,
) => Buffer._(pointer, bindings);

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
/// final buffer = renderer.getNextBuffer();
///
/// // Clear to dark background
/// buffer.clear(Color.fromHex('#1A202C'));
///
/// // Draw a bordered panel
/// buffer.drawBox(5, 2, 30, 15,
///     BoxOptions(sides: BorderSides.all(), title: 'Settings'),
///     Color.cyan, Color.darkGray);
///
/// // Add content text
/// buffer.drawText('Welcome to OpenTUI!', 10, 5, Color.white);
///
/// // Create a progress bar
/// buffer.fillRect(10, 8, 20, 1, Color.green);
/// ```
class Buffer {
  Buffer._(this._ptr, this._bindings) : _validity = _BufferValidity();

  Buffer._withValidity(this._ptr, this._bindings, this._validity);
  final OpenTuiBindings _bindings;
  final Pointer<OptimizedBufferHandle> _ptr;
  final _BufferValidity _validity;

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
    _validity,
    clipX: clipX,
    clipY: clipY,
    clipWidth: clipWidth,
    clipHeight: clipHeight,
  );

  void _checkValid() {
    if (!_validity.isValid) {
      throw StateError(
        'Buffer has been invalidated. Get a fresh buffer from renderer.nextBuffer.',
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
  bool get isInvalidated => !_validity.isValid;

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
  ///     bg: Color.yellow, attributes: TextAttribute.bold);
  /// ```
  ///
  /// [x] and [y] must fit unsigned 32-bit values and [attributes] an unsigned
  /// 8-bit value; violations throw a pre-invocation [RangeError] after the
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
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
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
  ///     BoxOptions(sides: BorderSides.all()),
  ///     Color.white, Color.transparent);
  ///
  /// // Dialog with title
  /// buffer.drawBox(15, 8, 35, 18,
  ///     BoxOptions(
  ///         sides: BorderSides.all(),
  ///         title: 'Confirm Action',
  ///         titleAlignment: TextAlign.center,
  ///         fill: true
  ///     ), Color.cyan, Color.darkBlue);
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
  /// [attributes] must fit an unsigned 8-bit value; a violation throws a
  /// pre-invocation [RangeError] after the lifecycle, character, and bounds
  /// checks.
  void setCell(int x, int y, String char, Color fg, Color bg, int attributes) {
    setCellWithAlphaBlending(x, y, char, fg, bg, attributes);
  }

  /// Sets a cell at (x, y) with full alpha-blending support.
  ///
  /// [attributes] must fit an unsigned 8-bit value; a violation throws a
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
  /// 8-bit [attributes] domain check. [charCode] is a Unicode scalar or a
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
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');

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
    _bindings.bufferResize(_ptr, newWidth, newHeight);
  }

  /// Get direct access to internal arrays for performance-critical operations.
  ///
  /// **WARNING**: The returned [DirectBufferAccess] contains views into native
  /// memory. These views are only valid until the buffer is invalidated (i.e.,
  /// until the next call to [Renderer.render()]). Accessing the views after
  /// invalidation may cause runtime failure or undefined behavior.
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

    return DirectBufferAccess(
      chars: charPtr.asTypedList(len),
      foregrounds: fgPtr.asTypedList(len * 4), // 4 floats per Color
      backgrounds: bgPtr.asTypedList(len * 4),
      attributes: attrPtr.asTypedList(len),
      width: w,
      height: h,
    );
  }

  /// Draw a [TextBuffer] to this buffer.
  ///
  /// [x], [y], and supplied [clipX]/[clipY] values must fit signed 32-bit
  /// integers. Supplied [clipWidth]/[clipHeight] values must fit unsigned
  /// 32-bit integers. Invalid destination or source lifecycles take precedence
  /// over these pre-invocation [RangeError] checks.
  void drawTextBuffer(
    TextBuffer textBuffer,
    int x,
    int y, {
    int? clipX,
    int? clipY,
    int? clipWidth,
    int? clipHeight,
  }) {
    final validation = _validateTextBufferDrawArguments(
      this,
      textBuffer,
      x,
      y,
      clipX: clipX,
      clipY: clipY,
      clipWidth: clipWidth,
      clipHeight: clipHeight,
    );
    _bindings.bufferDrawTextBuffer(
      _ptr,
      validation.textBufferHandle,
      x,
      y,
      clipX ?? 0,
      clipY ?? 0,
      clipWidth ?? 0,
      clipHeight ?? 0,
      validation.hasClipRect,
    );
  }

  /// Internal: raw native handle. Subject to invalidation; do not retain
  /// across frames or pass to user code. Validity-checked on read.
  @internal
  Pointer<OptimizedBufferHandle> get handle {
    _checkValid();
    return _ptr;
  }
}

/// Direct access to Buffer internal arrays for performance-critical operations
class DirectBufferAccess {
  /// Bundles cell-array views and dimensions for direct buffer operations.
  const DirectBufferAccess({
    required this.chars,
    required this.foregrounds,
    required this.backgrounds,
    required this.attributes,
    required this.width,
    required this.height,
  });

  /// Unicode code points for each cell in row-major order.
  final Uint32List chars;

  /// Foreground [Color] channels packed as four floats per cell (RGBA).
  final Float32List foregrounds;

  /// Background [Color] channels packed as four floats per cell (RGBA).
  final Float32List backgrounds;

  /// Text attributes bitmask for each cell.
  final Uint8List attributes;

  /// Width of the buffer in cells.
  final int width;

  /// Height of the buffer in cells.
  final int height;

  /// Get buffer length (width * height)
  int get length => width * height;

  /// Convert 2D coordinates to flat index
  int _getIndex(int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      throw RangeError(
        'Coordinates ($x, $y) out of bounds for ${width}x$height buffer',
      );
    }
    return y * width + x;
  }

  /// Get a character at the specified coordinates
  String getChar(int x, int y) {
    final index = _getIndex(x, y);
    return String.fromCharCode(chars[index]);
  }

  /// Set a character at the specified coordinates
  void setChar(int x, int y, String char) {
    final index = _getIndex(x, y);
    if (char.isEmpty) throw ArgumentError('Character cannot be empty');

    chars[index] = char.runes.first;
  }

  /// Get foreground color at the specified coordinates
  Color getForeground(int x, int y) {
    final index = _getIndex(x, y);
    return _readRgba(foregrounds, index);
  }

  /// Set foreground color at the specified coordinates
  void setForeground(int x, int y, Color color) {
    final index = _getIndex(x, y);
    _writeRgba(foregrounds, index, color);
  }

  /// Get background color at the specified coordinates
  Color getBackground(int x, int y) {
    final index = _getIndex(x, y);
    return _readRgba(backgrounds, index);
  }

  /// Set background color at the specified coordinates
  void setBackground(int x, int y, Color color) {
    final index = _getIndex(x, y);
    _writeRgba(backgrounds, index, color);
  }

  /// Get text attributes at the specified coordinates
  int getAttributes(int x, int y) {
    final index = _getIndex(x, y);
    return attributes[index];
  }

  /// Set text attributes at the specified coordinates.
  ///
  /// [attr] must fit an unsigned 8-bit value; violations throw [RangeError]
  /// before the native-memory store instead of silently truncating.
  void setAttributes(int x, int y, int attr) {
    final index = _getIndex(x, y);
    _checkUnsignedAbi(attr, 0xFF, 'attr');
    attributes[index] = attr;
  }
}

/// A [Buffer] view that silently drops draw calls outside a clip rectangle.
///
/// Internal: created via [Buffer.clipped]. Shares the parent's validity
/// token so that invalidating the parent invalidates every view of it.
/// Coordinates stay in signed logical space and clip silently, while the
/// lifecycle and unsigned 8-bit attribute domains are validated even for
/// calls the clip rectangle drops.
class _ClippedBufferView extends Buffer {
  _ClippedBufferView(
    super.ptr,
    super.bindings,
    super.validity, {
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
  void setCell(int x, int y, String char, Color fg, Color bg, int attributes) {
    _checkValid();
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
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
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
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
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
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

  /// Draws [textBuffer] through this clipped view.
  ///
  /// Destination and source lifecycle checks precede signed 32-bit [x], [y],
  /// [clipX], and [clipY] validation and unsigned 32-bit [clipWidth] and
  /// [clipHeight] validation. Every supplied clip value is checked even when
  /// the all-four-fields clip rectangle is inactive. The source must have
  /// finalized line metadata; stale metadata surfaces as the source's
  /// [StateError].
  @override
  void drawTextBuffer(
    TextBuffer textBuffer,
    int x,
    int y, {
    int? clipX,
    int? clipY,
    int? clipWidth,
    int? clipHeight,
  }) {
    final validation = _validateTextBufferDrawArguments(
      this,
      textBuffer,
      x,
      y,
      clipX: clipX,
      clipY: clipY,
      clipWidth: clipWidth,
      clipHeight: clipHeight,
    );
    final snapshot = textBuffer.compositingSnapshotFromCapturedHandle(
      validation.textBufferHandle,
    );
    if (this.clipWidth <= 0 || this.clipHeight <= 0) return;

    final extents = _textBufferExtents(snapshot);
    final sourceX = clipX ?? 0;
    final sourceY = clipY ?? 0;
    final visibleSourceWidth = this.clipX + this.clipWidth - x;
    final visibleSourceHeight = this.clipY + this.clipHeight - y;
    final inferredSourceWidth = extents.width - sourceX;
    final inferredSourceHeight = extents.height - sourceY;
    final sourceWidth =
        clipWidth ??
        (inferredSourceWidth > visibleSourceWidth
            ? inferredSourceWidth
            : visibleSourceWidth);
    final sourceHeight =
        clipHeight ??
        (inferredSourceHeight > visibleSourceHeight
            ? inferredSourceHeight
            : visibleSourceHeight);
    if (sourceWidth <= 0 || sourceHeight <= 0) return;

    final destLeft = x;
    final destTop = y;
    final destRight = x + sourceWidth;
    final destBottom = y + sourceHeight;

    final viewLeft = this.clipX;
    final viewTop = this.clipY;
    final viewRight = this.clipX + this.clipWidth;
    final viewBottom = this.clipY + this.clipHeight;

    final clippedLeft = destLeft < viewLeft ? viewLeft : destLeft;
    final clippedTop = destTop < viewTop ? viewTop : destTop;
    final clippedRight = destRight > viewRight ? viewRight : destRight;
    final clippedBottom = destBottom > viewBottom ? viewBottom : destBottom;
    if (clippedLeft >= clippedRight || clippedTop >= clippedBottom) return;

    _copyTextBufferCells(
      snapshot,
      clippedLeft,
      clippedTop,
      sourceX + (clippedLeft - destLeft),
      sourceY + (clippedTop - destTop),
      clippedRight - clippedLeft,
      clippedBottom - clippedTop,
    );
  }

  /// Copies snapshot cells to this view through [_setTextBufferCell].
  ///
  /// Snapshot attributes are native `u16` words, yet every value observed
  /// here fits the unsigned 8-bit cell domain: `TextBuffer.writeChunk` caps
  /// attributes at 0xFF before writing, the native TextBuffer `setCell` path
  /// stores `attributes & ATTR_MASK` (0xFF), and the `USE_DEFAULT_*` high
  /// bits accompany only null color pointers, which this package never
  /// passes. No mask is applied here; a violated invariant surfaces as the
  /// shared funnel's [RangeError] instead of silently diverging from the
  /// native `USE_DEFAULT_ATTR` semantics.
  void _copyTextBufferCells(
    ({DirectTextAccess access, List<int> lineStarts, List<int> lineWidths})
    snapshot,
    int destX,
    int destY,
    int sourceX,
    int sourceY,
    int drawWidth,
    int drawHeight,
  ) {
    final access = snapshot.access;
    final lineStarts = snapshot.lineStarts;
    final lineWidths = snapshot.lineWidths;

    for (var row = 0; row < drawHeight; row++) {
      final sourceRow = sourceY + row;
      if (sourceRow < 0 ||
          sourceRow >= lineStarts.length ||
          sourceRow >= lineWidths.length) {
        continue;
      }

      final lineStart = lineStarts[sourceRow];
      final lineWidth = lineWidths[sourceRow];
      int? lastDrawnGraphemeId;
      for (var col = 0; col < drawWidth; col++) {
        final sourceCol = sourceX + col;
        if (sourceCol < 0 || sourceCol >= lineWidth) {
          continue;
        }

        final sourceIndex = lineStart + sourceCol;
        if (sourceIndex < 0 || sourceIndex >= access.length) {
          continue;
        }

        final code = access.encodedCells[sourceIndex];
        if (code == 0 || code == 10) {
          continue;
        }

        final destCellX = destX + col;
        final destCellY = destY + row;
        final bg = _readTextBufferBackground(access, sourceIndex);
        final fg = _readRgba(access.foregrounds, sourceIndex);
        final attributes = access.attributes[sourceIndex];

        if (_isPackedGraphemeContinuation(code)) {
          final graphemeId = _packedGraphemeId(code);
          if (graphemeId == lastDrawnGraphemeId) {
            continue;
          }
          _setTextBufferCell(destCellX, destCellY, 32, fg, bg, attributes);
          continue;
        }

        if (_isPackedGraphemeStart(code)) {
          final width = 1 + _packedRightExtent(code);
          if (sourceCol + width > sourceX + drawWidth) {
            _setTextBufferCell(destCellX, destCellY, 32, fg, bg, attributes);
            continue;
          }
          lastDrawnGraphemeId = _packedGraphemeId(code);
        } else {
          lastDrawnGraphemeId = null;
        }

        _setTextBufferCell(destCellX, destCellY, code, fg, bg, attributes);
      }
    }
  }

  Color _readTextBufferBackground(DirectTextAccess access, int sourceIndex) {
    final bg = _readRgba(access.backgrounds, sourceIndex);
    return bg.a == 0 ? _textBufferTransparentCell : bg;
  }

  /// Compositing seam into the shared supported-tier funnel; the funnel's
  /// unsigned 8-bit attribute check owns rejection for this seam.
  void _setTextBufferCell(
    int x,
    int y,
    int charCode,
    Color fg,
    Color bg,
    int attributes,
  ) {
    super._setCellCodeWithAlphaBlending(x, y, charCode, fg, bg, attributes);
  }

  ({int width, int height}) _textBufferExtents(
    ({DirectTextAccess access, List<int> lineStarts, List<int> lineWidths})
    snapshot,
  ) {
    if (snapshot.lineWidths.isNotEmpty) {
      var width = 0;
      for (final lineWidth in snapshot.lineWidths) {
        if (lineWidth > width) {
          width = lineWidth;
        }
      }
      return (width: width, height: snapshot.lineStarts.length);
    }
    return (width: snapshot.access.length, height: 1);
  }
}
