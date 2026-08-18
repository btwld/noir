// ignore_for_file: avoid_positional_boolean_parameters, public_member_api_docs

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'generated_bindings.dart' as lookup;
import 'native_asset_bindings.dart' as bundled;

typedef OpenTuiNativeSymbolLookup =
    Pointer<T> Function<T extends NativeType>(String symbolName);

abstract interface class OpenTuiNativeSymbols {
  int createRenderer(int width, int height, int outputKind, int remoteMode);
  void destroyRenderer(int renderer);
  int render(int renderer, bool force);
  int getNextBuffer(int renderer);
  int getCurrentBuffer(int renderer);
  void resizeRenderer(int renderer, int width, int height);
  void setBackgroundColor(int renderer, Pointer<Uint16> color);
  void clearTerminal(int renderer);

  int getBufferWidth(int buffer);
  int getBufferHeight(int buffer);
  void bufferClear(int buffer, Pointer<Uint16> bg);
  void bufferDrawText(
    int buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  );
  void bufferFillRect(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint16> bg,
  );
  void bufferDrawBox(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Uint16> borderColor,
    Pointer<Uint16> backgroundColor,
    Pointer<Uint16> titleColor,
    Pointer<Uint8> title,
    int titleLen,
  );
  Pointer<Uint32> bufferGetCharPtr(int buffer);
  Pointer<Uint16> bufferGetFgPtr(int buffer);
  Pointer<Uint16> bufferGetBgPtr(int buffer);
  Pointer<Uint32> bufferGetAttributesPtr(int buffer);
  int bufferGetRealCharSize(int buffer);
  int bufferWriteResolvedChars(
    int buffer,
    Pointer<Uint8> output,
    int outputLen,
    bool addLineBreaks,
  );
  void bufferSetCellWithAlphaBlending(
    int buffer,
    int x,
    int y,
    int character,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  );
  void drawFrameBuffer(
    int target,
    int destX,
    int destY,
    int frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  );
  void bufferResize(int buffer, int width, int height);

  void bufferPushScissorRect(int buffer, int x, int y, int width, int height);
  void bufferPopScissorRect(int buffer);
  void bufferClearScissorRects(int buffer);
  void bufferPushOpacity(int buffer, double opacity);
  void bufferPopOpacity(int buffer);
  void bufferClearOpacity(int buffer);

  void setCursorPosition(int renderer, int x, int y, bool visible);
  void setCursorStyleOptions(
    int renderer,
    int style,
    int blinking,
    Pointer<Uint16> color,
  );

  void enableMouse(int renderer, bool enableMovement);
  void disableMouse(int renderer);
  void enableKittyKeyboard(int renderer, int flags);
  void disableKittyKeyboard(int renderer);
  void setupTerminal(int renderer, bool useAlternateScreen);
  void addToHitGrid(int renderer, int x, int y, int width, int height, int id);
  int checkHit(int renderer, int x, int y);
  void processCapabilityResponse(
    int renderer,
    Pointer<Uint8> response,
    int responseLen,
  );
}

final class LookupOpenTuiNativeSymbols implements OpenTuiNativeSymbols {
  LookupOpenTuiNativeSymbols(DynamicLibrary library)
    : this.fromLookup(library.lookup);

  LookupOpenTuiNativeSymbols.fromLookup(
    OpenTuiNativeSymbolLookup lookupFunction,
  ) : _bindings = lookup.OpenTuiBindings.fromLookup(lookupFunction);

  final lookup.OpenTuiBindings _bindings;

