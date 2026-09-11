import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('FocusManager key subscription is disposed by BuildOwner', () {
    final focusManagerSource = File(
      'lib/src/framework/focus_manager.dart',
    ).readAsStringSync();
    final buildOwnerSource = File(
      'lib/src/framework/owner.dart',
    ).readAsStringSync();

    expect(focusManagerSource, contains('InputSubscription'));
    expect(focusManagerSource, contains('_keySubscription.cancel()'));
    expect(
      buildOwnerSource,
      contains('attempt(focusManager.dispose)'),
      reason:
          'BuildOwner must attempt FocusManager disposal even when an '
          'earlier owned cleanup fails.',
    );
  });

  test('FocusNode child membership has one identity store and cached read-only '
      'view', () {
    final file = File('lib/src/framework/focus_manager.dart');
    final source = file.readAsStringSync();
    expect(
      RegExp(r'Set<FocusNode>\.identity\(\)').allMatches(source),
      hasLength(1),
    );
    expect(
      RegExp(
        r'late final Set<FocusNode> \w+ =\s*'
        r'UnmodifiableSetView<FocusNode>\(',
      ).allMatches(source),
      hasLength(1),
    );
    expect(
      source,
      contains('Iterable<FocusNode> get children => _childrenView;'),
    );
    expect(source, isNot(contains('get children => _children;')));
    expect(
      RegExp(
        r'_children\.(add|addAll|clear|remove|removeAll|removeWhere|retainAll|retainWhere)\(',
      ).allMatches(source).map((match) => match.group(1)),
      ['add', 'remove'],
    );
  });
}
