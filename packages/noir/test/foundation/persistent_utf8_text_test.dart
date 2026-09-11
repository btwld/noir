import 'dart:convert';
import 'dart:ffi';

import 'package:noir/src/foundation/persistent_utf8_text.dart';
import 'package:test/test.dart';

void main() {
  group('PersistentUtf8Text', () {
    test('stores nul-terminated UTF-8 bytes', () {
      final text = PersistentUtf8Text('é🙂');
      addTearDown(text.dispose);

      final expected = utf8.encode('é🙂');
      expect(text.length, expected.length);
      expect(text.pointer.asTypedList(text.length), expected);
      expect(text.pointer[text.length], 0);
    });

    test('reuses native allocation when updated text fits capacity', () {
      final text = PersistentUtf8Text('terminal');
      addTearDown(text.dispose);

      final firstAddress = text.pointer.address;
      final firstCapacity = text.capacity;

      text.update('tty');

      expect(text.pointer.address, firstAddress);
      expect(text.capacity, firstCapacity);
      expect(text.length, 3);
      expect(text.pointer.asTypedList(text.length), utf8.encode('tty'));
      expect(text.pointer[text.length], 0);
    });

    test('reallocates when updated text exceeds capacity', () {
      final text = PersistentUtf8Text('ui');
      addTearDown(text.dispose);

      final firstCapacity = text.capacity;

      text.update('terminal ui');

      expect(text.capacity, greaterThan(firstCapacity));
      expect(text.capacity, greaterThanOrEqualTo(text.length));
      expect(text.pointer.asTypedList(text.length), utf8.encode('terminal ui'));
      expect(text.pointer[text.length], 0);
    });

    test('bounded update rejects before changing any stored byte', () {
      final text = PersistentUtf8Text('seed');
      addTearDown(text.dispose);
      final beforeAddress = text.pointer.address;
      final beforeLength = text.length;
      final beforeCapacity = text.capacity;
      final beforeBytes = text.pointer
          .asTypedList(text.length + 1)
          .toList(growable: false);
      expect(beforeBytes.last, 0);

      expect(
        () => text.update('éé', maxBytes: 3),
        throwsA(
          isA<RangeError>().having(
            (error) =>
                '${error.name}|${error.invalidValue}|${error.start}|${error.end}|${error.message}',
            'exact bounded-update error',
            'text|4|0|3|encoded UTF-8 byte length exceeds maxBytes',
          ),
        ),
      );

      expect(text.pointer.address, beforeAddress);
      expect(text.length, beforeLength);
      expect(text.capacity, beforeCapacity);
      expect(text.pointer.asTypedList(text.length + 1), beforeBytes);
      expect(text.pointer[text.length], 0);
    });

    test('dispose clears storage and is idempotent', () {
      final text = PersistentUtf8Text('abc');

      for (var i = 0; i < 2; i++) {
        text.dispose();
      }

      expect(text.pointer, nullptr);
      expect(text.length, 0);
      expect(text.capacity, 0);
    });

    test('update after dispose fails loudly', () {
      final text = PersistentUtf8Text('abc')..dispose();

      expect(() => text.update('def', maxBytes: 0), throwsStateError);
    });
  });
}
