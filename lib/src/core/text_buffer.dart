import 'dart:ffi';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../ffi/bindings.dart';
import '../ffi/types.dart';
import '../foundation/persistent_utf8_text.dart';
import 'color.dart';

void _checkUnsignedAbi(int value, int maximum, String name) {
  if (value < 0 || value > maximum) {
    throw RangeError.range(value, 0, maximum, name);
  }
}

/// Width calculation methods for text
enum WidthMethod {
  /// Use OpenTUI's wcwidth-compatible cell-width calculation.
  wcwidth(0),

  /// Use OpenTUI's Unicode display-width calculation.
  unicode(1);

  const WidthMethod(this.value);

  /// Native OpenTUI width-method identifier.
  final int value;
}

/// High-performance text buffer with selection support, backed by native storage.
class TextBuffer {
  TextBuffer._(this._bindings, this._ptr) {
    _finalizer.attach(this, _ptr.cast<Void>(), detach: _finalizerKey);
  }

  /// Creates an empty native text buffer using [widthMethod].
  ///
  /// Its logical [length] starts at zero and grows as content is written or
  /// cells are set by index.
  factory TextBuffer.create({WidthMethod widthMethod = WidthMethod.unicode}) {
    final bindings = OpenTuiBindings();
    final ptr = bindings.createTextBuffer(0, widthMethod.value);
    if (ptr == nullptr) {
      throw StateError('Failed to create TextBuffer');
    }
    return TextBuffer._(bindings, ptr);
  }
  static final Finalizer<Pointer<Void>> _finalizer = Finalizer<Pointer<Void>>((
    pointer,
  ) {
    if (pointer == nullptr) {
      return;
    }
    final bindings = OpenTuiBindings();
    bindings.destroyTextBuffer(pointer.cast<TextBufferHandle>());
  });

  final OpenTuiBindings _bindings;
  final Pointer<TextBufferHandle> _ptr;
  final PersistentUtf8Text _utf8Scratch = PersistentUtf8Text();
  bool _disposed = false;
  bool _lineMetadataStale = false;
  final Object _finalizerKey = Object();

  /// Current number of logical cells stored in the native text buffer.
  int get length {
    _checkNotDisposed();
    return _bindings.textBufferGetLength(_ptr);
  }

  /// Replaces one zero-based logical cell at [index] and extends with spaces
  /// when needed.
  ///
  /// [scalar] must contain exactly one well-formed Unicode scalar. The native
  /// operation stores it as one raw cell word; it does not perform grapheme
  /// clustering or display-width expansion. Newline retains native line
  /// behavior. Marks line metadata stale until [finalizeLineInfo] runs.
  void setCell(int index, String scalar, Color fg, Color bg, int attributes) {
    _checkNotDisposed();
    if (index < 0 || index > 0xFFFFFFFF) {
      throw RangeError.range(index, 0, 0xFFFFFFFF, 'index');
    }
    if (attributes < 0 || attributes > 0xFFFF) {
      throw RangeError.range(attributes, 0, 0xFFFF, 'attributes');
    }
    final scalarValues = scalar.runes.toList(growable: false);
    final scalarValue = scalarValues.length == 1 ? scalarValues.single : -1;
    if (scalarValues.length != 1 ||
        (scalarValue >= 0xD800 && scalarValue <= 0xDFFF) ||
        String.fromCharCode(scalarValue) != scalar) {
      throw ArgumentError.value(
        scalar,
        'scalar',
        'must contain exactly one well-formed Unicode scalar',
      );
    }
    _lineMetadataStale = true;
    _bindings.textBufferSetCell(_ptr, index, scalarValue, fg, bg, attributes);
  }

  /// Appends [text] to the buffer at the current write position.
  ///
  /// [attributes] must fit an unsigned 8-bit mask, and [text]'s encoded UTF-8
  /// byte length must fit an unsigned 32-bit value. Marks line metadata stale
  /// until [finalizeLineInfo] runs.
  void writeChunk(String text, Color fg, Color bg, int attributes) {
    _checkNotDisposed();
    _checkUnsignedAbi(attributes, 0xFF, 'attributes');
    _utf8Scratch.update(text, maxBytes: 0xFFFFFFFF);
    _lineMetadataStale = true;
    _bindings.textBufferWriteUtf8Chunk(
      _ptr,
      _utf8Scratch.pointer,
      _utf8Scratch.length,
      fg,
      bg,
      attributes,
    );
  }

