// ignore_for_file: avoid_positional_boolean_parameters, public_member_api_docs

import 'dart:ffi';

import 'abi_contract.dart';
import 'generated_bindings.dart' as lookup;
import 'native_asset_bindings.dart' as bundled;

typedef OpenTuiNativeSymbolLookup =
    Pointer<T> Function<T extends NativeType>(String symbolName);
typedef _BundledSymbolResolver = Pointer<NativeType> Function();

final List<_BundledSymbolResolver>
_bundledRequiredSymbolResolvers = <_BundledSymbolResolver>[
  // ABI metadata and error channel.
  () => Native.addressOf<NativeFunction<Uint32 Function()>>(
    bundled.otui_dart_abi_version,
  ).cast(),
  () => Native.addressOf<NativeFunction<Pointer<Char> Function()>>(
    bundled.otui_dart_build_info,
  ).cast(),
  () => Native.addressOf<NativeFunction<Pointer<Char> Function()>>(
    bundled.otui_dart_last_error,
  ).cast(),
  () => Native.addressOf<NativeFunction<Void Function()>>(
    bundled.otui_dart_clear_error,
  ).cast(),

  // Renderer and session.
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<bundled.CliRenderer> Function(Uint32, Uint32, Bool)
            >
          >(bundled.createRenderer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Bool, Uint32)
            >
          >(bundled.destroyRenderer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Bool)>
          >(bundled.render)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<bundled.OptimizedBuffer> Function(
                Pointer<bundled.CliRenderer>,
              )
            >
          >(bundled.getNextBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<bundled.OptimizedBuffer> Function(
                Pointer<bundled.CliRenderer>,
              )
            >
          >(bundled.getCurrentBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Uint32, Uint32)
            >
          >(bundled.resizeRenderer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Pointer<Float>)
            >
          >(bundled.setBackgroundColor)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>)>
          >(bundled.clearTerminal)
          .cast(),

  // Buffer size and drawing.
  () =>
      Native.addressOf<
            NativeFunction<Uint32 Function(Pointer<bundled.OptimizedBuffer>)>
          >(bundled.getBufferWidth)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Uint32 Function(Pointer<bundled.OptimizedBuffer>)>
          >(bundled.getBufferHeight)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.OptimizedBuffer>, Pointer<Float>)
            >
          >(bundled.bufferClear)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Pointer<Uint8>,
                Size,
                Uint32,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
                Uint8,
              )
            >
          >(bundled.bufferDrawText)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Uint32,
                Uint32,
                Uint32,
                Uint32,
                Pointer<Float>,
              )
            >
          >(bundled.bufferFillRect)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Int32,
                Int32,
                Uint32,
                Uint32,
                Pointer<Uint32>,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
                Pointer<Uint8>,
                Uint32,
              )
            >
          >(bundled.bufferDrawBox)
          .cast(),

  // Cursor.
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Int32, Int32, Bool)
            >
          >(bundled.setCursorPosition)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.CliRenderer>,
                Pointer<Uint8>,
                Size,
                Bool,
              )
            >
          >(bundled.setCursorStyle)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Pointer<Float>)
            >
          >(bundled.setCursorColor)
          .cast(),

  // Guarded TextBuffer operations.
  () =>
      Native.addressOf<
            NativeFunction<Pointer<bundled.TextBuffer> Function(Uint32, Uint8)>
          >(bundled.createTextBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.TextBuffer>)>
          >(bundled.destroyTextBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Uint32 Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferGetLength)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.TextBuffer>,
                Uint32,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
                Uint16,
              )
            >
          >(bundled.textBufferSetCell)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Uint32 Function(
                Pointer<bundled.TextBuffer>,
                Pointer<Uint8>,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
                Pointer<Uint8>,
              )
            >
          >(bundled.textBufferWriteChunk)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferFinalizeLineInfo)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Uint32 Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferGetLineCount)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint32> Function(Pointer<bundled.TextBuffer>)
            >
          >(bundled.textBufferGetLineStartsPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint32> Function(Pointer<bundled.TextBuffer>)
            >
          >(bundled.textBufferGetLineWidthsPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferReset)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.TextBuffer>,
                Uint32,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
              )
            >
          >(bundled.textBufferSetSelection)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferResetSelection)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Pointer<bundled.TextBuffer>,
                Int32,
                Int32,
                Int32,
                Int32,
                Uint32,
                Uint32,
                Bool,
              )
            >
          >(bundled.bufferDrawTextBuffer)
          .cast(),

  // Terminal input modes.
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Bool)>
          >(bundled.enableMouse)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>)>
          >(bundled.disableMouse)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Uint8)>
          >(bundled.enableKittyKeyboard)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>)>
          >(bundled.disableKittyKeyboard)
          .cast(),

  // Direct buffer/TextBuffer access and composition.
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint32> Function(Pointer<bundled.OptimizedBuffer>)
            >
          >(bundled.bufferGetCharPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Float> Function(Pointer<bundled.OptimizedBuffer>)
            >
          >(bundled.bufferGetFgPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Float> Function(Pointer<bundled.OptimizedBuffer>)
            >
          >(bundled.bufferGetBgPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint8> Function(Pointer<bundled.OptimizedBuffer>)
            >
          >(bundled.bufferGetAttributesPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Uint32,
                Uint32,
                Uint32,
                Pointer<Float>,
                Pointer<Float>,
                Uint8,
              )
            >
          >(bundled.bufferSetCellWithAlphaBlending)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.OptimizedBuffer>,
                Int32,
                Int32,
                Pointer<bundled.OptimizedBuffer>,
                Uint32,
                Uint32,
                Uint32,
                Uint32,
              )
            >
          >(bundled.drawFrameBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.OptimizedBuffer>, Uint32, Uint32)
            >
          >(bundled.bufferResize)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint32> Function(Pointer<bundled.TextBuffer>)
            >
          >(bundled.textBufferGetCharPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Pointer<Float> Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferGetFgPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Pointer<Float> Function(Pointer<bundled.TextBuffer>)>
          >(bundled.textBufferGetBgPtr)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Pointer<Uint16> Function(Pointer<bundled.TextBuffer>)
            >
          >(bundled.textBufferGetAttributesPtr)
          .cast(),

  // Diagnostics, terminal setup, hit testing, and capabilities.
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.CliRenderer>,
                Double,
                Uint32,
                Double,
              )
            >
          >(bundled.updateStats)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.CliRenderer>,
                Uint32,
                Uint32,
                Uint32,
              )
            >
          >(bundled.updateMemoryStats)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Bool)>
          >(bundled.setupTerminal)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Bool, Uint8)
            >
          >(bundled.setDebugOverlay)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>)>
          >(bundled.dumpHitGrid)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Int64)>
          >(bundled.dumpBuffers)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<Void Function(Pointer<bundled.CliRenderer>, Int64)>
          >(bundled.dumpStdoutBuffer)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.CliRenderer>,
                Int32,
                Int32,
                Uint32,
                Uint32,
                Uint32,
              )
            >
          >(bundled.addToHitGrid)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Uint32 Function(Pointer<bundled.CliRenderer>, Uint32, Uint32)
            >
          >(bundled.checkHit)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(
                Pointer<bundled.CliRenderer>,
                Pointer<bundled.Capabilities>,
              )
            >
          >(bundled.getTerminalCapabilities)
          .cast(),
  () =>
      Native.addressOf<
            NativeFunction<
              Void Function(Pointer<bundled.CliRenderer>, Pointer<Uint8>, Size)
            >
          >(bundled.processCapabilityResponse)
          .cast(),
];

