// ignore_for_file: cascade_invocations

import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  group('ValueNotifier', () {
    test('notifies only when equality says the value changed', () {
      final notifier = ValueNotifier<int>(1);
      final values = <int>[];
      notifier.addListener(() => values.add(notifier.value));

      notifier.value = 1;
      notifier.value = 2;
      notifier.value = 2;
      notifier.value = 3;

      expect(values, [2, 3]);
    });
  });
}
