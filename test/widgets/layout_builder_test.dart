// `LayoutBuilder` is the only widget that reads the space its parent offers.
// These tests pin what triggers a rebuild, because an extra rebuild during
// layout is as wrong as a missing one: the builder runs inside the layout
// pass, not before it.
// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/test_element_host.dart';
import '../helpers/widget_tester.dart';

void main() {
  group('LayoutBuilder', () {
    test('reports the constraints its parent offers', () {
      final seen = <BoxConstraints>[];
      final tester = WidgetTester(maxWidth: 40, maxHeight: 10);
      try {
        tester.pumpWidget(
          SizedBox(
            width: 12,
            height: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                seen.add(constraints);
                return const SizedBox(width: 1, height: 1);
              },
            ),
          ),
        );
        expect(seen, hasLength(1));
        expect(seen.single.maxWidth, 12);
        expect(seen.single.maxHeight, 3);
      } finally {
        tester.dispose();
      }
    });

    test('lays the built child out in the same frame', () {
      final capture = BufferCapture(width: 8, height: 2);
      try {
        final frame = capture.capture(
          SizedBox(
            width: 8,
            height: 2,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  Text('w=${constraints.maxWidth}'),
            ),
          ),
        );
        expect(frame.toText(), contains('w=8'));
      } finally {
        capture.dispose();
      }
    });

    test('repeated layout at the same constraints does not rebuild', () {
      var builds = 0;
      final host = TestElementHost();
      try {
        host
          ..mount(
            LayoutBuilder(
              builder: (context, constraints) {
                builds++;
                return const SizedBox(width: 1, height: 1);
              },
            ),
          )
          ..pumpFrame(constraints: _outer);
        expect(builds, 1);

        // `flushLayout` skips a clean tree, so dirty the render object to force
        // real layout passes. Only then does the guard have anything to guard.
        for (var pass = 0; pass < 3; pass++) {
          host.renderObject!.markNeedsLayout();
          host.pumpFrame(constraints: _outer);
        }

        expect(builds, 1);
      } finally {
        host.dispose();
      }
    });

    test('changed constraints rebuild the child', () {
      final seen = <int?>[];
      final host = TestElementHost();
      try {
        host
          ..mount(
            LayoutBuilder(
              builder: (context, constraints) {
                seen.add(constraints.maxWidth);
                return const SizedBox(width: 1, height: 1);
              },
            ),
          )
          ..pumpFrame(constraints: _outer)
          ..pumpFrame(
            constraints: const BoxConstraints(maxWidth: 20, maxHeight: 6),
          );
        expect(seen, [30, 20]);
      } finally {
        host.dispose();
      }
    });

    test('a widget update rebuilds the child', () {
      final seen = <String>[];
      final host = TestElementHost();
      Widget build(String label) => LayoutBuilder(
        builder: (context, constraints) {
          seen.add(label);
          return const SizedBox(width: 1, height: 1);
        },
      );
      try {
        host
          ..mount(build('first'))
          ..pumpFrame(constraints: _outer)
          ..update(build('second'))
          ..pumpFrame(constraints: _outer);
        expect(seen, ['first', 'second']);
      } finally {
        host.dispose();
      }
    });

    test('an inherited widget update rebuilds the child', () {
      final seen = <Color>[];
      final host = TestElementHost();
      Widget build(Color surface) => Theme(
        data: ThemeData.dark.copyWith(surface: surface),
        child: LayoutBuilder(
          builder: (context, constraints) {
            seen.add(Theme.of(context).surface);
            return const SizedBox(width: 1, height: 1);
          },
        ),
      );
      try {
        host
          ..mount(build(Color.blue))
          ..pumpFrame(constraints: _outer)
          ..update(build(Color.red))
          ..pumpFrame(constraints: _outer);
        expect(seen, [Color.blue, Color.red]);
      } finally {
        host.dispose();
      }
    });

    test('a dependency the builder still reads notifies it', () {
      var builds = 0;
      final host = TestElementHost();
      try {
        host
          ..mount(
            Theme(
              data: ThemeData.dark,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  builds++;
                  Theme.of(context);
                  return const SizedBox(width: 1, height: 1);
                },
              ),
            ),
          )
          ..pumpFrame(constraints: _outer);
        expect(builds, 1);

        // Notify without rebuilding the subtree, so only the registered
        // dependency can reach the builder.
        _inheritedElement(host.root!).notifyDependents();
        host.pumpFrame(constraints: _outer);

        expect(builds, 2);
      } finally {
        host.dispose();
      }
    });

    test('a dependency the builder stopped reading no longer notifies it', () {
      var builds = 0;
      var reads = true;
      final host = TestElementHost();
      try {
        host
          ..mount(
            Theme(
              data: ThemeData.dark,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  builds++;
                  if (reads) Theme.of(context);
                  return const SizedBox(width: 1, height: 1);
                },
              ),
            ),
          )
          ..pumpFrame(constraints: _outer);
        expect(builds, 1);

        // The build this notification triggers drops the dependency.
        reads = false;
        _inheritedElement(host.root!).notifyDependents();
        host.pumpFrame(constraints: _outer);
        expect(builds, 2);

        _inheritedElement(host.root!).notifyDependents();
        host.pumpFrame(constraints: _outer);

        expect(builds, 2);
      } finally {
        host.dispose();
      }
    });

    test('the built child keeps its State across a constraint change', () {
      final log = <String>[];
      final host = TestElementHost();
      try {
        host
          ..mount(
            LayoutBuilder(builder: (context, constraints) => _Probe(log: log)),
          )
          ..pumpFrame(constraints: _outer)
          ..pumpFrame(
            constraints: const BoxConstraints(maxWidth: 20, maxHeight: 6),
          );
        expect(log, ['init']);
      } finally {
        host.dispose();
      }
    });

    test('nested builders each report their own space', () {
      final outer = <int?>[];
      final inner = <int?>[];
      final host = TestElementHost();
      try {
        host
          ..mount(
            LayoutBuilder(
              builder: (context, constraints) {
                outer.add(constraints.maxWidth);
                return SizedBox(
                  width: 7,
                  height: 2,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      inner.add(constraints.maxWidth);
                      return const SizedBox(width: 1, height: 1);
                    },
                  ),
                );
              },
            ),
          )
          ..pumpFrame(constraints: _outer);
        expect(outer, [30]);
        expect(inner, [7]);
      } finally {
        host.dispose();
      }
    });

    test('unbounded and zero space reach the builder unchanged', () {
      final seen = <BoxConstraints>[];
      final host = TestElementHost();
      Widget build() => LayoutBuilder(
        builder: (context, constraints) {
          seen.add(constraints);
          return const SizedBox(width: 1, height: 1);
        },
      );
      try {
        host
          ..mount(build())
          ..pumpFrame(constraints: const BoxConstraints())
          ..pumpFrame(
            constraints: const BoxConstraints.tight(width: 0, height: 0),
          );
        expect(seen.first.maxWidth, isNull);
        expect(seen.first.maxHeight, isNull);
        expect(seen.last.maxWidth, 0);
        expect(seen.last.maxHeight, 0);
      } finally {
        host.dispose();
      }
    });

    test('a builder failure leaves the next layout able to retry', () {
      var attempts = 0;
      final host = TestElementHost();
      try {
        host.mount(
          LayoutBuilder(
            builder: (context, constraints) {
              attempts++;
              if (attempts == 1) throw StateError('builder failed');
              return const SizedBox(width: 1, height: 1);
            },
          ),
        );
        expect(
          () => host.pumpFrame(constraints: _outer),
          throwsA(isA<StateError>()),
        );
        host.pumpFrame(constraints: _outer);
        expect(attempts, 2);
      } finally {
        host.dispose();
      }
    });

    test('swapping the built child disposes the old one in the same frame', () {
      final log = <String>[];
      var swapped = false;
      final host = TestElementHost();
      Widget build() => LayoutBuilder(
        builder: (context, constraints) =>
            swapped ? _OtherProbe(log: log) : _Probe(log: log),
      );
      try {
        host
          ..mount(build())
          ..pumpFrame(constraints: _outer);
        expect(log, ['init']);

        swapped = true;
        host
          ..update(build())
          ..pumpFrame(constraints: _outer);

        expect(log, ['init', 'other-init', 'dispose']);
      } finally {
        host.dispose();
      }
    });

    test('the render object drops its child when the builder is torn down', () {
      final log = <String>[];
      final host = TestElementHost();
      host
        ..mount(
          LayoutBuilder(builder: (context, constraints) => _Probe(log: log)),
        )
        ..pumpFrame(constraints: _outer)
        ..dispose();
      expect(log, ['init', 'dispose']);
    });
  });
}

