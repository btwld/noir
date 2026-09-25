import 'package:muse_noir/muse_noir.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'value adapter forwards current values and detaches deterministically',
    () {
      final source = ValueNotifier<int>(1);
      final adapter = MuseValueListenable<int>(source);
      var calls = 0;
      void listener() => calls += 1;
      adapter.addListener(listener);
      adapter.addListener(listener);
      source.value = 2;
      expect(adapter.value, 2);
      expect(calls, 1);
      adapter.removeListener(listener);
      source.value = 3;
      expect(calls, 1);
      adapter.dispose();
      adapter.dispose();
      expect(source.value, 3);
      expect(() => adapter.value, throwsStateError);
      source.dispose();
    },
  );

  test(
    'notifier adapter derives live values and never disposes its source',
    () {
      final source = _Counter();
      final adapter = MuseNotifierListenable<_Counter, String>(
        source,
        (counter) => 'value:${counter.value}',
      );
      var calls = 0;
      void listener() => calls += 1;
      adapter.addListener(listener);
      source.increment();
      expect(adapter.value, 'value:1');
      expect(calls, 1);
      adapter.dispose();
      source.increment();
      expect(calls, 1);
      expect(source.value, 2);
      source.dispose();
    },
  );
}

final class _Counter extends ChangeNotifier {
  int value = 0;

  void increment() {
    value += 1;
    notifyListeners();
  }
}