abstract interface class OpenTuiNativeSymbols {
  int otuiDartAbiVersion();
  Pointer<Char> otuiDartBuildInfo();
  void resolveRequiredSymbols();

  Pointer<NativeType> createRenderer(int width, int height, bool testing);
  void destroyRenderer(
    Pointer<NativeType> renderer,
    bool useAlternateScreen,
    int splitHeight,
  );
  void render(Pointer<NativeType> renderer, bool force);
  Pointer<NativeType> getNextBuffer(Pointer<NativeType> renderer);
  Pointer<NativeType> getCurrentBuffer(Pointer<NativeType> renderer);
  void resizeRenderer(Pointer<NativeType> renderer, int width, int height);
  void setBackgroundColor(Pointer<NativeType> renderer, Pointer<Float> color);
  void clearTerminal(Pointer<NativeType> renderer);

  int getBufferWidth(Pointer<NativeType> buffer);
  int getBufferHeight(Pointer<NativeType> buffer);
  void bufferClear(Pointer<NativeType> buffer, Pointer<Float> bg);
  void bufferDrawText(
    Pointer<NativeType> buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  );
  void bufferFillRect(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Float> bg,
  );
  void bufferDrawBox(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Float> borderColor,
    Pointer<Float> backgroundColor,
    Pointer<Uint8> title,
    int titleLen,
  );
  void setCursorPosition(
    Pointer<NativeType> renderer,
    int x,
    int y,
    bool visible,
  );
  void setCursorStyle(
    Pointer<NativeType> renderer,
    Pointer<Uint8> style,
    int styleLen,
    bool blinking,
  );
  void setCursorColor(Pointer<NativeType> renderer, Pointer<Float> color);

