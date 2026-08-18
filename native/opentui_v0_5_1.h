#ifndef NOIR_OPENTUI_V0_5_1_H_
#define NOIR_OPENTUI_V0_5_1_H_

#include <stdbool.h>
#include <stdint.h>

// Noir-owned declaration of the canonical OpenTUI v0.5.1 exports selected by
// this package. The source of truth is external/opentui/packages/core/src/zig/
// lib.zig at ad9a818d7a9d73f3386e92a445d0feb4b395c69e.

typedef uint32_t OpenTuiHandle;

typedef struct CursorStyleOptions {
  uint8_t style;
  uint8_t blinking;
  const uint16_t *color;
  uint8_t cursor;
} CursorStyleOptions;

OpenTuiHandle createRenderer(uint32_t width, uint32_t height,
                             uint8_t bufferedDestinationKind,
                             uint8_t remoteModeValue, void *feedPtr);
void destroyRenderer(OpenTuiHandle renderer);
uint8_t render(OpenTuiHandle renderer, bool force);
OpenTuiHandle getNextBuffer(OpenTuiHandle renderer);
OpenTuiHandle getCurrentBuffer(OpenTuiHandle renderer);
void resizeRenderer(OpenTuiHandle renderer, uint32_t width, uint32_t height);
void setBackgroundColor(OpenTuiHandle renderer, const uint16_t *color);
void clearTerminal(OpenTuiHandle renderer);

uint32_t getBufferWidth(OpenTuiHandle buffer);
uint32_t getBufferHeight(OpenTuiHandle buffer);
void bufferClear(OpenTuiHandle buffer, const uint16_t *bg);
void bufferDrawText(OpenTuiHandle buffer, const uint8_t *text,
                    uint32_t textLen, uint32_t x, uint32_t y,
                    const uint16_t *fg, const uint16_t *bg,
                    uint32_t attributes);
void bufferFillRect(OpenTuiHandle buffer, uint32_t x, uint32_t y,
                    uint32_t width, uint32_t height, const uint16_t *bg);
void bufferDrawBox(OpenTuiHandle buffer, int32_t x, int32_t y, uint32_t width,
                   uint32_t height, const uint32_t *borderChars,
                   uint32_t packedOptions, const uint16_t *borderColor,
                   const uint16_t *backgroundColor,
                   const uint16_t *titleColor, const uint8_t *title,
                   uint32_t titleLen, const uint8_t *bottomTitle,
                   uint32_t bottomTitleLen);
uint32_t *bufferGetCharPtr(OpenTuiHandle buffer);
uint16_t *bufferGetFgPtr(OpenTuiHandle buffer);
uint16_t *bufferGetBgPtr(OpenTuiHandle buffer);
uint32_t *bufferGetAttributesPtr(OpenTuiHandle buffer);
uint32_t bufferGetRealCharSize(OpenTuiHandle buffer);
uint32_t bufferWriteResolvedChars(OpenTuiHandle buffer, uint8_t *output,
                                  uint32_t outputLen, bool addLineBreaks);
void bufferSetCellWithAlphaBlending(OpenTuiHandle buffer, uint32_t x,
                                    uint32_t y, uint32_t character,
                                    const uint16_t *fg, const uint16_t *bg,
                                    uint32_t attributes);
void drawFrameBuffer(OpenTuiHandle target, int32_t destX, int32_t destY,
                     OpenTuiHandle frameBuffer, uint32_t sourceX,
                     uint32_t sourceY, uint32_t sourceWidth,
                     uint32_t sourceHeight);
void bufferResize(OpenTuiHandle buffer, uint32_t width, uint32_t height);

// Native clip and opacity stacks. Every native write funnel honours both
// (buffer.zig validateAndIndex -> isPointInScissor, and getCurrentOpacity).
// Exposed on the raw binding surface; Noir's own clip seam stays in Dart.
void bufferPushScissorRect(OpenTuiHandle buffer, int32_t x, int32_t y,
                           uint32_t width, uint32_t height);
void bufferPopScissorRect(OpenTuiHandle buffer);
void bufferClearScissorRects(OpenTuiHandle buffer);
void bufferPushOpacity(OpenTuiHandle buffer, float opacity);
void bufferPopOpacity(OpenTuiHandle buffer);
void bufferClearOpacity(OpenTuiHandle buffer);

void setCursorPosition(OpenTuiHandle renderer, int32_t x, int32_t y,
                       bool visible);
void setCursorStyleOptions(OpenTuiHandle renderer,
                           const CursorStyleOptions *options);

void enableMouse(OpenTuiHandle renderer, bool enableMovement);
void disableMouse(OpenTuiHandle renderer);
void enableKittyKeyboard(OpenTuiHandle renderer, uint8_t flags);
void disableKittyKeyboard(OpenTuiHandle renderer);

void setupTerminal(OpenTuiHandle renderer, bool useAlternateScreen);
void addToHitGrid(OpenTuiHandle renderer, int32_t x, int32_t y,
                  uint32_t width, uint32_t height, uint32_t id);
uint32_t checkHit(OpenTuiHandle renderer, uint32_t x, uint32_t y);
void processCapabilityResponse(OpenTuiHandle renderer,
                               const uint8_t *response, uint32_t responseLen);

#endif  // NOIR_OPENTUI_V0_5_1_H_
