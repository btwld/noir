import 'dart:io';

import 'package:test/test.dart';

void main() {
  final owner = File('lib/src/framework/owner.dart').readAsStringSync();
  final compactOwner = owner.replaceAll(RegExp(r'\s+'), ' ');
  final element = File('lib/src/framework/element.dart').readAsStringSync();
  final flexible = File('lib/src/widgets/flexible.dart').readAsStringSync();
  final overlay = File('lib/src/widgets/overlay.dart').readAsStringSync();
  final productionSources = <String, String>{
    for (final file in Directory(
      'lib',
    ).listSync(recursive: true).whereType<File>())
      if (file.path.endsWith('.dart'))
        file.path.replaceAll(r'\', '/'): file.readAsStringSync(),
  };
  final elementExportPattern = RegExp(
    r"export\s+'[^']*framework/element\.dart'\s*([^;]*);",
    dotAll: true,
  );
  final elementExportClauses = <String, String>{
    for (final entry in productionSources.entries)
      if (elementExportPattern.firstMatch(entry.value) case final match?)
        entry.key: match.group(1)!,
  };

  test('maintained depth owners stay identity-based and walk-free', () {
    expect(
      compactOwner,
      contains(
        'final Map<Element, int> _depths = '
        'HashMap<Element, int>.identity();',
      ),
    );
    expect(
      compactOwner,
      contains(
        'final Map<Element, _DirtyReservation> _dirtyReservations = '
        'HashMap<Element, _DirtyReservation>.identity();',
      ),
    );
    expect(
      compactOwner,
      contains(
        'final Set<Element> _inactiveElements = '
        'HashSet<Element>.identity();',
      ),
    );
    expect(owner, contains('_DirtyBuckets'));

    final scheduling = [
      _slice(
        owner,
        'void scheduleBuild(Element e)',
        '/// Removes [e] from the live dirty reservation',
      ),
      _slice(owner, 'void buildScope()', 'void _registerElement'),
      _slice(
        owner,
        'final class _DirtyBuckets',
        '/// Registers [element] under [parent]',
      ),
    ].join('\n');
    expect(scheduling, isNot(contains('_elementDepth')));
    expect(scheduling, isNot(matches(RegExp(r'\.\s*parent\b'))));
    expect(scheduling, isNot(matches(RegExp(r'\.sort\s*\('))));
  });

  test('Element parent/depth writers are internal and owner-only', () {
    expect(element, contains('Element? get parent => _parent'));
    expect(element, isNot(contains('Element? parent;')));
    expect(
      elementExportClauses,
      hasLength(1),
      reason: 'framework/element.dart must have one curated direct export',
    );
    for (final entry in elementExportClauses.entries) {
      expect(
        entry.value,
        contains('show'),
        reason: '${entry.key} must keep an explicit element export surface',
      );
    }

    for (final writer in ['updateElementParent', 'updateElementDepth']) {
      final definition = RegExp('@internal\\s+void\\s+$writer\\s*\\(');
      expect(
        definition.allMatches(element),
        hasLength(1),
        reason: '$writer must have one @internal definition',
      );

      final callPattern = RegExp('\\b$writer\\s*\\(');
      expect(owner, matches(callPattern));
      expect(
        callPattern.allMatches(element),
        hasLength(1),
        reason: '$writer must not be called inside its defining library',
      );
      for (final entry in productionSources.entries) {
        if (entry.key.endsWith('/framework/element.dart') ||
            entry.key.endsWith('/framework/owner.dart')) {
          continue;
        }
        expect(
          entry.value,
          isNot(matches(callPattern)),
          reason: '${entry.key} must not call $writer',
        );
      }

      for (final barrel in elementExportClauses.entries) {
        expect(
          barrel.value,
          isNot(contains(writer)),
          reason: '${barrel.key} must not export $writer',
        );
      }
    }
  });

  test('built-in Element owners expose one private read-only child store', () {
    final baseElement = element.substring(
      element.indexOf('abstract class Element'),
      element.indexOf('/// Element backing a [StatelessWidget]'),
    );
    final ownerSlices = <String, String>{
      '_ElementBase': _slice(
        element,
        'abstract class _ElementBase',
        '/// Element backing a [ProxyWidget]',
      ),
      'SingleChildRenderObjectElement': _slice(
        element,
        'class SingleChildRenderObjectElement',
        '/// Element for RenderObjectWidgets with multiple children.',
      ),
      'MultiChildRenderObjectElement': _slice(
        element,
        'class MultiChildRenderObjectElement',
        '/// Non-virtual parent write',
      ),
      'FlexibleElement': _slice(
        flexible,
        'class FlexibleElement',
        '/// [MultiChildRenderObjectElement] specialised',
      ),
    };

    expect(baseElement, isNot(contains('final List<Element> children =')));
    expect(
      element,
      contains('List<Element> get children => const <Element>[]'),
    );
    for (final entry in ownerSlices.entries) {
      _expectOnePrivateChildStore(entry.key, entry.value);
    }

    expect(element, isNot(contains('_updateTrackedChildren')));
    expect(element, isNot(contains('mutableChildrenForFramework')));
    expect(element, isNot(contains('rawChildren')));
  });

  test('production child writes target only owner-private backing lists', () {
    final sources = '$element\n$flexible';
    final publicMutation = RegExp(
      r'^\s*children\s*(?:\.\.)?\s*\.(?:'
      'add|addAll|insert|insertAll|remove|removeAt|removeLast|removeRange|'
      'clear|setAll|setRange|fillRange|replaceRange|removeWhere|retainWhere|'
      r'sort|shuffle)\s*\(',
      multiLine: true,
    );
    expect(sources, isNot(matches(publicMutation)));

    final multi = _slice(
      element,
      'class MultiChildRenderObjectElement extends RenderObjectElement',
      '/// Non-virtual parent write',
    );
    final multiBacking = _childBackingName(
      'MultiChildRenderObjectElement',
      multi,
    );
    expect(
      RegExp(
        '^\\s*${RegExp.escape(multiBacking)}\\s*=',
        multiLine: true,
      ).allMatches(multi),
      isEmpty,
      reason: 'the retained multi-child backing list must never be replaced',
    );
  });

  test(
    'committed deactivation cleanup stays with each Element child owner',
    () {
      final deactivateCall = RegExp(r'\bowner\.deactivateChild\s*\(');
      final callCounts = <String, int>{
        for (final entry in productionSources.entries)
          if (deactivateCall.allMatches(entry.value).length case final count
              when count > 0)
            entry.key: count,
      };
      expect(
        callCounts,
        <String, int>{
          'lib/src/framework/element.dart': 3,
          'lib/src/widgets/flexible.dart': 1,
          'lib/src/widgets/overlay.dart': 3,
        },
        reason: 'every production deactivation caller must be inventoried',
      );

      final singleOwnerMethods = <String, String>{
        '_ElementBase': _slice(
          element,
          '  void _updateChild(Widget newWidget)',
          '  void _markNeedsBuild()',
        ),
        'SingleChildRenderObjectElement': _slice(
          element,
          '  void _updateChild(Widget? newWidget)',
          '  @override\n  void unmount()',
        ),
        'FlexibleElement': _slice(
          flexible,
          '  void performRebuild()',
          '  @override\n  RenderObject? findRenderObject()',
        ),
        '_OverlayTheaterElement': _slice(
          overlay,
          '  void _updateChild(Widget newWidget)',
          '  void _attachChildRenderObject()',
        ),
      };
      for (final entry in singleOwnerMethods.entries) {
        expect(
          deactivateCall.allMatches(entry.value),
          hasLength(1),
          reason: '${entry.key} deactivation call count drifted',
        );
        expect(
          _singleCommittedCleanup.allMatches(entry.value),
          hasLength(1),
          reason:
              '${entry.key} must pair its deactivation call with committed '
              'private-list cleanup in the same finally',
        );
      }

      final multiDeactivate = _slice(
        element,
        '  void _deactivateChild(Element child)',
        '  void _syncRenderChildren()',
      );
      expect(
        deactivateCall.allMatches(multiDeactivate),
        hasLength(1),
        reason: 'MultiChildRenderObjectElement must have one deactivate call',
      );
      expect(
        _multiCommittedCleanup.allMatches(multiDeactivate),
        hasLength(1),
        reason:
            'MultiChildRenderObjectElement must pair its deactivation call '
            'with committed identity cleanup in the same finally',
      );

      final portalSlot = _slice(
        overlay,
        '  void _updateSlot({',
        '  @override\n  void insertRenderObjectChild',
      );
      expect(
        deactivateCall.allMatches(portalSlot),
        hasLength(2),
        reason:
            '_PortalElement must deactivate both overlay slots through owner',
      );
      expect(
        _portalCommittedCleanup.allMatches(portalSlot),
        hasLength(2),
        reason:
            '_PortalElement must pair each deactivation call with committed '
            'identity cleanup in the same finally',
      );
    },
  );
}

String _slice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start);
  expect(start, isNonNegative, reason: 'missing class marker: $startMarker');
  expect(end, greaterThan(start), reason: 'missing end marker: $endMarker');
  return source.substring(start, end);
}

