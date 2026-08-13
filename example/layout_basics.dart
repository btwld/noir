// ignore_for_file: cascade_invocations
import 'dart:async';
import 'dart:io';

import 'package:noir/noir.dart';

Future<void> main() async {
  final app = runTuiApp(const LayoutBasics());

  // Enable keyboard so we can exit (q or Ctrl+C)
  app.enableKittyKeyboard();

  final exitCompleter = Completer<void>();
  app.onKey((event) {
    if (event.isPress &&
        (event.character == 'q' ||
            (event.logicalKey == LogicalKeyboardKey.keyC &&
                event.isControlPressed))) {
      event.consume();
      if (!exitCompleter.isCompleted) exitCompleter.complete();
    }
  });

  await Future.any([exitCompleter.future, ProcessSignal.sigint.watch().first]);

  app.dispose();
}

/// A compact demo showcasing core layout behaviors:
/// - Row/Column structure
/// - MainAxisAlignment variants (no stretch)
/// - Flex distribution with Expanded/Flexible
class LayoutBasics extends StatelessWidget {
  const LayoutBasics({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: Color.rgb(0.05, 0.05, 0.12),
    padding: const EdgeInsets.all(1),
    child: Column(
      children: const [
        _Section(title: 'MainAxis: center'),
        _MainAxisCenterRow(),
        SizedBox(height: 1),
        _Section(title: 'MainAxis: spaceBetween'),
        _MainAxisSpaceBetweenRow(),
        SizedBox(height: 1),
        _Section(title: 'Flex distribution'),
        _FlexRow(),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    height: 2,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 1),
    color: Color.rgb(0.25, 0.35, 0.6),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
  );
}

class _Block extends StatelessWidget {
  const _Block({
    required this.label,
    required this.color,
    this.width,
    this.height,
  });
  final String label;
  final Color color;
  final int? width;
  final int? height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    color: color,
    child: Text(label, style: const TextStyle(color: Color.black)),
  );
}

class _MainAxisCenterRow extends StatelessWidget {
  const _MainAxisCenterRow();

  @override
  Widget build(BuildContext context) => Container(
    height: 6, // account for padding + border + content
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.3))),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _Block(label: 'A', color: Color(0.3, 0.6, 0.9), width: 5, height: 2),
        SizedBox(width: 1),
        _Block(label: 'B', color: Color(0.3, 0.9, 0.5), width: 5, height: 2),
        SizedBox(width: 1),
        _Block(label: 'C', color: Color(0.9, 0.6, 0.3), width: 5, height: 2),
      ],
    ),
  );
}

class _MainAxisSpaceBetweenRow extends StatelessWidget {
  const _MainAxisSpaceBetweenRow();

  @override
  Widget build(BuildContext context) => Container(
    height: 6, // account for padding + border + content
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.3))),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: const [
        _Block(label: 'A', color: Color(0.8, 0.3, 0.3), width: 5, height: 2),
        _Block(label: 'B', color: Color(0.2, 0.8, 0.8), width: 5, height: 2),
        _Block(label: 'C', color: Color(0.8, 0.8, 0.2), width: 5, height: 2),
      ],
    ),
  );
}

class _FlexRow extends StatelessWidget {
  const _FlexRow();

  @override
  Widget build(BuildContext context) => Container(
    height: 7, // account for 3-content + padding + border
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: Color(1, 1, 1, 0.3))),
    child: Row(
      children: const [
        Expanded(
          child: _Block(
            label: 'Flex 1',
            color: Color(0.3, 0.7, 0.9),
            height: 3,
          ),
        ),
        SizedBox(width: 1),
        Expanded(
          flex: 2,
          child: _Block(
            label: 'Flex 2',
            color: Color(0.9, 0.6, 0.3),
            height: 3,
          ),
        ),
        SizedBox(width: 1),
        Flexible(
          child: _Block(label: 'Loose', color: Color(0.6, 0.3, 0.9), height: 3),
        ),
      ],
    ),
  );
}
