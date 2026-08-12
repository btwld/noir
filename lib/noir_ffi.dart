/// Noir — raw FFI surface.
///
/// **Unstable.** This barrel exposes the guarded FFI wrapper and typed native
/// handles. Generated bindings and
/// native library loading remain internal. The shape of this API tracks the C
/// ABI of `libopentui` and can break whenever that ABI bumps. Application code
/// should use `package:noir/noir.dart` or
/// `package:noir/noir_low_level.dart`.
library;

export 'src/core/color.dart' show Color;
export 'src/core/terminal_style.dart'
    show Attr, BorderSides, BoxOptions, TextAlign;
export 'src/ffi/bindings.dart'
    show FFIException, OpenTuiBindings, OpenTuiRenderStatus;
export 'src/ffi/library.dart' show OpenTuiLibraryLoadException;
export 'src/ffi/types.dart'
    show OpenTuiHandle, OptimizedBufferHandle, RendererHandle;
