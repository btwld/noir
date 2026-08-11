import 'dart:io';

import 'package:test/test.dart';

void main() {
  test(
    'GlobalKey lifecycle registration is framework-internal, not public API',
    () {
      final source = File('lib/src/framework/key.dart').readAsStringSync();

      const oldPublicApi = [
        'void registerElement(',
        'void unregisterElement(',
        'void updateWidgetBinding(',
        'void updateStateBinding(',
      ];
      for (final signature in oldPublicApi) {
        expect(
          source,
          isNot(contains(signature)),
          reason:
              'GlobalKey lifecycle registration must not be public app API; '
              'only BuildOwner may bind/unbind a GlobalKey.',
        );
      }

      expect(
        source,
        contains("import 'package:meta/meta.dart';"),
        reason:
            'GlobalKey needs package:meta for its @internal registration '
            'hooks.',
      );

      expect(
        RegExp(r'@internal\s+void register\(Element').hasMatch(source),
        isTrue,
        reason: 'GlobalKey.register must be annotated @internal.',
      );
      expect(
        RegExp(r'@internal\s+void unregister\(Element').hasMatch(source),
        isTrue,
        reason: 'GlobalKey.unregister must be annotated @internal.',
      );
    },
  );

  test(
    'BuildOwner owns GlobalKey placement and teardown as internal wiring',
    () {
      final source = File('lib/src/framework/owner.dart').readAsStringSync();

      const requiredInternalMembers = <String, String>{
        'registerGlobalKey': r'@internal\s+void registerGlobalKey\(',
        'unregisterGlobalKey': r'@internal\s+void unregisterGlobalKey\(',
        'validateGlobalKeyPlacement':
            r'@internal\s+void validateGlobalKeyPlacement\(',
        'deactivateChild': r'@internal\s+void deactivateChild\(',
        'finalizeTree': r'@internal\s+void finalizeTree\(',
      };
      for (final member in requiredInternalMembers.entries) {
        expect(
          RegExp(member.value).hasMatch(source),
          isTrue,
          reason:
              'BuildOwner must own GlobalKey placement/teardown: '
              '${member.key} must be annotated @internal.',
        );
      }
    },
  );

  test('partial reparenting and forced-detach machinery cannot return', () {
    final owner = File('lib/src/framework/owner.dart').readAsStringSync();
    final element = File('lib/src/framework/element.dart').readAsStringSync();
    final frameworkSource = '$owner\n$element';

    const removedSurface = [
      'retakeInactiveElement',
      'reparentElementWithBuildOwner',
      '_reparentElement',
      'forgetChild',
      'GlobalKeyReservation',
      '_globalKeyReservations',
    ];
    for (final token in removedSurface) {
      expect(
        frameworkSource,
        isNot(contains(token)),
        reason:
            'GlobalKey is lookup plus same-parent identity only; '
            '$token must not restore cross-parent movement machinery.',
      );
    }

    final baseElement = _sourceSlice(
      element,
      'abstract class Element',
      'class StatelessElement',
    );
    expect(
      baseElement,
      isNot(contains('void activate()')),
      reason: 'Base Element must not regain cross-parent GlobalKey activation.',
    );
  });

  test('incoming child owners preflight GlobalKey placement', () {
    final element = File('lib/src/framework/element.dart').readAsStringSync();
    final flexible = File('lib/src/widgets/flexible.dart').readAsStringSync();

    expect(
      _sourceSlice(
        element,
        'abstract class _ElementBase',
        'class ProxyElement',
      ),
      contains('validateGlobalKeyPlacement'),
    );
    expect(
      _sourceSlice(
        element,
        'class SingleChildRenderObjectElement',
        'class MultiChildRenderObjectElement',
      ),
      contains('validateGlobalKeyPlacement'),
    );
    expect(
      _sourceSlice(
        element,
        'class MultiChildRenderObjectElement',
        'void updateElementParent',
      ),
      contains('validateGlobalKeyPlacement'),
    );
    expect(
      _sourceSlice(
        flexible,
        'class FlexibleElement',
        'class FlexRenderObjectElement',
      ),
      contains('validateGlobalKeyPlacement'),
    );

    final inflateWidget = _sourceSlice(
      element,
      'static Element inflateWidget(',
      '/// Updates this element',
    );
    final placementValidation = inflateWidget.indexOf(
      'validateGlobalKeyPlacement',
    );
    final elementCreation = inflateWidget.indexOf('createElement()');
    expect(
      placementValidation,
      isNonNegative,
      reason: 'Element.inflateWidget must retain final placement validation.',
    );
    expect(
      elementCreation,
      greaterThan(placementValidation),
      reason:
          'Element.inflateWidget must validate a GlobalKey before creating '
          'the candidate Element.',
    );
  });

  test('BuildOwner teardown unregisters residual GlobalKey handles', () {
    final source = File('lib/src/framework/owner.dart').readAsStringSync();
    final disposeStart = source.indexOf('  void dispose() {');
    final disposeEnd = source.indexOf(
      '  void _handleNeedVisualUpdate()',
      disposeStart,
    );
    expect(disposeStart, isNonNegative);
    expect(disposeEnd, greaterThan(disposeStart));
    final disposeSource = source.substring(disposeStart, disposeEnd);

    expect(
      RegExp(
        r'_globalKeyRegistry\.entries[\s\S]*unregisterGlobalKey\(',
      ).hasMatch(disposeSource),
      isTrue,
      reason:
          'BuildOwner.dispose must clear each GlobalKey through the existing '
          'unregister path before clearing its registry.',
    );
  });

  test('State framework wiring (attach/updateWidget/detach) is internal, not '
      'public app API', () {
    final source = File('lib/src/framework/widget.dart').readAsStringSync();

    expect(
      source,
      contains("import 'package:meta/meta.dart';"),
      reason: 'State needs package:meta for its @internal framework wiring.',
    );

    expect(
      RegExp(r'@internal\s+void attach\(').hasMatch(source),
      isTrue,
      reason:
          'State.attach is framework wiring called only by StatefulElement '
          'and must be annotated @internal.',
    );
    expect(
      RegExp(r'@internal\s+void updateWidget\(').hasMatch(source),
      isTrue,
      reason:
          'State.updateWidget is framework wiring called only by '
          'StatefulElement and must be annotated @internal.',
    );
    expect(
      RegExp(r'@internal\s+void detach\(').hasMatch(source),
      isTrue,
      reason:
          'State.detach is framework wiring called only by StatefulElement '
          'and must be annotated @internal.',
    );
  });
}

String _sourceSlice(String source, String startToken, String endToken) {
  final start = source.indexOf(startToken);
  final end = source.indexOf(endToken, start + startToken.length);
  expect(start, isNonNegative, reason: 'missing source token: $startToken');
  expect(end, greaterThan(start), reason: 'missing source token: $endToken');
  return source.substring(start, end);
}
