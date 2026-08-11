// ignore_for_file: avoid_positional_boolean_parameters
import 'dart:convert' as convert;
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/terminal_style.dart';
import 'library.dart';
import 'native_symbols.dart';
import 'types.dart';

Pointer<Float> _colorToNative(Color color, Allocator alloc) {
  final pointer = alloc<Float>(4);
  pointer[0] = color.r;
  pointer[1] = color.g;
  pointer[2] = color.b;
  pointer[3] = color.a;
  return pointer;
}

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

/// Requires [value] to fit the unsigned 32-bit OpenTUI ABI domain.
@internal
void validateUnsigned32Abi(int value, String name) {
  _checkUnsignedAbi(value, 0xFFFFFFFF, name);
}

Pointer<Uint8> _copyBytes(Allocator alloc, List<int> bytes) {
  final pointer = alloc<Uint8>(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    pointer[i] = bytes[i];
  }
  return pointer;
}

int _boxOptionsToNative(BoxOptions options) {
  var packed = 0;
  if (options.sides.top) packed |= 0x8;
  if (options.sides.right) packed |= 0x4;
  if (options.sides.bottom) packed |= 0x2;
  if (options.sides.left) packed |= 0x1;
  if (options.fill) packed |= 1 << 4;
  final alignment = switch (options.titleAlignment) {
    TextAlign.left => 0,
    TextAlign.center => 1,
    TextAlign.right => 2,
  };
  return packed | ((alignment & 0x3) << 5);
}

/// Requires renderer dimensions between 1 and the unsigned 32-bit maximum.
///
/// Non-positive values use [ArgumentError] to preserve the renderer contract;
/// larger values use [RangeError] before OpenTUI's unsigned extent boundary.
@internal
void validateRendererDimensions(int width, int height) {
  if (width <= 0) {
    throw ArgumentError.value(width, 'width', 'must be greater than zero');
  }
  _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
  if (height <= 0) {
    throw ArgumentError.value(height, 'height', 'must be greater than zero');
  }
  _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
}

/// Guarded Dart wrapper around the generated OpenTUI FFI surface.
class OpenTuiBindings {
  /// Opens the configured native library for guarded OpenTUI operations.
  OpenTuiBindings() {
    _generated = OpenTuiNativeLibrary.open();
  }
  late final OpenTuiNativeSymbols _generated;

  // --- Internal helpers --------------------------------------------------
  // Consolidates the try/catch + arena allocation + UTF-8 marshalling that
  // every public method below would otherwise repeat verbatim.

  T _guard<T>(String operation, T Function() body) {
    try {
      return body();
    } catch (e) {
      throw FFIException('$operation: $e');
    }
  }

  T _guardAlloc<T>(String operation, T Function(Allocator alloc) body) =>
      using((alloc) => _guard(operation, () => body(alloc)));

  Pointer<U> _checkNonNull<U extends NativeType>(
    String operation,
    Pointer<U> ptr,
  ) {
    if (ptr == nullptr) {
      throw FFIException('$operation: returned null pointer');
    }
    return ptr;
  }

  /// Encodes [text] as UTF-8 into a native buffer and returns the pointer
  /// together with its byte length. Most FFI calls need both.
  (Pointer<Uint8>, int) _utf8(Allocator alloc, String text) {
    final bytes = convert.utf8.encode(text);
    return (_copyBytes(alloc, bytes), bytes.length);
  }

  // -----------------------------------------------------------------------

  // Renderer management
  /// Creates a native renderer of [width]×[height] and returns its handle.
  ///
  /// [width] and [height] must be between 1 and the unsigned 32-bit maximum.
  /// Non-positive values throw [ArgumentError]; larger values throw a
  /// pre-invocation [RangeError]. Throws [FFIException] on a null result.
  Pointer<RendererHandle> createRenderer(
    int width,
    int height, {
    bool testing = false,
  }) {
    validateRendererDimensions(width, height);
    return _guard('Failed to create renderer', () {
      final ptr = _checkNonNull(
        'Failed to create renderer',
        _generated.createRenderer(width, height, testing),
      );
      return ptr.cast<RendererHandle>();
    });
  }

  /// Destroys [renderer], optionally restoring the main screen and reserving
  /// [splitHeight] rows. [splitHeight] must fit an unsigned 32-bit value;
  /// violations throw a pre-invocation [RangeError]. Throws [FFIException] on
  /// failure.
  void destroyRenderer(
    Pointer<RendererHandle> renderer, {
    bool useAlternateScreen = false,
    int splitHeight = 0,
  }) {
    validateUnsigned32Abi(splitHeight, 'splitHeight');
    _guard('Failed to destroy renderer', () {
      _generated.destroyRenderer(
        renderer.cast(),
        useAlternateScreen,
        splitHeight,
      );
    });
  }

  /// Renders [renderer]'s current frame to the terminal, redrawing everything
  /// when [force] is true. Throws [FFIException] on failure.
  void render(Pointer<RendererHandle> renderer, bool force) {
    _guard('Failed to render', () {
      _generated.render(renderer.cast(), force);
    });
  }

