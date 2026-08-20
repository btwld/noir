import 'dart:async';

import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  test('hooks reject calls outside a HookWidget build', () {
    expect(() => useState<int>(0), throwsA(isA<StateError>()));
    expect(useContext, throwsA(isA<StateError>()));
  });

  test('useContext returns the active Noir build context', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    BuildContext? builderContext;
    BuildContext? hookContext;

    host.mount(
      HookBuilder(
        builder: (context) {
          builderContext = context;
          hookContext = useContext();
          return const Container();
        },
      ),
    );

    expect(hookContext, same(builderContext));
  });

  test('useContext does not consume a stateful hook slot', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var readContext = true;
    late ValueNotifier<int> tail;
    ValueNotifier<int>? firstTail;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        useState<int>(0);
        if (readContext) {
          expect(useContext(), same(context));
        }
        tail = useState<int>(1);
        firstTail ??= tail;
        return const Container();
      },
    );

    host.mount(buildRoot());
    readContext = false;
    host.update(buildRoot());

    expect(tail, same(firstTail));
  });

  test('useState retains identity and schedules rebuilds', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    late ValueNotifier<int> counter;
    ValueNotifier<int>? firstCounter;
    var builds = 0;

    host.mount(
      HookBuilder(
        builder: (context) {
          builds++;
          counter = useState<int>(0);
          firstCounter ??= counter;
          return const Container();
        },
      ),
    );

    expect(builds, 1);
    expect(counter.value, 0);

    counter.value = 2;
    host.pumpBuild();

    expect(builds, 2);
    expect(counter, same(firstCounter));
    expect(counter.value, 2);
  });

  test('key lists are snapshotted before later mutation', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final keys = <Object?>[1];
    late Object memoized;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        memoized = useMemoized<Object>(Object.new, keys);
        return const Container();
      },
    );

    host.mount(buildRoot());
    final first = memoized;

    keys[0] = 2;
    host.update(buildRoot());

    expect(memoized, isNot(same(first)));
  });

  test('a key change recreates only its own hook slot', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = 0;
    late Object keyedValue;
    late Object tailValue;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        keyedValue = useMemoized<Object>(Object.new, <Object?>[key]);
        tailValue = useMemoized<Object>(Object.new);
        return const Container();
      },
    );

    host.mount(buildRoot());
    final firstKeyedValue = keyedValue;
    final firstTailValue = tailValue;

    key = 1;
    host.update(buildRoot());

    expect(keyedValue, isNot(same(firstKeyedValue)));
    expect(tailValue, same(firstTailValue));
  });

  test('useCallback retains identity until its keys change', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = 0;
    var value = 1;
    late int Function() callback;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final capturedValue = value;
        callback = useCallback<int Function()>(() => capturedValue, <Object?>[
          key,
        ]);
        return const Container();
      },
    );

    host.mount(buildRoot());
    final firstCallback = callback;

    value = 2;
    host.update(buildRoot());
    expect(callback, same(firstCallback));
    expect(callback(), 1);

    key = 1;
    host.update(buildRoot());
    expect(callback, isNot(same(firstCallback)));
    expect(callback(), 2);
  });

  test('keys preserve NaN and distinguish signed zero', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var key = double.nan;
    late Object value;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        value = useMemoized<Object>(Object.new, <Object?>[key]);
        return const Container();
      },
    );

    host.mount(buildRoot());
    final nanValue = value;

    key = double.nan;
    host.update(buildRoot());
    expect(value, same(nanValue));

    key = 0.0;
    host.update(buildRoot());
    final positiveZeroValue = value;
    expect(value, isNot(same(nanValue)));

    key = -0.0;
    host.update(buildRoot());
    expect(value, isNot(same(positiveZeroValue)));
  });

  test('keyed useEffect installs its replacement before old cleanup', () {
    final host = TestElementHost();
    final log = <String>[];
    var key = 'a';

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final effectKey = key;
        useEffect(() {
          log.add('effect:$effectKey');
          return () {
            log.add('cleanup:$effectKey');
          };
        }, <Object?>[effectKey]);
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(log, <String>['effect:a']);

    host.update(buildRoot());
    expect(log, <String>['effect:a']);

    key = 'b';
    host.update(buildRoot());
    expect(log, <String>['effect:a', 'effect:b', 'cleanup:a']);

    host.dispose();
    expect(log, <String>['effect:a', 'effect:b', 'cleanup:a', 'cleanup:b']);
  });

  test('useEffect without keys reruns on every build', () {
    final host = TestElementHost();
    final log = <String>[];

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        useEffect(() {
          log.add('effect');
          return () {
            log.add('cleanup');
          };
        });
        return const Container();
      },
    );

    host.mount(buildRoot());
    host.update(buildRoot());
    host.dispose();

    expect(log, <String>['effect', 'cleanup', 'effect', 'cleanup']);
  });

  test('useEffect fails fast when it synchronously requests a rebuild', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final errors = <Object>[];
    var effectCount = 0;

    runZonedGuarded(() {
      host.mount(
        HookBuilder(
          builder: (context) {
            final counter = useState<int>(0);
            useEffect(() {
              effectCount++;
              if (effectCount < 3) {
                counter.value++;
              }
              return null;
            });
            return const Container();
          },
        ),
      );
    }, (error, stackTrace) => errors.add(error));
    expect(effectCount, 1);
    expect(errors, hasLength(1));
    expect(errors.single, _effectRebuildError);

    runZonedGuarded(host.pumpBuild, (error, stackTrace) => errors.add(error));
    expect(effectCount, 1, reason: 'no effect-driven rebuild was scheduled');
    expect(errors, hasLength(1));
  });

  test('effect cleanup rebuild failures preserve work and reset the guard', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final errors = <Object>[];
    final log = <String>[];
    late ValueNotifier<int> counter;
    var requestRebuildFromCleanup = true;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        counter = useState<int>(0);
        useEffect(() {
          log.add('effect');
          return () {
            log.add('cleanup');
            if (requestRebuildFromCleanup) {
              requestRebuildFromCleanup = false;
              counter.value++;
            }
          };
        });
        return const Container();
      },
    );

    host.mount(buildRoot());

    runZonedGuarded(
      () => host.update(buildRoot()),
      (error, stackTrace) => errors.add(error),
    );
    expect(errors, hasLength(1));
    expect(errors.single, _effectRebuildError);
    expect(log, <String>[
      'effect',
      'cleanup',
      'effect',
    ], reason: 'the replacement effect is still attempted after cleanup');
    runZonedGuarded(
      () => counter.value++,
      (error, stackTrace) => errors.add(error),
    );
    expect(errors, hasLength(1), reason: 'the effect guard must be restored');
  });

  test('keyless effects preserve the first cleanup failure', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final cleanupError = StateError('cleanup failed');
    final effectError = StateError('effect failed');
    final errors = <Object>[];
    final log = <String>[];
    late ValueNotifier<int> counter;
    var fail = false;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        counter = useState<int>(0);
        useEffect(() {
          log.add('effect');
          if (fail) {
            throw effectError;
          }
          return () {
            log.add('cleanup');
            if (fail) {
              throw cleanupError;
            }
          };
        });
        return const Container();
      },
    );

    host.mount(buildRoot());
    fail = true;

    expect(() => host.update(buildRoot()), throwsA(same(cleanupError)));
    expect(log, <String>['effect', 'cleanup', 'effect']);
    runZonedGuarded(
      () => counter.value++,
      (error, stackTrace) => errors.add(error),
    );
    expect(errors, isEmpty, reason: 'the effect guard must restore on failure');
  });

  test('keyed effect cleanup rebuild failures preserve replacement order', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    final errors = <Object>[];
    final log = <String>[];
    var key = 0;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final counter = useState<int>(0);
        final effectKey = key;
        useEffect(() {
          log.add('effect:first:$effectKey');
          return () {
            log.add('cleanup:first:$effectKey');
          };
        }, <Object?>[effectKey]);
        useEffect(() {
          log.add('effect:second:$effectKey');
          return () {
            log.add('cleanup:second:$effectKey');
            if (effectKey == 0) {
              counter.value++;
            }
          };
        }, <Object?>[effectKey]);
        return const Container();
      },
    );

    host.mount(buildRoot());
    key = 1;
    runZonedGuarded(
      () => host.update(buildRoot()),
      (error, stackTrace) => errors.add(error),
    );

    expect(errors, hasLength(1));
    expect(errors.single, _effectRebuildError);
    expect(log, <String>[
      'effect:first:0',
      'effect:second:0',
      'effect:first:1',
      'effect:second:1',
      'cleanup:second:0',
      'cleanup:first:0',
    ]);
  });

  test('effect disposal cleanup rebuild failures preserve later cleanup', () {
    final host = TestElementHost();
    final errors = <Object>[];
    final log = <String>[];

    host.mount(
      HookBuilder(
        builder: (context) {
          final counter = useState<int>(0);
          useEffect(
            () => () {
              log.add('first');
            },
            const <Object?>[],
          );
          useEffect(
            () => () {
              log.add('second');
              counter.value++;
            },
            const <Object?>[],
          );
          return const Container();
        },
      ),
    );

    runZonedGuarded(host.dispose, (error, stackTrace) => errors.add(error));

    expect(errors, hasLength(1));
    expect(errors.single, _effectRebuildError);
    expect(log, <String>['second', 'first']);
  });

  test('runtime-type mismatch throws outside reassemble', () {
    final host = TestElementHost();
    final log = <String>[];
    var useStateFirst = true;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        if (useStateFirst) {
          useState<int>(0);
        } else {
          useMemoized<Object>(Object.new);
        }
        useOnDispose(() {
          log.add('tail disposed');
        });
        return const Container();
      },
    );

    host.mount(buildRoot());
    useStateFirst = false;

    expect(
      () => host.update(buildRoot()),
      throwsA(
        isA<StateError>().having(
          (error) => error.toString(),
          'message',
          contains('Hook type mismatch'),
        ),
      ),
    );
    expect(log, <String>['tail disposed']);

    host.dispose();
    expect(log, <String>['tail disposed']);
  });

  test('reassemble permits one structural hook replacement build', () {
    final host = TestElementHost();
    final log = <String>[];
    var useStateFirst = true;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        if (useStateFirst) {
          useState<int>(0);
        } else {
          useMemoized<Object>(Object.new);
        }
        useOnDispose(() {
          log.add('tail disposed');
        });
        return const Container();
      },
    );

    host.mount(buildRoot());
    useStateFirst = false;
    host.owner.reassemble();
    host.pumpBuild();

    expect(log, <String>['tail disposed']);

    useStateFirst = true;
    expect(
      () => host.update(buildRoot()),
      throwsA(isA<StateError>()),
      reason: 'the reassemble recovery applies only to its scheduled build',
    );
    expect(log, <String>['tail disposed', 'tail disposed']);

    host.dispose();
  });

  test('HookState.reassemble attempts every retained hook', () {
    final host = TestElementHost();
    final log = <String>[];

    host.mount(
      HookBuilder(
        builder: (context) {
          use(_ReassembleProbeHook('first', log, shouldThrow: true));
          use(_ReassembleProbeHook('second', log));
          return const Container();
        },
      ),
    );

    expect(host.owner.reassemble, throwsA(isA<StateError>()));
    expect(log, <String>['reassemble:first', 'reassemble:second']);

    host.pumpBuild();
    host.dispose();
  });

  test('class-based HookState.build may compose later hooks', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var initialValue = 3;
    late ValueNotifier<int> value;
    ValueNotifier<int>? firstValue;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        value = use(_ComposedStateHook(initialValue));
        firstValue ??= value;
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(value.value, 3);

    value.value = 4;
    host.pumpBuild();
    initialValue = 9;
    host.update(buildRoot());

    expect(value, same(firstValue));
    expect(value.value, 4);
  });

  test('non-build hook lifecycle callbacks cannot call hooks', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var version = 0;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        use(_InvalidUpdateHook(version));
        return const Container();
      },
    );

    host.mount(buildRoot());
    version = 1;

    expect(() => host.update(buildRoot()), throwsA(isA<StateError>()));
  });

  test('useContext rejects non-build hook lifecycle callbacks', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var version = 0;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        use(_InvalidContextUpdateHook(version));
        return const Container();
      },
    );

    host.mount(buildRoot());
    version = 1;

    expect(() => host.update(buildRoot()), throwsA(isA<StateError>()));
  });

  test('tail cleanup callbacks cannot create new hook slots', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var includeHook = true;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        if (includeHook) {
          useOnDispose(() {
            useState<int>(0);
          });
        }
        return const Container();
      },
    );

    host.mount(buildRoot());
    includeHook = false;

    expect(() => host.update(buildRoot()), throwsA(isA<StateError>()));
  });

  test('class-based hooks receive update and disposal lifecycle', () {
    final host = TestElementHost();
    final log = <String>[];
    var value = 1;
    late int result;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        result = use(_ProbeHook(value, log));
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(result, 1);
    expect(log, <String>['init:1', 'build:1']);

    value = 2;
    host.update(buildRoot());
    expect(result, 2);
    expect(log, <String>['init:1', 'build:1', 'update:1->2', 'build:2']);

    host.dispose();
    expect(log.last, 'dispose:2');
  });

  test('all hook cleanups run when one cleanup throws', () {
    final host = TestElementHost();
    final log = <String>[];

    host.mount(
      HookBuilder(
        builder: (context) {
          useOnDispose(() {
            log.add('first');
          });
          useOnDispose(() {
            log.add('second');
            throw StateError('cleanup failed');
          });
          return const Container();
        },
      ),
    );

    expect(host.dispose, throwsA(isA<StateError>()));
    expect(log, <String>['second', 'first']);
  });

  test('useReducer retains its store and uses the latest reducer', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var multiplier = 1;
    late Store<int, int> store;
    Store<int, int>? firstStore;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        final currentMultiplier = multiplier;
        store = useReducer<int, int>(
          (state, action) => state + action * currentMultiplier,
          0,
        );
        firstStore ??= store;
        return const Container();
      },
    );

    host.mount(buildRoot());
    store.dispatch(2);
    host.pumpBuild();
    expect(store.value, 2);

    multiplier = 3;
    host.update(buildRoot());
    store.dispatch(2);
    host.pumpBuild();

    expect(store, same(firstStore));
    expect(store.value, 8);
  });

  test('useValueChanged accumulates from the previous callback result', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var value = 2;
    late int? result;
    final calls = <(int, int?)>[];

    int accumulate(int oldValue, int? oldResult) {
      calls.add((oldValue, oldResult));
      return (oldResult ?? 0) + oldValue;
    }

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        result = useValueChanged<int, int>(value, accumulate);
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(result, isNull);
    expect(calls, isEmpty);

    value = 3;
    host.update(buildRoot());
    expect(result, 2);
    expect(calls, <(int, int?)>[(2, null)]);

    value = 5;
    host.update(buildRoot());
    expect(result, 5);
    expect(calls, <(int, int?)>[(2, null), (3, 2)]);

    host.update(buildRoot());
    expect(result, 5);
    expect(calls, hasLength(2));
  });

  test('usePrevious reports null, updates, and repeated equal values', () {
    final host = TestElementHost();
    addTearDown(host.dispose);
    var value = 1;
    late int? previous;

    Widget buildRoot() => HookBuilder(
      builder: (context) {
        previous = usePrevious<int>(value);
        return const Container();
      },
    );

    host.mount(buildRoot());
    expect(previous, isNull);

    value = 2;
    host.update(buildRoot());
    expect(previous, 1);

    host.update(buildRoot());
    expect(previous, 2);
  });

  test('useIsMounted returns one stable lifecycle callback', () {
    final host = TestElementHost();
    late bool Function() isMounted;
    bool Function()? firstCallback;

    host.mount(
      HookBuilder(
        builder: (context) {
          isMounted = useIsMounted();
          firstCallback ??= isMounted;
          return const Container();
        },
      ),
    );

    expect(isMounted(), isTrue);
    host.update(
      HookBuilder(
        builder: (context) {
          isMounted = useIsMounted();
          return const Container();
        },
      ),
    );
    expect(isMounted, same(firstCallback));

    host.dispose();
    expect(isMounted(), isFalse);
  });
}

