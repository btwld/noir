// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:convert' as convert;
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/terminal_style.dart';
import 'library.dart';
import 'native_symbols.dart';
import 'types.dart';

const _unchangedCursorOption = 0xFF;

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

/// Requires renderer dimensions between 1 and the unsigned 32-bit maximum.
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

Pointer<Uint8> _copyBytes(Allocator allocator, List<int> bytes) {
  final pointer = allocator<Uint8>(bytes.length);
  pointer.asTypedList(bytes.length).setAll(0, bytes);
  return pointer;
}

Pointer<Uint16> _colorToNative(Color color, Allocator allocator) {
  final pointer = allocator<Uint16>(4);
  pointer[0] = (color.r * 255).round();
  pointer[1] = (color.g * 255).round();
  pointer[2] = (color.b * 255).round();
  pointer[3] = (color.a * 255).round();
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
  return packed | (alignment << 5);
}

/// Status returned by canonical OpenTUI rendering.
enum OpenTuiRenderStatus {
  /// OpenTUI emitted the frame.
  rendered,

  /// OpenTUI intentionally skipped an unchanged frame.
  skipped,
}

/// Decodes OpenTUI's `RenderStatus` and rejects failed or unknown values.
@visibleForTesting
OpenTuiRenderStatus decodeOpenTuiRenderStatus(int value) => switch (value) {
  0 => OpenTuiRenderStatus.rendered,
  1 => OpenTuiRenderStatus.skipped,
  2 => throw FFIException('OpenTUI render failed'),
  _ => throw FFIException('OpenTUI returned unknown render status $value'),
};

/// Guarded Dart wrapper around Noir's selected OpenTUI v0.5.1 exports.
class OpenTuiBindings {
  /// Opens the configured native library.
  OpenTuiBindings() : _native = OpenTuiNativeLibrary.open();

  /// Creates bindings around [native] for focused contract tests.
  @internal
  @visibleForTesting
  OpenTuiBindings.fromNativeSymbols(this._native);

  final OpenTuiNativeSymbols _native;

  T _guard<T>(String operation, T Function() body) {
    try {
      return body();
    } on FFIException {
      rethrow;
    } catch (error) {
      throw FFIException('$operation: $error');
    }
  }

  T _guardAlloc<T>(String operation, T Function(Allocator allocator) body) =>
      using((allocator) => _guard(operation, () => body(allocator)));

  (Pointer<Uint8>, int) _utf8(Allocator allocator, String text) {
    final bytes = convert.utf8.encode(text);
    _checkUnsignedAbi(bytes.length, 0xFFFFFFFF, 'textLength');
    return (_copyBytes(allocator, bytes), bytes.length);
  }

  /// Creates a renderer. Testing renderers use OpenTUI's memory output.
  RendererHandle createRenderer(int width, int height, {bool testing = false}) {
    validateRendererDimensions(width, height);
    return _guard(
      'Failed to create renderer',
      () => RendererHandle.fromNative(
        _native.createRenderer(width, height, testing ? 1 : 0, 0),
      ),
    );
  }

  /// Destroys [renderer].
  void destroyRenderer(RendererHandle renderer) {
    _guard('Failed to destroy renderer', () {
      _native.destroyRenderer(renderer.value);
    });
  }

  /// Renders a frame, accepting both rendered and intentionally skipped frames.
  OpenTuiRenderStatus render(RendererHandle renderer, bool force) => _guard(
    'Failed to render',
    () => decodeOpenTuiRenderStatus(_native.render(renderer.value, force)),
  );

  /// Returns the borrowed next-frame buffer handle.
  OptimizedBufferHandle getNextBuffer(RendererHandle renderer) => _guard(
    'Failed to get next buffer',
    () =>
        OptimizedBufferHandle.fromNative(_native.getNextBuffer(renderer.value)),
  );

  /// Returns the borrowed current-frame buffer handle.
  OptimizedBufferHandle getCurrentBuffer(RendererHandle renderer) => _guard(
    'Failed to get current buffer',
    () => OptimizedBufferHandle.fromNative(
      _native.getCurrentBuffer(renderer.value),
    ),
  );

  /// Resizes the renderer and its owned buffers.
  void resizeRenderer(RendererHandle renderer, int width, int height) {
    validateRendererDimensions(width, height);
    _guard('Failed to resize renderer', () {
      _native.resizeRenderer(renderer.value, width, height);
    });
  }