void _expectOnePrivateChildStore(String ownerName, String source) {
  final backingName = _childBackingName(ownerName, source);
  final viewMatches = _childViewPattern.allMatches(source).toList();
  expect(
    viewMatches,
    hasLength(1),
    reason: '$ownerName must cache exactly one public child inspection view',
  );
  expect(
    viewMatches.single.group(1),
    backingName,
    reason: '$ownerName child view must wrap its sole private backing list',
  );

  final elementStorageFields = <String>{
    for (final match in _typedElementFieldPattern.allMatches(source))
      match.group(1)!,
    backingName,
  };
  expect(
    elementStorageFields,
    unorderedEquals(<String>[backingName, 'children']),
    reason:
        '$ownerName must not declare parallel Element scalar or list storage',
  );
}

String _childBackingName(String ownerName, String source) {
  final backingMatches = _childBackingPattern.allMatches(source).toList();
  expect(
    backingMatches,
    hasLength(1),
    reason: '$ownerName must own exactly one private final Element list',
  );
  final name =
      backingMatches.single.group(1) ?? backingMatches.single.group(2)!;
  expect(
    name,
    startsWith('_'),
    reason: '$ownerName backing list must be private',
  );
  return name;
}

final _childBackingPattern = RegExp(
  r'^  final[ \t]+(?:'
  r'List[ \t]*<[ \t]*Element[ \t]*>[ \t]+([_$A-Za-z][_$A-Za-z0-9]*)'
  r'[ \t]*=[ \t]*(?:<[ \t]*Element[ \t]*>[ \t]*)?\[\]'
  r'|([_$A-Za-z][_$A-Za-z0-9]*)[ \t]*=[ \t]*'
  r'<[ \t]*Element[ \t]*>[ \t]*\[\]'
  r')[ \t]*;$',
  multiLine: true,
);

