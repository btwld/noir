// ignore_for_file: avoid_equals_and_hash_code_on_mutable_classes
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('StatefulElement lifecycle', () {
    test('initState runs before first build and widget is available', () {
      final log = <String>[];
      final widget = _LifecycleProbeWidget(log);
      final owner = BuildOwner();
      final element = widget.createElement();

      element.mount(null, owner);

      expect(log, ['initState', 'build']);
      element.unmount();
    });

    test('didUpdateWidget fires before rebuild when configuration changes', () {
      final log = <String>[];
      final owner = BuildOwner();
      final first = _DidUpdateProbeWidget(value: 1, log: log);
      final element = first.createElement();

      element.mount(null, owner);
      expect(log, ['build:1']);

      final updated = _DidUpdateProbeWidget(value: 2, log: log);
      element.update(updated);

      expect(log.length, 3);
      expect(log[1], 'didUpdateWidget:1->2');
      expect(log[2], 'build:2');

      element.unmount();
    });

    test('updating with identical widget instance still rebuilds', () {
      final log = <String>[];
      final owner = BuildOwner();
      final widget = _DidUpdateProbeWidget(value: 1, log: log);
      final element = widget.createElement();

      element.mount(null, owner);
      expect(log, hasLength(1));

      element.update(widget);

      expect(log, ['build:1', 'didUpdateWidget:1->1', 'build:1']);
      element.unmount();
    });

    test(
      'value-equality widgets still trigger didUpdateWidget and rebuild',
      () {
        final log = <String>[];
        final owner = BuildOwner();
        final first = _ValueEqualityWidget(value: 1, log: log);
        final element = first.createElement();

        element.mount(null, owner);
        expect(log, ['build:1']);

        log.clear();
        final equalButNew = _ValueEqualityWidget(value: 1, log: log);
        element.update(equalButNew);

        expect(log, ['didUpdateWidget', 'build:1']);

        element.unmount();
      },
    );
  });

  group('State dispose/detach ordering', () {
    test('dispose() observes mounted and a readable context; detach clears '
        'both only afterward', () {
      final owner = BuildOwner();
      final recorder = _DisposeOrderRecorder();
      final key = GlobalKey<_DisposeOrderProbeState>();
      final widget = _DisposeOrderProbeWidget(key: key, recorder: recorder);
      final element = widget.createElement();

      element.mount(null, owner);
      final state = key.currentState!;

      element.unmount();

      expect(
        recorder.mountedDuringDispose,
        isTrue,
        reason: 'State.dispose() must observe mounted == true',
      );
      expect(
        recorder.contextDuringDispose,
        isNotNull,
        reason: 'State.dispose() must observe a readable context',
      );
      expect(recorder.contextReadError, isNull);

      expect(state.mounted, isFalse);
      expect(() => state.context, throwsA(anything));
    });
  });

  group('State.setState safeguards', () {
    test(
      'throws StateError when called after dispose and ignores callback',
      () {
        final log = <String>[];
        final key = GlobalKey<_SetStateGuardState>();
        final owner = BuildOwner();
        final widget = _SetStateGuardWidget(key: key, log: log);
        final element = widget.createElement();

        element.mount(null, owner);
        final state = key.currentState!;

        state.setState(() {
          log.add('mounted setState');
        });
        owner.buildScope();
        expect(log, ['initState', 'build', 'mounted setState', 'build']);

        element.unmount();

        var invoked = false;
        expect(
          () => state.setState(() {
            invoked = true;
          }),
          throwsA(isA<StateError>()),
        );
        expect(invoked, isFalse);
      },
    );

    test('throws StateError while dispose() is still running', () {
      final owner = BuildOwner();
      final key = GlobalKey<_DisposeSetStateProbeState>();
      final element = _DisposeSetStateProbeWidget(key: key).createElement();

      element.mount(null, owner);
      final state = key.currentState!;

      element.unmount();

      expect(
        state.mountedDuringDispose,
        isTrue,
        reason: 'the guard covers the window where mounted is still true',
      );
      expect(state.setStateError, isA<StateError>());
      expect(state.callbackInvoked, isFalse);
    });
  });

  group('Key implementations', () {
    test('GlobalKey tracks current state, context, and widget', () {
      final key = GlobalKey<_GlobalKeyProbeState>();
      final owner = BuildOwner();
      final widget = _GlobalKeyProbeWidget(key: key, value: 1);
      final element = widget.createElement();

      element.mount(null, owner);

      expect(key.currentState, isNotNull);
      expect(key.currentState!.value, equals(1));
      expect(key.currentWidget, same(widget));
      expect(key.currentContext, isNotNull);

      final updated = _GlobalKeyProbeWidget(key: key, value: 2);
      element.update(updated);

      expect(key.currentWidget, same(updated));
      expect(key.currentState!.value, equals(2));

      element.unmount();

      expect(key.currentState, isNull);
      expect(key.currentWidget, isNull);
      expect(key.currentContext, isNull);
    });

    test('UniqueKey instances are never equal', () {
      final a = UniqueKey();
      final b = UniqueKey();
      expect(a == b, isFalse);
    });

    test('ObjectKey equality is based on object identity', () {
      final value = Object();
      expect(ObjectKey(value), equals(ObjectKey(value)));
      final first = String.fromCharCodes([65]);
      final second = String.fromCharCodes([65]);
      expect(first, equals(second));
      expect(identical(first, second), isFalse);
      expect(ObjectKey(first), isNot(equals(ObjectKey(second))));
    });

    test('GlobalKey registers on update when newly introduced', () {
      final key = GlobalKey<_GlobalKeyProbeState>();
      final owner = BuildOwner();
      final widget = _GlobalKeyProbeWidget(value: 1);
      final element = widget.createElement();

      element.mount(null, owner);
      expect(key.currentContext, isNull);

      final updated = _GlobalKeyProbeWidget(key: key, value: 2);
      element.update(updated);

      expect(key.currentContext, isNotNull);
      expect(key.currentWidget, same(updated));

      element.unmount();
    });

    test('GlobalKey unregisters old key when key instance changes', () {
      final keyA = GlobalKey<_GlobalKeyProbeState>();
      final keyB = GlobalKey<_GlobalKeyProbeState>();
      final owner = BuildOwner();
      final widget = _GlobalKeyProbeWidget(key: keyA, value: 1);
      final element = widget.createElement();

      element.mount(null, owner);
      expect(keyA.currentContext, isNotNull);

      final updated = _GlobalKeyProbeWidget(key: keyB, value: 2);
      element.update(updated);

      expect(keyA.currentContext, isNull);
      expect(keyB.currentContext, isNotNull);

      element.unmount();
    });
  });
}

