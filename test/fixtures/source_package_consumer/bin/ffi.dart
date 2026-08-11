import 'dart:ffi';

import 'package:noir/noir_ffi.dart';

/// Type-checks the complete guarded ABI error and constant surface.
void consumeConsumerAbiContract(
  FFIException ffiException,
  OpenTuiAbiMismatchException abiMismatch,
  OpenTuiLibraryLoadException libraryLoad,
) {
  final Object values = (
    ffiException,
    abiMismatch,
    libraryLoad,
    expectedOpenTuiAbiVersion,
    openTuiCodeAssetId,
  );
  values.toString();
}

/// Type-checks representative guarded FFI calls without executing native code.
Pointer<RendererHandle> createConsumerRenderer(OpenTuiBindings bindings) =>
    bindings.createRenderer(20, 5, testing: true);

/// Type-checks every shared semantic value needed by guarded FFI methods.
void drawConsumerBox(
  OpenTuiBindings bindings,
  Pointer<RendererHandle> renderer,
) {
  final Pointer<OptimizedBufferHandle> buffer = bindings.getNextBuffer(
    renderer,
  );
  bindings
    ..bufferClear(buffer, Color.black)
    ..bufferDrawBox(
      buffer,
      0,
      0,
      8,
      3,
      const BoxOptions(
        sides: BorderSides(right: false),
        titleAlignment: TextAlign.center,
      ),
      Color.white,
      Color.transparent,
    )
    ..bufferDrawText(buffer, 'Noir', 1, 1, Color.white, Color.black, Attr.bold);
}

Pointer<OptimizedBufferHandle> consumerBufferHandle(
  Pointer<OptimizedBufferHandle> handle,
) => handle;

Pointer<TextBufferHandle> consumerTextBufferHandle(
  Pointer<TextBufferHandle> handle,
) => handle;

/// Type-checks the guarded raw two-slot TextBuffer creation boundary.
Pointer<TextBufferHandle> createConsumerTextBuffer(
  OpenTuiBindings bindings,
  int widthMethod,
) => bindings.createTextBuffer(0, widthMethod);

Pointer<CapabilitiesHandle> consumerCapabilitiesHandle(
  Pointer<CapabilitiesHandle> handle,
) => handle;

/// Type-checks opaque-handle disposal through the guarded FFI barrel.
void destroyConsumerRenderer(
  OpenTuiBindings bindings,
  Pointer<RendererHandle> renderer,
) {
  bindings.destroyRenderer(renderer);
}
