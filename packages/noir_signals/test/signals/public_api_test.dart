import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

void main() {
  test('signal hooks reject calls outside a hook-enabled build', () {
    expect(() => useSignal<int>(0), throwsA(isA<StateError>()));
    expect(() => useComputed<int>(() => 0), throwsA(isA<StateError>()));
    expect(() => useSignalValue<int>(signal(0)), throwsA(isA<StateError>()));
    expect(() => useSignalEffect(() {}), throwsA(isA<StateError>()));
  });

  test('the entrypoint re-exports the upstream primitives unchanged', () {
    final count = signal(1);
    addTearDown(count.dispose);
    final doubled = computed(() => count.value * 2);
    addTearDown(doubled.dispose);

    expect(count, isA<Signal<int>>());
    expect(count, isA<ReadonlySignal<int>>());
    expect(doubled, isA<Computed<int>>());
    expect(doubled.value, 2);

    final seen = <int>[];
    final stop = effect(() {
      seen.add(doubled.value);
    });
    addTearDown(stop);

    batch(() {
      count.value = 2;
      count.value = 3;
    });

    expect(seen, <int>[2, 6]);
    expect(untracked(() => count.value), 3);
  });

  test('the hook Effect typedef survives the upstream name collision', () {
    // `signals_core` also declares `Effect`. The hook typedef keeps the name.
    const cleanupOnly = _noEffect;

    expect(cleanupOnly, isA<Effect>());
    expect(cleanupOnly, isA<Dispose? Function()>());
    expect(cleanupOnly(), isNull);
  });

  test('SignalValueBuilder is a HookWidget with a typed builder', () {
    final source = signal(0);
    addTearDown(source.dispose);
    final builder = SignalValueBuilder<int>(
      signal: source,
      builder: (context, value) => Text('$value'),
    );

    expect(builder, isA<HookWidget>());
    expect(builder.signal, same(source));
    expect(builder.builder, isA<SignalValueWidgetBuilder<int>>());
  });
}

Dispose? _noEffect() => null;