class _LifecycleProbeWidget extends StatefulWidget {
  const _LifecycleProbeWidget(this.log);
  final List<String> log;

  @override
  State<StatefulWidget> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbeWidget> {
  @override
  void initState() {
    super.initState();
    widget.log.add('initState');
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build');
    return Container();
  }
}

class _DidUpdateProbeWidget extends StatefulWidget {
  const _DidUpdateProbeWidget({required this.value, required this.log});
  final int value;
  final List<String> log;

  @override
  State<StatefulWidget> createState() => _DidUpdateProbeState();
}

class _DidUpdateProbeState extends State<_DidUpdateProbeWidget> {
  @override
  void didUpdateWidget(covariant _DidUpdateProbeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.log.add('didUpdateWidget:${oldWidget.value}->${widget.value}');
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:${widget.value}');
    return Container();
  }
}

class _DisposeOrderRecorder {
  bool? mountedDuringDispose;
  BuildContext? contextDuringDispose;
  Object? contextReadError;
}

class _DisposeOrderProbeWidget extends StatefulWidget {
  const _DisposeOrderProbeWidget({required this.recorder, super.key});
  final _DisposeOrderRecorder recorder;

  @override
  State<StatefulWidget> createState() => _DisposeOrderProbeState();
}

class _DisposeOrderProbeState extends State<_DisposeOrderProbeWidget> {
  @override
  Widget build(BuildContext context) => Container();

  @override
  void dispose() {
    widget.recorder.mountedDuringDispose = mounted;
    try {
      widget.recorder.contextDuringDispose = context;
    } catch (e) {
      widget.recorder.contextReadError = e;
    }
    super.dispose();
  }
}

class _SetStateGuardWidget extends StatefulWidget {
  const _SetStateGuardWidget({required this.log, super.key});
  final List<String> log;

  @override
  State<StatefulWidget> createState() => _SetStateGuardState();
}

class _SetStateGuardState extends State<_SetStateGuardWidget> {
  @override
  void initState() {
    super.initState();
    widget.log.add('initState');
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build');
    return Container();
  }
}

class _DisposeSetStateProbeWidget extends StatefulWidget {
  const _DisposeSetStateProbeWidget({super.key});

  @override
  State<StatefulWidget> createState() => _DisposeSetStateProbeState();
}

class _DisposeSetStateProbeState extends State<_DisposeSetStateProbeWidget> {
  bool? mountedDuringDispose;
  bool callbackInvoked = false;
  Object? setStateError;

  @override
  Widget build(BuildContext context) => Container();

  @override
  void dispose() {
    mountedDuringDispose = mounted;
    try {
      setState(() {
        callbackInvoked = true;
      });
      // ignore: avoid_catching_errors
    } on StateError catch (error) {
      setStateError = error;
    }
    super.dispose();
  }
}

class _GlobalKeyProbeWidget extends StatefulWidget {
  const _GlobalKeyProbeWidget({required this.value, super.key});
  final int value;

  @override
  State<StatefulWidget> createState() => _GlobalKeyProbeState();
}

class _GlobalKeyProbeState extends State<_GlobalKeyProbeWidget> {
  int value = 0;

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }

  @override
  void didUpdateWidget(covariant _GlobalKeyProbeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    value = widget.value;
  }

  @override
  Widget build(BuildContext context) => Container();
}

class _ValueEqualityWidget extends StatefulWidget {
  const _ValueEqualityWidget({required this.value, required this.log});

  final int value;
  final List<String> log;

  @override
  State<_ValueEqualityWidget> createState() => _ValueEqualityState();

  @override
  bool operator ==(Object other) =>
      other is _ValueEqualityWidget && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

class _ValueEqualityState extends State<_ValueEqualityWidget> {
  @override
  void didUpdateWidget(covariant _ValueEqualityWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.log.add('didUpdateWidget');
  }

  @override
  Widget build(BuildContext context) {
    widget.log.add('build:${widget.value}');
    return Container();
  }
}