  /// Sets the terminal background color.
  void setBackgroundColor(RendererHandle renderer, Color color) {
    validateColorChannels(color);
    _guardAlloc('Failed to set background color', (allocator) {
      _native.setBackgroundColor(
        renderer.value,
        _colorToNative(color, allocator),
      );
    });
  }

  /// Clears the terminal.
  void clearTerminal(RendererHandle renderer) {
    _guard('Failed to clear terminal', () {
      _native.clearTerminal(renderer.value);
    });
  }

  /// Copies UTF-8 [text] through OpenTUI's OSC 52 terminal writer.
  bool copyToClipboardOSC52(RendererHandle renderer, int target, String text) {
    _checkUnsignedAbi(target, 0xFF, 'target');
    return _guardAlloc('Failed to copy to clipboard', (allocator) {
      final (pointer, length) = _utf8(allocator, text);
      return _native.copyToClipboardOSC52(
        renderer.value,
        target,
        pointer,
        length,
      );
    });
  }

  /// Clears one OSC 52 clipboard [target].
  bool clearClipboardOSC52(RendererHandle renderer, int target) {
    _checkUnsignedAbi(target, 0xFF, 'target');
    return _guard(
      'Failed to clear clipboard',
      () => _native.clearClipboardOSC52(renderer.value, target),
    );
  }

  /// Allocates a native hyperlink ID for a UTF-8 URL of at most 512 bytes.
  int linkAlloc(Uri uri) {
    final bytes = convert.utf8.encode(uri.toString());
    if (bytes.length > 512) {
      throw ArgumentError.value(uri, 'uri', 'must encode to at most 512 bytes');
    }
    if (bytes.isEmpty) return 0;
    return _guardAlloc(
      'Failed to allocate hyperlink',
      (allocator) =>
          _native.linkAlloc(_copyBytes(allocator, bytes), bytes.length),
    );
  }

  /// Resolves a native hyperlink ID to its semantic URL.
  String? linkGetUrl(int id) {
    _checkUnsignedAbi(id, 0xFFFFFFFF, 'id');
    if (id == 0) return null;
    return _guardAlloc('Failed to resolve hyperlink', (allocator) {
      final out = allocator<Uint8>(512);
      final length = _native.linkGetUrl(id, out, 512);
      if (length == 0) return null;
      return convert.utf8.decode(out.asTypedList(length));
    });
  }

  /// Packs [linkId] into a native text attribute word.
  int attributesWithLink(int baseAttributes, int linkId) {
    _checkUnsignedAbi(baseAttributes, 0xFFFFFFFF, 'baseAttributes');
    _checkUnsignedAbi(linkId, 0xFFFFFFFF, 'linkId');
    return _guard(
      'Failed to encode hyperlink attributes',
      () => _native.attributesWithLink(baseAttributes, linkId),
    );
  }

  /// Extracts the native hyperlink ID from [attributes].
  int attributesGetLinkId(int attributes) {
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    return _guard(
      'Failed to decode hyperlink attributes',
      () => _native.attributesGetLinkId(attributes),
    );
  }

  /// Returns [buffer]'s width in cells.
  int getBufferWidth(OptimizedBufferHandle buffer) => _guard(
    'Failed to get buffer width',
    () => _native.getBufferWidth(buffer.value),
  );

  /// Returns [buffer]'s height in cells.
  int getBufferHeight(OptimizedBufferHandle buffer) => _guard(
    'Failed to get buffer height',
    () => _native.getBufferHeight(buffer.value),
  );

  /// Clears [buffer] to [background].
  void bufferClear(OptimizedBufferHandle buffer, Color background) {
    validateColorChannels(background, name: 'background');
    _guardAlloc('Failed to clear buffer', (allocator) {
      _native.bufferClear(buffer.value, _colorToNative(background, allocator));
    });
  }

  /// Draws one styled UTF-8 run.
  void bufferDrawText(
    OptimizedBufferHandle buffer,
    String text,
    int x,
    int y,
    Color foreground,
    Color? background,
    int attributes,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    validateColorChannels(foreground, name: 'foreground');
    if (background != null) {
      validateColorChannels(background, name: 'background');
    }
    _guardAlloc('Failed to draw text', (allocator) {
      final (textPointer, textLength) = _utf8(allocator, text);
      _native.bufferDrawText(
        buffer.value,
        textPointer,
        textLength,
        x,
        y,
        _colorToNative(foreground, allocator),
        background == null ? nullptr : _colorToNative(background, allocator),
        attributes,
      );
    });
  }