  @override
  int createRenderer(int width, int height, int outputKind, int remoteMode) =>
      _bindings.createRenderer(width, height, outputKind, remoteMode, nullptr);
  @override
  void destroyRenderer(int renderer) => _bindings.destroyRenderer(renderer);
  @override
  int render(int renderer, bool force) => _bindings.render(renderer, force);
  @override
  int getNextBuffer(int renderer) => _bindings.getNextBuffer(renderer);
  @override
  int getCurrentBuffer(int renderer) => _bindings.getCurrentBuffer(renderer);
  @override
  void resizeRenderer(int renderer, int width, int height) =>
      _bindings.resizeRenderer(renderer, width, height);
  @override
  void setBackgroundColor(int renderer, Pointer<Uint16> color) =>
      _bindings.setBackgroundColor(renderer, color);
  @override
  void clearTerminal(int renderer) => _bindings.clearTerminal(renderer);
  @override
  int getBufferWidth(int buffer) => _bindings.getBufferWidth(buffer);
  @override
  int getBufferHeight(int buffer) => _bindings.getBufferHeight(buffer);
  @override
  void bufferClear(int buffer, Pointer<Uint16> bg) =>
      _bindings.bufferClear(buffer, bg);
  @override
  void bufferDrawText(
    int buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  ) =>
      _bindings.bufferDrawText(buffer, text, textLen, x, y, fg, bg, attributes);
  @override
  void bufferFillRect(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint16> bg,
  ) => _bindings.bufferFillRect(buffer, x, y, width, height, bg);
  @override
  void bufferDrawBox(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Uint16> borderColor,
    Pointer<Uint16> backgroundColor,
    Pointer<Uint16> titleColor,
    Pointer<Uint8> title,
    int titleLen,
  ) => _bindings.bufferDrawBox(
    buffer,
    x,
    y,
    width,
    height,
    borderChars,
    packedOptions,
    borderColor,
    backgroundColor,
    titleColor,
    title,
    titleLen,
    nullptr,
    0,
  );
  @override
  Pointer<Uint32> bufferGetCharPtr(int buffer) =>
      _bindings.bufferGetCharPtr(buffer);
  @override
  Pointer<Uint16> bufferGetFgPtr(int buffer) =>
      _bindings.bufferGetFgPtr(buffer);
  @override
  Pointer<Uint16> bufferGetBgPtr(int buffer) =>
      _bindings.bufferGetBgPtr(buffer);
  @override
  Pointer<Uint32> bufferGetAttributesPtr(int buffer) =>
      _bindings.bufferGetAttributesPtr(buffer);
  @override
  int bufferGetRealCharSize(int buffer) =>
      _bindings.bufferGetRealCharSize(buffer);
  @override
  int bufferWriteResolvedChars(
    int buffer,
    Pointer<Uint8> output,
    int outputLen,
    bool addLineBreaks,
  ) => _bindings.bufferWriteResolvedChars(
    buffer,
    output,
    outputLen,
    addLineBreaks,
  );
  @override
  void bufferSetCellWithAlphaBlending(
    int buffer,
    int x,
    int y,
    int character,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  ) => _bindings.bufferSetCellWithAlphaBlending(
    buffer,
    x,
    y,
    character,
    fg,
    bg,
    attributes,
  );
  @override
  void drawFrameBuffer(
    int target,
    int destX,
    int destY,
    int frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) => _bindings.drawFrameBuffer(
    target,
    destX,
    destY,
    frameBuffer,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
  );
  @override
  void bufferResize(int buffer, int width, int height) =>
      _bindings.bufferResize(buffer, width, height);
  @override
  void bufferPushScissorRect(int buffer, int x, int y, int width, int height) =>
      _bindings.bufferPushScissorRect(buffer, x, y, width, height);
  @override
  void bufferPopScissorRect(int buffer) =>
      _bindings.bufferPopScissorRect(buffer);
  @override
  void bufferClearScissorRects(int buffer) =>
      _bindings.bufferClearScissorRects(buffer);
  @override
  void bufferPushOpacity(int buffer, double opacity) =>
      _bindings.bufferPushOpacity(buffer, opacity);
  @override
  void bufferPopOpacity(int buffer) => _bindings.bufferPopOpacity(buffer);
  @override
  void bufferClearOpacity(int buffer) => _bindings.bufferClearOpacity(buffer);
  @override
  void setCursorPosition(int renderer, int x, int y, bool visible) =>
      _bindings.setCursorPosition(renderer, x, y, visible);
  @override
  void setCursorStyleOptions(
    int renderer,
    int style,
    int blinking,
    Pointer<Uint16> color,
  ) {
    using((arena) {
      final options = arena<lookup.CursorStyleOptions>();
      options.ref
        ..style = style
        ..blinking = blinking
        ..color = color
        ..cursor = 0xFF;
      _bindings.setCursorStyleOptions(renderer, options);
    });
  }