final Matcher _effectRebuildError = isA<StateError>().having(
  (error) => error.message,
  'message',
  'HookState.setState() cannot request a rebuild while a useEffect callback '
      'or cleanup is running.',
);

final class _ComposedStateHook extends Hook<ValueNotifier<int>> {
  const _ComposedStateHook(this.initialValue);

  final int initialValue;

  @override
  _ComposedStateHookState createState() => _ComposedStateHookState();
}

final class _ComposedStateHookState
    extends HookState<ValueNotifier<int>, _ComposedStateHook> {
  @override
  ValueNotifier<int> build(BuildContext context) =>
      useState<int>(hook.initialValue);
}

final class _ProbeHook extends Hook<int> {
  const _ProbeHook(this.value, this.log);

  final int value;
  final List<String> log;

  @override
  _ProbeHookState createState() => _ProbeHookState();
}

final class _ProbeHookState extends HookState<int, _ProbeHook> {
  @override
  void initHook() => hook.log.add('init:${hook.value}');

  @override
  void didUpdateHook(_ProbeHook oldHook) =>
      hook.log.add('update:${oldHook.value}->${hook.value}');

  @override
  int build(BuildContext context) {
    hook.log.add('build:${hook.value}');
    return hook.value;
  }

  @override
  void dispose() {
    try {
      hook.log.add('dispose:${hook.value}');
    } finally {
      super.dispose();
    }
  }
}

