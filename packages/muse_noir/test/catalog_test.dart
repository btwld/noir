import 'package:muse_noir/muse_noir.dart';
import 'package:test/test.dart';

void main() {
  const componentTypes = <String>[
    'Column',
    'Row',
    'Panel',
    'Text',
    'Badge',
    'Callout',
    'Divider',
    'Progress',
    'Spinner',
    'Button',
    'Question',
  ];

  test('v2 catalog and renderer derive the same eleven declarations', () {
    expect(museNoirCatalogId, endsWith('/v2'));
    expect(museNoirCatalog.id, museNoirCatalogId);
    expect(museNoirCatalog.components.keys, orderedEquals(componentTypes));
    expect(museNoirRenderer.components.keys, orderedEquals(componentTypes));
    for (final type in componentTypes) {
      expect(
        museNoirRenderer.components[type]!.component,
        same(museNoirCatalog.components[type]),
      );
    }
  });

  test('Question owns a bindable checked answer draft', () {
    final question = museNoirCatalog.components['Question']!;
    expect(question.checkable, isTrue);
    expect(question.properties['answer']!.bindable, isTrue);
    expect(question.properties['questionId']!.bindable, isFalse);
    expect(
      question.properties['answer']!.schema.safeParse(<String, Object?>{
        'selectedValues': <String>['yes'],
        'freeText': '',
      }).isOk,
      isTrue,
    );
  });

  test('reusable constraints bound question count and autofocus', () {
    expect(museNoirConstraints, hasLength(2));
    expect(
      museNoirConstraints.map((constraint) => constraint.toJson()),
      containsAll(<Object?>[
        containsPair('maximum', 4),
        containsPair('maximum', 1),
      ]),
    );
  });

  test('binding and catalog views are immutable', () {
    expect(museNoirComponentBindings.removeLast, throwsUnsupportedError);
    expect(
      () => museNoirRenderer.components.remove('Text'),
      throwsUnsupportedError,
    );
    expect(
      () => museNoirCatalog.components.remove('Text'),
      throwsUnsupportedError,
    );
  });

  test('deferred Fortal components are not advertised', () {
    expect(museNoirCatalog.components, isNot(contains('Grid')));
    expect(museNoirCatalog.components, isNot(contains('TextField')));
    expect(museNoirCatalog.components, isNot(contains('LineChart')));
  });
}
