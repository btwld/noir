import 'package:noir/src/core/renderer.dart';
import 'package:noir/src/ffi/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('validateRendererDimensions', () {
    for (final width in <int>[0, -1]) {
      test('rejects width $width with parameter-specific context', () {
        expect(
          () => validateRendererDimensions(width, 1),
          _throwsInvalidDimension('width', width),
        );
      });
    }

    for (final height in <int>[0, -1]) {
      test('rejects height $height with parameter-specific context', () {
        expect(
          () => validateRendererDimensions(1, height),
          _throwsInvalidDimension('height', height),
        );
      });
    }

    test('accepts positive dimensions', () {
      expect(() => validateRendererDimensions(1, 1), returnsNormally);
      expect(() => validateRendererDimensions(80, 24), returnsNormally);
    });
  });

  group('Renderer.create', () {
    for (final width in <int>[0, -1]) {
      test('rejects width $width before binding construction', () {
        expect(
          () => Renderer.create(width, 1, testing: true),
          _throwsInvalidDimension('width', width),
        );
      });
    }

    for (final height in <int>[0, -1]) {
      test('rejects height $height before binding construction', () {
        expect(
          () => Renderer.create(1, height, testing: true),
          _throwsInvalidDimension('height', height),
        );
      });
    }
  });

  group('Renderer.resize', () {
    for (final dimensions in <(int, int, String, int)>[
      (0, 2, 'width', 0),
      (-1, 2, 'width', -1),
      (2, 0, 'height', 0),
      (2, -1, 'height', -1),
    ]) {
      test(
        'rejects (${dimensions.$1}, ${dimensions.$2}) without changing the buffer',
        () {
          final renderer = Renderer.create(4, 2, testing: true);
          addTearDown(renderer.dispose);
          final buffer = renderer.nextBuffer;

          expect(
            () => renderer.resize(dimensions.$1, dimensions.$2),
            _throwsInvalidDimension(dimensions.$3, dimensions.$4),
          );

          expect(buffer.isInvalidated, isFalse);
          expect((buffer.width, buffer.height), (4, 2));
          expect(renderer.nextBuffer, same(buffer));
        },
      );
    }

    test('reports disposed state before validating dimensions', () {
      final renderer = Renderer.create(2, 1, testing: true)..dispose();

      expect(
        () => renderer.resize(0, 0),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Renderer is disposed',
          ),
        ),
      );
    });
  });
}

Matcher _throwsInvalidDimension(String name, int value) => throwsA(
  isA<ArgumentError>()
      .having((error) => error.name, 'name', name)
      .having((error) => error.invalidValue, 'invalidValue', value)
      .having((error) => error.message, 'message', 'must be greater than zero'),
);
