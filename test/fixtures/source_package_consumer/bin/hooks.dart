import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';

final class HooksConsumer extends HookWidget {
  const HooksConsumer({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useState(0);
    final label = useMemoized(() => 'count');
    return Text('$label: ${count.value}');
  }
}

void main() {
  const HooksConsumer();
}