  /// Clears all content so [length] becomes zero.
  ///
  /// Line metadata returns to the freshly created single empty line, so
  /// line-metadata reads need no new [finalizeLineInfo].
  void reset() {
    _checkNotDisposed();
    _bindings.textBufferReset(_ptr);
    _lineMetadataStale = false;
  }

  /// Finalize line metadata after writing content.
  ///
  /// [writeChunk] and [setCell] mark line metadata stale; this call restores
  /// [lineCount], [lineStarts], [lineWidths], and [lineInfo] reads.
  void finalizeLineInfo() {
    _checkNotDisposed();
    _bindings.textBufferFinalizeLineInfo(_ptr);
    _lineMetadataStale = false;
  }

  /// Number of lines tracked by the buffer.
  ///
  /// Throws [StateError] when [writeChunk] or [setCell] ran after the last
  /// [finalizeLineInfo], creation, or [reset].
  int get lineCount {
    _checkNotDisposed();
    _checkLineMetadataFinalized();
    return _bindings.textBufferGetLineCount(_ptr);
  }

  /// Zero-based start indices for each line; stale line metadata throws
  /// [StateError] under [lineCount]'s finalize-before-read rule.
  List<int> get lineStarts => lineInfo.starts;

  /// Display widths for each line; stale line metadata throws [StateError]
  /// under [lineCount]'s finalize-before-read rule.
  List<int> get lineWidths => lineInfo.widths;

  /// Internal: finalized line starts and display widths; stale line metadata
  /// throws [StateError] under [lineCount]'s finalize-before-read rule.
  @internal
  ({List<int> starts, List<int> widths}) get lineInfo {
    _checkNotDisposed();
    return _lineInfoFromHandle(_ptr);
  }

  /// Highlights the half-open native-cell range `[start, end)` with the given
  /// colors: [start] is included and [end] is excluded.
  ///
  /// Both endpoints must fit unsigned 32-bit values and [end] must be greater
  /// than or equal to [start]. Endpoints may exceed the current [length].
  void setSelection(int start, int end, Color bgColor, Color fgColor) {
    _checkNotDisposed();
    _checkUnsignedAbi(start, 0xFFFFFFFF, 'start');
    _checkUnsignedAbi(end, 0xFFFFFFFF, 'end');
    if (start > end) {
      throw ArgumentError.value(
        end,
        'end',
        'must be greater than or equal to start',
      );
    }
    _bindings.textBufferSetSelection(_ptr, start, end, bgColor, fgColor);
  }

  /// Clears the current selection, removing any highlight.
  void resetSelection() {
    _checkNotDisposed();
    _bindings.textBufferResetSelection(_ptr);
  }

  /// Get direct access to internal arrays for performance-critical operations.
  DirectTextAccess getDirectAccess() {
    _checkNotDisposed();
    return _directAccessFromHandle(_ptr);
  }

  /// Internal: reads one synchronous compositing snapshot from the handle
  /// already captured by the supported draw preflight.
  ///
  /// Throws [StateError] when line metadata is stale.
  @internal
  ({DirectTextAccess access, List<int> lineStarts, List<int> lineWidths})
  compositingSnapshotFromCapturedHandle(
    Pointer<TextBufferHandle> capturedHandle,
  ) {
    final access = _directAccessFromHandle(capturedHandle);
    final lineInfo = _lineInfoFromHandle(capturedHandle);
    return (
      access: access,
      lineStarts: lineInfo.starts,
      lineWidths: lineInfo.widths,
    );
  }

  DirectTextAccess _directAccessFromHandle(
    Pointer<TextBufferHandle> capturedHandle,
  ) {
    final len = _bindings.textBufferGetLength(capturedHandle);
    if (len == 0) {
      return DirectTextAccess._(
        encodedCells: Uint32List(0),
        foregrounds: Float32List(0),
        backgrounds: Float32List(0),
        attributes: Uint16List(0),
        length: 0,
      );
    }

    final charPtr = _bindings.textBufferGetCharPtr(capturedHandle);
    final attrPtr = _bindings.textBufferGetAttributesPtr(capturedHandle);

    return DirectTextAccess._(
      encodedCells: charPtr.asTypedList(len),
      foregrounds: _textBufferColors(capturedHandle, len, foreground: true),
      backgrounds: _textBufferColors(capturedHandle, len, foreground: false),
      attributes: attrPtr.asTypedList(len),
      length: len,
    );
  }

