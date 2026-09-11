import 'package:noir/noir_ffi.dart';

/// Type-checks the guarded FFI error surface.
void consumeConsumerFfiErrors(
  FFIException ffiException,
  OpenTuiLibraryLoadException libraryLoad,
) {
  final Object values = (ffiException, libraryLoad);
  values.toString();
}

/// Type-checks representative guarded FFI calls without executing native code.
RendererHandle createConsumerRenderer(OpenTuiBindings bindings) =>
    bindings.createRenderer(20, 5, testing: true);

/// Type-checks every shared semantic value needed by guarded FFI methods.
void drawConsumerBox(OpenTuiBindings bindings, RendererHandle renderer) {
  final OptimizedBufferHandle buffer = bindings.getNextBuffer(renderer);
  bindings
    ..bufferClear(buffer, Color.black)
    ..bufferDrawBox(
      buffer,
      0,
      0,
      8,
      3,
      BoxOptions(
        sides: BorderSides(right: false),
        titleAlignment: TextAlign.center,
      ),
      Color.white,
      Color.transparent,
    )
    ..bufferDrawText(buffer, 'Noir', 1, 1, Color.white, Color.black, Attr.bold);
}

OptimizedBufferHandle consumerBufferHandle(OptimizedBufferHandle handle) =>
    handle;

OpenTuiHandle consumerNativeHandle(OpenTuiHandle handle) => handle;

/// Type-checks typed-handle disposal through the guarded FFI barrel.
void destroyConsumerRenderer(
  OpenTuiBindings bindings,
  RendererHandle renderer,
) {
  bindings.destroyRenderer(renderer);
}
