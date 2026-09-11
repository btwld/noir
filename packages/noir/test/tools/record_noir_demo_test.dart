import 'dart:convert';
import 'dart:io';

import 'package:noir/noir.dart' show Attr;
import 'package:test/test.dart';

import '../../tool/driver/noir_driver.dart';
import '../../tool/record_noir_demo.dart';

void main() {
  group('RecordingRecipe', () {
    test('parses and orders a bounded recording recipe', () {
      final recipe = RecordingRecipe.fromJson({
        'version': 1,
        'entrypoint': 'example/counter.dart',
        'output': '.context/demos/counter.cast',
        'title': 'Noir counter',
        'width': 80,
        'height': 24,
        'durationMs': 2400,
        'fps': 12,
        'actions': [
          {'atMs': 1500, 'key': 'down'},
          {'atMs': 700, 'key': 'up'},
        ],
      });

      expect(recipe.entrypoint, 'example/counter.dart');
      expect(recipe.output, '.context/demos/counter.cast');
      expect(recipe.width, 80);
      expect(recipe.height, 24);
      expect(recipe.duration, const Duration(milliseconds: 2400));
      expect(recipe.fps, 12);
      expect(
        recipe.actions.map((action) => action.at),
        orderedEquals(const [
          Duration(milliseconds: 700),
          Duration(milliseconds: 1500),
        ]),
      );
    });

    test('rejects an action beyond the recording duration', () {
      expect(
        () => RecordingRecipe.fromJson({
          'version': 1,
          'entrypoint': 'example/counter.dart',
          'output': '.context/demos/counter.cast',
          'title': 'Noir counter',
          'width': 80,
          'height': 24,
          'durationMs': 1000,
          'fps': 12,
          'actions': [
            {'atMs': 1001, 'key': 'up'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('reserves Ctrl+C for recorder cleanup regardless of casing', () {
      expect(
        () => RecordingRecipe.fromJson({
          'version': 1,
          'entrypoint': 'example/counter.dart',
          'output': '.context/demos/counter.cast',
          'title': 'Noir counter',
          'width': 80,
          'height': 24,
          'durationMs': 1000,
          'fps': 12,
          'actions': [
            {'atMs': 500, 'key': 'CTRL-C'},
          ],
        }),
        throwsFormatException,
      );
    });

    test('tracked showcase recipes have intentional destinations', () {
      const expected = <String>{
        'chat-loading.json',
        'components-spinner.json',
        'counter.json',
        'like-reactor.json',
        'pub-search.json',
        'pulse-animation.json',
      };
      // `doc_frames.json` is the static-frame manifest for
      // `scripts/capture_doc_frames.dart`, not an asciicast recipe. Its own
      // architecture test covers it.
      const frameManifest = 'doc_frames.json';
      final files = Directory('tool/recordings')
          .listSync()
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.json') &&
                file.uri.pathSegments.last != frameManifest,
          )
          .toList(growable: false);

      expect(
        File('tool/recordings/$frameManifest').existsSync(),
        isTrue,
        reason: 'the frame manifest must stay beside the recording recipes',
      );
      expect(files.map((file) => file.uri.pathSegments.last), expected);
      for (final file in files) {
        final recipe = RecordingRecipe.fromJson(
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
        );
        expect(File(recipe.entrypoint).existsSync(), isTrue, reason: file.path);
        if (file.uri.pathSegments.last == 'counter.json') {
          expect(
            recipe.output,
            '../../website/public/demos/counter.cast',
            reason: '${file.path} owns the published website recording',
          );
        } else {
          expect(
            recipe.output,
            startsWith('.context/demos/'),
            reason: '${file.path} must remain a local review artifact',
          );
        }
      }
    });
  });

  test('asciicast encoder preserves styled frames and skips duplicates', () {
    final frame = _frame('N', visibleCursor: false);
    final encoder =
        AsciicastEncoder(
            width: 2,
            height: 1,
            title: 'Noir demo',
            command: 'dart run example/demo.dart',
            duration: const Duration(seconds: 2),
          )
          ..addFrame(Duration.zero, frame)
          ..addFrame(const Duration(milliseconds: 100), frame)
          ..addInput(const Duration(milliseconds: 200), ' ')
          ..addClick(const Duration(milliseconds: 250), const DriverPoint(1, 0))
          ..addFrame(
            const Duration(milliseconds: 300),
            _frame(
              'R',
              visibleCursor: true,
              cursorStyle: 'underline',
              cursorColor: const DriverColor(18, 52, 86, 255),
              cursorBlinking: true,
            ),
          );

    final lines = const LineSplitter().convert(encoder.encode());
    expect(lines, hasLength(6));

    final header = jsonDecode(lines.first) as Map<String, Object?>;
    expect(header['version'], 2);
    expect(header['width'], 2);
    expect(header['height'], 1);
    expect(header['duration'], 2.0);

    final firstFrame = jsonDecode(lines[1]) as List<Object?>;
    expect(firstFrame[0], 0.0);
    expect(firstFrame[1], 'o');
    expect(firstFrame[2], contains('\x1b[2J'));
    expect(firstFrame[2], contains('\x1b[0;1;38;2;255;255;255;48;2;0;0;0m'));
    expect(firstFrame[2], contains('N'));

    final input = jsonDecode(lines[2]) as List<Object?>;
    expect(input, [0.2, 'i', ' ']);

    final click = jsonDecode(lines[3]) as List<Object?>;
    expect(click, [0.25, 'i', '\x1b[<0;2;1M\x1b[<0;2;1m']);

    final changedFrame = jsonDecode(lines[4]) as List<Object?>;
    expect(changedFrame[0], 0.3);
    expect(changedFrame[1], 'o');
    expect(changedFrame[2], contains('R'));
    expect(changedFrame[2], contains('\x1b]12;#123456\x1b\\'));
    expect(changedFrame[2], contains('\x1b[3 q'));
    expect(changedFrame[2], contains('\x1b[?25h'));

    expect(
      jsonDecode(lines[5]),
      [2.0, 'o', '\x1b[0m'],
      reason: 'the final frame must remain visible for the recipe duration',
    );
  });

  test('non-zero app exit prevents a successful recording', () {
    expect(
      () => requireSuccessfulAppExit(7, 'example/demo.dart'),
      throwsA(
        isA<ProcessException>()
            .having((error) => error.errorCode, 'errorCode', 7)
            .having(
              (error) => error.message,
              'message',
              contains('non-zero status'),
            ),
      ),
    );
    expect(
      () => requireSuccessfulAppExit(0, 'example/demo.dart'),
      returnsNormally,
    );
  });

  group('writeRecordingArtifact', () {
    late Directory temporaryDirectory;

    setUp(() {
      temporaryDirectory = Directory.systemTemp.createTempSync(
        'noir_recording_test_',
      );
    });

    tearDown(() {
      temporaryDirectory.deleteSync(recursive: true);
    });

    test('publishes a new output without leaving a sibling behind', () async {
      final output = File('${temporaryDirectory.path}/demo.cast');

      await writeRecordingArtifact(output, 'new recording', force: false);

      expect(output.readAsStringSync(), 'new recording');
      expect(
        temporaryDirectory.listSync().where(
          (entry) => entry.path.contains('.partial.'),
        ),
        isEmpty,
      );
    });

    test('does not replace an output that appears without force', () async {
      final output = File('${temporaryDirectory.path}/demo.cast')
        ..writeAsStringSync('existing');
      final conventionalPartial = File('${output.path}.partial')
        ..writeAsStringSync('keep me');

      await expectLater(
        writeRecordingArtifact(output, 'replacement', force: false),
        throwsA(isA<FileSystemException>()),
      );

      expect(output.readAsStringSync(), 'existing');
      expect(conventionalPartial.readAsStringSync(), 'keep me');
      expect(
        temporaryDirectory.listSync().where(
          (entry) => entry.path.contains('.partial.'),
        ),
        isEmpty,
      );
    });

    test(
      'force publishes the complete sibling over an existing output',
      () async {
        final output = File('${temporaryDirectory.path}/demo.cast')
          ..writeAsStringSync('existing');
        final conventionalPartial = File('${output.path}.partial')
          ..writeAsStringSync('keep me');

        await writeRecordingArtifact(output, 'replacement', force: true);

        expect(output.readAsStringSync(), 'replacement');
        expect(conventionalPartial.readAsStringSync(), 'keep me');
        expect(
          temporaryDirectory.listSync().where(
            (entry) => entry.path.contains('.partial.'),
          ),
          isEmpty,
        );
      },
    );

    test('force restores the existing output when publication fails', () async {
      final output = File('${temporaryDirectory.path}/demo.cast')
        ..writeAsStringSync('existing');
      var renameCount = 0;

      await expectLater(
        writeRecordingArtifact(
          output,
          'replacement',
          force: true,
          renameFile: (source, destination) async {
            renameCount++;
            if (renameCount == 2) {
              throw FileSystemException(
                'simulated publish failure',
                destination,
              );
            }
            return source.rename(destination);
          },
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(renameCount, 3);
      expect(output.readAsStringSync(), 'existing');
      expect(
        temporaryDirectory.listSync().where(
          (entry) =>
              entry.path.contains('.partial.') ||
              entry.path.contains('.backup.'),
        ),
        isEmpty,
      );
    });
  });
}

DriverFrame _frame(
  String firstCharacter, {
  required bool visibleCursor,
  String cursorStyle = 'block',
  DriverColor cursorColor = const DriverColor(255, 255, 255, 255),
  bool cursorBlinking = false,
}) => DriverFrame(
  width: 2,
  height: 1,
  lines: [firstCharacter],
  rows: [
    [
      DriverCell(
        char: firstCharacter,
        foreground: const DriverColor(255, 255, 255, 255),
        background: const DriverColor(0, 0, 0, 255),
        attributes: Attr.bold,
      ),
      const DriverCell(
        char: ' ',
        foreground: DriverColor(255, 255, 255, 255),
        background: DriverColor(0, 0, 0, 255),
        attributes: 0,
      ),
    ],
  ],
  cursor: DriverCursor(
    visible: visibleCursor,
    x: 1,
    y: 0,
    style: cursorStyle,
    color: cursorColor,
    blinking: cursorBlinking,
  ),
);