final _childViewPattern = RegExp(
  r'^  (?:late[ \t]+)?final[ \t]+List[ \t]*<[ \t]*Element[ \t]*>'
  r'[ \t]+children[ \t]*=[ \t]*UnmodifiableListView'
  r'(?:[ \t]*<[ \t]*Element[ \t]*>)?[ \t]*\([ \t]*'
  r'([_$A-Za-z][_$A-Za-z0-9]*)[ \t]*\)[ \t]*;$',
  multiLine: true,
);

final _singleCommittedCleanup = RegExp(
  r'try\s*\{\s*'
  r'owner\.deactivateChild\(currentChild\);\s*'
  r'\}\s*finally\s*\{\s*'
  r'if\s*\(\s*currentChild\.parent\s*==\s*null\s*'
  r'&&\s*!currentChild\.active\s*\)\s*\{\s*'
  r'_children\.clear\(\);\s*'
  r'\}\s*\}',
  multiLine: true,
);

final _portalCommittedCleanup = RegExp(
  r'try\s*\{\s*'
  r'owner\.deactivateChild\(current\);\s*'
  r'\}\s*finally\s*\{\s*'
  r'if\s*\(\s*current\.parent\s*==\s*null\s*'
  r'&&\s*!current\.active\s*\)\s*\{\s*'
  r'_children\.removeWhere\(\s*'
  r'\(candidate\)\s*=>\s*identical\(candidate,\s*current\)\s*'
  r'\);\s*'
  r'assign\(null\);\s*'
  r'\}\s*\}',
  multiLine: true,
);

final _multiCommittedCleanup = RegExp(
  r'try\s*\{\s*'
  r'owner\.deactivateChild\(child\);\s*'
  r'\}\s*finally\s*\{\s*'
  r'if\s*\(\s*child\.parent\s*==\s*null\s*'
  r'&&\s*!child\.active\s*\)\s*\{\s*'
  r'_children\.removeWhere\(\s*'
  r'\(candidate\)\s*=>\s*identical\(candidate,\s*child\)\s*'
  r'\);\s*'
  r'\}\s*\}',
  multiLine: true,
);

final _typedElementFieldPattern = RegExp(
  r'^  (?:(?:late|static|final|const)[ \t]+)*'
  r'(?:Element[ \t]*\??|List[ \t]*<[ \t]*Element[ \t]*>[ \t]*\??)'
  r'[ \t]+([_$A-Za-z][_$A-Za-z0-9]*)'
  r'(?=[ \t]*(?:=|;))',
  multiLine: true,
);
