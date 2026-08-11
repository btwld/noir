import 'package:noir/noir.dart';
import 'package:noir/src/framework/owner.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/key_driver.dart';

void main() {
  group('TextInput obscureText', () {
    test(
      'onChanged receives the raw user text, not the obscuring character',
      () async {
        final changes = <String>[];
        final driver = KeyDriver(
          TextInput(autofocus: true, obscureText: true, onChanged: changes.add),
        );
        await driver.ready();
        await driver.sendCharacter('s');
        await driver.sendCharacter('e');
        await driver.sendCharacter('c');
        await driver.sendCharacter('r');
        await driver.sendCharacter('e');
        await driver.sendCharacter('t');
        expect(changes, equals(['s', 'se', 'sec', 'secr', 'secre', 'secret']));
        driver.dispose();
      },
    );

    test('paints obscuringCharacter ("*") for each grapheme in the value', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final captured = capture.capture(
          const TextInput(value: 'pass', obscureText: true),
        );
        // Width should be enough to fit all 4 stars.
        expect(captured.getRegion(0, 0, 12, 1).startsWith('****'), isTrue);
      } finally {
        capture.dispose();
      }
    });

    test('custom obscuringCharacter is honoured at paint time', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        final captured = capture.capture(
          const TextInput(
            value: 'abc',
            obscureText: true,
            obscuringCharacter: '•',
          ),
        );
        expect(captured.getRegion(0, 0, 12, 1).startsWith('•••'), isTrue);
      } finally {
        capture.dispose();
      }
    });

    test('accepts one-cell obscuring characters', () {
      final capture = BufferCapture(width: 12, height: 1);
      try {
        expect(
          () =>
              capture.capture(const TextInput(value: 'abc', obscureText: true)),
          returnsNormally,
        );
        expect(
          () => capture.capture(
            const TextInput(
              value: 'abc',
              obscureText: true,
              obscuringCharacter: '•',
            ),
          ),
          returnsNormally,
        );
      } finally {
        capture.dispose();
      }
    });

    test('rejects invalid obscuringCharacter values on mount', () {
      expect(
        () => _mountTextInputWithObscuringCharacter(''),
        throwsArgumentError,
      );
      expect(
        () => _mountTextInputWithObscuringCharacter('ab'),
        throwsArgumentError,
      );
      expect(
        () => _mountTextInputWithObscuringCharacter('中'),
        throwsArgumentError,
      );
    });

    test('rejects invalid obscuringCharacter values on update', () {
      final owner = BuildOwner();
      final element = const TextInput(
        value: 'abc',
        obscureText: true,
      ).createElement()..mount(null, owner);
      try {
        expect(
          () => element.update(
            const TextInput(
              value: 'abc',
              obscureText: true,
              obscuringCharacter: '中',
            ),
          ),
          throwsArgumentError,
        );
      } finally {
        element.unmount();
        owner.dispose();
      }
    });
  });
}

void _mountTextInputWithObscuringCharacter(String obscuringCharacter) {
  final owner = BuildOwner();
  final element = TextInput(
    value: 'abc',
    obscureText: true,
    obscuringCharacter: obscuringCharacter,
  ).createElement();
  var mounted = false;
  try {
    element.mount(null, owner);
    mounted = true;
  } finally {
    if (mounted) {
      element.unmount();
    }
    owner.dispose();
  }
}