  /// Returns [renderer]'s next (back) buffer handle for drawing.
  /// Throws [FFIException] on a null result.
  Pointer<OptimizedBufferHandle> getNextBuffer(
    Pointer<RendererHandle> renderer,
  ) => _guard('Failed to get next buffer', () {
    final ptr = _checkNonNull(
      'Failed to get next buffer',
      _generated.getNextBuffer(renderer.cast()),
    );
    return ptr.cast<OptimizedBufferHandle>();
  });

  /// Returns [renderer]'s current (front) buffer handle.
  /// Throws [FFIException] on a null result.
  Pointer<OptimizedBufferHandle> getCurrentBuffer(
    Pointer<RendererHandle> renderer,
  ) => _guard('Failed to get current buffer', () {
    final ptr = _checkNonNull(
      'Failed to get current buffer',
      _generated.getCurrentBuffer(renderer.cast()),
    );
    return ptr.cast<OptimizedBufferHandle>();
  });

  /// Resizes [renderer] and its buffers to [width]×[height].
  ///
  /// [width] and [height] must be between 1 and the unsigned 32-bit maximum.
  /// Non-positive values throw [ArgumentError]; larger values throw a
  /// pre-invocation [RangeError]. Throws [FFIException] on native failure.
  void resizeRenderer(Pointer<RendererHandle> renderer, int width, int height) {
    validateRendererDimensions(width, height);
    _guard('Failed to resize renderer', () {
      _generated.resizeRenderer(renderer.cast(), width, height);
    });
  }

  /// Sets [renderer]'s clear/background [color]. Throws [FFIException] on
  /// failure.
  void setBackgroundColor(Pointer<RendererHandle> renderer, Color color) {
    _guardAlloc('Failed to set background color', (alloc) {
      _generated.setBackgroundColor(
        renderer.cast(),
        _colorToNative(color, alloc),
      );
    });
  }

  /// Clears the terminal driven by [renderer]. Throws [FFIException] on
  /// failure.
  void clearTerminal(Pointer<RendererHandle> renderer) {
    _guard('Failed to clear terminal', () {
      _generated.clearTerminal(renderer.cast());
    });
  }

  // Buffer management
  /// Returns the width of [buffer] in cells. Throws [FFIException] on failure.
  int getBufferWidth(Pointer<OptimizedBufferHandle> buffer) => _guard(
    'Failed to get buffer width',
    () => _generated.getBufferWidth(buffer.cast()),
  );

  /// Returns the height of [buffer] in cells. Throws [FFIException] on failure.
  int getBufferHeight(Pointer<OptimizedBufferHandle> buffer) => _guard(
    'Failed to get buffer height',
    () => _generated.getBufferHeight(buffer.cast()),
  );

  /// Clears every cell of [buffer] to the [bg] color. Throws [FFIException] on
  /// failure.
  void bufferClear(Pointer<OptimizedBufferHandle> buffer, Color bg) {
    _guardAlloc('Failed to clear buffer', (alloc) {
      _generated.bufferClear(buffer.cast(), _colorToNative(bg, alloc));
    });
  }

  /// Draws UTF-8 [text] at ([x],[y]) into [buffer] with [fg]/[bg] colors and
  /// packed [attributes]. A null [bg] is passed as a null pointer (transparent).
  /// The pinned export swallows native text-drawing errors, so they are not
  /// observable. The encoded text byte length crosses as a native `usize`, so
  /// no narrowing check applies to it. [x] and [y] must fit unsigned 32-bit
  /// values and [attributes] an unsigned 8-bit value; violations throw a
  /// pre-invocation [RangeError]. Dart-side marshalling or invocation
  /// exceptions are mapped to [FFIException].
  void bufferDrawText(
    Pointer<OptimizedBufferHandle> buffer,
    String text,
    int x,
    int y,
    Color fg,
    Color? bg,
    int attributes,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
    _guardAlloc('Failed to draw text', (alloc) {
      final (textPtr, textLen) = _utf8(alloc, text);
      final fgPtr = _colorToNative(fg, alloc);
      final bgPtr = bg == null ? nullptr : _colorToNative(bg, alloc);

      _generated.bufferDrawText(
        buffer.cast(),
        textPtr,
        textLen,
        x,
        y,
        fgPtr,
        bgPtr,
        attributes,
      );
    });
  }

  /// Fills the [width]×[height] rectangle at ([x],[y]) in [buffer] with the
  /// [bg] color. The pinned export swallows native fill errors, so they are
  /// not observable. [x], [y], [width], and [height] must fit unsigned 32-bit
  /// values; violations throw a pre-invocation [RangeError]. Dart-side
  /// marshalling or invocation exceptions are mapped to [FFIException].
  void bufferFillRect(
    Pointer<OptimizedBufferHandle> buffer,
    int x,
    int y,
    int width,
    int height,
    Color bg,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _guardAlloc('Failed to fill rect', (alloc) {
      _generated.bufferFillRect(
        buffer.cast(),
        x,
        y,
        width,
        height,
        _colorToNative(bg, alloc),
      );
    });
  }