  Pointer<NativeType> createTextBuffer(int length, int widthMethod);
  void destroyTextBuffer(Pointer<NativeType> textBuffer);
  int textBufferGetLength(Pointer<NativeType> textBuffer);
  void textBufferSetCell(
    Pointer<NativeType> textBuffer,
    int index,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  );
  int textBufferWriteChunk(
    Pointer<NativeType> textBuffer,
    Pointer<Uint8> textBytes,
    int textLen,
    Pointer<Float> fg,
    Pointer<Float> bg,
    Pointer<Uint8> attr,
  );
  void textBufferFinalizeLineInfo(Pointer<NativeType> textBuffer);
  int textBufferGetLineCount(Pointer<NativeType> textBuffer);
  Pointer<Uint32> textBufferGetLineStartsPtr(Pointer<NativeType> textBuffer);
  Pointer<Uint32> textBufferGetLineWidthsPtr(Pointer<NativeType> textBuffer);
  void textBufferReset(Pointer<NativeType> textBuffer);
  void textBufferSetSelection(
    Pointer<NativeType> textBuffer,
    int start,
    int end,
    Pointer<Float> bgColor,
    Pointer<Float> fgColor,
  );
  void textBufferResetSelection(Pointer<NativeType> textBuffer);
  void bufferDrawTextBuffer(
    Pointer<NativeType> buffer,
    Pointer<NativeType> textBuffer,
    int x,
    int y,
    int clipX,
    int clipY,
    int clipWidth,
    int clipHeight,
    bool hasClipRect,
  );

  void enableMouse(Pointer<NativeType> renderer, bool enableMovement);
  void disableMouse(Pointer<NativeType> renderer);
  void enableKittyKeyboard(Pointer<NativeType> renderer, int flags);
  void disableKittyKeyboard(Pointer<NativeType> renderer);

  Pointer<Uint32> bufferGetCharPtr(Pointer<NativeType> buffer);
  Pointer<Float> bufferGetFgPtr(Pointer<NativeType> buffer);
  Pointer<Float> bufferGetBgPtr(Pointer<NativeType> buffer);
  Pointer<Uint8> bufferGetAttributesPtr(Pointer<NativeType> buffer);
  void bufferSetCellWithAlphaBlending(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  );
  void drawFrameBuffer(
    Pointer<NativeType> target,
    int destX,
    int destY,
    Pointer<NativeType> frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  );
  void bufferResize(Pointer<NativeType> buffer, int width, int height);
  Pointer<Uint32> textBufferGetCharPtr(Pointer<NativeType> textBuffer);
  Pointer<Float> textBufferGetFgPtr(Pointer<NativeType> textBuffer);
  Pointer<Float> textBufferGetBgPtr(Pointer<NativeType> textBuffer);
  Pointer<Uint16> textBufferGetAttributesPtr(Pointer<NativeType> textBuffer);

  void updateStats(
    Pointer<NativeType> renderer,
    double time,
    int fps,
    double frameCallbackTime,
  );
  void updateMemoryStats(
    Pointer<NativeType> renderer,
    int heapUsed,
    int heapTotal,
    int arrayBuffers,
  );
  void setupTerminal(Pointer<NativeType> renderer, bool useAlternateScreen);
  void setDebugOverlay(Pointer<NativeType> renderer, bool enabled, int corner);
  void dumpHitGrid(Pointer<NativeType> renderer);
  void dumpBuffers(Pointer<NativeType> renderer, int timestamp);
  void dumpStdoutBuffer(Pointer<NativeType> renderer, int timestamp);
  void addToHitGrid(
    Pointer<NativeType> renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  );
  int checkHit(Pointer<NativeType> renderer, int x, int y);
  void getTerminalCapabilities(
    Pointer<NativeType> renderer,
    Pointer<NativeType> caps,
  );
  void processCapabilityResponse(
    Pointer<NativeType> renderer,
    Pointer<Uint8> response,
    int responseLen,
  );
}

final class LookupOpenTuiNativeSymbols implements OpenTuiNativeSymbols {
  LookupOpenTuiNativeSymbols(DynamicLibrary library)
    : this.fromLookup(library.lookup);

