import 'package:noir/noir.dart';

void main() => runTuiApp(const LayoutBasics());

/// A compact demo showcasing core layout behaviors:
/// - Row/Column structure
/// - MainAxisAlignment variants (no stretch)
/// - Flex distribution with Expanded/Flexible
class LayoutBasics extends StatelessWidget {
  const LayoutBasics({super.key});

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event.isPress && event.character == 'q') {
        TuiApp.exit(context);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Container(
      color: Theme.of(context).surface,
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
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 1,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 1),
      color: theme.selectedBackground,
      child: Text(
        title,
        style: TextStyle(
          color: theme.selectedForeground,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
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
    height: 5, // retain breathing room around the two-row blocks
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).border),
    ),
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
    height: 5, // retain breathing room around the two-row blocks
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).border),
    ),
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
    height: 6, // retain breathing room around the three-row blocks
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).border),
    ),
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