  /// Draws a [width]×[height] box at ([x],[y]) into [buffer] using the border
  /// glyphs, packed flags, and optional title from [options], with
  /// [borderColor] and [backgroundColor]. Defaults to single-line border chars
  /// when [options] does not supply all 11. The pinned export swallows native
  /// box-drawing errors, so they are not observable. [x] and [y] must fit
  /// signed 32-bit values; [width], [height], each selected border character,
  /// and the encoded title byte length must fit unsigned 32-bit values;
  /// violations throw a pre-invocation [RangeError]. The packed options word
  /// stays at most 0x7F by construction, so it crosses unchecked. Dart-side
  /// marshalling or invocation exceptions are mapped to [FFIException].
  void bufferDrawBox(
    Pointer<OptimizedBufferHandle> buffer,
    int x,
    int y,
    int width,
    int height,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    const defaultBorderChars = <int>[
      0x250C, 0x2510, 0x2514, 0x2518, 0x2500, 0x2502, // corners and lines
      0x252C, 0x2534, 0x251C, 0x2524, 0x253C, // T junctions and cross
    ];

    final provided = options.borderChars;
    final borderChars = (provided != null && provided.length == 11)
        ? provided
        : defaultBorderChars;

    for (final borderChar in borderChars) {
      _checkUnsignedAbi(borderChar, 0xFFFFFFFF, 'borderChars');
    }
    final titleBytes = convert.utf8.encode(options.title ?? '');
    final titleLen = titleBytes.length;
    _checkUnsignedAbi(titleLen, 0xFFFFFFFF, 'title');

    _guardAlloc('Failed to draw box', (alloc) {
      // OpenTUI expects 11 code points in this order:
      // [topLeft, topRight, bottomLeft, bottomRight, horizontal, vertical, topT, bottomT, leftT, rightT, cross]
      final borderPtr = alloc<Uint32>(borderChars.length);
      for (var i = 0; i < borderChars.length; i++) {
        borderPtr[i] = borderChars[i];
      }

      final titlePtr = _copyBytes(alloc, titleBytes);

      _generated.bufferDrawBox(
        buffer.cast(),
        x,
        y,
        width,
        height,
        borderPtr,
        _boxOptionsToNative(options),
        _colorToNative(borderColor, alloc),
        _colorToNative(backgroundColor, alloc),
        titlePtr,
        titleLen,
      );
    });
  }

  // Cursor management
  /// Moves [renderer]'s terminal cursor to ([x],[y]) and sets its [visible]
  /// state. [x] and [y] must fit signed 32-bit values; violations throw a
  /// pre-invocation [RangeError]. Throws [FFIException] on failure.
  void setCursorPosition(
    Pointer<RendererHandle> renderer,
    int x,
    int y,
    bool visible,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _guard('Failed to set cursor position', () {
      _generated.setCursorPosition(renderer.cast(), x, y, visible);
    });
  }

  /// Sets [renderer]'s cursor shape to [style] with optional [blinking].
  /// Throws [FFIException] on failure.
  void setCursorStyle(
    Pointer<RendererHandle> renderer,
    String style,
    bool blinking,
  ) {
    _guardAlloc('Failed to set cursor style', (alloc) {
      final (stylePtr, styleLen) = _utf8(alloc, style);
      _generated.setCursorStyle(renderer.cast(), stylePtr, styleLen, blinking);
    });
  }

  /// Sets [renderer]'s cursor [color]. Throws [FFIException] on failure.
  void setCursorColor(Pointer<RendererHandle> renderer, Color color) {
    _guardAlloc('Failed to set cursor color', (alloc) {
      _generated.setCursorColor(renderer.cast(), _colorToNative(color, alloc));
    });
  }

  // TextBuffer functions
  /// Calls native ABI 2 to create a text buffer.
  ///
  /// ABI 2 keeps two required integers. The first slot, [abiLength], is
  /// ignored by the pinned native implementation, so ordinary raw callers
  /// pass zero in that slot. The second value, [widthMethod], is the native
  /// width-method identifier.
  /// Native initialization may return `nullptr`; the supported `TextBuffer`
  /// wrapper maps null to [StateError]. Dart-side marshalling or invocation
  /// exceptions are mapped to [FFIException]. [abiLength] must fit unsigned
  /// 32-bit and [widthMethod] unsigned 8-bit values; either violation throws a
  /// pre-invocation [RangeError].
  Pointer<TextBufferHandle> createTextBuffer(int abiLength, int widthMethod) {
    _checkUnsignedAbi(abiLength, 0xFFFFFFFF, 'abiLength');
    _checkUnsignedAbi(widthMethod, 0xFF, 'widthMethod');
    return _guard(
      'Failed to create text buffer',
      () => _generated
          .createTextBuffer(abiLength, widthMethod)
          .cast<TextBufferHandle>(),
    );
  }

  /// Destroys [textBuffer]. The native export is status-free `void`, so native
  /// failure is not reported separately. Dart-side marshalling or invocation
  /// exceptions are mapped to [FFIException].
  void destroyTextBuffer(Pointer<TextBufferHandle> textBuffer) {
    _guard('Failed to destroy text buffer', () {
      _generated.destroyTextBuffer(textBuffer.cast());
    });
  }

