import 'package:noir_hooks/noir_hooks.dart';
import 'package:test/test.dart';

void main() {
  test('hooks reject calls outside a hook-enabled build', () {
    expect(() => useState<int>(0), throwsA(isA<StateError>()));
  });

  test('AsyncSnapshot retains payload while changing connection state', () {
    const snapshot = AsyncSnapshot<int>.withData(ConnectionState.active, 7);

    final completed = snapshot.inState(ConnectionState.done);

    expect(completed.connectionState, ConnectionState.done);
    expect(completed.requireData, 7);
    expect(completed.hasError, isFalse);
  });

  test('ObjectRef mutates without replacing its identity', () {
    final reference = ObjectRef<int>(1);

    reference.value = 2;

    expect(reference.value, 2);
  });
}
