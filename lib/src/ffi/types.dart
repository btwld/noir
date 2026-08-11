import 'dart:ffi';

/// Opaque native renderer state; usable only behind a [Pointer].
final class RendererHandle extends Opaque {}

/// Opaque native optimized-buffer state; usable only behind a [Pointer].
final class OptimizedBufferHandle extends Opaque {}

/// Opaque native text-buffer state; usable only behind a [Pointer].
final class TextBufferHandle extends Opaque {}

/// Opaque native capabilities record; usable only behind a [Pointer].
final class CapabilitiesHandle extends Opaque {}
