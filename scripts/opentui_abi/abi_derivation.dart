/// Derives C ABI signatures from the pinned OpenTUI Zig source so the
/// Noir-owned header can be verified mechanically rather than by hand.
///
/// `native/opentui_v0_5_1.h` is hand-written: every selected export's prototype
/// is transcribed from `external/opentui/packages/core/src/zig/lib.zig`. A
/// transcription error is an ABI bug that no Dart-side guard can catch, because
/// the guard asserts the domain the header claims, not the one Zig declares.
///
/// This library re-derives each prototype from the pinned source and compares
/// the ABI-relevant shape: the return type and the ordered parameter types.
/// Parameter *names* are deliberately not compared — they do not affect the
/// ABI, and Noir's header names them for readability.
library;

/// The ABI-relevant shape of one exported function.
class AbiSignature {
  /// Records a return type and the ordered parameter types for [name].
  const AbiSignature(this.name, this.returnType, this.parameterTypes);

  /// The exported symbol name.
  final String name;

  /// The C return type.
  final String returnType;

  /// The C parameter types, in declaration order.
  final List<String> parameterTypes;

  /// Comparable form. Parameter names are excluded: they carry no ABI meaning.
  String get canonical => '$returnType(${parameterTypes.join(', ')})';

  @override
  String toString() => canonical;
}

/// Zig-to-C type correspondence for the OpenTUI v0.5.1 ABI.
///
/// Derived from, and cross-checked against, the prototypes already present in
/// `native/opentui_v0_5_1.h`. Zig's optional pointers (`?[*]T`) and non-optional
/// slices-as-pointers (`[*]T`) share one C spelling: nullability is a Zig-side
/// contract, not an ABI difference.
const zigToCTypes = <String, String>{
  'void': 'void',
  'bool': 'bool',
  'u8': 'uint8_t',
  'u16': 'uint16_t',
  'u32': 'uint32_t',
  'u64': 'uint64_t',
  'i32': 'int32_t',
  'i64': 'int64_t',
  'usize': 'size_t',
  'f32': 'float',
  'f64': 'double',
  'NativeHandle': 'OpenTuiHandle',
  '?[*]const u8': 'const uint8_t*',
  '[*]const u8': 'const uint8_t*',
  '?[*]const u16': 'const uint16_t*',
  '[*]const u16': 'const uint16_t*',
  '?[*]const u32': 'const uint32_t*',
  '[*]const u32': 'const uint32_t*',
  '?[*]const i32': 'const int32_t*',
  '[*]const i32': 'const int32_t*',
  '?[*]const f32': 'const float*',
  '[*]const f32': 'const float*',
  '?[*]u8': 'uint8_t*',
  '[*]u8': 'uint8_t*',
  '?[*]u32': 'uint32_t*',
  '[*]u32': 'uint32_t*',
  '?[*]f32': 'float*',
  '[*]f32': 'float*',
  // RGBA is an extern struct of four u16 channels; the ABI is a u16 pointer.
  '?[*]RGBA': 'uint16_t*',
  '[*]RGBA': 'uint16_t*',
  '*u32': 'uint32_t*',
  '?*u32': 'uint32_t*',
  '*usize': 'size_t*',
  '?*NativeHandle': 'OpenTuiHandle*',
  '*const CursorStyleOptions': 'const CursorStyleOptions*',
  '*const ExternalImageDrawOptions': 'const ImageDrawOptions*',
  '?*native_image.Info': 'NativeImageInfo*',
  // An opaque stream handle Noir never dereferences.
  '?*native_span_feed.Stream': 'void*',
};

