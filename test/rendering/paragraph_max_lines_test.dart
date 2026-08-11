import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart' show RenderParagraph, Renderer;
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';
import '../helpers/test_element_host.dart';

void main() {
  group('positive-or-null maxLines', () {
    test('constructors accept null, 1, and greater values', () {
      expect(() => const Text('a'), returnsNormally);
      expect(() => const Text('a', maxLines: 1), returnsNormally);
      expect(() => const Text('a', maxLines: 3), returnsNormally);
      expect(
        () => const Text.rich(TextSpan(text: 'a'), maxLines: 2),
        returnsNormally,
      );
      expect(
        () => const RichText(text: TextSpan(text: 'a'), maxLines: 2),
        returnsNormally,
      );
      expect(
        () => RenderParagraph(text: const TextSpan(text: 'a')),
        returnsNormally,
      );
      expect(
        () => RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 1),
        returnsNormally,
      );
      expect(
        () => RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 4),
        returnsNormally,
      );
    });

    test('assertions reject zero and negative widget maxLines', () {
      expect(() => Text('a', maxLines: 0), throwsA(isA<AssertionError>()));
      expect(() => Text('a', maxLines: -1), throwsA(isA<AssertionError>()));
      expect(
        () => Text.rich(const TextSpan(text: 'a'), maxLines: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Text.rich(const TextSpan(text: 'a'), maxLines: -2),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RichText(text: const TextSpan(text: 'a'), maxLines: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => RichText(text: const TextSpan(text: 'a'), maxLines: -3),
        throwsA(isA<AssertionError>()),
      );
    });

    test('RenderParagraph constructor and setter reject non-positive', () {
      expect(
        () => RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 0),
        throwsArgumentError,
      );
      expect(
        () => RenderParagraph(text: const TextSpan(text: 'a'), maxLines: -1),
        throwsArgumentError,
      );

      final paragraph = RenderParagraph(
        text: const TextSpan(text: 'a'),
        maxLines: 2,
      );
      expect(() => paragraph.maxLines = 0, throwsArgumentError);
      expect(paragraph.maxLines, 2);
      expect(() => paragraph.maxLines = -5, throwsArgumentError);
      expect(paragraph.maxLines, 2);
    });

    test('setter validates before equality and preserves clean state', () {
      final paragraph = RenderParagraph(
        text: const TextSpan(text: 'hello world'),
        maxLines: 1,
      )..layout(const BoxConstraints.tight(width: 5, height: 3));
      final beforeLayout = paragraph.debugTextLayout;
      expect(beforeLayout, isNotNull);
      expect(paragraph.debugNeedsLayout, isFalse);

      expect(() => paragraph.maxLines = 0, throwsArgumentError);
      expect(paragraph.maxLines, 1);
      expect(identical(paragraph.debugTextLayout, beforeLayout), isTrue);
      expect(paragraph.debugNeedsLayout, isFalse);

      // Equal valid assignment is a no-op.
      paragraph.maxLines = 1;
      expect(paragraph.debugNeedsLayout, isFalse);

      paragraph.maxLines = 2;
      expect(paragraph.maxLines, 2);
      expect(paragraph.debugNeedsLayout, isTrue);
    });

    test('null, 1, and positive limits drive size height', () {
      const text = TextSpan(text: 'one\ntwo\nthree');
      final unlimited = RenderParagraph(text: text)
        ..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));
      expect(unlimited.size.height, 3);

      final one = RenderParagraph(text: text, maxLines: 1)
        ..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));
      expect(one.size.height, 1);

      final two = RenderParagraph(text: text, maxLines: 2)
        ..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));
      expect(two.size.height, 2);

      final above = RenderParagraph(text: text, maxLines: 10)
        ..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));
      expect(above.size.height, 3);
    });

    test('soft wrap with maxLines limits laid-out height', () {
      // Long single hard line soft-wraps into multiple visual lines.
      final unlimited = RenderParagraph(
        text: const TextSpan(text: 'abcdefghijabcdefghij'),
      )..layout(const BoxConstraints(maxWidth: 10, maxHeight: 10));
      expect(unlimited.size.height, greaterThan(1));

      final limited = RenderParagraph(
        text: const TextSpan(text: 'abcdefghijabcdefghij'),
        maxLines: 1,
      )..layout(const BoxConstraints(maxWidth: 10, maxHeight: 10));
      expect(limited.size.height, 1);
    });

    test('ellipsis overflow with maxLines remains valid configuration', () {
      final paragraph = RenderParagraph(
        text: const TextSpan(text: 'one\ntwo\nthree\nfour'),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      )..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));
      expect(paragraph.maxLines, 2);
      expect(paragraph.size.height, 2);
      expect(paragraph.overflow, TextOverflow.ellipsis);
    });

    test('ellipsis paints the final visible cells', () {
      final capture = BufferCapture(width: 8, height: 1);
      addTearDown(capture.dispose);

      final rendered = capture.capture(
        const SizedBox(
          width: 8,
          height: 1,
          child: Text(
            'abcdefghij',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

      expect(rendered.getRegion(0, 0, 8, 1), 'abcde...');
    });

    test(
      'selection is forwarded on the same maxLines-clipped paint command',
      () {
        const selection = TextHighlight(
          start: 0,
          end: 3,
          foregroundColor: Color.black,
          backgroundColor: Color.blue,
        );
        final paragraph = RenderParagraph(
          text: const TextSpan(text: 'one\ntwo\nthree\nfour'),
          maxLines: 2,
          selection: selection,
        )..layout(const BoxConstraints(maxWidth: 20, maxHeight: 10));

        expect(paragraph.size.height, 2);
        expect(paragraph.selection, selection);

        final renderer = Renderer.create(20, 4, testing: true);
        addTearDown(renderer.dispose);
        final buffer = renderer.nextBuffer;
        final canvas = createTuiCanvas();
        paragraph.paint(PaintingContext(canvas), Offset.zero);
        commitTuiCanvas(buffer, canvas);

        final cells = buffer.getDirectAccess();
        expect(cells.getChar(0, 0), 'o');
        expect(cells.getBackground(0, 0), Color.blue);
        expect(cells.getForeground(0, 0), Color.black);
        expect(cells.getChar(0, 1), 't');
        expect(cells.getChar(0, 2), ' ');
        expect(paragraph.debugTextLayout!.lineCount, greaterThan(2));
      },
    );

    test('widget updates apply valid maxLines to the same render object', () {
      final host = TestElementHost()..mount(const Text('a\nb\nc', maxLines: 2));
      final first = host.renderObject! as RenderParagraph;
      expect(first.maxLines, 2);

      host.root!.update(const Text('a\nb\nc', maxLines: 1));
      host.owner.buildScope();
      final second = host.renderObject! as RenderParagraph;
      expect(identical(first, second), isTrue);
      expect(second.maxLines, 1);

      host.root!.update(const Text('a\nb\nc'));
      host.owner.buildScope();
      expect((host.renderObject! as RenderParagraph).maxLines, isNull);

      host.dispose();
    });

    test(
      'invalid const maxLines fails constant evaluation',
      () async {
        final temp = await Directory.systemTemp.createTemp(
          'noir-p9-025-const-',
        );
        addTearDown(() => temp.delete(recursive: true));
        final packageConfig =
            '${Directory.current.path}/.dart_tool/package_config.json';
        final cases = <String, String>{
          'text-zero': "const value = Text('x', maxLines: 0);",
          'text-neg': "const value = Text('x', maxLines: -1);",
          'rich-zero':
              "const value = Text.rich(TextSpan(text: 'x'), maxLines: 0);",
          'richtext-zero':
              "const value = RichText(text: TextSpan(text: 'x'), maxLines: 0);",
        };

        for (final entry in cases.entries) {
          final file = File('${temp.path}/${entry.key}.dart');
          await file.writeAsString('''
import 'package:noir/noir.dart';
${entry.value}
void main() { print(value); }
''');
          final result = await Process.run(Platform.resolvedExecutable, [
            '--packages=$packageConfig',
            file.path,
          ]);
          expect(
            result.exitCode,
            isNot(0),
            reason: '${entry.key} unexpectedly compiled:\n${result.stdout}',
          );
          expect(
            '${result.stdout}\n${result.stderr}'.toLowerCase(),
            anyOf(contains('constant'), contains('assert')),
          );
        }
      },
      tags: const ['process-spawning'],
    );
  });
}
