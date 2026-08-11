import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('normalized geometry', () {
    test('valid bounded, unbounded, and zero constraints stay normalized', () {
      expect(const BoxConstraints().isNormalized, isTrue);
      expect(
        const BoxConstraints.tight(width: 0, height: 0).isNormalized,
        isTrue,
      );
      expect(
        const BoxConstraints(
          minWidth: 2,
          maxWidth: 5,
          minHeight: 3,
          maxHeight: 7,
        ).isNormalized,
        isTrue,
      );
      expect(Size.zero, Size.zero);
    });

    test(
      'invalid non-const geometry is rejected by constructor assertions',
      () {
        expect(
          () => BoxConstraints(minWidth: -1),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => BoxConstraints(minWidth: 4, maxWidth: 3),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => BoxConstraints.tight(width: -1, height: 0),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => BoxConstraints.loose(maxWidth: -1),
          throwsA(isA<AssertionError>()),
        );
        expect(
          () => BoxConstraints.expand(height: -1),
          throwsA(isA<AssertionError>()),
        );
        expect(() => Size(-1, 0), throwsA(isA<AssertionError>()));
        expect(() => Size.square(-1), throwsA(isA<AssertionError>()));
        expect(() => EdgeInsets(left: -1), throwsA(isA<AssertionError>()));
      },
    );

    test('transforms reject negative arguments and preserve normalization', () {
      const constraints = BoxConstraints(
        minWidth: 3,
        maxWidth: 8,
        minHeight: 2,
        maxHeight: 6,
      );

      expect(() => constraints.constrain(width: -1), throwsArgumentError);
      expect(() => constraints.deflate(height: -1), throwsArgumentError);
      expect(() => constraints.tighten(width: -1), throwsArgumentError);
      expect(() => constraints.constrainWidth(-1), throwsArgumentError);
      expect(() => constraints.constrainHeight(-1), throwsArgumentError);

      final narrowed = constraints.constrain(width: 1, height: 1);
      expect(narrowed.minWidth, 3);
      expect(narrowed.maxWidth, 3);
      expect(narrowed.minHeight, 2);
      expect(narrowed.maxHeight, 2);
      expect(narrowed.isNormalized, isTrue);

      final deflated = constraints.deflate(width: 100, height: 100);
      expect(deflated, isA<BoxConstraints>());
      expect(deflated.minWidth, 0);
      expect(deflated.maxWidth, 0);
      expect(deflated.minHeight, 0);
      expect(deflated.maxHeight, 0);
      expect(deflated.isNormalized, isTrue);
    });
  });

  group('constraints value equality', () {
    // Non-const instances with runtime-computed fields defeat const
    // canonicalization, so these assertions exercise `==`, not identity.
    test('field-equal Constraints compare equal with matching hashCodes', () {
      final a = Constraints(maxWidth: 6 + 1, maxHeight: 2 + 1);
      final b = Constraints(maxWidth: 6 + 1, maxHeight: 2 + 1);
      expect(a, b);
      expect(a.hashCode, b.hashCode);

      final unboundedA = Constraints();
      final unboundedB = Constraints();
      expect(unboundedA, unboundedB);
      expect(unboundedA.hashCode, unboundedB.hashCode);
    });

    test('each differing Constraints field breaks equality', () {
      final base = Constraints(maxWidth: 6 + 1, maxHeight: 2 + 1);
      expect(base, isNot(Constraints(maxWidth: 8, maxHeight: 3)));
      expect(base, isNot(Constraints(maxWidth: 7, maxHeight: 4)));
      expect(base, isNot(Constraints(maxHeight: 3)));
      expect(base, isNot(Constraints(maxWidth: 7)));
    });

    test(
      'field-equal BoxConstraints compare equal with matching hashCodes',
      () {
        final a = BoxConstraints(
          minWidth: 0 + 1,
          minHeight: 1 + 1,
          maxWidth: 6 + 1,
          maxHeight: 7 + 1,
        );
        final b = BoxConstraints(
          minWidth: 0 + 1,
          minHeight: 1 + 1,
          maxWidth: 6 + 1,
          maxHeight: 7 + 1,
        );
        expect(a, b);
        expect(a.hashCode, b.hashCode);

        final looseA = BoxConstraints(maxWidth: 6 + 1);
        final looseB = BoxConstraints.loose(maxWidth: 6 + 1);
        expect(looseA, looseB);
        expect(looseA.hashCode, looseB.hashCode);
      },
    );

    test('each differing BoxConstraints field breaks equality', () {
      final base = BoxConstraints(
        minWidth: 0 + 1,
        minHeight: 1 + 1,
        maxWidth: 6 + 1,
        maxHeight: 7 + 1,
      );
      expect(
        base,
        isNot(
          BoxConstraints(minWidth: 2, minHeight: 2, maxWidth: 7, maxHeight: 8),
        ),
      );
      expect(
        base,
        isNot(
          BoxConstraints(minWidth: 1, minHeight: 1, maxWidth: 7, maxHeight: 8),
        ),
      );
      expect(
        base,
        isNot(
          BoxConstraints(minWidth: 1, minHeight: 2, maxWidth: 6, maxHeight: 8),
        ),
      );
      expect(
        base,
        isNot(
          BoxConstraints(minWidth: 1, minHeight: 2, maxWidth: 7, maxHeight: 9),
        ),
      );
      expect(
        base,
        isNot(BoxConstraints(minWidth: 1, minHeight: 2, maxHeight: 8)),
      );
      expect(
        base,
        isNot(BoxConstraints(minWidth: 1, minHeight: 2, maxWidth: 7)),
      );
    });

    test('runtime type participates in constraints equality', () {
      final basic = Constraints(maxWidth: 6 + 1, maxHeight: 7 + 1);
      final box = BoxConstraints(maxWidth: 6 + 1, maxHeight: 7 + 1);
      expect(basic, isNot(box));
      expect(box, isNot(basic));
    });
  });

  test(
    'invalid const geometry fails constant evaluation',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'noir-geometry-const-',
      );
      addTearDown(() => temp.delete(recursive: true));
      final packageConfig =
          '${Directory.current.path}/.dart_tool/package_config.json';
      final cases = <String, String>{
        'constraints': 'const value = Constraints(maxWidth: -1);',
        'box': 'const value = BoxConstraints(minWidth: 2, maxWidth: 1);',
        'size': 'const value = Size(-1, 0);',
        'insets': 'const value = EdgeInsets(left: -1);',
      };

      for (final entry in cases.entries) {
        final file = File('${temp.path}/${entry.key}.dart');
        await file.writeAsString('''
import 'package:noir/noir.dart';
${entry.value}
void main() { print(value); }
''');
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=$packageConfig',
          file.path,
        ]);
        expect(
          result.exitCode,
          isNot(0),
          reason: '${entry.key} unexpectedly compiled:\n${result.stdout}',
        );
        expect(
          '${result.stdout}\n${result.stderr}'.toLowerCase(),
          anyOf(contains('constant'), contains('assert')),
        );
      }
    },
    tags: const ['safe-process-spawning'],
  );
}
