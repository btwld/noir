import 'dart:convert';
import 'dart:ffi';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show TextLayoutEngine;
import 'package:noir/src/core/buffer.dart' show createBufferFromNative;
import 'package:noir/src/ffi/bindings.dart';
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:noir/src/ffi/types.dart';
import 'package:noir/src/painting/tui_canvas.dart'
    show commitTuiCanvas, createTuiCanvas;
import 'package:test/test.dart';

void main() {
  test('link bindings enforce the 512-byte UTF-8 limit and resolve URLs', () {
    final native = _LinkNativeSymbols();
    final bindings = OpenTuiBindings.fromNativeSymbols(native);
    final exact = Uri.parse('https://x.test/${'a' * 497}');
    expect(utf8.encode(exact.toString()), hasLength(512));

    expect(bindings.linkAlloc(exact), 9);
    expect(native.allocatedUrl, exact.toString());
    expect(bindings.linkGetUrl(9), exact.toString());
    expect(
      () => bindings.linkAlloc(Uri.parse('${exact}a')),
      throwsArgumentError,
    );
  });

  test('text layout preserves inherited semantic links', () {
    final uri = Uri.parse('https://example.test');
    final layout = const TextLayoutEngine().layout(
      TextSpan(
        uri: uri,
        children: const <InlineSpan>[TextSpan(text: 'link')],
      ),
      const BoxConstraints(maxWidth: 20),
    );

    expect(layout.lines.single.runs.single.uri, uri);
  });

  test('compositor allocates links only for visible non-empty runs', () {
    final native = _LinkNativeSymbols();
    final bindings = OpenTuiBindings.fromNativeSymbols(native);
    final buffer = createBufferFromNative(
      OptimizedBufferHandle.fromNative(2),
      bindings,
      () => false,
    );
    final uri = Uri.parse('https://example.test/visible');
    final layout = const TextLayoutEngine().layout(
      TextSpan(text: 'link', uri: uri),
      const BoxConstraints(maxWidth: 20),
    );

    final clipped = createTuiCanvas()
      ..drawTextLayout(
        layout,
        Offset.zero,
        sourceRect: const Rect.fromLTWH(10, 0, 1, 1),
      );
    commitTuiCanvas(buffer, clipped);
    expect(native.allocations, 0);

    final destinationClipped = createTuiCanvas()
      ..clipRect(const Rect.fromLTWH(0, 0, 5, 1))
      ..drawTextLayout(layout, const Offset(10, 0));
    commitTuiCanvas(buffer, destinationClipped);
    expect(
      native.allocations,
      0,
      reason: 'fully clipped runs must not consume native link slots',
    );

    final visible = createTuiCanvas()..drawTextLayout(layout, Offset.zero);
    commitTuiCanvas(buffer, visible);
    expect(native.allocations, 1);
  });
}

final class _LinkNativeSymbols implements OpenTuiNativeSymbols {
  int allocations = 0;
  String? allocatedUrl;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final arguments = invocation.positionalArguments;
    switch (invocation.memberName) {
      case #getBufferWidth:
        return 20;
      case #getBufferHeight:
        return 2;
      case #linkAlloc:
        allocations++;
        final pointer = arguments[0]! as Pointer<Uint8>;
        final length = arguments[1]! as int;
        allocatedUrl = utf8.decode(pointer.asTypedList(length));
        return 9;
      case #linkGetUrl:
        final bytes = utf8.encode(allocatedUrl!);
        final out = arguments[1]! as Pointer<Uint8>;
        out.asTypedList(bytes.length).setAll(0, bytes);
        return bytes.length;
      case #attributesWithLink:
        return (arguments[0]! as int) | 0x100;
      case #attributesGetLinkId:
        return (arguments[0]! as int) & 0x100 == 0 ? 0 : 9;
      case #bufferDrawText:
        return null;
      default:
        throw UnsupportedError(invocation.memberName.toString());
    }
  }
}
