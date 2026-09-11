import 'dart:typed_data';

import 'package:noir/noir.dart';
import 'package:noir/src/core/buffer.dart';
import 'package:noir/src/ffi/bindings.dart';
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:noir/src/ffi/types.dart';
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:test/test.dart';

void main() {
  test('image commands retain placement and apply clips through scissor', () {
    final native = _ImageDrawNativeSymbols();
    final bindings = OpenTuiBindings.fromNativeSymbols(native);
    final image = TerminalImage.fromRgba(
      Uint8List.fromList(<int>[255, 0, 0, 255]),
      pixelWidth: 1,
      pixelHeight: 1,
      rowStride: 4,
    );
    final buffer = createBufferFromNative(
      OptimizedBufferHandle.fromNative(3),
      bindings,
      () => false,
    );
    final canvas = createTuiCanvas()
      ..save()
      ..clipRect(const Rect.fromLTWH(2, 1, 4, 3))
      ..drawImage(
        image,
        const Rect.fromLTWH(0, 0, 8, 4),
        pixelWidth: 80,
        pixelHeight: 40,
        sourceRect: const Rect.fromLTWH(4, 2, 16, 8),
        protocol: ImageProtocol.sixel,
      )
      ..restore();

    commitTuiCanvas(buffer, canvas);

    expect(native.calls, <String>['push:2,1,4,3', 'draw', 'pop']);
    expect(native.drawArguments, <int>[
      3,
      image.handle.value,
      0,
      0,
      8,
      4,
      80,
      40,
      4,
      2,
      16,
      8,
      2,
    ]);
    image.dispose();
  });
}

final class _ImageDrawNativeSymbols implements OpenTuiNativeSymbols {
  final calls = <String>[];
  List<int>? drawArguments;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final arguments = invocation.positionalArguments;
    switch (invocation.memberName) {
      case #getBufferWidth:
        return 20;
      case #getBufferHeight:
        return 10;
      case #bufferPushScissorRect:
        calls.add('push:${arguments.skip(1).join(',')}');
        return null;
      case #bufferDrawImage:
        calls.add('draw');
        drawArguments = arguments.cast<int>();
        return 1;
      case #bufferPopScissorRect:
        calls.add('pop');
        return null;
      default:
        throw UnsupportedError(invocation.memberName.toString());
    }
  }
}
