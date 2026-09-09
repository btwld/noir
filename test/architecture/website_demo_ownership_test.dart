import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test(
    'website counter recording is reproducible from the shipped example',
    () {
      final recipe =
          jsonDecode(File('scripts/recordings/counter.json').readAsStringSync())
              as Map<String, Object?>;

      expect(recipe['entrypoint'], 'example/counter.dart');
      expect(recipe['output'], 'website/public/demos/counter.cast');
      expect(recipe['width'], 64);
      expect(recipe['height'], 18);
      expect(recipe['durationMs'], 2800);
    },
  );

  test('website counter proof is a real bounded Noir capture', () {
    final artifact = File('website/public/demos/counter.cast');

    expect(artifact.existsSync(), isTrue);
    final lines = const LineSplitter()
        .convert(artifact.readAsStringSync())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    final header = jsonDecode(lines.first) as Map<String, Object?>;
    final events = [
      for (final line in lines.skip(1)) jsonDecode(line) as List<Object?>,
    ];
    final output = events
        .where((event) => event[1] == 'o')
        .map((event) => event[2]! as String)
        .join();

    expect(header['version'], 2);
    expect(header['width'], 64);
    expect(header['height'], 18);
    expect(header['duration'], 2.8);
    expect(
      events.last,
      [2.8, 'o', '\x1b[0m'],
      reason: 'the player derives its loop boundary from the final event',
    );
    expect(
      header['command'],
      'NoirDriver (NOIR_DRIVE=1): example/counter.dart',
    );
    expect(events.where((event) => event[1] == 'o').length, greaterThan(1));
    expect(output, contains('Noir Counter'));
    expect(output, contains('You have pushed the button'));
    expect(
      output,
      matches(RegExp(r'this many times:[\s\S]*3')),
      reason: 'the published capture must include the pointer interaction',
    );
  });

  test('the recording lives with the program it records', () {
    final examples = File(
      'website/src/content/examples.mdx',
    ).readAsStringSync();
    final homepage = File('website/src/app/page.tsx').readAsStringSync();
    final tutorial = File(
      'website/src/content/docs/getting-started.mdx',
    ).readAsStringSync();
    final player = File(
      'website/src/components/TerminalRecording.tsx',
    ).readAsStringSync();

    expect(examples, contains('<TerminalRecording'));
    expect(examples, contains('example/counter.dart'));
    // The larger repository counter is not the program either page teaches.
    expect(homepage, isNot(contains('<TerminalRecording')));
    expect(tutorial, isNot(contains('<TerminalRecording')));
    expect(player, contains("poster: 'npt:0:00.1'"));
    expect(player, contains('autoplay: false'));
    expect(player, contains('prefers-reduced-motion'));
    expect(player, contains('AsciinemaPlayer.create'));
  });

  test('every published frame is a capture of a shipped checkpoint', () {
    final manifest =
        jsonDecode(
              File('scripts/recordings/doc_frames.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final output = manifest['output']! as String;
    expect(output, 'website/src/generated/terminal-frames.json');

    final scenes = (manifest['scenes']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(scenes, isNotEmpty);

    final captured =
        jsonDecode(File(output).readAsStringSync()) as Map<String, Object?>;
    expect(captured['capturedWith'], contains('NOIR_DRIVE=1'));
    final frames = captured['frames']! as Map<String, Object?>;
    expect(frames.keys, unorderedEquals(scenes.map((s) => s['id'])));

    for (final scene in scenes) {
      final id = scene['id']! as String;
      final entrypoint = scene['entrypoint']! as String;
      final source = File(entrypoint);
      expect(
        source.existsSync(),
        isTrue,
        reason: 'scene $id must capture a file that ships in this repository',
      );

      final frame = frames[id]! as Map<String, Object?>;
      expect(frame['entrypoint'], entrypoint);
      expect(
        frame['sourceSha256'],
        sha256.convert(source.readAsBytesSync()).toString(),
        reason:
            'scene $id is stale. Run `dart run scripts/capture_doc_frames.dart`.',
      );
      expect(frame['lines']! as List<Object?>, isNotEmpty);
    }
  });

  test('every published screenshot names the checkpoint it came from', () {
    // Recapturing text must not silently approve an old JPEG. Its reviewed
    // source, visual capture and image bytes live in a separate manifest.
    const imageRoot = 'packages/noir_signals/doc/images';
    final published = Directory(imageRoot)
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.endsWith('.jpg'))
        .toSet();
    expect(published, isNotEmpty);

    final provenance =
        jsonDecode(File('$imageRoot/provenance.json').readAsStringSync())
            as Map<String, dynamic>;
    final frames =
        (jsonDecode(
                  File(
                    'website/src/generated/terminal-frames.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>)['frames']
            as Map<String, dynamic>;
    expect(provenance.keys, unorderedEquals(published));
    for (final frame in frames.values.cast<Map<String, dynamic>>()) {
      final image = frame['image'] as String?;
      if (image == null) continue;
      final reviewed = provenance[image] as Map<String, dynamic>;
      expect(frame['visualSha256'], matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(reviewed['sourceSha256'], frame['sourceSha256'], reason: image);
      expect(reviewed['visualSha256'], frame['visualSha256'], reason: image);
      expect(
        reviewed['imageSha256'],
        sha256.convert(File('$imageRoot/$image').readAsBytesSync()).toString(),
        reason: image,
      );
    }

    final manifest =
        jsonDecode(
              File('scripts/recordings/doc_frames.json').readAsStringSync(),
            )
            as Map<String, Object?>;
    final backed = <String>{
      for (final scene
          in (manifest['scenes']! as List<Object?>)
              .cast<Map<String, Object?>>())
        if (scene['image'] case final String image) image,
    };

    expect(
      published.difference(backed),
      isEmpty,
      reason:
          'add a scene to scripts/recordings/doc_frames.json so a checkpoint '
          'change fails before the screenshot goes stale',
    );
    expect(
      backed.difference(published),
      isEmpty,
      reason: 'a scene names a screenshot that $imageRoot does not publish',
    );

    // The walkthrough index has to keep describing exactly those files.
    final index = File('$imageRoot/README.md').readAsStringSync();
    for (final image in published) {
      expect(index, contains('`$image`'), reason: image);
    }
  });

  test('the first-app tutorial and its homepage proof share one source', () {
    final checkpoint = File(
      'example/tutorials/first_app/step_01.dart',
    ).readAsStringSync();
    final edited = File(
      'example/tutorials/first_app/step_02.dart',
    ).readAsStringSync();
    final tutorial = File(
      'website/src/content/docs/getting-started.mdx',
    ).readAsStringSync();
    final generated = File(
      'website/src/generated/checkpoints.ts',
    ).readAsStringSync();

    expect(checkpoint, contains(r"Text('Count: $_count')"));
    expect(edited, contains(r"Text('Total: $_count')"));
    expect(
      checkpoint.replaceAll('Count: ', 'Total: '),
      edited,
      reason: 'the two checkpoints must differ only by the taught edit',
    );
    expect(tutorial, contains(checkpoint.trimRight()));
    expect(generated, contains(jsonEncode(checkpoint.trimRight())));
    expect(
      generated,
      contains('example/tutorials/first_app/step_01.dart'),
      reason: 'the homepage excerpt must name the file it came from',
    );
  });
}