  LookupOpenTuiNativeSymbols.fromLookup(
    OpenTuiNativeSymbolLookup lookupFunction,
  ) : _lookup = lookupFunction,
      _bindings = lookup.OpenTuiBindings.fromLookup(lookupFunction);

  final OpenTuiNativeSymbolLookup _lookup;
  final lookup.OpenTuiBindings _bindings;

  @override
  void resolveRequiredSymbols() {
    for (final symbolName in requiredOpenTuiNativeSymbolNames) {
      try {
        final pointer = _lookup<NativeFunction<Void Function()>>(symbolName);
        if (pointer == nullptr) {
          throw StateError('lookup returned nullptr');
        }
      } catch (error) {
        throw StateError(
          'Could not resolve required native symbol $symbolName: $error',
        );
      }
    }
  }

  @override
  int otuiDartAbiVersion() => _bindings.otui_dart_abi_version();

  @override
  Pointer<Char> otuiDartBuildInfo() => _bindings.otui_dart_build_info();

  @override
  Pointer<NativeType> createRenderer(int width, int height, bool testing) =>
      _bindings.createRenderer(width, height, testing).cast();

  @override
  void destroyRenderer(
    Pointer<NativeType> renderer,
    bool useAlternateScreen,
    int splitHeight,
  ) => _bindings.destroyRenderer(
    renderer.cast(),
    useAlternateScreen,
    splitHeight,
  );

  @override
  void render(Pointer<NativeType> renderer, bool force) =>
      _bindings.render(renderer.cast(), force);

  @override
  Pointer<NativeType> getNextBuffer(Pointer<NativeType> renderer) =>
      _bindings.getNextBuffer(renderer.cast()).cast();

  @override
  Pointer<NativeType> getCurrentBuffer(Pointer<NativeType> renderer) =>
      _bindings.getCurrentBuffer(renderer.cast()).cast();

  @override
  void resizeRenderer(Pointer<NativeType> renderer, int width, int height) =>
      _bindings.resizeRenderer(renderer.cast(), width, height);

  @override
  void setBackgroundColor(Pointer<NativeType> renderer, Pointer<Float> color) =>
      _bindings.setBackgroundColor(renderer.cast(), color);

  @override
  void clearTerminal(Pointer<NativeType> renderer) =>
      _bindings.clearTerminal(renderer.cast());

  @override
  int getBufferWidth(Pointer<NativeType> buffer) =>
      _bindings.getBufferWidth(buffer.cast());

  @override
  int getBufferHeight(Pointer<NativeType> buffer) =>
      _bindings.getBufferHeight(buffer.cast());

  @override
  void bufferClear(Pointer<NativeType> buffer, Pointer<Float> bg) =>
      _bindings.bufferClear(buffer.cast(), bg);

