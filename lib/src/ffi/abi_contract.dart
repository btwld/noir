/// Dart/OpenTUI native ABI version expected by this package.
const int expectedOpenTuiAbiVersion = 2;

/// Default native asset ID used by generated `@Native` bindings.
const String openTuiCodeAssetId =
    'package:noir/src/ffi/native_asset_bindings.dart';

/// Native exports required by the guarded OpenTUI Dart surface.
const List<String> requiredOpenTuiNativeSymbolNames = <String>[
  // ABI metadata and error channel.
  'otui_dart_abi_version',
  'otui_dart_build_info',
  'otui_dart_last_error',
  'otui_dart_clear_error',

  // Renderer and session.
  'createRenderer',
  'destroyRenderer',
  'render',
  'getNextBuffer',
  'getCurrentBuffer',
  'resizeRenderer',
  'setBackgroundColor',
  'clearTerminal',

  // Buffer size and drawing.
  'getBufferWidth',
  'getBufferHeight',
  'bufferClear',
  'bufferDrawText',
  'bufferFillRect',
  'bufferDrawBox',

  // Cursor.
  'setCursorPosition',
  'setCursorStyle',
  'setCursorColor',

  // Guarded TextBuffer operations.
  'createTextBuffer',
  'destroyTextBuffer',
  'textBufferGetLength',
  'textBufferSetCell',
  'textBufferWriteChunk',
  'textBufferFinalizeLineInfo',
  'textBufferGetLineCount',
  'textBufferGetLineStartsPtr',
  'textBufferGetLineWidthsPtr',
  'textBufferReset',
  'textBufferSetSelection',
  'textBufferResetSelection',
  'bufferDrawTextBuffer',

  // Terminal input modes.
  'enableMouse',
  'disableMouse',
  'enableKittyKeyboard',
  'disableKittyKeyboard',

  // Direct buffer/TextBuffer access and composition.
  'bufferGetCharPtr',
  'bufferGetFgPtr',
  'bufferGetBgPtr',
  'bufferGetAttributesPtr',
  'bufferSetCellWithAlphaBlending',
  'drawFrameBuffer',
  'bufferResize',
  'textBufferGetCharPtr',
  'textBufferGetFgPtr',
  'textBufferGetBgPtr',
  'textBufferGetAttributesPtr',

  // Diagnostics, terminal setup, hit testing, and capabilities.
  'updateStats',
  'updateMemoryStats',
  'setupTerminal',
  'setDebugOverlay',
  'dumpHitGrid',
  'dumpBuffers',
  'dumpStdoutBuffer',
  'addToHitGrid',
  'checkHit',
  'getTerminalCapabilities',
  'processCapabilityResponse',
];