  ({List<int> starts, List<int> widths}) _lineInfoFromHandle(
    Pointer<TextBufferHandle> capturedHandle,
  ) {
    _checkLineMetadataFinalized();
    final count = _bindings.textBufferGetLineCount(capturedHandle);
    return count == 0
        ? (starts: const <int>[], widths: const <int>[])
        : (
            starts: _readLineMetadata(
              _bindings.textBufferGetLineStartsPtr(capturedHandle),
              count,
            ),
            widths: _readLineMetadata(
              _bindings.textBufferGetLineWidthsPtr(capturedHandle),
              count,
            ),
          );
  }

  Float32List _textBufferColors(
    Pointer<TextBufferHandle> capturedHandle,
    int length, {
    required bool foreground,
  }) {
    final ptr = foreground
        ? _bindings.textBufferGetFgPtr(capturedHandle)
        : _bindings.textBufferGetBgPtr(capturedHandle);
    return ptr.asTypedList(length * 4);
  }

  List<int> _readLineMetadata(Pointer<Uint32> ptr, int count) {
    final view = ptr.asTypedList(count);
    return List<int>.unmodifiable(List<int>.generate(count, (i) => view[i]));
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('TextBuffer is disposed');
  }

  void _checkLineMetadataFinalized() {
    if (_lineMetadataStale) {
      throw StateError(
        'TextBuffer line metadata is stale; call finalizeLineInfo() '
        'after writeChunk or setCell',
      );
    }
  }

  /// Releases all native resources held by this buffer.
  void dispose() {
    if (_disposed) return;
    _finalizer.detach(_finalizerKey);
    _utf8Scratch.dispose();
    _bindings.destroyTextBuffer(_ptr);
    _disposed = true;
  }

  /// Internal: raw native handle. Not for user code.
  @internal
  Pointer<TextBufferHandle> get handle {
    _checkNotDisposed();
    return _ptr;
  }
}

/// Read-only direct views of TextBuffer native cache arrays.
///
/// [encodedCells] contains native encoded cell words, not a Unicode string or
/// a uniformly decodable code-point array. Top bits `00` identify a direct
/// scalar word. Top bits `10` identify a packed grapheme-start word carrying
/// its right extent and an opaque 26-bit pool identity. Top bits `11` identify
/// a continuation word carrying left and right extents and the same opaque
/// identity. Those identities belong to the process-global native grapheme
/// pool and cannot independently recover grapheme text.
///
/// When [length] is positive, the non-empty views are native-owned, read-only,
/// and valid only for immediate inspection until the next TextBuffer mutation,
/// reset, or disposal. When [length] is zero, getDirectAccess returns Dart-owned
/// empty typed lists rather than native views. All four views are unmodifiable,
/// including aliases created from their byte buffers. Their wrappers are
/// zero-copy and do not extend the lifetime of the underlying native storage.
class DirectTextAccess {
  DirectTextAccess._({
    required Uint32List encodedCells,
    required Float32List foregrounds,
    required Float32List backgrounds,
    required Uint16List attributes,
    required this.length,
  }) : encodedCells = encodedCells.asUnmodifiableView(),
       foregrounds = foregrounds.asUnmodifiableView(),
       backgrounds = backgrounds.asUnmodifiableView(),
       attributes = attributes.asUnmodifiableView();

  /// Native encoded cell words; use their `00`, `10`, and `11` top-bit class
  /// rather than treating every word as a Unicode code point.
  final Uint32List encodedCells;

  /// RGBA foreground channels, four floats per cell.
  final Float32List foregrounds;

  /// RGBA background channels, four floats per cell.
  final Float32List backgrounds;

  /// Text attributes for each cell.
  final Uint16List attributes;

  /// Number of cells exposed by these views.
  final int length;
}