  /// Returns [textBuffer]'s native logical cell count. The native export has
  /// no native failure status. Dart-side marshalling or invocation exceptions
  /// are mapped to [FFIException].
  int textBufferGetLength(Pointer<TextBufferHandle> textBuffer) => _guard(
    'Failed to get text buffer length',
    () => _generated.textBufferGetLength(textBuffer.cast()),
  );

  /// Sets one cell; [charCode] is one raw cell word. Native allocation or
  /// update errors are swallowed by the pinned export and are not observable.
  /// [index] and [charCode] must fit unsigned 32-bit values and [attributes]
  /// an unsigned 16-bit value; violations throw pre-invocation [RangeError].
  /// Dart-side marshalling or invocation exceptions are mapped to [FFIException].
  void textBufferSetCell(
    Pointer<TextBufferHandle> textBuffer,
    int index,
    int charCode,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkUnsignedAbi(index, 0xFFFFFFFF, 'index');
    _checkUnsignedAbi(charCode, 0xFFFFFFFF, 'charCode');
    _checkUnsignedAbi(attributes, 0xFFFF, 'attributes');
    _guardAlloc('Failed to set text buffer cell', (alloc) {
      _generated.textBufferSetCell(
        textBuffer.cast(),
        index,
        charCode,
        _colorToNative(fg, alloc),
        _colorToNative(bg, alloc),
        attributes,
      );
    });
  }

  /// Appends UTF-8 [text] and returns an opaque native write result.
  /// [attributes] must fit unsigned 8-bit and the encoded [text] byte length
  /// unsigned 32-bit values; violations throw pre-invocation [RangeError].
  /// Dart-side marshalling or invocation exceptions are mapped to [FFIException];
  /// native write failure may be represented only inside the opaque result,
  /// including zero.
  int textBufferWriteChunk(
    Pointer<TextBufferHandle> textBuffer,
    String text,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
    final bytes = convert.utf8.encode(text);
    _checkUnsignedAbi(bytes.length, 0xFFFFFFFF, 'text');
    return _guardAlloc('Failed to write text buffer chunk', (alloc) {
      final textPtr = _copyBytes(alloc, bytes);
      final attrPtr = alloc<Uint8>()..value = attributes;
      return _generated.textBufferWriteChunk(
        textBuffer.cast(),
        textPtr,
        bytes.length,
        _colorToNative(fg, alloc),
        _colorToNative(bg, alloc),
        attrPtr,
      );
    });
  }

  /// Appends [textLen] caller-owned UTF-8 [textBytes] and returns an opaque
  /// native write result. The caller owns persistent bytes for the call.
  /// [textLen] must fit unsigned 32-bit and [attributes] unsigned 8-bit values;
  /// violations throw pre-invocation [RangeError].
  /// Dart-side marshalling or invocation exceptions are mapped to [FFIException];
  /// native write failure may be represented only inside the opaque result,
  /// including zero.
  int textBufferWriteUtf8Chunk(
    Pointer<TextBufferHandle> textBuffer,
    Pointer<Uint8> textBytes,
    int textLen,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkUnsignedAbi(textLen, 0xFFFFFFFF, 'textLen');
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
    return _guardAlloc('Failed to write text buffer UTF-8 chunk', (alloc) {
      final attrPtr = alloc<Uint8>()..value = attributes;
      return _generated.textBufferWriteChunk(
        textBuffer.cast(),
        textBytes,
        textLen,
        _colorToNative(fg, alloc),
        _colorToNative(bg, alloc),
        attrPtr,
      );
    });
  }

  /// Finalizes [textBuffer]'s line metadata through a status-free `void`
  /// export with no native failure status. Dart-side marshalling or invocation
  /// exceptions are mapped to [FFIException].
  void textBufferFinalizeLineInfo(Pointer<TextBufferHandle> textBuffer) {
    _guard('TextBuffer finalize failed', () {
      _generated.textBufferFinalizeLineInfo(textBuffer.cast());
    });
  }

  /// Returns [textBuffer]'s current native line count. Cache-construction
  /// failure has no separate status. Dart-side marshalling or invocation
  /// exceptions are mapped to [FFIException]. The count derives from live
  /// native lines and can exceed the cached line-metadata arrays until the
  /// next finalize-and-refresh; the supported `TextBuffer` wrapper owns the
  /// finalize-before-read rule.
  int textBufferGetLineCount(Pointer<TextBufferHandle> textBuffer) => _guard(
    'TextBuffer line count query failed',
    () => _generated.textBufferGetLineCount(textBuffer.cast()),
  );

  /// Returns a native-owned pointer interpreted only with the reported line
  /// count; zero count means no element may be dereferenced. There is no
  /// nullable empty or failure sentinel. Cache construction may leave
  /// incomplete or empty data with no status. Dart-side marshalling or
  /// invocation exceptions are mapped to [FFIException].
  Pointer<Uint32> textBufferGetLineStartsPtr(
    Pointer<TextBufferHandle> textBuffer,
  ) => _guard(
    'Failed to get TextBuffer line starts pointer',
    () => _generated.textBufferGetLineStartsPtr(textBuffer.cast()),
  );