/// Parses every `export fn` in [zigSource] whose types are fully mappable.
///
/// Symbols using a type outside [zigToCTypes] — the audio, image, Yoga, and
/// text-buffer subsystems pass subsystem structs and callbacks — are omitted
/// and their offending types appended to [unmappable]. Those need a struct or
/// callback typedef before they can be bound, which is a deliberate decision
/// rather than a transcription.
Map<String, AbiSignature> parseZigExports(
  String zigSource, {
  List<String>? unmappable,
}) {
  const marker = 'export fn ';
  final signatures = <String, AbiSignature>{};
  var cursor = 0;

  while (true) {
    final start = zigSource.indexOf(
      RegExp('^$marker', multiLine: true),
      cursor,
    );
    if (start < 0) break;

    final open = zigSource.indexOf('(', start);
    final close = _matchingParen(zigSource, open);
    final brace = zigSource.indexOf('{', close);
    if (open < 0 || close < 0 || brace < 0) break;
    cursor = brace;

    final name = zigSource.substring(start + marker.length, open).trim();
    final returnType =
        zigToCTypes[zigSource.substring(close + 1, brace).trim()];
    var mappable = returnType != null;
    if (returnType == null) {
      unmappable?.add(
        '$name (return ${zigSource.substring(close + 1, brace).trim()})',
      );
    }

    final parameters = <String>[];
    for (final parameter in splitTopLevel(
      zigSource.substring(open + 1, close),
    )) {
      final colon = parameter.indexOf(':');
      if (colon < 0) continue;
      final zigType = parameter.substring(colon + 1).trim();
      final cType = zigToCTypes[zigType];
      if (cType == null) {
        mappable = false;
        unmappable?.add('$name (parameter $zigType)');
        continue;
      }
      parameters.add(cType);
    }

    if (mappable) {
      signatures[name] = AbiSignature(name, returnType!, parameters);
    }
  }

  return signatures;
}

/// Parses the function prototypes declared in [headerSource].
Map<String, AbiSignature> parseCHeader(String headerSource) {
  var source = headerSource
      .replaceAll(RegExp('//[^\n]*'), '')
      .replaceAll(RegExp(r'#\w+[^\n]*'), '')
      .replaceAll(RegExp(r'typedef\s+struct\s+\w+\s*\{[^}]*\}\s*\w+\s*;'), '')
      .replaceAll(RegExp('typedef[^;]*;'), '');
  source = source.replaceAll(RegExp(r'\s+'), ' ');

  final signatures = <String, AbiSignature>{};
  for (final statement in source.split(';')) {
    final declaration = statement.trim();
    final open = declaration.indexOf('(');
    final close = declaration.lastIndexOf(')');
    if (open < 0 || close < open) continue;

    final head = RegExp(
      r'^(.*?)([A-Za-z_]\w*)$',
    ).firstMatch(declaration.substring(0, open).trim());
    if (head == null) continue;

    final parameters = <String>[];
    for (final parameter in splitTopLevel(
      declaration.substring(open + 1, close),
    )) {
      final type = _normalizePointer(
        parameter.trim().replaceFirst(RegExp(r'\s*[A-Za-z_]\w*$'), ''),
      );
      if (type.isNotEmpty && type != 'void') parameters.add(type);
    }

    signatures[head.group(2)!] = AbiSignature(
      head.group(2)!,
      _normalizePointer(head.group(1)!),
      parameters,
    );
  }

  return signatures;
}

/// Renders [signature] as a C prototype, ready to paste into the header.
String renderPrototype(AbiSignature signature) {
  final parameters = signature.parameterTypes.isEmpty
      ? 'void'
      : signature.parameterTypes.join(', ');
  final spacer = signature.returnType.endsWith('*') ? '' : ' ';
  return '${signature.returnType}$spacer${signature.name}($parameters);';
}

/// Splits [text] on commas that are not nested inside brackets or parentheses.
List<String> splitTopLevel(String text) {
  final parts = <String>[];
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final character = text[i];
    if (character == '(' || character == '[' || character == '{') depth++;
    if (character == ')' || character == ']' || character == '}') depth--;
    if (character == ',' && depth == 0) {
      parts.add(text.substring(start, i));
      start = i + 1;
    }
  }
  if (text.substring(start).trim().isNotEmpty) parts.add(text.substring(start));
  return parts;
}

int _matchingParen(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    if (text[i] == '(') depth++;
    if (text[i] == ')') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String _normalizePointer(String type) {
  final normalized = type
      .trim()
      .replaceAll(RegExp(r'\s*\*\s*'), '*')
      .replaceAll(RegExp(r'\s+'), ' ');
  return normalized.isEmpty ? 'void' : normalized;
}
