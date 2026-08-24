import 'dart:io';

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import 'golden_testing.dart';

void main() {
  group('GoldenTester cleanup behavior', () {
    final failureDir = Directory('test/failures');
    final goldenDir = Directory('test/goldens');
    final generatedNames = <String>[
      'visual_default_visual_golden',
      'visual_multi_visual_golden',
    ];

    setUp(() async {
      if (failureDir.existsSync()) {
        await failureDir.delete(recursive: true);
      }
      await _deleteGeneratedGoldens(goldenDir, generatedNames);
    });

    tearDown(() async {
      if (failureDir.existsSync()) {
        await failureDir.delete(recursive: true);
      }
      await _deleteGeneratedGoldens(goldenDir, generatedNames);
    });

    test(
      'passing golden buffer comparisons do not create failure artifacts',
      () async {
        final tester = GoldenTester();

        try {
          final widget = Container(
            color: Color.black,
            child: Row(
              children: const [Text('Left'), Text('Middle'), Text('Right')],
            ),
          );

          await tester.expectGoldenBuffer(widget, 'row_three_labels');

          expect(failureDir.existsSync(), isFalse);
        } finally {
          tester.dispose();
        }
      },
    );

    test('cleanFailures removes saved failure artifacts', () async {
      final tester = GoldenTester();

      try {
        await failureDir.create(recursive: true);
        await File('test/failures/sample.txt').writeAsString('artifact');

        await tester.cleanFailures();

        expect(failureDir.existsSync(), isFalse);
      } finally {
        tester.dispose();
      }
    });

    test('visual goldens default to buffer, style, and cursor files', () async {
      final tester = GoldenTester(width: 20, height: 4);
      const testName = 'visual_default_visual_golden';

      try {
        await tester.expectGolden(
          const Text('Styled', style: TextStyle(color: Color.green)),
          testName,
          updateGoldens: true,
        );

        expect(
          _goldenFile(goldenDir, testName, 'buffer.txt').existsSync(),
          isTrue,
        );
        expect(
          _goldenFile(goldenDir, testName, 'styles.txt').existsSync(),
          isTrue,
        );
        expect(
          await _goldenFile(goldenDir, testName, 'styles.txt').readAsString(),
          contains(RegExp(r'\* \d+')),
        );
        expect(
          _goldenFile(goldenDir, testName, 'cursor.txt').existsSync(),
          isTrue,
        );
      } finally {
        tester.dispose();
      }
    });

    test(
      'multi visual goldens also default to style and cursor sidecars',
      () async {
        final tester = GoldenTester(width: 20, height: 4);
        const suiteName = 'visual_multi_visual_golden';

        try {
          await tester.expectGoldenMulti(
            const <String, Widget>{
              'plain': Text('Plain'),
              'styled': Text('Styled', style: TextStyle(color: Color.yellow)),
            },
            suiteName,
            updateGoldens: true,
          );

          expect(
            _goldenFile(goldenDir, suiteName, 'buffer.txt').existsSync(),
            isTrue,
          );
          expect(
            _goldenFile(goldenDir, suiteName, 'styles.txt').existsSync(),
            isTrue,
          );
          expect(
            _goldenFile(goldenDir, suiteName, 'cursor.txt').existsSync(),
            isTrue,
          );
        } finally {
          tester.dispose();
        }
      },
    );
  });
}

File _goldenFile(Directory goldenDir, String name, String extension) =>
    File('${goldenDir.path}/$name.$extension');

Future<void> _deleteGeneratedGoldens(
  Directory goldenDir,
  Iterable<String> names,
) async {
  for (final name in names) {
    if (!goldenDir.existsSync()) continue;
    await for (final entry in goldenDir.list()) {
      if (entry is File && entry.uri.pathSegments.last.startsWith('$name.')) {
        await entry.delete();
      }
    }
  }
}