  /// Fills a rectangular region.
  void bufferFillRect(
    OptimizedBufferHandle buffer,
    int x,
    int y,
    int width,
    int height,
    Color background,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    validateColorChannels(background, name: 'background');
    _guardAlloc('Failed to fill rectangle', (allocator) {
      _native.bufferFillRect(
        buffer.value,
        x,
        y,
        width,
        height,
        _colorToNative(background, allocator),
      );
    });
  }

  /// Draws a box with optional title.
  void bufferDrawBox(
    OptimizedBufferHandle buffer,
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
    validateColorChannels(borderColor, name: 'borderColor');
    validateColorChannels(backgroundColor, name: 'backgroundColor');
    const defaults = <int>[
      0x250C,
      0x2510,
      0x2514,
      0x2518,
      0x2500,
      0x2502,
      0x252C,
      0x2534,
      0x251C,
      0x2524,
      0x253C,
    ];
    final borderChars = options.borderChars ?? defaults;
    for (final character in borderChars) {
      _checkUnsignedAbi(character, 0xFFFFFFFF, 'borderChars');
    }
    _guardAlloc('Failed to draw box', (allocator) {
      final nativeBorderChars = allocator<Uint32>(11);
      nativeBorderChars.asTypedList(11).setAll(0, borderChars);
      final (title, titleLength) = _utf8(allocator, options.title ?? '');
      final nativeBorderColor = _colorToNative(borderColor, allocator);
      _native.bufferDrawBox(
        buffer.value,
        x,
        y,
        width,
        height,
        nativeBorderChars,
        _boxOptionsToNative(options),
        nativeBorderColor,
        _colorToNative(backgroundColor, allocator),
        nativeBorderColor,
        title,
        titleLength,
      );
    });
  }

  /// Returns the native encoded-character array.
  Pointer<Uint32> bufferGetCharPtr(OptimizedBufferHandle buffer) =>
      _guard('Failed to access buffer chars', () {
        final pointer = _native.bufferGetCharPtr(buffer.value);
        if (pointer == nullptr) throw StateError('returned nullptr');
        return pointer;
      });

  /// Returns canonical packed u16 foreground storage.
  Pointer<Uint16> bufferGetFgPtr(OptimizedBufferHandle buffer) =>
      _guard('Failed to access buffer foregrounds', () {
        final pointer = _native.bufferGetFgPtr(buffer.value);
        if (pointer == nullptr) throw StateError('returned nullptr');
        return pointer;
      });

  /// Returns canonical packed u16 background storage.
  Pointer<Uint16> bufferGetBgPtr(OptimizedBufferHandle buffer) =>
      _guard('Failed to access buffer backgrounds', () {
        final pointer = _native.bufferGetBgPtr(buffer.value);
        if (pointer == nullptr) throw StateError('returned nullptr');
        return pointer;
      });

  /// Returns canonical u32 attribute storage.
  Pointer<Uint32> bufferGetAttributesPtr(OptimizedBufferHandle buffer) =>
      _guard('Failed to access buffer attributes', () {
        final pointer = _native.bufferGetAttributesPtr(buffer.value);
        if (pointer == nullptr) throw StateError('returned nullptr');
        return pointer;
      });

  /// Resolves the buffer's native grapheme storage to UTF-8 text.
  @internal
  String bufferResolvedCharacters(
    OptimizedBufferHandle buffer, {
    bool addLineBreaks = false,
  }) => _guardAlloc('Failed to resolve buffer characters', (allocator) {
    final realSize = _native.bufferGetRealCharSize(buffer.value);
    final lineBreakBytes = addLineBreaks
        ? _native.getBufferHeight(buffer.value)
        : 0;
    final capacity = realSize + lineBreakBytes;
    if (capacity == 0) return '';
    final output = allocator<Uint8>(capacity);
    final written = _native.bufferWriteResolvedChars(
      buffer.value,
      output,
      capacity,
      addLineBreaks,
    );
    if (written == 0) {
      throw StateError('native buffer resolution returned no bytes');
    }
    return convert.utf8.decode(output.asTypedList(written));
  });

