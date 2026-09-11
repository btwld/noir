import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  group('*OfExactType matches the exact runtime type', () {
    test('a subclassed InheritedWidget does not answer a base-type lookup', () {
      final results = _Results();
      final host = TestElementHost()
        ..mount(
          _DerivedInherited(value: 'derived', child: _LookupProbe(results)),
        );

      expect(
        results.baseInherited,
        isNull,
        reason: '_DerivedInherited is not a _BaseInherited lookup answer',
      );
      expect(results.baseInheritedElement, isNull);
      expect(results.derivedInherited?.value, 'derived');

      host.dispose();
    });

    test('a base-type lookup walks past a nearer subclass to its own '
        'type', () {
      final results = _Results();
      final host = TestElementHost()
        ..mount(
          _BaseInherited(
            value: 'base',
            child: _DerivedInherited(
              value: 'derived',
              child: _LookupProbe(results),
            ),
          ),
        );

      expect(results.baseInherited?.value, 'base');
      expect(results.derivedInherited?.value, 'derived');

      host.dispose();
    });

    test('a subclassed ancestor widget does not answer a base-type '
        'lookup', () {
      final results = _Results();
      final host = TestElementHost()
        ..mount(_DerivedHost(child: _LookupProbe(results)));

      expect(results.baseHost, isNull);
      expect(results.derivedHost, isA<_DerivedHost>());

      host.dispose();
    });

    test('a base-type widget lookup walks past a nearer subclass to its '
        'own type', () {
      final results = _Results();
      final outer = _BaseHost(
        child: _DerivedHost(child: _LookupProbe(results)),
      );
      final host = TestElementHost()..mount(outer);

      expect(
        results.baseHost,
        same(outer),
        reason:
            '_DerivedHost is not a _BaseHost lookup answer; the walk '
            'continues to the farther exact ancestor',
      );
      expect(results.derivedHost, isA<_DerivedHost>());

      host.dispose();
    });

    test('findAncestorStateOfType still matches subtypes', () {
      final results = _Results();
      final host = TestElementHost()
        ..mount(_StatefulHost(child: _LookupProbe(results)));

      expect(
        results.anyState,
        isNotNull,
        reason: 'only the *OfExactType lookups are exact',
      );

      host.dispose();
    });
  });
}

class _Results {
  _BaseInherited? baseInherited;
  _DerivedInherited? derivedInherited;
  Object? baseInheritedElement;
  _BaseHost? baseHost;
  _DerivedHost? derivedHost;
  State<StatefulWidget>? anyState;
}

class _LookupProbe extends StatelessWidget {
  const _LookupProbe(this.results);

  final _Results results;

  @override
  Widget build(BuildContext context) {
    results
      ..baseInherited = context
          .dependOnInheritedWidgetOfExactType<_BaseInherited>()
      ..derivedInherited = context
          .dependOnInheritedWidgetOfExactType<_DerivedInherited>()
      ..baseInheritedElement = context
          .getElementForInheritedWidgetOfExactType<_BaseInherited>()
      ..baseHost = context.findAncestorWidgetOfExactType<_BaseHost>()
      ..derivedHost = context.findAncestorWidgetOfExactType<_DerivedHost>()
      ..anyState = context.findAncestorStateOfType<State<StatefulWidget>>();
    return const SizedBox(width: 1, height: 1);
  }
}

class _BaseInherited extends InheritedWidget {
  const _BaseInherited({required this.value, required super.child});

  final String value;

  @override
  bool updateShouldNotify(_BaseInherited oldWidget) => oldWidget.value != value;
}

class _DerivedInherited extends _BaseInherited {
  const _DerivedInherited({required super.value, required super.child});
}

class _BaseHost extends StatelessWidget {
  const _BaseHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _DerivedHost extends _BaseHost {
  const _DerivedHost({required super.child});
}

class _StatefulHost extends StatefulWidget {
  const _StatefulHost({required this.child});

  final Widget child;

  @override
  State<_StatefulHost> createState() => _StatefulHostState();
}

class _StatefulHostState extends State<_StatefulHost> {
  @override
  Widget build(BuildContext context) => widget.child;
}
