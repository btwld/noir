import 'dart:ffi';

import 'package:noir/src/core/color.dart';
import 'package:noir/src/core/cursor.dart';
import 'package:noir/src/ffi/bindings.dart';
import 'package:noir/src/ffi/generated_bindings.dart' as lookup;
import 'package:noir/src/ffi/native_asset_bindings.dart' as bundled;
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:noir/src/ffi/types.dart';
import 'package:test/test.dart';

void main() {
  test('typed handles accept only nonzero u32 native values', () {
    expect(RendererHandle.fromNative(1).value, 1);
    expect(RendererHandle.fromNative(0xFFFFFFFF).value, 0xFFFFFFFF);
    expect(OptimizedBufferHandle.fromNative(7).value, 7);
    expect(TerminalImageHandle.fromNative(8).value, 8);

    for (final invalid in <int>[-1, 0, 0x100000000]) {
      expect(() => RendererHandle.fromNative(invalid), throwsRangeError);
      expect(() => OptimizedBufferHandle.fromNative(invalid), throwsRangeError);
      expect(() => TerminalImageHandle.fromNative(invalid), throwsRangeError);
    }
  });

  test('rendered and skipped statuses succeed while other values fail', () {
    expect(decodeOpenTuiRenderStatus(0), OpenTuiRenderStatus.rendered);
    expect(decodeOpenTuiRenderStatus(1), OpenTuiRenderStatus.skipped);
    expect(
      () => decodeOpenTuiRenderStatus(2),
      throwsA(
        isA<FFIException>().having(
          (error) => error.message,
          'message',
          contains('failed'),
        ),
      ),
    );
    expect(
      () => decodeOpenTuiRenderStatus(3),
      throwsA(
        isA<FFIException>().having(
          (error) => error.message,
          'message',
          contains('unknown render status'),
        ),
      ),
    );
  });

  test('image ABI structs match in lookup and bundled bindings', () {
    expect(sizeOf<lookup.NativeImageInfo>(), 32);
    expect(sizeOf<bundled.NativeImageInfo>(), 32);
    expect(sizeOf<lookup.ImageDrawOptions>(), 44);
    expect(sizeOf<bundled.ImageDrawOptions>(), 44);
  });

  test('cursor styles and colors use canonical cursor options', () {
    final native = _RecordingNativeSymbols();
    final bindings = OpenTuiBindings.fromNativeSymbols(native);
    final renderer = RendererHandle.fromNative(9);

    bindings.setCursorStyle(renderer, CursorStyle.block.value, false);
    bindings.setCursorStyle(renderer, CursorStyle.bar.value, true);
    bindings.setCursorStyle(renderer, CursorStyle.underline.value, false);
    bindings.setCursorColor(renderer, const Color(1, 0.5, 0.25, 0));

    expect(native.cursorOptions, <List<Object?>>[
      <Object?>[9, 0, 0, null],
      <Object?>[9, 1, 1, null],
      <Object?>[9, 2, 0, null],
      <Object?>[
        9,
        0xFF,
        0xFF,
        <int>[255, 128, 64, 0],
      ],
    ]);
  });
}

final class _RecordingNativeSymbols implements OpenTuiNativeSymbols {
  final cursorOptions = <List<Object?>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName != #setCursorStyleOptions) {
      throw UnsupportedError(invocation.memberName.toString());
    }
    final arguments = invocation.positionalArguments;
    final color = arguments[3]! as Pointer<Uint16>;
    final List<int>? colorValues;
    if (color == nullptr) {
      colorValues = null;
    } else {
      colorValues = List<int>.of(color.asTypedList(4));
    }
    cursorOptions.add(<Object?>[
      arguments[0]! as int,
      arguments[1]! as int,
      arguments[2]! as int,
      colorValues,
    ]);
  }
}