/// The first [InheritedElement] at or under [element].
InheritedElement _inheritedElement(Element element) {
  if (element is InheritedElement) return element;
  for (final child in element.children) {
    final found = _maybeInheritedElement(child);
    if (found != null) return found;
  }
  throw StateError('no InheritedElement under ${element.widget.runtimeType}');
}

InheritedElement? _maybeInheritedElement(Element element) {
  if (element is InheritedElement) return element;
  for (final child in element.children) {
    final found = _maybeInheritedElement(child);
    if (found != null) return found;
  }
  return null;
}

/// Outer constraints the layout tests reuse.
const _outer = BoxConstraints(maxWidth: 30, maxHeight: 8);

/// Records its own lifecycle so a test can see whether a rebuild replaced it.
class _Probe extends StatefulWidget {
  const _Probe({required this.log});

  /// Lifecycle log this probe appends to.
  final List<String> log;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('init');
  }

  @override
  void dispose() {
    widget.log.add('dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}

/// A second probe type, so a rebuild replaces the child instead of updating it.
class _OtherProbe extends StatefulWidget {
  const _OtherProbe({required this.log});

  /// Lifecycle log this probe appends to.
  final List<String> log;

  @override
  State<_OtherProbe> createState() => _OtherProbeState();
}

class _OtherProbeState extends State<_OtherProbe> {
  @override
  void initState() {
    super.initState();
    widget.log.add('other-init');
  }

  @override
  void dispose() {
    widget.log.add('other-dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 1, height: 1);
}