  /// Returns a native-owned pointer interpreted only with the reported line
  /// count; zero count means no element may be dereferenced. There is no
  /// nullable empty or failure sentinel. Cache construction may leave
  /// incomplete or empty data with no status. Dart-side marshalling or
  /// invocation exceptions are mapped to [FFIException].
  Pointer<Uint32> textBufferGetLineWidthsPtr(
    Pointer<TextBufferHandle> textBuffer,
  ) => _guard(
    'Failed to get TextBuffer line widths pointer',
    () => _generated.textBufferGetLineWidthsPtr(textBuffer.cast()),
  );

  /// Clears [textBuffer] through a status-free `void` export with no native
  /// failure status. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  void textBufferReset(Pointer<TextBufferHandle> textBuffer) {
    _guard('TextBuffer reset failed', () {
      _generated.textBufferReset(textBuffer.cast());
    });
  }

  /// Applies the half-open native-cell range `[start, end)`: [start] is
  /// included and [end] is excluded. The export is status-free `void` with no
  /// native failure status. Dart-side marshalling or invocation exceptions are
  /// mapped to [FFIException]. [start] and [end] must fit unsigned 32-bit
  /// values; violations throw pre-invocation [RangeError]. Raw intervals may
  /// be reversed, equal, or beyond the current length.
  void textBufferSetSelection(
    Pointer<TextBufferHandle> textBuffer,
    int start,
    int end,
    Color bgColor,
    Color fgColor,
  ) {
    _checkUnsignedAbi(start, 0xFFFFFFFF, 'start');
    _checkUnsignedAbi(end, 0xFFFFFFFF, 'end');
    _guardAlloc('TextBuffer selection failed', (alloc) {
      _generated.textBufferSetSelection(
        textBuffer.cast(),
        start,
        end,
        _colorToNative(bgColor, alloc),
        _colorToNative(fgColor, alloc),
      );
    });
  }

  /// Clears selection through a status-free `void` export with no native
  /// failure status. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  void textBufferResetSelection(Pointer<TextBufferHandle> textBuffer) {
    _guard('TextBuffer selection failed', () {
      _generated.textBufferResetSelection(textBuffer.cast());
    });
  }

  /// Renders [textBuffer] into [buffer] at ([x],[y]). The pinned export swallows
  /// native drawing errors, so they are not observable. Dart-side marshalling
  /// or invocation exceptions are mapped to [FFIException]. [hasClipRect]
  /// selects the ([clipX],[clipY],[clipWidth],[clipHeight]) region. [x], [y],
  /// [clipX], and [clipY] must fit signed 32-bit values; [clipWidth] and
  /// [clipHeight] must fit unsigned 32-bit values regardless of [hasClipRect].
  /// Violations throw pre-invocation [RangeError].
  void bufferDrawTextBuffer(
    Pointer<OptimizedBufferHandle> buffer,
    Pointer<TextBufferHandle> textBuffer,
    int x,
    int y,
    int clipX,
    int clipY,
    int clipWidth,
    int clipHeight,
    bool hasClipRect,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkSigned32Abi(clipX, 'clipX');
    _checkSigned32Abi(clipY, 'clipY');
    _checkUnsignedAbi(clipWidth, 0xFFFFFFFF, 'clipWidth');
    _checkUnsignedAbi(clipHeight, 0xFFFFFFFF, 'clipHeight');
    _guard('TextBuffer drawing failed', () {
      _generated.bufferDrawTextBuffer(
        buffer.cast(),
        textBuffer.cast(),
        x,
        y,
        clipX,
        clipY,
        clipWidth,
        clipHeight,
        hasClipRect,
      );
    });
  }

  // Mouse control bindings exposed by the native OpenTUI API.
  /// Enables mouse reporting for [renderer], including motion events when
  /// [enableMovement] is true. Throws [FFIException] on failure.
  void enableMouse(Pointer<RendererHandle> renderer, bool enableMovement) {
    _guard('Failed to enable mouse', () {
      _generated.enableMouse(renderer.cast(), enableMovement);
    });
  }

  /// Disables mouse reporting for [renderer]. Throws [FFIException] on failure.
  void disableMouse(Pointer<RendererHandle> renderer) {
    _guard('Failed to disable mouse', () {
      _generated.disableMouse(renderer.cast());
    });
  }

  /// Enables the Kitty keyboard protocol for [renderer] with the given
  /// progressive-enhancement [flags]. [flags] must fit an unsigned 8-bit
  /// value; violations throw a pre-invocation [RangeError]. Throws
  /// [FFIException] on failure.
  void enableKittyKeyboard(Pointer<RendererHandle> renderer, int flags) {
    _checkUnsignedAbi(flags, 0xFF, 'flags');
    _guard('Failed to enable kitty keyboard', () {
      _generated.enableKittyKeyboard(renderer.cast(), flags);
    });
  }

  /// Disables the Kitty keyboard protocol for [renderer]. Throws
  /// [FFIException] on failure.
  void disableKittyKeyboard(Pointer<RendererHandle> renderer) {
    _guard('Failed to disable kitty keyboard', () {
      _generated.disableKittyKeyboard(renderer.cast());
    });
  }

  // Buffer pointer methods
  /// Returns a pointer to [buffer]'s character-code cell array.
  /// Throws [FFIException] on a null result.
  Pointer<Uint32> bufferGetCharPtr(Pointer<OptimizedBufferHandle> buffer) =>
      _guard(
        'Failed to get char pointer',
        () => _checkNonNull(
          'Failed to get char pointer',
          _generated.bufferGetCharPtr(buffer.cast()),
        ),
      );

  /// Returns a pointer to [buffer]'s foreground-color (RGBA float) array.
  /// Throws [FFIException] on a null result.
  Pointer<Float> bufferGetFgPtr(Pointer<OptimizedBufferHandle> buffer) =>
      _guard(
        'Failed to get fg pointer',
        () => _checkNonNull(
          'Failed to get fg pointer',
          _generated.bufferGetFgPtr(buffer.cast()),
        ),
      );

  /// Returns a pointer to [buffer]'s background-color (RGBA float) array.
  /// Throws [FFIException] on a null result.
  Pointer<Float> bufferGetBgPtr(Pointer<OptimizedBufferHandle> buffer) =>
      _guard(
        'Failed to get bg pointer',
        () => _checkNonNull(
          'Failed to get bg pointer',
          _generated.bufferGetBgPtr(buffer.cast()),
        ),
      );

  /// Returns a pointer to [buffer]'s per-cell packed attributes array.
  /// Throws [FFIException] on a null result.
  Pointer<Uint8> bufferGetAttributesPtr(
    Pointer<OptimizedBufferHandle> buffer,
  ) => _guard(
    'Failed to get attributes pointer',
    () => _checkNonNull(
      'Failed to get attributes pointer',
      _generated.bufferGetAttributesPtr(buffer.cast()),
    ),
  );

  /// Sets the cell at ([x],[y]) in [buffer] to [charCode] with [fg]/[bg] colors
  /// and packed [attributes], alpha-blending against existing content.
  /// The pinned export swallows native cell-update errors, so they are not
  /// observable. [x], [y], and [charCode] must fit unsigned 32-bit values and
  /// [attributes] an unsigned 8-bit value; violations throw a pre-invocation
  /// [RangeError]. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  void bufferSetCellWithAlphaBlending(
    Pointer<OptimizedBufferHandle> buffer,
    int x,
    int y,
    int charCode,
    Color fg,
    Color bg,
    int attributes,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(charCode, 0xFFFFFFFF, 'charCode');
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
    _guardAlloc('Failed to set cell with alpha blending', (alloc) {
      _generated.bufferSetCellWithAlphaBlending(
        buffer.cast(),
        x,
        y,
        charCode,
        _colorToNative(fg, alloc),
        _colorToNative(bg, alloc),
        attributes,
      );
    });
  }

  /// Composites the ([sourceX],[sourceY],[sourceWidth],[sourceHeight]) region of
  /// [frameBuffer] onto [target] at ([destX],[destY]). A zero source
  /// coordinate or extent crosses as native null, selecting the native
  /// full-extent default. The export is status-free `void` with no native
  /// failure status. [destX] and [destY] must fit signed 32-bit values;
  /// [sourceX], [sourceY], [sourceWidth], and [sourceHeight] must fit
  /// unsigned 32-bit values; violations throw a pre-invocation [RangeError].
  /// Dart-side marshalling or invocation exceptions are mapped to
  /// [FFIException].
  void drawFrameBuffer(
    Pointer<OptimizedBufferHandle> target,
    int destX,
    int destY,
    Pointer<OptimizedBufferHandle> frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) {
    _checkSigned32Abi(destX, 'destX');
    _checkSigned32Abi(destY, 'destY');
    _checkUnsignedAbi(sourceX, 0xFFFFFFFF, 'sourceX');
    _checkUnsignedAbi(sourceY, 0xFFFFFFFF, 'sourceY');
    _checkUnsignedAbi(sourceWidth, 0xFFFFFFFF, 'sourceWidth');
    _checkUnsignedAbi(sourceHeight, 0xFFFFFFFF, 'sourceHeight');
    _guard('Failed to draw frame buffer', () {
      _generated.drawFrameBuffer(
        target.cast(),
        destX,
        destY,
        frameBuffer.cast(),
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
      );
    });
  }

  /// Resizes [buffer] to [width]×[height] cells. The pinned export swallows
  /// native resize errors, so they are not observable; the call reports no native
  /// failure.
  /// [width] and [height] must fit unsigned 32-bit values; violations throw
  /// a pre-invocation [RangeError]. Raw zero dimensions forward unchanged;
  /// the supported `Buffer.resize` wrapper owns the positive-dimensions rule.
  /// Dart-side marshalling or invocation exceptions are mapped to
  /// [FFIException].
  void bufferResize(
    Pointer<OptimizedBufferHandle> buffer,
    int width,
    int height,
  ) {
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _guard('Failed to resize buffer', () {
      _generated.bufferResize(buffer.cast(), width, height);
    });
  }

  // TextBuffer pointer methods
  /// Returns a native-owned pointer to encoded cell words, interpreted only
  /// with the logical cell count. There is no nullable empty or failure
  /// sentinel. Direct-cache construction may leave incomplete or empty data
  /// with no status. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  Pointer<Uint32> textBufferGetCharPtr(Pointer<TextBufferHandle> textBuffer) =>
      _guard(
        'Failed to get TextBuffer char pointer',
        () => _generated.textBufferGetCharPtr(textBuffer.cast()),
      );

  /// Returns a native-owned RGBA cache pointer that is count-bounded. There is
  /// no nullable empty or failure sentinel; the cache may be possibly partial
  /// with no status. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  Pointer<Float> textBufferGetFgPtr(Pointer<TextBufferHandle> textBuffer) =>
      _guard(
        'Failed to get TextBuffer fg pointer',
        () => _generated.textBufferGetFgPtr(textBuffer.cast()),
      );

  /// Returns a native-owned RGBA cache pointer that is count-bounded. There is
  /// no nullable empty or failure sentinel; the cache may be possibly partial
  /// with no status. Dart-side marshalling or invocation exceptions are mapped
  /// to [FFIException].
  Pointer<Float> textBufferGetBgPtr(Pointer<TextBufferHandle> textBuffer) =>
      _guard(
        'Failed to get TextBuffer bg pointer',
        () => _generated.textBufferGetBgPtr(textBuffer.cast()),
      );

  /// Returns a native-owned packed-attribute cache pointer that is
  /// count-bounded. There is no nullable empty or failure sentinel; the cache
  /// may be possibly partial with no status. Dart-side marshalling or
  /// invocation exceptions are mapped to [FFIException].
  Pointer<Uint16> textBufferGetAttributesPtr(
    Pointer<TextBufferHandle> textBuffer,
  ) => _guard(
    'Failed to get TextBuffer attributes pointer',
    () => _generated.textBufferGetAttributesPtr(textBuffer.cast()),
  );

  // Stats and Memory Stats
  /// Updates [renderer]'s debug-overlay frame stats with [time], [fps], and
  /// [frameCallbackTime]. [fps] must fit an unsigned 32-bit value; violations
  /// throw a pre-invocation [RangeError]. Throws [FFIException] on failure.
  void updateStats(
    Pointer<RendererHandle> renderer,
    double time,
    int fps,
    double frameCallbackTime,
  ) {
    _checkUnsignedAbi(fps, 0xFFFFFFFF, 'fps');
    _guard('Failed to update stats', () {
      _generated.updateStats(renderer.cast(), time, fps, frameCallbackTime);
    });
  }

  /// Updates [renderer]'s debug-overlay memory stats with [heapUsed],
  /// [heapTotal], and [arrayBuffers]. [heapUsed], [heapTotal], and
  /// [arrayBuffers] must fit unsigned 32-bit values; violations throw a
  /// pre-invocation [RangeError]. Throws [FFIException] on failure.
  void updateMemoryStats(
    Pointer<RendererHandle> renderer,
    int heapUsed,
    int heapTotal,
    int arrayBuffers,
  ) {
    _checkUnsignedAbi(heapUsed, 0xFFFFFFFF, 'heapUsed');
    _checkUnsignedAbi(heapTotal, 0xFFFFFFFF, 'heapTotal');
    _checkUnsignedAbi(arrayBuffers, 0xFFFFFFFF, 'arrayBuffers');
    _guard('Failed to update memory stats', () {
      _generated.updateMemoryStats(
        renderer.cast(),
        heapUsed,
        heapTotal,
        arrayBuffers,
      );
    });
  }

  // Terminal setup
  /// Prepares the terminal for [renderer], switching to the alternate screen
  /// when [useAlternateScreen] is true. Throws [FFIException] on failure.
  void setupTerminal(
    Pointer<RendererHandle> renderer,
    bool useAlternateScreen,
  ) {
    _guard('Failed to setup terminal', () {
      _generated.setupTerminal(renderer.cast(), useAlternateScreen);
    });
  }

  // Debug functions
  /// Toggles [renderer]'s debug overlay via [enabled] and positions it at the
  /// given [corner]. [corner] must fit an unsigned 8-bit value; violations
  /// throw a pre-invocation [RangeError]. Throws [FFIException] on failure.
  void setDebugOverlay(
    Pointer<RendererHandle> renderer,
    bool enabled,
    int corner,
  ) {
    _checkUnsignedAbi(corner, 0xFF, 'corner');
    _guard('Failed to set debug overlay', () {
      _generated.setDebugOverlay(renderer.cast(), enabled, corner);
    });
  }

  /// Dumps [renderer]'s hit grid for debugging. Throws [FFIException] on
  /// failure.
  void dumpHitGrid(Pointer<RendererHandle> renderer) {
    _guard('Failed to dump hit grid', () {
      _generated.dumpHitGrid(renderer.cast());
    });
  }

  /// Dumps [renderer]'s buffers for debugging, tagged with [timestamp].
  /// Throws [FFIException] on failure.
  void dumpBuffers(Pointer<RendererHandle> renderer, int timestamp) {
    _guard('Failed to dump buffers', () {
      _generated.dumpBuffers(renderer.cast(), timestamp);
    });
  }

  /// Dumps [renderer]'s pending stdout buffer for debugging, tagged with
  /// [timestamp]. Throws [FFIException] on failure.
  void dumpStdoutBuffer(Pointer<RendererHandle> renderer, int timestamp) {
    _guard('Failed to dump stdout buffer', () {
      _generated.dumpStdoutBuffer(renderer.cast(), timestamp);
    });
  }

  /// Registers a rectangular region in OpenTUI's low-level hit grid.
  ///
  /// This is a native/debug primitive. Built-in widgets route pointer events
  /// through render-tree hit testing and [MouseEvent.localPosition], not this
  /// ID grid. Keep this available for direct OpenTUI experiments, diagnostics,
  /// and parity checks against the native API.
  ///
  /// Example:
  /// ```dart
  /// // Register a debug overlay region.
  /// bindings.addToHitGrid(rendererHandle, 10, 5, 15, 3, debugOverlayId);
  ///
  /// final hitId = bindings.checkHit(rendererHandle, mouseX, mouseY);
  /// print('native hit grid returned $hitId');
  /// ```
  ///
  /// Parameters:
  /// - [renderer]: The renderer to add the hit region to
  /// - [x]: Left edge column position (0-based)
  /// - [y]: Top edge row position (0-based)
  /// - [width]: Region width in columns
  /// - [height]: Region height in rows
  /// - [id]: Unique identifier for this low-level region
  ///
  /// [x] and [y] must fit signed 32-bit values. [width], [height], and [id]
  /// must fit unsigned 32-bit values. Violations throw a pre-invocation
  /// [RangeError].
  ///
  /// IDs should be unique within the current hit grid. Overlapping regions
  /// may return the most recently added ID.
  ///
  /// Throws [FFIException] if the underlying C function fails.
  ///
  /// See also:
  /// - [checkHit] for querying this low-level grid
  /// - [enableMouse] for enabling mouse input
  void addToHitGrid(
    Pointer<RendererHandle> renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _checkUnsignedAbi(id, 0xFFFFFFFF, 'id');
    _guard('Failed to add to hit grid', () {
      _generated.addToHitGrid(renderer.cast(), x, y, width, height, id);
    });
  }

  /// Queries OpenTUI's low-level hit grid at the specified coordinates.
  ///
  /// Returns the ID of a region registered with [addToHitGrid], or 0 if no
  /// region was hit. This is a native/debug primitive; built-in widgets use
  /// render-tree hit testing for pointer dispatch.
  ///
  /// Example:
  /// ```dart
  /// // Query a region previously registered for native parity debugging.
  /// final hitId = bindings.checkHit(rendererHandle, mouseX, mouseY);
  /// print('native hit grid returned $hitId');
  /// ```
  ///
  /// Parameters:
  /// - [renderer]: The renderer to test coordinates against
  /// - [x]: Column position to test (0-based)
  /// - [y]: Row position to test (0-based)
  ///
  /// [x] and [y] must fit unsigned 32-bit values; violations throw a
  /// pre-invocation [RangeError].
  ///
  /// Returns:
  /// - The registered native/debug region ID, or 0 if no region contains
  ///   the coordinates
  ///
  /// ABI-valid coordinates outside the terminal bounds always return 0.
  /// When multiple regions overlap, the most recently added region's ID
  /// is returned.
  ///
  /// Throws [FFIException] if the underlying C function fails.
  ///
  /// See also:
  /// - [addToHitGrid] for registering native/debug regions
  /// - [enableMouse] for enabling mouse input events
  int checkHit(Pointer<RendererHandle> renderer, int x, int y) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    return _guard(
      'Failed to check hit',
      () => _generated.checkHit(renderer.cast(), x, y),
    );
  }

  // Terminal capabilities
  /// Fills [caps] with the terminal capabilities detected for [renderer].
  /// Throws [FFIException] on failure.
  void getTerminalCapabilities(
    Pointer<RendererHandle> renderer,
    Pointer<CapabilitiesHandle> caps,
  ) {
    _guard('Failed to get terminal capabilities', () {
      _generated.getTerminalCapabilities(renderer.cast(), caps.cast());
    });
  }

  /// Parses a terminal capability query [response] into [renderer]'s detected
  /// capabilities. Throws [FFIException] on failure.
  void processCapabilityResponse(
    Pointer<RendererHandle> renderer,
    String response,
  ) {
    _guardAlloc('Failed to process capability response', (alloc) {
      final (responsePtr, responseLen) = _utf8(alloc, response);
      _generated.processCapabilityResponse(
        renderer.cast(),
        responsePtr,
        responseLen,
      );
    });
  }
}

/// Exception thrown when FFI operations fail
class FFIException implements Exception {
  /// Wraps the supplied [message] for reporting through [toString].
  FFIException(this.message);

  /// Human-readable failure detail included by [toString].
  final String message;

  @override
  String toString() => 'FFI Error: $message';
}
