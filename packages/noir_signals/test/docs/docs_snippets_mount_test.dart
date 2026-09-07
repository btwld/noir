import 'dart:async';

import 'package:noir/noir.dart';
import 'package:noir_signals/noir_signals.dart';
import 'package:test/test.dart';

import '../helpers/noir_test_helpers.dart';

// These widgets copy published documentation snippets, including their
// block-bodied build methods.
// ignore_for_file: prefer_expression_function_bodies

class PollingBadge extends HookWidget {
  const PollingBadge({required this.interval, super.key});

  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final ticks = useState<int>(0);

    useEffect(() {
      final timer = Timer.periodic(interval, (_) {
        ticks.value++;
      });
      return timer.cancel;
    }, <Object?>[interval]);

    return Row(
      spacing: 1,
      children: [
        const Badge(label: 'POLLING', variant: BadgeVariant.info),
        Text('${ticks.value} checks'),
      ],
    );
  }
}

void main() {
  late BufferCapture capture;

  setUp(() => capture = BufferCapture(width: 40, height: 6));
  tearDown(() => capture.dispose());

  test('PollingBadge paints its status', () {
    expect(
      capture
          .capture(const PollingBadge(interval: Duration(hours: 1)))
          .toText(),
      contains('POLLING'),
    );
  });
}
