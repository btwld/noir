/// Minimal Noir hello-world: a [StatelessWidget] root rendered through
/// [runTuiApp], demonstrating [Container], [Row], [Column], and [Expanded].
library;

// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

void main() {
  runTuiApp(const HelloApp());
}

class HelloApp extends StatelessWidget {
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) => Container(
    color: Color.rgb(0.05, 0.06, 0.1),
    padding: const EdgeInsets.all(2),
    child: Column(
      spacing: 1,
      children: const [
        Text(
          'Noir',
          style: TextStyle(color: Color.yellow, fontWeight: FontWeight.bold),
        ),
        Text('Flutter-like widgets for terminal apps.'),
        SizedBox(height: 1),
        Row(
          spacing: 1,
          children: [
            Expanded(
              child: _Panel(
                title: 'Layout',
                body: 'Row, Column, Container, Expanded',
                color: Color.cyan,
              ),
            ),
            Expanded(
              child: _Panel(
                title: 'State',
                body: 'StatelessWidget and StatefulWidget',
                color: Color.green,
              ),
            ),
          ],
        ),
        Text('Press Ctrl+C to exit.', style: TextStyle(color: Color.lightGray)),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.body, required this.color});

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 5,
    padding: const EdgeInsets.all(1),
    decoration: BoxDecoration(border: Border.all(color: color)),
    child: Column(
      spacing: 1,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        Text(body),
      ],
    ),
  );
}
