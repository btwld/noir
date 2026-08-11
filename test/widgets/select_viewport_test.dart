import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';

List<SelectOption<int>> _numbers(int n) => List<SelectOption<int>>.generate(
  n,
  (i) => SelectOption(name: 'Item ${i + 1}', value: i),
);

void main() {
  group('Select viewport / paging from laid-out size', () {
    test('PageDown over a 100-item list with viewportExtent=5 moves '
        'the highlight by 5', () async {
      final changes = <int>[];
      final driver = KeyDriver(
        Select<int>(
          autofocus: true,
          height: 5,
          options: _numbers(100),
          onChanged: (i, _) => changes.add(i),
        ),
        paintFrames: true,
      );
      await driver.ready();

      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      expect(changes.last, 5);
      await driver.sendLogicalKey(LogicalKeyboardKey.pageDown);
      expect(changes.last, 10);
      driver.dispose();
    });

    test('clicking a row computes the right item from the paint-time '
        'viewport top', () async {
      final selects = <int>[];
      final driver = KeyDriver(
        Select<int>(
          // No autofocus so the initial state doesn't shuffle.
          height: 4,
          options: _numbers(20),
          onSelect: (i, _) => selects.add(i),
        ),
        paintFrames: true,
      );
      await driver.ready();

      // Click on the third painted row → item 2 (zero-based).
      await driver.sendMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 2,
        ),
      );
      expect(selects, equals([2]));
      driver.dispose();
    });

    test(
      'clicking an offset Select uses hit-test local row coordinates',
      () async {
        final selects = <int>[];
        final driver = KeyDriver(
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Select<int>(
              height: 4,
              options: _numbers(20),
              onSelect: (i, _) => selects.add(i),
            ),
          ),
          paintFrames: true,
        );
        await driver.ready();

        await driver.sendMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 0,
            y: 7,
          ),
        );
        expect(selects, equals([2]));
        driver.dispose();
      },
    );
  });
}
