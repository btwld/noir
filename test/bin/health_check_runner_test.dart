import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../../bin/health_check.dart' as health_check;

void main() {
  test(
    'cleanup failure is reported after every renderer is released',
    () async {
      var creationCount = 0;
      var disposalAttemptCount = 0;
      final output = <String>[];
      final runner = health_check.HealthCheckRunner(
        createRenderer: (width, height) {
          creationCount++;
          return Renderer.create(width, height, testing: true);
        },
        disposeRenderer: (renderer) {
          disposalAttemptCount++;
          renderer.dispose();
          throw StateError('forced cleanup failure');
        },
        emit: output.add,
      );

      final result = await runner.run();
      final combinedOutput = output.join('\n');

      expect(result, 1);
      expect(creationCount, greaterThan(0));
      expect(disposalAttemptCount, creationCount);
      expect(combinedOutput, contains('forced cleanup failure'));
      expect(combinedOutput, isNot(contains('ALL CHECKS PASSED')));
    },
  );
}
