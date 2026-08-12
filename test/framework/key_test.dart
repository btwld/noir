import 'package:meta/meta.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('Keys', () {
    test('ObjectKey compares wrapped objects by identity', () {
      final first = _EqualById(1);
      final second = _EqualById(1);

      expect(first, equals(second));
      expect(identical(first, second), isFalse);
      expect(ObjectKey(first), equals(ObjectKey(first)));
      expect(ObjectKey(first), isNot(equals(ObjectKey(second))));
    });

    test('ValueKey compares wrapped objects by value equality', () {
      final first = _EqualById(1);
      final second = _EqualById(1);

      expect(ValueKey(first), equals(ValueKey(second)));
    });
  });
}

@immutable
class _EqualById {
  const _EqualById(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is _EqualById && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