  @override
  void bufferDrawText(
    Pointer<NativeType> buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => _bindings.bufferDrawText(
    buffer.cast(),
    text,
    textLen,
    x,
    y,
    fg,
    bg,
    attributes,
  );

  @override
  void bufferFillRect(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Float> bg,
  ) => _bindings.bufferFillRect(buffer.cast(), x, y, width, height, bg);

  @override
  void bufferDrawBox(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Float> borderColor,
    Pointer<Float> backgroundColor,
    Pointer<Uint8> title,
    int titleLen,
  ) => _bindings.bufferDrawBox(
    buffer.cast(),
    x,
    y,
    width,
    height,
    borderChars,
    packedOptions,
    borderColor,
    backgroundColor,
    title,
    titleLen,
  );

  @override
  void setCursorPosition(
    Pointer<NativeType> renderer,
    int x,
    int y,
    bool visible,
  ) => _bindings.setCursorPosition(renderer.cast(), x, y, visible);

  @override
  void setCursorStyle(
    Pointer<NativeType> renderer,
    Pointer<Uint8> style,
    int styleLen,
    bool blinking,
  ) => _bindings.setCursorStyle(renderer.cast(), style, styleLen, blinking);

  @override
  void setCursorColor(Pointer<NativeType> renderer, Pointer<Float> color) =>
      _bindings.setCursorColor(renderer.cast(), color);

  @override
  Pointer<NativeType> createTextBuffer(int length, int widthMethod) =>
      _bindings.createTextBuffer(length, widthMethod).cast();

  @override
  void destroyTextBuffer(Pointer<NativeType> textBuffer) =>
      _bindings.destroyTextBuffer(textBuffer.cast());

  @override
  int textBufferGetLength(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetLength(textBuffer.cast());

  @override
  void textBufferSetCell(
    Pointer<NativeType> textBuffer,
    int index,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => _bindings.textBufferSetCell(
    textBuffer.cast(),
    index,
    charCode,
    fg,
    bg,
    attributes,
  );

  @override
  int textBufferWriteChunk(
    Pointer<NativeType> textBuffer,
    Pointer<Uint8> textBytes,
    int textLen,
    Pointer<Float> fg,
    Pointer<Float> bg,
    Pointer<Uint8> attr,
  ) => _bindings.textBufferWriteChunk(
    textBuffer.cast(),
    textBytes,
    textLen,
    fg,
    bg,
    attr,
  );

  @override
  void textBufferFinalizeLineInfo(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferFinalizeLineInfo(textBuffer.cast());

  @override
  int textBufferGetLineCount(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetLineCount(textBuffer.cast());

  @override
  Pointer<Uint32> textBufferGetLineStartsPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetLineStartsPtr(textBuffer.cast());

  @override
  Pointer<Uint32> textBufferGetLineWidthsPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetLineWidthsPtr(textBuffer.cast());

  @override
  void textBufferReset(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferReset(textBuffer.cast());

  @override
  void textBufferSetSelection(
    Pointer<NativeType> textBuffer,
    int start,
    int end,
    Pointer<Float> bgColor,
    Pointer<Float> fgColor,
  ) => _bindings.textBufferSetSelection(
    textBuffer.cast(),
    start,
    end,
    bgColor,
    fgColor,
  );

  @override
  void textBufferResetSelection(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferResetSelection(textBuffer.cast());

  @override
  void bufferDrawTextBuffer(
    Pointer<NativeType> buffer,
    Pointer<NativeType> textBuffer,
    int x,
    int y,
    int clipX,
    int clipY,
    int clipWidth,
    int clipHeight,
    bool hasClipRect,
  ) => _bindings.bufferDrawTextBuffer(
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

  @override
  void enableMouse(Pointer<NativeType> renderer, bool enableMovement) =>
      _bindings.enableMouse(renderer.cast(), enableMovement);

  @override
  void disableMouse(Pointer<NativeType> renderer) =>
      _bindings.disableMouse(renderer.cast());

  @override
  void enableKittyKeyboard(Pointer<NativeType> renderer, int flags) =>
      _bindings.enableKittyKeyboard(renderer.cast(), flags);

  @override
  void disableKittyKeyboard(Pointer<NativeType> renderer) =>
      _bindings.disableKittyKeyboard(renderer.cast());

  @override
  Pointer<Uint32> bufferGetCharPtr(Pointer<NativeType> buffer) =>
      _bindings.bufferGetCharPtr(buffer.cast());

  @override
  Pointer<Float> bufferGetFgPtr(Pointer<NativeType> buffer) =>
      _bindings.bufferGetFgPtr(buffer.cast());

  @override
  Pointer<Float> bufferGetBgPtr(Pointer<NativeType> buffer) =>
      _bindings.bufferGetBgPtr(buffer.cast());

  @override
  Pointer<Uint8> bufferGetAttributesPtr(Pointer<NativeType> buffer) =>
      _bindings.bufferGetAttributesPtr(buffer.cast());

  @override
  void bufferSetCellWithAlphaBlending(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => _bindings.bufferSetCellWithAlphaBlending(
    buffer.cast(),
    x,
    y,
    charCode,
    fg,
    bg,
    attributes,
  );

  @override
  void drawFrameBuffer(
    Pointer<NativeType> target,
    int destX,
    int destY,
    Pointer<NativeType> frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) => _bindings.drawFrameBuffer(
    target.cast(),
    destX,
    destY,
    frameBuffer.cast(),
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
  );

  @override
  void bufferResize(Pointer<NativeType> buffer, int width, int height) =>
      _bindings.bufferResize(buffer.cast(), width, height);

  @override
  Pointer<Uint32> textBufferGetCharPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetCharPtr(textBuffer.cast());

  @override
  Pointer<Float> textBufferGetFgPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetFgPtr(textBuffer.cast());

  @override
  Pointer<Float> textBufferGetBgPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetBgPtr(textBuffer.cast());

  @override
  Pointer<Uint16> textBufferGetAttributesPtr(Pointer<NativeType> textBuffer) =>
      _bindings.textBufferGetAttributesPtr(textBuffer.cast());

  @override
  void updateStats(
    Pointer<NativeType> renderer,
    double time,
    int fps,
    double frameCallbackTime,
  ) => _bindings.updateStats(renderer.cast(), time, fps, frameCallbackTime);

  @override
  void updateMemoryStats(
    Pointer<NativeType> renderer,
    int heapUsed,
    int heapTotal,
    int arrayBuffers,
  ) => _bindings.updateMemoryStats(
    renderer.cast(),
    heapUsed,
    heapTotal,
    arrayBuffers,
  );

  @override
  void setupTerminal(Pointer<NativeType> renderer, bool useAlternateScreen) =>
      _bindings.setupTerminal(renderer.cast(), useAlternateScreen);

  @override
  void setDebugOverlay(
    Pointer<NativeType> renderer,
    bool enabled,
    int corner,
  ) => _bindings.setDebugOverlay(renderer.cast(), enabled, corner);

  @override
  void dumpHitGrid(Pointer<NativeType> renderer) =>
      _bindings.dumpHitGrid(renderer.cast());

  @override
  void dumpBuffers(Pointer<NativeType> renderer, int timestamp) =>
      _bindings.dumpBuffers(renderer.cast(), timestamp);

  @override
  void dumpStdoutBuffer(Pointer<NativeType> renderer, int timestamp) =>
      _bindings.dumpStdoutBuffer(renderer.cast(), timestamp);

  @override
  void addToHitGrid(
    Pointer<NativeType> renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) => _bindings.addToHitGrid(renderer.cast(), x, y, width, height, id);

  @override
  int checkHit(Pointer<NativeType> renderer, int x, int y) =>
      _bindings.checkHit(renderer.cast(), x, y);

  @override
  void getTerminalCapabilities(
    Pointer<NativeType> renderer,
    Pointer<NativeType> caps,
  ) => _bindings.getTerminalCapabilities(renderer.cast(), caps.cast());

  @override
  void processCapabilityResponse(
    Pointer<NativeType> renderer,
    Pointer<Uint8> response,
    int responseLen,
  ) => _bindings.processCapabilityResponse(
    renderer.cast(),
    response,
    responseLen,
  );
}

final class BundledOpenTuiNativeSymbols implements OpenTuiNativeSymbols {
  @override
  void resolveRequiredSymbols() {
    if (_bundledRequiredSymbolResolvers.length !=
        requiredOpenTuiNativeSymbolNames.length) {
      throw StateError(
        'Bundled native resolver count does not match the required ABI',
      );
    }
    for (
      var index = 0;
      index < _bundledRequiredSymbolResolvers.length;
      index++
    ) {
      final symbolName = requiredOpenTuiNativeSymbolNames[index];
      try {
        final pointer = _bundledRequiredSymbolResolvers[index]();
        if (pointer == nullptr) {
          throw StateError('Native.addressOf returned nullptr');
        }
      } catch (error) {
        throw StateError(
          'Could not resolve required native symbol $symbolName: $error',
        );
      }
    }
  }

  @override
  int otuiDartAbiVersion() => bundled.otui_dart_abi_version();

  @override
  Pointer<Char> otuiDartBuildInfo() => bundled.otui_dart_build_info();

  @override
  Pointer<NativeType> createRenderer(int width, int height, bool testing) =>
      bundled.createRenderer(width, height, testing).cast();

  @override
  void destroyRenderer(
    Pointer<NativeType> renderer,
    bool useAlternateScreen,
    int splitHeight,
  ) =>
      bundled.destroyRenderer(renderer.cast(), useAlternateScreen, splitHeight);

  @override
  void render(Pointer<NativeType> renderer, bool force) =>
      bundled.render(renderer.cast(), force);

  @override
  Pointer<NativeType> getNextBuffer(Pointer<NativeType> renderer) =>
      bundled.getNextBuffer(renderer.cast()).cast();

  @override
  Pointer<NativeType> getCurrentBuffer(Pointer<NativeType> renderer) =>
      bundled.getCurrentBuffer(renderer.cast()).cast();

  @override
  void resizeRenderer(Pointer<NativeType> renderer, int width, int height) =>
      bundled.resizeRenderer(renderer.cast(), width, height);

  @override
  void setBackgroundColor(Pointer<NativeType> renderer, Pointer<Float> color) =>
      bundled.setBackgroundColor(renderer.cast(), color);

  @override
  void clearTerminal(Pointer<NativeType> renderer) =>
      bundled.clearTerminal(renderer.cast());

  @override
  int getBufferWidth(Pointer<NativeType> buffer) =>
      bundled.getBufferWidth(buffer.cast());

  @override
  int getBufferHeight(Pointer<NativeType> buffer) =>
      bundled.getBufferHeight(buffer.cast());

  @override
  void bufferClear(Pointer<NativeType> buffer, Pointer<Float> bg) =>
      bundled.bufferClear(buffer.cast(), bg);

  @override
  void bufferDrawText(
    Pointer<NativeType> buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => bundled.bufferDrawText(
    buffer.cast(),
    text,
    textLen,
    x,
    y,
    fg,
    bg,
    attributes,
  );

  @override
  void bufferFillRect(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Float> bg,
  ) => bundled.bufferFillRect(buffer.cast(), x, y, width, height, bg);

  @override
  void bufferDrawBox(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Float> borderColor,
    Pointer<Float> backgroundColor,
    Pointer<Uint8> title,
    int titleLen,
  ) => bundled.bufferDrawBox(
    buffer.cast(),
    x,
    y,
    width,
    height,
    borderChars,
    packedOptions,
    borderColor,
    backgroundColor,
    title,
    titleLen,
  );

  @override
  void setCursorPosition(
    Pointer<NativeType> renderer,
    int x,
    int y,
    bool visible,
  ) => bundled.setCursorPosition(renderer.cast(), x, y, visible);

  @override
  void setCursorStyle(
    Pointer<NativeType> renderer,
    Pointer<Uint8> style,
    int styleLen,
    bool blinking,
  ) => bundled.setCursorStyle(renderer.cast(), style, styleLen, blinking);

  @override
  void setCursorColor(Pointer<NativeType> renderer, Pointer<Float> color) =>
      bundled.setCursorColor(renderer.cast(), color);

  @override
  Pointer<NativeType> createTextBuffer(int length, int widthMethod) =>
      bundled.createTextBuffer(length, widthMethod).cast();

  @override
  void destroyTextBuffer(Pointer<NativeType> textBuffer) =>
      bundled.destroyTextBuffer(textBuffer.cast());

  @override
  int textBufferGetLength(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetLength(textBuffer.cast());

  @override
  void textBufferSetCell(
    Pointer<NativeType> textBuffer,
    int index,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => bundled.textBufferSetCell(
    textBuffer.cast(),
    index,
    charCode,
    fg,
    bg,
    attributes,
  );

  @override
  int textBufferWriteChunk(
    Pointer<NativeType> textBuffer,
    Pointer<Uint8> textBytes,
    int textLen,
    Pointer<Float> fg,
    Pointer<Float> bg,
    Pointer<Uint8> attr,
  ) => bundled.textBufferWriteChunk(
    textBuffer.cast(),
    textBytes,
    textLen,
    fg,
    bg,
    attr,
  );

  @override
  void textBufferFinalizeLineInfo(Pointer<NativeType> textBuffer) =>
      bundled.textBufferFinalizeLineInfo(textBuffer.cast());

  @override
  int textBufferGetLineCount(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetLineCount(textBuffer.cast());

  @override
  Pointer<Uint32> textBufferGetLineStartsPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetLineStartsPtr(textBuffer.cast());

  @override
  Pointer<Uint32> textBufferGetLineWidthsPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetLineWidthsPtr(textBuffer.cast());

  @override
  void textBufferReset(Pointer<NativeType> textBuffer) =>
      bundled.textBufferReset(textBuffer.cast());

  @override
  void textBufferSetSelection(
    Pointer<NativeType> textBuffer,
    int start,
    int end,
    Pointer<Float> bgColor,
    Pointer<Float> fgColor,
  ) => bundled.textBufferSetSelection(
    textBuffer.cast(),
    start,
    end,
    bgColor,
    fgColor,
  );

  @override
  void textBufferResetSelection(Pointer<NativeType> textBuffer) =>
      bundled.textBufferResetSelection(textBuffer.cast());

  @override
  void bufferDrawTextBuffer(
    Pointer<NativeType> buffer,
    Pointer<NativeType> textBuffer,
    int x,
    int y,
    int clipX,
    int clipY,
    int clipWidth,
    int clipHeight,
    bool hasClipRect,
  ) => bundled.bufferDrawTextBuffer(
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

  @override
  void enableMouse(Pointer<NativeType> renderer, bool enableMovement) =>
      bundled.enableMouse(renderer.cast(), enableMovement);

  @override
  void disableMouse(Pointer<NativeType> renderer) =>
      bundled.disableMouse(renderer.cast());

  @override
  void enableKittyKeyboard(Pointer<NativeType> renderer, int flags) =>
      bundled.enableKittyKeyboard(renderer.cast(), flags);

  @override
  void disableKittyKeyboard(Pointer<NativeType> renderer) =>
      bundled.disableKittyKeyboard(renderer.cast());

  @override
  Pointer<Uint32> bufferGetCharPtr(Pointer<NativeType> buffer) =>
      bundled.bufferGetCharPtr(buffer.cast());

  @override
  Pointer<Float> bufferGetFgPtr(Pointer<NativeType> buffer) =>
      bundled.bufferGetFgPtr(buffer.cast());

  @override
  Pointer<Float> bufferGetBgPtr(Pointer<NativeType> buffer) =>
      bundled.bufferGetBgPtr(buffer.cast());

  @override
  Pointer<Uint8> bufferGetAttributesPtr(Pointer<NativeType> buffer) =>
      bundled.bufferGetAttributesPtr(buffer.cast());

  @override
  void bufferSetCellWithAlphaBlending(
    Pointer<NativeType> buffer,
    int x,
    int y,
    int charCode,
    Pointer<Float> fg,
    Pointer<Float> bg,
    int attributes,
  ) => bundled.bufferSetCellWithAlphaBlending(
    buffer.cast(),
    x,
    y,
    charCode,
    fg,
    bg,
    attributes,
  );

  @override
  void drawFrameBuffer(
    Pointer<NativeType> target,
    int destX,
    int destY,
    Pointer<NativeType> frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) => bundled.drawFrameBuffer(
    target.cast(),
    destX,
    destY,
    frameBuffer.cast(),
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
  );

  @override
  void bufferResize(Pointer<NativeType> buffer, int width, int height) =>
      bundled.bufferResize(buffer.cast(), width, height);

  @override
  Pointer<Uint32> textBufferGetCharPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetCharPtr(textBuffer.cast());

  @override
  Pointer<Float> textBufferGetFgPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetFgPtr(textBuffer.cast());

  @override
  Pointer<Float> textBufferGetBgPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetBgPtr(textBuffer.cast());

  @override
  Pointer<Uint16> textBufferGetAttributesPtr(Pointer<NativeType> textBuffer) =>
      bundled.textBufferGetAttributesPtr(textBuffer.cast());

  @override
  void updateStats(
    Pointer<NativeType> renderer,
    double time,
    int fps,
    double frameCallbackTime,
  ) => bundled.updateStats(renderer.cast(), time, fps, frameCallbackTime);

  @override
  void updateMemoryStats(
    Pointer<NativeType> renderer,
    int heapUsed,
    int heapTotal,
    int arrayBuffers,
  ) => bundled.updateMemoryStats(
    renderer.cast(),
    heapUsed,
    heapTotal,
    arrayBuffers,
  );

  @override
  void setupTerminal(Pointer<NativeType> renderer, bool useAlternateScreen) =>
      bundled.setupTerminal(renderer.cast(), useAlternateScreen);

  @override
  void setDebugOverlay(
    Pointer<NativeType> renderer,
    bool enabled,
    int corner,
  ) => bundled.setDebugOverlay(renderer.cast(), enabled, corner);

  @override
  void dumpHitGrid(Pointer<NativeType> renderer) =>
      bundled.dumpHitGrid(renderer.cast());

  @override
  void dumpBuffers(Pointer<NativeType> renderer, int timestamp) =>
      bundled.dumpBuffers(renderer.cast(), timestamp);

  @override
  void dumpStdoutBuffer(Pointer<NativeType> renderer, int timestamp) =>
      bundled.dumpStdoutBuffer(renderer.cast(), timestamp);

  @override
  void addToHitGrid(
    Pointer<NativeType> renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) => bundled.addToHitGrid(renderer.cast(), x, y, width, height, id);

  @override
  int checkHit(Pointer<NativeType> renderer, int x, int y) =>
      bundled.checkHit(renderer.cast(), x, y);

  @override
  void getTerminalCapabilities(
    Pointer<NativeType> renderer,
    Pointer<NativeType> caps,
  ) => bundled.getTerminalCapabilities(renderer.cast(), caps.cast());

  @override
  void processCapabilityResponse(
    Pointer<NativeType> renderer,
    Pointer<Uint8> response,
    int responseLen,
  ) =>
      bundled.processCapabilityResponse(renderer.cast(), response, responseLen);
}
