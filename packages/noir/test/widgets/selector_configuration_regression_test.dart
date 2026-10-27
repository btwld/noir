import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/key_driver.dart';
import '../helpers/tui_test_app.dart';

void main() {
  for (final tabs in [false, true]) {
    test('reused options reconcile selection (tabs: $tabs)', () async {
      final key = GlobalKey<_OptionsHostState>();
      final selected = <int>[];
      final driver = KeyDriver(
        _OptionsHost(key: key, tabs: tabs, onSelect: selected.add),
      );
      addTearDown(driver.dispose);
      await driver.ready();

      key.currentState!.shrink();
      driver.app.debugFlushFrame();
      await driver.sendLogicalKey(LogicalKeyboardKey.enter);

      expect(selected, [0]);
    });
  }

  test(
    'constrained Select paints and activates the same initial window',
    () async {
      final selected = <int>[];
      final app = createTuiTestApp(
        Select<int>(
          options: List.generate(
            10,
            (i) => SelectOption<int>(name: 'Item $i', value: i),
          ),
          selectedIndex: 7,
          onSelect: (index, _) => selected.add(index),
        ),
        width: 12,
        height: 2,
      );
      addTearDown(app.dispose);
      app.pumpFrame();
      expect(app.captureFrame().toLines(), ['Item 6', 'Item 7']);

      app.binding.inputManager.dispatchMouse(
        MouseEvent(
          type: MouseEventType.down,
          button: MouseButton.left,
          x: 0,
          y: 0,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();
      expect(selected, [6]);
      expect(app.captureFrame().toLines(), ['Item 6', 'Item 7']);

      app.resize(12, 1);
      app.pumpFrame();
      expect(app.captureFrame().toLines(), ['Item 6']);
    },
  );

  test(
    'paint-only navigation keeps painting and pointer mapping in sync',
    () async {
      final selected = <int>[];
      final app = createTuiTestApp(
        Select<int>(
          options: List.generate(
            10,
            (index) => SelectOption<int>(name: 'Item $index', value: index),
          ),
          selectedIndex: 7,
          autofocus: true,
          onSelect: (index, _) => selected.add(index),
        ),
        width: 12,
        height: 2,
      );
      addTearDown(app.dispose);
      app.pumpFrame();
      await Future<void>.delayed(Duration.zero);
      app.pumpFrame();

      for (final target in [
        (key: LogicalKeyboardKey.end, first: 8, second: 9),
        (key: LogicalKeyboardKey.home, first: 0, second: 1),
      ]) {
        app.binding.inputManager.dispatchKey(
          KeyEvent(logicalKey: target.key, keyCode: 0),
        );
        await Future<void>.delayed(Duration.zero);
        app.pumpFrame();
        expect(app.captureFrame().toLines(), [
          'Item ${target.first}',
          'Item ${target.second}',
        ]);

        app.binding.inputManager.dispatchMouse(
          MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 0,
            y: 1,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        app.pumpFrame();
        expect(selected.last, target.second);
      }
    },
  );
}

class _OptionsHost extends StatefulWidget {
  const _OptionsHost({required this.tabs, required this.onSelect, super.key});
  final bool tabs;
  final void Function(int) onSelect;
  @override
  State<_OptionsHost> createState() => _OptionsHostState();
}

class _OptionsHostState extends State<_OptionsHost> {
  final options = List.generate(
    3,
    (i) => SelectOption<int>(name: 'Item $i', value: i),
  );
  void shrink() => setState(() => options.removeRange(1, 3));
  @override
  Widget build(BuildContext context) => widget.tabs
      ? TabSelect<int>(
          options: options,
          selectedIndex: 2,
          autofocus: true,
          onSelect: (index, _) => widget.onSelect(index),
        )
      : Select<int>(
          options: options,
          selectedIndex: 2,
          autofocus: true,
          onSelect: (index, _) => widget.onSelect(index),
        );
}
