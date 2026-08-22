import 'dart:io';

import 'package:test/test.dart';

void main() {
  final renderSource = File('lib/src/rendering/object.dart').readAsStringSync();
  final elementSource = File(
    'lib/src/framework/element.dart',
  ).readAsStringSync();
  final ownerSource = File('lib/src/framework/owner.dart').readAsStringSync();
  final flexSource = File('lib/src/rendering/flex.dart').readAsStringSync();
  final singleChildSources = <String, String>{
    for (final path in <String>[
      'lib/src/rendering/proxy_box.dart',
      'lib/src/rendering/constrained_box.dart',
      'lib/src/rendering/padding.dart',
      'lib/src/rendering/positioned_box.dart',
      'lib/src/rendering/decorated_box.dart',
      'lib/src/rendering/render_view.dart',
    ])
      path: File(path).readAsStringSync(),
  };

  test('pipeline scheduling validates ownership before disposed return', () {
    for (final signature in [
      'void scheduleLayout(RenderObject node)',
      'void schedulePaint(RenderObject node)',
    ]) {
      final method = _methodBody(renderSource, signature);
      expect(method, isNot(contains('node._pipelineOwner = this')));
      final ownershipCheck = method.indexOf(
        'identical(node._pipelineOwner, this)',
      );
      final disposedReturn = method.indexOf('if (_disposed)');
      expect(ownershipCheck, greaterThanOrEqualTo(0));
      expect(disposedReturn, greaterThan(ownershipCheck));
    }
  });

  test('render detach forgets ownership and attached drop detaches child', () {
    final detach = _methodBody(renderSource, 'void detach()');
    expect(detach, contains('_pipelineOwner = null'));
    expect(detach, contains('detach()'));

    final drop = _methodBody(renderSource, 'void _dropChild(');
    expect(drop, contains('child.detach()'));
  });

  test('generic render edge has one private store and read-only live view', () {
    final renderObject = _classBody(
      renderSource,
      'abstract class RenderObject',
    );
    expect(
      RegExp(
        r'^  RenderObject\? get parent => _parent;$',
        multiLine: true,
      ).allMatches(renderObject),
      hasLength(1),
    );
    expect(
      renderObject,
      isNot(
        matches(
          RegExp(
            r'^  (?:RenderObject\? parent;|(?:void\s+)?set parent\s*\()',
            multiLine: true,
          ),
        ),
      ),
    );

    expect(
      RegExp(
        r'^  final List<RenderObject> _children = <RenderObject>\[\];$',
        multiLine: true,
      ).allMatches(renderObject),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^  late final List<RenderObject> children =\s*'
        r'UnmodifiableListView<RenderObject>\(\s*_children,?\s*\);$',
        multiLine: true,
      ).allMatches(renderObject),
      hasLength(1),
    );
    final childStateMembers = RegExp(
      r'^  (?:(?:late|final)\s+)*(?:List|Set|Queue|LinkedList|Iterable)<RenderObject>\??\s+([_$A-Za-z][_$A-Za-z0-9]*)\s*(?:=|;)'
      r'|^  \S[^\n]*?\b([_$A-Za-z][_$A-Za-z0-9]*)(?:\([^)\n]*\))?\s*(?:(?:=>|=)\s*_children\s*;'
      r'|\{\s*return\s+_children\s*;\s*\})',
      multiLine: true,
    ).allMatches(renderObject).map((match) => match.group(1) ?? match.group(2));
    expect(
      childStateMembers,
      <String?>['_children', 'children'],
      reason: 'RenderObject must retain one child store and read-only view',
    );
    expect(
      RegExp(
        r'^  (?:final )?RenderObject\? '
        r'([_$A-Za-z][_$A-Za-z0-9]*)[ \t]*(?:=|;)',
        multiLine: true,
      ).allMatches(renderObject).map((match) => match.group(1)),
      <String?>['_parent'],
      reason: 'RenderObject must retain only one parent store',
    );

    final externalSources = <String, String>{
      for (final file in Directory(
        'lib',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') &&
            !file.path.endsWith('/src/rendering/object.dart'))
          file.path: file.readAsStringSync(),
      for (final file in Directory(
        'test/rendering',
      ).listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart')) file.path: file.readAsStringSync(),
    };
    final parentWrite = RegExp(r'\.parent\s*=(?!=)');
    final childrenMutation = RegExp(
      r'\.children\s*(?:\[[^\n]+\]\s*=|\.\s*(?:'
      'add|addAll|insert|insertAll|remove|removeAt|removeLast|removeRange|'
      'clear|setAll|setRange|fillRange|replaceRange|removeWhere|retainWhere|'
      r'sort|shuffle)\s*\()',
    );
    for (final entry in externalSources.entries) {
      expect(
        entry.value,
        isNot(matches(parentWrite)),
        reason: '${entry.key} must not assign a render parent directly',
      );
      expect(
        entry.value,
        isNot(matches(childrenMutation)),
        reason: '${entry.key} must not mutate render children directly',
      );
    }
  });

  test('root attachment publishes state only after recursive attach', () {
    final attachRoot = _methodBody(
      ownerSource,
      'void attachRootRenderObject(RenderObjectWithSingleChild root)',
    );
    final attach = attachRoot.indexOf('.attach(pipelineOwner)');
    expect(attach, greaterThanOrEqualTo(0));
    expect(attachRoot.indexOf('_rootRenderObject = root'), greaterThan(attach));
    expect(
      attachRoot.indexOf('_pointerRouter.root = root'),
      greaterThan(attach),
    );

    final clearRoot = _methodBody(
      ownerSource,
      'void clearRootRenderObject(RenderObjectWithSingleChild root)',
    );
    final childRemoval = clearRoot.indexOf(
      'attempt(() => root.setChild(null))',
    );
    final rootDetach = clearRoot.indexOf(
      'attempt((root as RenderObject).detach)',
    );
    expect(childRemoval, greaterThanOrEqualTo(0));
    expect(rootDetach, greaterThan(childRemoval));
    expect(
      clearRoot.indexOf('_rootRenderObject = null'),
      greaterThan(rootDetach),
    );
    expect(
      clearRoot.indexOf('_pointerRouter.root = null'),
      greaterThan(rootDetach),
    );
  });

  test('element unmount removes edges before standalone detach fallback', () {
    final renderElement = _classBody(
      elementSource,
      'class RenderObjectElement',
    );
    final unmount = _methodBody(renderElement, 'void unmount()');
    final edgeRemoval = unmount.indexOf('failures.attempt(detachRenderObject)');
    final standaloneDetach = unmount.indexOf(
      'failures.attempt(renderObject!.detach)',
    );
    expect(edgeRemoval, greaterThanOrEqualTo(0));
    expect(standaloneDetach, greaterThanOrEqualTo(0));
    expect(
      edgeRemoval,
      lessThan(standaloneDetach),
      reason:
          'external render-edge removal must remain before the exhaustive '
          'standalone detach fallback',
    );

    final multi = _classBody(
      elementSource,
      'class MultiChildRenderObjectElement',
    );
    final remove = _methodBody(
      multi,
      'void removeRenderObjectChild(RenderObject child, Element childElement)',
    );
    expect(remove, contains('dropChildRenderObject('));
    expect(remove, contains('child.parent'));
  });

  test('committed removals finish publication before original rethrow', () {
    final deactivate = _methodBody(
      ownerSource,
      'void deactivateChild(Element child)',
    );
    _expectInOrder(deactivate, [
      '_preflightDeactivate(child)',
      'collectOwnedExternalRenderEdges(externalEdges)',
      '_validateExternalRenderEdges(externalEdges)',
      '.detachRenderObject()',
      '_confirmDetached(',
      '_publishDeactivate(plan)',
      'child.deactivate()',
      'on Object catch (error, stackTrace)',
      'deferredError ??= error',
      '_inactiveElements.add(child)',
      'Error.throwWithStackTrace(',
    ]);
    expect(deactivate, contains('oldRenderParent'));
    expect(deactivate, contains('childObject.parent != null'));
    expect(deactivate, contains('expectedParent.children.any('));
    expect(deactivate, contains('identical(candidate, childObject)'));
    expect(deactivate, contains('identical(edge.child, renderObject)'));
    expect(
      elementSource,
      contains('void collectOwnedExternalRenderEdges(List<ExternalRenderEdge>'),
    );
    expect(elementSource, contains('class ExternalRenderEdge'));

    final flexRemove = _methodBody(flexSource, 'void remove(RenderBox child)');
    final drop = flexRemove.indexOf('dropChild(child)');
    final finallyBlock = flexRemove.indexOf('finally');
    final metadataRemoval = flexRemove.indexOf('_childrenData.remove(child)');
    expect(flexRemove, contains('wasOwned'));
    expect(drop, isNonNegative);
    expect(finallyBlock, greaterThan(drop));
    expect(flexRemove, contains('child.parent == null'));
    expect(flexRemove, contains('children.any('));
    expect(flexRemove, contains('identical(candidate, child)'));
    expect(metadataRemoval, greaterThan(finallyBlock));
  });

  test('built-in deactivation is exhaustive before first-error rethrow', () {
    final element = _classBody(elementSource, 'abstract class Element');
    _expectInOrder(_methodBody(element, 'void deactivate()'), [
      '_deactivated = true',
      'List<Element>.from(children)',
      'failures.attempt(child.deactivate)',
      'failures.rethrowFirst()',
    ]);

    final stateful = _classBody(elementSource, 'class StatefulElement');
    _expectInOrder(_methodBody(stateful, 'void deactivate()'), [
      'failures.attempt(_state.deactivate)',
      'failures.attempt(super.deactivate)',
      'failures.rethrowFirst()',
    ]);
  });

  test('single-child transition owns one non-virtual render edge', () {
    expect(
      RegExp(
        r'@internal\s+void\s+setSingleRenderObjectChild\(\s*'
        r'RenderObjectWithSingleChild owner,\s*'
        r'RenderObject\? next,\s*\)',
        multiLine: true,
      ).hasMatch(renderSource),
      isTrue,
    );

    final transition = _methodBody(
      renderSource,
      'void setSingleRenderObjectChild(',
    );
    expect(transition, isNot(contains('.setChild(')));
    expect(transition, isNot(contains('.adoptChild(')));
    expect(transition, isNot(contains('.dropChild(')));
    expect(renderSource, isNot(contains('updateSingleRenderObjectChild')));
    expect(renderSource, isNot(contains('updateChild(')));

    final mixin = _classBody(renderSource, 'mixin RenderObjectWithSingleChild');
    expect(mixin, contains('RenderObject? get child'));
    expect(mixin, contains('setSingleRenderObjectChild(this, child)'));
    expect(mixin, contains('void adoptChild(RenderObject child)'));
    expect(mixin, contains('void dropChild(RenderObject child)'));
    expect(
      _methodBody(mixin, 'void adoptChild(RenderObject child)'),
      contains('setChild(child)'),
    );
    expect(
      _methodBody(mixin, 'void dropChild(RenderObject child)'),
      contains('setChild(null)'),
    );

    for (final barrel in [
      'lib/noir.dart',
      'lib/noir_low_level.dart',
      'lib/noir_ffi.dart',
    ]) {
      expect(
        File(barrel).readAsStringSync(),
        allOf(
          isNot(contains('setSingleRenderObjectChild')),
          isNot(contains('updateSingleRenderObjectChild')),
        ),
      );
    }
  });

  test(
    'six single-child owners keep no parallel child storage or traversal',
    () {
      for (final entry in singleChildSources.entries) {
        expect(entry.value, isNot(contains('_child')), reason: entry.key);
        expect(
          entry.value,
          isNot(contains('void visitChildren(')),
          reason: entry.key,
        );
      }

      for (final path in <String>[
        'lib/src/rendering/proxy_box.dart',
        'lib/src/rendering/constrained_box.dart',
        'lib/src/rendering/padding.dart',
        'lib/src/rendering/positioned_box.dart',
      ]) {
        expect(
          singleChildSources[path],
          isNot(contains('void paint(')),
          reason: path,
        );
      }
      expect(
        singleChildSources['lib/src/rendering/decorated_box.dart'],
        contains('void paint('),
      );
      expect(
        singleChildSources['lib/src/rendering/render_view.dart'],
        isNot(contains('void paint(')),
      );
    },
  );

  test('typed owner member surfaces stay intentionally distinct', () {
    const getterOnlyOwners = <String, String>{
      'lib/src/rendering/constrained_box.dart': 'RenderConstrainedBox',
      'lib/src/rendering/padding.dart': 'RenderPadding',
      'lib/src/rendering/positioned_box.dart': 'RenderPositionedBox',
      'lib/src/rendering/decorated_box.dart': 'RenderDecoratedBox',
    };
    for (final entry in getterOnlyOwners.entries) {
      final path = entry.key;
      final source = singleChildSources[path]!;
      expect(source, isNot(contains('extends RenderProxyBox')), reason: path);
      expect(source, isNot(matches(RegExp(r'\bset child\s*\('))), reason: path);
      expect(source, isNot(contains('adoptChild(')), reason: path);
      _expectNonVirtualChildConstructor(source, entry.value, path);
    }

    final proxy = singleChildSources['lib/src/rendering/proxy_box.dart']!;
    expect(proxy, matches(RegExp(r'\bset child\s*\(')));
    expect(proxy, isNot(contains('adoptChild(')));
    _expectNonVirtualChildConstructor(
      proxy,
      'RenderProxyBox',
      'lib/src/rendering/proxy_box.dart',
    );

    final view = singleChildSources['lib/src/rendering/render_view.dart']!;
    expect(
      view,
      contains(
        'final class RenderView extends RenderBox '
        'with RenderObjectWithSingleChild',
      ),
    );
    expect(view, isNot(contains('RenderBox? get child')));
    expect(view, isNot(contains('set child(')));
  });
}

void _expectNonVirtualChildConstructor(
  String source,
  String className,
  String path,
) {
  final constructor = _methodBody(source, '$className(');
  expect(
    constructor,
    contains('setSingleRenderObjectChild(this, child)'),
    reason: path,
  );
  expect(constructor, isNot(contains('setChild(')), reason: path);
  expect(constructor, isNot(contains('adoptChild(')), reason: path);
  expect(constructor, isNot(contains('dropChild(')), reason: path);
  expect(constructor, isNot(contains('this.child =')), reason: path);
}

void _expectInOrder(String source, List<String> values) {
  var previous = -1;
  for (final value in values) {
    final current = source.indexOf(value, previous + 1);
    expect(
      current,
      greaterThan(previous),
      reason: 'missing/out of order: $value',
    );
    previous = current;
  }
}

String _methodBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $signature');
  final openParenthesis = source.indexOf('(', start);
  expect(openParenthesis, greaterThanOrEqualTo(0));
  var depth = 0;
  for (var index = openParenthesis; index < source.length; index++) {
    switch (source[index]) {
      case '(':
        depth++;
      case ')':
        depth--;
        if (depth == 0) {
          return _braceBody(source, source.indexOf('{', index));
        }
    }
  }
  fail('unbalanced parameters for $signature');
}

String _classBody(String source, String declaration) {
  final start = source.indexOf(declaration);
  expect(start, greaterThanOrEqualTo(0), reason: 'missing $declaration');
  return _braceBody(source, source.indexOf('{', start));
}

String _braceBody(String source, int openBrace) {
  expect(openBrace, greaterThanOrEqualTo(0));
  var depth = 0;
  for (var index = openBrace; index < source.length; index++) {
    switch (source[index]) {
      case '{':
        depth++;
      case '}':
        depth--;
        if (depth == 0) {
          return source.substring(openBrace, index + 1);
        }
    }
  }
  fail('unbalanced source fixture');
}