  @override
  void enableMouse(int renderer, bool enableMovement) =>
      _bindings.enableMouse(renderer, enableMovement);
  @override
  void disableMouse(int renderer) => _bindings.disableMouse(renderer);
  @override
  void enableKittyKeyboard(int renderer, int flags) =>
      _bindings.enableKittyKeyboard(renderer, flags);
  @override
  void disableKittyKeyboard(int renderer) =>
      _bindings.disableKittyKeyboard(renderer);
  @override
  void setupTerminal(int renderer, bool useAlternateScreen) =>
      _bindings.setupTerminal(renderer, useAlternateScreen);
  @override
  void addToHitGrid(
    int renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) => _bindings.addToHitGrid(renderer, x, y, width, height, id);
  @override
  int checkHit(int renderer, int x, int y) =>
      _bindings.checkHit(renderer, x, y);
  @override
  void processCapabilityResponse(
    int renderer,
    Pointer<Uint8> response,
    int responseLen,
  ) => _bindings.processCapabilityResponse(renderer, response, responseLen);
}

final class BundledOpenTuiNativeSymbols implements OpenTuiNativeSymbols {
  @override
  int createRenderer(int width, int height, int outputKind, int remoteMode) =>
      bundled.createRenderer(width, height, outputKind, remoteMode, nullptr);
  @override
  void destroyRenderer(int renderer) => bundled.destroyRenderer(renderer);
  @override
  int render(int renderer, bool force) => bundled.render(renderer, force);
  @override
  int getNextBuffer(int renderer) => bundled.getNextBuffer(renderer);
  @override
  int getCurrentBuffer(int renderer) => bundled.getCurrentBuffer(renderer);
  @override
  void resizeRenderer(int renderer, int width, int height) =>
      bundled.resizeRenderer(renderer, width, height);
  @override
  void setBackgroundColor(int renderer, Pointer<Uint16> color) =>
      bundled.setBackgroundColor(renderer, color);
  @override
  void clearTerminal(int renderer) => bundled.clearTerminal(renderer);
  @override
  int getBufferWidth(int buffer) => bundled.getBufferWidth(buffer);
  @override
  int getBufferHeight(int buffer) => bundled.getBufferHeight(buffer);
  @override
  void bufferClear(int buffer, Pointer<Uint16> bg) =>
      bundled.bufferClear(buffer, bg);
  @override
  void bufferDrawText(
    int buffer,
    Pointer<Uint8> text,
    int textLen,
    int x,
    int y,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  ) => bundled.bufferDrawText(buffer, text, textLen, x, y, fg, bg, attributes);
  @override
  void bufferFillRect(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint16> bg,
  ) => bundled.bufferFillRect(buffer, x, y, width, height, bg);
  @override
  void bufferDrawBox(
    int buffer,
    int x,
    int y,
    int width,
    int height,
    Pointer<Uint32> borderChars,
    int packedOptions,
    Pointer<Uint16> borderColor,
    Pointer<Uint16> backgroundColor,
    Pointer<Uint16> titleColor,
    Pointer<Uint8> title,
    int titleLen,
  ) => bundled.bufferDrawBox(
    buffer,
    x,
    y,
    width,
    height,
    borderChars,
    packedOptions,
    borderColor,
    backgroundColor,
    titleColor,
    title,
    titleLen,
    nullptr,
    0,
  );
  @override
  Pointer<Uint32> bufferGetCharPtr(int buffer) =>
      bundled.bufferGetCharPtr(buffer);
  @override
  Pointer<Uint16> bufferGetFgPtr(int buffer) => bundled.bufferGetFgPtr(buffer);
  @override
  Pointer<Uint16> bufferGetBgPtr(int buffer) => bundled.bufferGetBgPtr(buffer);
  @override
  Pointer<Uint32> bufferGetAttributesPtr(int buffer) =>
      bundled.bufferGetAttributesPtr(buffer);
  @override
  int bufferGetRealCharSize(int buffer) =>
      bundled.bufferGetRealCharSize(buffer);
  @override
  int bufferWriteResolvedChars(
    int buffer,
    Pointer<Uint8> output,
    int outputLen,
    bool addLineBreaks,
  ) => bundled.bufferWriteResolvedChars(
    buffer,
    output,
    outputLen,
    addLineBreaks,
  );
  @override
  void bufferSetCellWithAlphaBlending(
    int buffer,
    int x,
    int y,
    int character,
    Pointer<Uint16> fg,
    Pointer<Uint16> bg,
    int attributes,
  ) => bundled.bufferSetCellWithAlphaBlending(
    buffer,
    x,
    y,
    character,
    fg,
    bg,
    attributes,
  );
  @override
  void drawFrameBuffer(
    int target,
    int destX,
    int destY,
    int frameBuffer,
    int sourceX,
    int sourceY,
    int sourceWidth,
    int sourceHeight,
  ) => bundled.drawFrameBuffer(
    target,
    destX,
    destY,
    frameBuffer,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
  );
  @override
  void bufferResize(int buffer, int width, int height) =>
      bundled.bufferResize(buffer, width, height);
  @override
  void bufferPushScissorRect(int buffer, int x, int y, int width, int height) =>
      bundled.bufferPushScissorRect(buffer, x, y, width, height);
  @override
  void bufferPopScissorRect(int buffer) => bundled.bufferPopScissorRect(buffer);
  @override
  void bufferClearScissorRects(int buffer) =>
      bundled.bufferClearScissorRects(buffer);
  @override
  void bufferPushOpacity(int buffer, double opacity) =>
      bundled.bufferPushOpacity(buffer, opacity);
  @override
  void bufferPopOpacity(int buffer) => bundled.bufferPopOpacity(buffer);
  @override
  void bufferClearOpacity(int buffer) => bundled.bufferClearOpacity(buffer);
  @override
  void setCursorPosition(int renderer, int x, int y, bool visible) =>
      bundled.setCursorPosition(renderer, x, y, visible);
  @override
  void setCursorStyleOptions(
    int renderer,
    int style,
    int blinking,
    Pointer<Uint16> color,
  ) {
    using((arena) {
      final options = arena<bundled.CursorStyleOptions>();
      options.ref
        ..style = style
        ..blinking = blinking
        ..color = color
        ..cursor = 0xFF;
      bundled.setCursorStyleOptions(renderer, options);
    });
  }

  @override
  void enableMouse(int renderer, bool enableMovement) =>
      bundled.enableMouse(renderer, enableMovement);
  @override
  void disableMouse(int renderer) => bundled.disableMouse(renderer);
  @override
  void enableKittyKeyboard(int renderer, int flags) =>
      bundled.enableKittyKeyboard(renderer, flags);
  @override
  void disableKittyKeyboard(int renderer) =>
      bundled.disableKittyKeyboard(renderer);
  @override
  void setupTerminal(int renderer, bool useAlternateScreen) =>
      bundled.setupTerminal(renderer, useAlternateScreen);
  @override
  void addToHitGrid(
    int renderer,
    int x,
    int y,
    int width,
    int height,
    int id,
  ) => bundled.addToHitGrid(renderer, x, y, width, height, id);
  @override
  int checkHit(int renderer, int x, int y) => bundled.checkHit(renderer, x, y);
  @override
  void processCapabilityResponse(
    int renderer,
    Pointer<Uint8> response,
    int responseLen,
  ) => bundled.processCapabilityResponse(renderer, response, responseLen);
}
