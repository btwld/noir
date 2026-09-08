import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

final class HooksConsumer extends SignalWidget {
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
