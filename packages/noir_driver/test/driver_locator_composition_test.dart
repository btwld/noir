@TestOn('vm')
library;

import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

/// Two dialogs owning the same key is the case a flat locator cannot express.
///
/// Every locator was an exact match on one node, and [DriverTree.find] is
/// strict, so the only way through was `findAll` plus a hand-written walk up
/// [DriverNode.parent].
DriverTree _tree() => DriverTree.fromJson(<String, Object?>{
  'type': 'Success',
  'root': _node(
    type: 'Root',
    children: <Map<String, Object?>>[
      _node(
        type: 'Dialog',
        key: 'dialog-a',
        children: <Map<String, Object?>>[
          _node(type: 'Button', key: 'confirm', text: 'Keep', x: 2, y: 1),
        ],
      ),
      _node(
        type: 'Dialog',
        key: 'dialog-b',
        children: <Map<String, Object?>>[
          _node(
            type: 'Row',
            children: <Map<String, Object?>>[
              _node(
                type: 'Button',
                key: 'confirm',
                text: 'Discard',
                x: 8,
                y: 4,
              ),
            ],
          ),
        ],
      ),
      _node(type: 'Button', key: 'close', text: 'Close', x: 0, y: 9),
    ],
  ),
});

Map<String, Object?> _node({
  required String type,
  String? key,
  String? text,
  int? x,
  int? y,
  List<Map<String, Object?>> children = const <Map<String, Object?>>[],
}) => <String, Object?>{
  'type': type,
  'key': key,
  'text': text,
  'focused': false,
  'hasFocusedDescendant': false,
  'hitPoint': x == null || y == null ? null : <String, Object?>{'x': x, 'y': y},
  'children': children,
};

/// Asserts that [locator] fails against [tree] with a message matching all
/// of [fragments].
///
/// Follows the repository idiom of matching on the thrown error rather than
/// catching it, which `avoid_catching_errors` rules out.
void _expectMiss(
  DriverTree tree,
  DriverLocator locator,
  List<String> fragments,
) {
  var matcher = isA<StateError>();
  for (final fragment in fragments) {
    matcher = matcher.having(
      (error) => error.message,
      'message',
      contains(fragment),
    );
  }
  expect(() => tree.find(locator), throwsA(matcher));
}

void main() {
  group('descendantOf', () {
    test('narrows an otherwise ambiguous key to one node', () {
      final tree = _tree();
      const confirm = DriverLocator.byKey('confirm');

      expect(tree.findAll(confirm), hasLength(2));

      expect(
        tree.find(confirm.descendantOf(const DriverLocator.byKey('dialog-a'))),
        isA<DriverNode>().having((node) => node.text, 'text', 'Keep'),
      );
      expect(
        tree.find(confirm.descendantOf(const DriverLocator.byKey('dialog-b'))),
        isA<DriverNode>().having((node) => node.text, 'text', 'Discard'),
      );
    });

    test('reaches a nested descendant, not only a direct child', () {
      // The dialog-b button sits under an intermediate Row.
      final match = _tree().find(
        const DriverLocator.byKey(
          'confirm',
        ).descendantOf(const DriverLocator.byType('Dialog').at(1)),
      );

      expect(match.text, 'Discard');
    });

    test('does not match the ancestor itself', () {
      final tree = _tree();

      expect(
        tree.findAll(
          const DriverLocator.byKey(
            'dialog-a',
          ).descendantOf(const DriverLocator.byKey('dialog-a')),
        ),
        isEmpty,
      );
    });

    test('leaves the locator it narrows unchanged', () {
      const confirm = DriverLocator.byKey('confirm');
      confirm.descendantOf(const DriverLocator.byKey('dialog-a'));

      expect(_tree().findAll(confirm), hasLength(2));
    });

    test('says when the ancestor itself matches nothing', () {
      _expectMiss(
        _tree(),
        const DriverLocator.byKey(
          'confirm',
        ).descendantOf(const DriverLocator.byKey('nope')),
        // The inventory that makes a flat miss diagnosable still appears.
        <String>['No node matches the ancestor', 'key "nope"', 'dialog-a'],
      );
    });

    test('says when the base matched but nothing sits inside', () {
      _expectMiss(
        _tree(),
        const DriverLocator.byKey(
          'close',
        ).descendantOf(const DriverLocator.byKey('dialog-a')),
        <String>['matched 1', 'none is inside', 'Close'],
      );
    });

    final ambiguousAncestor = const DriverLocator.byKey(
      'confirm',
    ).descendantOf(const DriverLocator.byType('Dialog'));
    final nestedAmbiguousAncestor = const DriverLocator.byType(
      'Text',
    ).descendantOf(ambiguousAncestor);
    final ambiguityError = throwsA(
      isA<StateError>().having(
        (error) => error.message,
        'message',
        allOf(contains('ancestor'), contains('ambiguous: 2 matches')),
      ),
    );

    for (final locator in <DriverLocator>[
      ambiguousAncestor,
      nestedAmbiguousAncestor,
    ]) {
      test('findAll rejects ambiguous ancestry for $locator', () {
        expect(() => _tree().findAll(locator), ambiguityError);
      });

      test('absence never passes for ambiguous ancestry in $locator', () async {
        await expectLater(
          waitForAbsentDriverLocator(
            locator,
            fetchTree: () async => _tree(),
            timeout: Duration.zero,
          ),
          ambiguityError,
        );
      });

      test('waiting reports ambiguous ancestry in $locator', () async {
        await expectLater(
          waitForDriverLocator(
            locator,
            fetchTree: () async => _tree(),
            timeout: Duration.zero,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              allOf(
                contains('ambiguous: 2 matches'),
                isNot(contains('Timed out')),
              ),
            ),
          ),
        );
      });
    }

    test('a missing ancestor still establishes absence', () async {
      final locator = const DriverLocator.byKey(
        'confirm',
      ).descendantOf(const DriverLocator.byKey('missing-dialog'));
      expect(_tree().findAll(locator), isEmpty);
      await expectLater(
        waitForAbsentDriverLocator(
          locator,
          fetchTree: () async => _tree(),
          timeout: Duration.zero,
        ),
        completes,
      );
    });
  });

  group('at', () {
    test('selects a match by document order', () {
      final tree = _tree();
      const button = DriverLocator.byType('Button');

      expect(tree.findAll(button), hasLength(3));
      expect(tree.find(button.at(0)).text, 'Keep');
      expect(tree.find(button.at(1)).text, 'Discard');
      expect(tree.find(button.at(2)).text, 'Close');
    });

    test('reports the count when the index is out of range', () {
      _expectMiss(_tree(), const DriverLocator.byType('Button').at(7), <String>[
        'matched 3',
        'index 7',
      ]);
    });

    test('rejects a negative index up front', () {
      expect(
        () => const DriverLocator.byType('Button').at(-1),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('composed descriptions', () {
    test('read as one sentence', () {
      expect(
        const DriverLocator.byKey(
          'confirm',
        ).descendantOf(const DriverLocator.byKey('dialog-b')).toString(),
        'key "confirm" inside key "dialog-b"',
      );
      expect(
        const DriverLocator.byType('Button').at(2).toString(),
        'type "Button" at index 2',
      );
      expect(
        const DriverLocator.byText(
          'Save',
        ).descendantOf(const DriverLocator.byType('Dialog')).at(0).toString(),
        'text "Save" inside type "Dialog" at index 0',
      );
    });
  });
}
