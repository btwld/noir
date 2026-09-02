/// Minimal Noir hello-world: a [StatelessWidget] root rendered through
/// [runTuiApp], demonstrating [Container], [Row], [Column], and [Expanded],
/// framed by the shared demo chrome in `src/shared/demo_scaffold.dart`.
library;

// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';

import 'src/shared/demo_scaffold.dart';

void main() => runTuiApp(const HelloApp());

class HelloApp extends StatelessWidget {
  const HelloApp({super.key});

  @override
  Widget build(BuildContext context) => DemoScaffold(
    title: 'Noir',
    hint: 'Flutter-like widgets for terminal apps.',
    child: Column(
      spacing: 1,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          spacing: 1,
          children: [
            Expanded(
              child: Panel(
                title: 'Layout',
                child: Text('Row, Column, Container, Expanded'),
              ),
            ),
            Expanded(
              child: Panel(
                title: 'State',
                child: Text('StatelessWidget and StatefulWidget'),
              ),
            ),
          ],
        ),
        Text(
          'Press Ctrl+C to exit.',
          style: TextStyle(color: Theme.of(context).textMuted),
        ),
      ],
    ),
  );
}