final class _ReassembleProbeHook extends Hook<Object?> {
  const _ReassembleProbeHook(this.label, this.log, {this.shouldThrow = false});

  final String label;
  final List<String> log;
  final bool shouldThrow;

  @override
  _ReassembleProbeHookState createState() => _ReassembleProbeHookState();
}

final class _ReassembleProbeHookState
    extends HookState<Object?, _ReassembleProbeHook> {
  @override
  void reassemble() {
    hook.log.add('reassemble:${hook.label}');
    if (hook.shouldThrow) {
      throw StateError('reassemble failed');
    }
  }

  @override
  Object? build(BuildContext context) => null;
}

final class _InvalidUpdateHook extends Hook<Object?> {
  const _InvalidUpdateHook(this.version);

  final int version;

  @override
  _InvalidUpdateHookState createState() => _InvalidUpdateHookState();
}

final class _InvalidUpdateHookState
    extends HookState<Object?, _InvalidUpdateHook> {
  @override
  void didUpdateHook(_InvalidUpdateHook oldHook) {
    if (oldHook.version != hook.version) {
      useState<int>(0);
    }
  }

  @override
  Object? build(BuildContext context) => null;
}

final class _InvalidContextUpdateHook extends Hook<Object?> {
  const _InvalidContextUpdateHook(this.version);

  final int version;

  @override
  _InvalidContextUpdateHookState createState() =>
      _InvalidContextUpdateHookState();
}

final class _InvalidContextUpdateHookState
    extends HookState<Object?, _InvalidContextUpdateHook> {
  @override
  void didUpdateHook(_InvalidContextUpdateHook oldHook) {
    if (oldHook.version != hook.version) {
      useContext();
    }
  }

  @override
  Object? build(BuildContext context) => null;
}
