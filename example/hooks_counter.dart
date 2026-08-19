import 'dart:async';

import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';

void main() => runTuiApp(const CounterApp());

class CounterApp extends HookWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState<int>(0);

    useEffect(() {
      final timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => count.value++,
      );
      return timer.cancel;
    }, const <Object?>[]);

    return Text('Ticks: ${count.value}');
  }
}
