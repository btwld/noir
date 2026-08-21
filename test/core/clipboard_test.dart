import 'dart:convert';
import 'dart:ffi';

import 'package:noir/noir_low_level.dart';
import 'package:noir/src/core/renderer.dart' show createRendererForTesting;
import 'package:noir/src/ffi/bindings.dart';
import 'package:noir/src/ffi/native_symbols.dart';
import 'package:noir/src/ffi/types.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ClipboardSupport forwards UTF-8 text and target and reports status',
    () {
      final native = _ClipboardNativeSymbols();
      final renderer = createRendererForTesting(
        OpenTuiBindings.fromNativeSymbols(native),
        RendererHandle.fromNative(7),
      );
      addTearDown(renderer.dispose);

      expect(
        renderer.copyToClipboard('世界', target: TerminalClipboardTarget.primary),
        isTrue,
      );
      expect(native.copied, (renderer: 7, target: 1, text: '世界'));
      expect(
        renderer.clearClipboard(target: TerminalClipboardTarget.secondary),
        isFalse,
      );
      expect(native.cleared, (renderer: 7, target: 3));
    },
  );

  test('empty copy is rejected without calling native code', () {
    final native = _ClipboardNativeSymbols();
    final renderer = createRendererForTesting(
      OpenTuiBindings.fromNativeSymbols(native),
      RendererHandle.fromNative(8),
    );
    addTearDown(renderer.dispose);

    expect(renderer.copyToClipboard(''), isFalse);
    expect(native.copied, isNull);
  });
}

final class _ClipboardNativeSymbols implements OpenTuiNativeSymbols {
  ({int renderer, int target, String text})? copied;
  ({int renderer, int target})? cleared;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final arguments = invocation.positionalArguments;
    switch (invocation.memberName) {
      case #copyToClipboardOSC52:
        final pointer = arguments[2]! as Pointer<Uint8>;
        final length = arguments[3]! as int;
        copied = (
          renderer: arguments[0]! as int,
          target: arguments[1]! as int,
          text: utf8.decode(pointer.asTypedList(length)),
        );
        return true;
      case #clearClipboardOSC52:
        cleared = (
          renderer: arguments[0]! as int,
          target: arguments[1]! as int,
        );
        return false;
      case #destroyRenderer:
        return null;
      default:
        throw UnsupportedError(invocation.memberName.toString());
    }
  }
}
