import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';

final class SignalsConsumer extends SignalWidget {
  const SignalsConsumer({super.key});

  @override
  Widget build(BuildContext context) {
    final count = useSignal(0);
    final doubled = useComputed(() => count.value * 2, keys: <Object?>[count]);
    return SignalValueBuilder<int>(
      signal: doubled,
      builder: (context, value) => Text('$value'),
    );
  }
}

void main() {
  const SignalsConsumer();
}
