import 'dart:convert';
import 'dart:io';

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

  test('homepage uses the real capture without autoplay or mock output', () {
    final homepage = File('website/src/app/page.tsx').readAsStringSync();
    final player = File(
      'website/src/components/TerminalRecording.tsx',
    ).readAsStringSync();

    expect(homepage, contains('<TerminalRecording'));
    expect(homepage, isNot(contains('counterFrameAfterIncrement')));
    expect(homepage, isNot(contains('<TerminalFrame')));
    expect(player, contains("poster: 'npt:0:00.1'"));
    expect(player, contains('autoplay: false'));
    expect(player, contains('prefers-reduced-motion'));
    expect(player, contains('AsciinemaPlayer.create'));
  });
}