  /// Writes one encoded cell through OpenTUI's alpha-blending path.
  void bufferSetCellWithAlphaBlending(
    OptimizedBufferHandle buffer,
    int x,
    int y,
    int character,
    Color foreground,
    Color background,
    int attributes,
  ) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    _checkUnsignedAbi(character, 0xFFFFFFFF, 'character');
    _checkUnsignedAbi(attributes, 0xFFFFFFFF, 'attributes');
    validateColorChannels(foreground, name: 'foreground');
    validateColorChannels(background, name: 'background');
    _guardAlloc('Failed to set buffer cell', (allocator) {
      _native.bufferSetCellWithAlphaBlending(
        buffer.value,
        x,
        y,
        character,
        _colorToNative(foreground, allocator),
        _colorToNative(background, allocator),
        attributes,
      );
    });
  }

  /// Composites [frameBuffer] into [target].
  void drawFrameBuffer(
    OptimizedBufferHandle target,
    int destX,
    int destY,
    OptimizedBufferHandle frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) {
    _checkSigned32Abi(destX, 'destX');
    _checkSigned32Abi(destY, 'destY');
    for (final (value, name) in <(int, String)>[
      (sourceX, 'sourceX'),
      (sourceY, 'sourceY'),
      (sourceWidth, 'sourceWidth'),
      (sourceHeight, 'sourceHeight'),
    ]) {
      _checkUnsignedAbi(value, 0xFFFFFFFF, name);
    }
    _guard('Failed to draw frame buffer', () {
      _native.drawFrameBuffer(
        target.value,
        destX,
        destY,
        frameBuffer.value,
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
      );
    });
  }

  /// Resizes [buffer].
  void bufferResize(OptimizedBufferHandle buffer, int width, int height) {
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _guard('Failed to resize buffer', () {
      _native.bufferResize(buffer.value, width, height);
    });
  }

  /// Pushes a clip rectangle onto [buffer]'s native scissor stack.
  ///
  /// Clips subsequent draws until the matching [bufferPopScissorRect], except
  /// transparent-background `drawBox` borders, which bypass the scissor.
  ///
  /// Four properties surprise callers, all of them upstream behaviour:
  ///
  /// * The push **intersects** with the current rectangle rather than
  ///   replacing it, so nesting narrows and never widens.
  /// * The stack is state on the native buffer, not on a view. It outlives
  ///   `render()` and `resize()`, because OpenTUI allocates its buffers once
  ///   per renderer and never swaps them. Noir clears both stacks as each
  ///   frame borrows its buffer, so an unpopped push corrupts only the frame
  ///   that leaked it — but within a frame the pairing is the caller's.
  /// * It also clips writes made through [Buffer.clipped], whose Dart-side
  ///   rectangle is then no longer the only thing deciding what lands.
  /// * `drawBox` with a transparent background escapes it entirely: upstream
  ///   writes those borders through an unchecked index.
  void bufferPushScissorRect(
    OptimizedBufferHandle buffer,
    int x,
    int y,
    int width,
    int height,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _checkUnsignedAbi(width, 0xFFFFFFFF, 'width');
    _checkUnsignedAbi(height, 0xFFFFFFFF, 'height');
    _guard('Failed to push scissor rect', () {
      _native.bufferPushScissorRect(buffer.value, x, y, width, height);
    });
  }

  /// Pops the innermost clip rectangle from [buffer]'s scissor stack.
  void bufferPopScissorRect(OptimizedBufferHandle buffer) {
    _guard('Failed to pop scissor rect', () {
      _native.bufferPopScissorRect(buffer.value);
    });
  }

  /// Clears every clip rectangle from [buffer]'s scissor stack.
  void bufferClearScissorRects(OptimizedBufferHandle buffer) {
    _guard('Failed to clear scissor rects', () {
      _native.bufferClearScissorRects(buffer.value);
    });
  }

  /// Pushes [opacity] onto [buffer]'s native opacity stack.
  ///
  /// Noir rejects an [opacity] outside `0.0..1.0` so the domain stays
  /// explicit, and clears the stack as each frame borrows its buffer for the
  /// same reason as [bufferPushScissorRect].
  ///
  /// This primitive is far narrower than its name suggests, all upstream:
  ///
  /// * **It does not fade ordinary text.** `bufferDrawText` takes an ASCII
  ///   fast path whenever the foreground and background are both fully
  ///   opaque, writing cells directly and skipping the opacity funnel, so any
  ///   value in `(0.0, 1.0)` paints identically to `1.0`. Only `0.0` reads as
  ///   transparent, and it does so through a separate early-out. Blending is
  ///   observable through [bufferSetCellWithAlphaBlending] and
  ///   [bufferFillRect]. An `Opacity` widget cannot be built on this alone.
  /// * The push **multiplies** with the current value rather than replacing
  ///   it, so `0.5` inside `0.5` yields `0.25`.
  /// * [drawFrameBuffer] reads the destination's stack and ignores the
  ///   source's, so pushing opacity onto an offscreen layer does nothing.
  void bufferPushOpacity(OptimizedBufferHandle buffer, double opacity) {
    if (opacity.isNaN || opacity < 0.0 || opacity > 1.0) {
      throw RangeError.range(opacity, 0, 1, 'opacity');
    }
    _guard('Failed to push opacity', () {
      _native.bufferPushOpacity(buffer.value, opacity);
    });
  }

  /// Pops the innermost value from [buffer]'s opacity stack.
  void bufferPopOpacity(OptimizedBufferHandle buffer) {
    _guard('Failed to pop opacity', () {
      _native.bufferPopOpacity(buffer.value);
    });
  }

  /// Clears every value from [buffer]'s opacity stack.
  void bufferClearOpacity(OptimizedBufferHandle buffer) {
    _guard('Failed to clear opacity', () {
      _native.bufferClearOpacity(buffer.value);
    });
  }

  /// Decodes encoded image bytes into a native image handle.
  ({int status, TerminalImageHandle? handle}) imageDecode(Uint8List data) {
    _checkUnsignedAbi(data.length, 0xFFFFFFFF, 'dataLength');
    return _guardAlloc('Failed to decode image', (allocator) {
      final bytes = _copyBytes(allocator, data);
      final output = allocator<Uint32>()..value = 0;
      final status = _native.imageDecode(bytes, data.length, output);
      final value = output.value;
      return (
        status: status,
        handle: value == 0 ? null : TerminalImageHandle.fromNative(value),
      );
    });
  }

  /// Creates a native image by copying an RGBA pixel buffer.
  ({int status, TerminalImageHandle? handle}) imageCreateFromRgba(
    Uint8List pixels, {
    required int width,
    required int height,
    required int stride,
  }) {
    for (final (name, value) in <(String, int)>[
      ('width', width),
      ('height', height),
      ('stride', stride),
    ]) {
      _checkUnsignedAbi(value, 0xFFFFFFFF, name);
    }
    return _guardAlloc('Failed to create RGBA image', (allocator) {
      final bytes = _copyBytes(allocator, pixels);
      final output = allocator<Uint32>()..value = 0;
      final status = _native.imageCreateFromRgba(
        bytes,
        pixels.length,
        width,
        height,
        stride,
        output,
      );
      final value = output.value;
      return (
        status: status,
        handle: value == 0 ? null : TerminalImageHandle.fromNative(value),
      );
    });
  }

  /// Returns the eight canonical `NativeImageInfo` fields and native status.
  ({int status, List<int> fields}) imageGetInfo(TerminalImageHandle image) =>
      _guardAlloc('Failed to get image info', (allocator) {
        final output = allocator<Uint32>(8);
        final status = _native.imageGetInfo(image.value, output);
        return (status: status, fields: List<int>.of(output.asTypedList(8)));
      });

  /// Destroys [image].
  void imageDestroy(TerminalImageHandle image) {
    _guard('Failed to destroy image', () => _native.imageDestroy(image.value));
  }

  /// Records a native image placement in [buffer].
  bool bufferDrawImage(
    OptimizedBufferHandle buffer,
    TerminalImageHandle image, {
    required int x,
    required int y,
    required int width,
    required int height,
    required int pixelWidth,
    required int pixelHeight,
    required int sourceX,
    required int sourceY,
    required int sourceWidth,
    required int sourceHeight,
    required int protocol,
  }) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    for (final (name, value) in <(String, int)>[
      ('width', width),
      ('height', height),
      ('pixelWidth', pixelWidth),
      ('pixelHeight', pixelHeight),
      ('sourceX', sourceX),
      ('sourceY', sourceY),
      ('sourceWidth', sourceWidth),
      ('sourceHeight', sourceHeight),
      ('protocol', protocol),
    ]) {
      _checkUnsignedAbi(value, 0xFFFFFFFF, name);
    }
    return _guard(
      'Failed to draw image',
      () =>
          _native.bufferDrawImage(
            buffer.value,
            image.value,
            x,
            y,
            width,
            height,
            pixelWidth,
            pixelHeight,
            sourceX,
            sourceY,
            sourceWidth,
            sourceHeight,
            protocol,
          ) !=
          0,
    );
  }

  /// Asks the terminal to report pixel resolution.
  void queryPixelResolution(RendererHandle renderer) {
    _guard(
      'Failed to query pixel resolution',
      () => _native.queryPixelResolution(renderer.value),
    );
  }

  /// Sets cursor position and visibility.
  void setCursorPosition(RendererHandle renderer, int x, int y, bool visible) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    _guard('Failed to set cursor position', () {
      _native.setCursorPosition(renderer.value, x, y, visible);
    });
  }

  /// Sets cursor style and blinking through `setCursorStyleOptions`.
  void setCursorStyle(RendererHandle renderer, int style, bool blinking) {
    _checkUnsignedAbi(style, 3, 'style');
    _guard('Failed to set cursor style', () {
      _native.setCursorStyleOptions(
        renderer.value,
        style,
        blinking ? 1 : 0,
        nullptr,
      );
    });
  }

  /// Sets cursor color through `setCursorStyleOptions`.
  void setCursorColor(RendererHandle renderer, Color color) {
    validateColorChannels(color);
    _guardAlloc('Failed to set cursor color', (allocator) {
      _native.setCursorStyleOptions(
        renderer.value,
        _unchangedCursorOption,
        _unchangedCursorOption,
        _colorToNative(color, allocator),
      );
    });
  }

  /// Enables mouse input.
  void enableMouse(RendererHandle renderer, bool enableMovement) {
    _guard('Failed to enable mouse input', () {
      _native.enableMouse(renderer.value, enableMovement);
    });
  }

  /// Disables mouse input.
  void disableMouse(RendererHandle renderer) {
    _guard('Failed to disable mouse input', () {
      _native.disableMouse(renderer.value);
    });
  }

  /// Enables Kitty keyboard input.
  void enableKittyKeyboard(RendererHandle renderer, int flags) {
    _checkUnsignedAbi(flags, 0xFF, 'flags');
    _guard('Failed to enable Kitty keyboard input', () {
      _native.enableKittyKeyboard(renderer.value, flags);
    });
  }

  /// Disables Kitty keyboard input.
  void disableKittyKeyboard(RendererHandle renderer) {
    _guard('Failed to disable Kitty keyboard input', () {
      _native.disableKittyKeyboard(renderer.value);
    });
  }

  /// Sets up terminal modes.
  void setupTerminal(RendererHandle renderer, bool useAlternateScreen) {
    _guard('Failed to set up terminal', () {
      _native.setupTerminal(renderer.value, useAlternateScreen);
    });
  }

  /// Adds a native debug hit-grid region.
  void addToHitGrid(
    RendererHandle renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) {
    _checkSigned32Abi(x, 'x');
    _checkSigned32Abi(y, 'y');
    for (final (value, name) in <(int, String)>[
      (width, 'width'),
      (height, 'height'),
      (id, 'id'),
    ]) {
      _checkUnsignedAbi(value, 0xFFFFFFFF, name);
    }
    _guard('Failed to add hit-grid region', () {
      _native.addToHitGrid(renderer.value, x, y, width, height, id);
    });
  }

  /// Checks a native debug hit-grid coordinate.
  int checkHit(RendererHandle renderer, int x, int y) {
    _checkUnsignedAbi(x, 0xFFFFFFFF, 'x');
    _checkUnsignedAbi(y, 0xFFFFFFFF, 'y');
    return _guard(
      'Failed to check hit grid',
      () => _native.checkHit(renderer.value, x, y),
    );
  }

  /// Processes a terminal capability response.
  void processCapabilityResponse(RendererHandle renderer, String response) {
    _guardAlloc('Failed to process capability response', (allocator) {
      final (pointer, length) = _utf8(allocator, response);
      _native.processCapabilityResponse(renderer.value, pointer, length);
    });
  }
}

/// Exception thrown when a guarded FFI operation fails.
class FFIException implements Exception {
  /// Creates an exception with [message].
  FFIException(this.message);

  /// Human-readable failure detail.
  final String message;

  @override
  String toString() => 'FFI Error: $message';
}
