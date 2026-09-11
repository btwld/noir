@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/driver/noir_driver.dart';
import '../helpers/tool_json_output.dart';

const _wideExamples = <String>{
  'chat_demo.dart',
  'data_table_demo.dart',
  'focus_form.dart',
  'like_reactor.dart',
  'listview_demo.dart',
  'parity_components_demo.dart',
  'widgets_tour.dart',
};

void main() {
  final examples =
      Directory('example')
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.dart'))
          .toList()
        ..sort();

  group('example drive catalog', () {
    for (final name in examples) {
      if (name == 'bindings_validation.dart') {
        test('bindings_validation refuses drive mode', () async {
          final result = await _driveCli(name);
          expect(result.code, 70, reason: result.stderr);
        });
        continue;
      }

      test(name, () async {
        final result = await _driveCli(
          name,
          size: _wideExamples.contains(name) ? '100x30' : '80x24',
        );
        expect(result.code, 0, reason: result.stderr);
        expect(result.captures, isNotEmpty, reason: result.stdout);
        expect(
          (result.captures.first['lines']! as List<Object?>).cast<String>().any(
            (line) => line.trim().isNotEmpty,
          ),
          isTrue,
          reason: result.stdout,
        );
        expect(result.trees.single['root'], isNotNull, reason: result.stdout);
      });
    }
  });

  group('keyed example locators', () {
    test(
      'agent chat composer survives locator input, resize, and graceful exit',
      () async {
        final driver = await NoirDriver.launch('example/chat_demo.dart');
        var exited = false;
        addTearDown(() async {
          if (!exited) await driver.quit();
        });

        const composer = DriverLocator.byKey('composer');
        await driver.waitFor(composer);
        await driver.clickLocator(composer);
        await driver.typeText('drive-mode draft');
        expect((await driver.capture()).contains('drive-mode draft'), isTrue);

        expect(await driver.resize(64, 18), (width: 64, height: 18));
        expect((await driver.find(composer)).hasFocusedDescendant, isTrue);
        expect((await driver.capture()).contains('drive-mode draft'), isTrue);

        expect(await driver.resize(120, 30), (width: 120, height: 30));
        expect((await driver.capture()).contains('drive-mode draft'), isTrue);

        await driver.sendKey('esc');
        expect(
          await driver.waitForExit().timeout(const Duration(seconds: 5)),
          0,
        );
        exited = true;
      },
    );

    test('counter increment key click advances the count', () async {
      final driver = await NoirDriver.launch('example/counter.dart');
      addTearDown(driver.quit);

      expect((await driver.capture()).lines.any(_isCountLine('0')), isTrue);
      await driver.clickLocator(const DriverLocator.byKey('increment'));
      expect((await driver.capture()).lines.any(_isCountLine('1')), isTrue);
    });

    test('companion counter add-one key click advances the count', () async {
      final driver = await NoirDriver.launch(
        '../noir_signals/example/counter.dart',
      );
      addTearDown(driver.quit);

      expect((await driver.capture()).contains('Count: 0'), isTrue);
      await driver.clickLocator(const DriverLocator.byKey('add-one'));
      expect((await driver.capture()).contains('Count: 1'), isTrue);
    });

    test('select fruit key click changes the highlight', () async {
      final driver = await NoirDriver.launch('example/select_demo.dart');
      addTearDown(driver.quit);

      await driver.clickLocator(const DriverLocator.byKey('fruit'));
      final frame = await driver.capture();
      expect(
        frame.lines.any(
          (line) => line.contains('Highlight:') || line.contains('You picked:'),
        ),
        isTrue,
        reason: frame.lines.join('\n'),
      );
    });

    test('components step key click advances the progress', () async {
      final driver = await NoirDriver.launch('example/components_demo.dart');
      addTearDown(driver.quit);

      expect((await driver.capture()).contains('3/10'), isTrue);
      await driver.clickLocator(const DriverLocator.byKey('step'));
      expect((await driver.capture()).contains('4/10'), isTrue);
    });

    test('components modal locators confirm the overlay specimen', () async {
      final driver = await NoirDriver.launch('example/components_demo.dart');
      addTearDown(driver.quit);

      await driver.sendKey('shift-tab');
      await driver.sendKey('right');
      await driver.sendKey('right');
      await driver.waitFor(const DriverLocator.byKey('open-modal'));

      await driver.clickLocator(const DriverLocator.byKey('open-modal'));
      expect((await driver.capture()).contains('Review changes'), isTrue);

      await driver.clickLocator(const DriverLocator.byKey('modal-confirm'));
      final frame = await driver.capture();
      expect(frame.contains('Review changes'), isFalse);
      expect(frame.contains('Result: approved'), isTrue);
      expect(frame.contains('Transitions: 1 open / 1 close'), isTrue);
    });

    test('components data category exposes both public data widgets', () async {
      final driver = await NoirDriver.launch('example/components_demo.dart');
      addTearDown(driver.quit);

      await driver.sendKey('shift-tab');
      await driver.sendKey('right');
      await driver.sendKey('right');
      await driver.sendKey('right');
      await driver.waitFor(
        const DriverLocator.byKey('component-autocomplete-ready'),
      );
      await driver.waitFor(const DriverLocator.byKey('component-tree'));

      final frame = await driver.capture();
      for (final text in const [
        'Loading…',
        'No options.',
        'Options unavailable.',
        'noir_cli',
        'src / expanded',
        'noir.dart / selected',
        'archive / collapsed',
      ]) {
        expect(frame.contains(text), isTrue, reason: text);
      }
    });

    test('focus form Save key exposes both blank-field errors', () async {
      final driver = await NoirDriver.launch('example/focus_form.dart');
      addTearDown(driver.quit);

      // The driver service can be ready before autofocus and layout finish.
      expect(await driver.waitStable(), isTrue);
      await driver.clickLocator(const DriverLocator.byKey('save'));
      final frame = await driver.capture();
      expect(frame.contains('Name error: Enter your name.'), isTrue);
      expect(
        frame.contains('Email error: Enter an email like name@example.com.'),
        isTrue,
      );
      expect(frame.contains('Saved:'), isFalse);
    });

    test('dialog locators confirm a deployment through the modal', () async {
      final driver = await NoirDriver.launch('example/dialog_demo.dart');
      addTearDown(driver.quit);

      await driver.clickLocator(const DriverLocator.byKey('open-dialog'));
      expect((await driver.capture()).contains('Confirm deployment'), isTrue);

      await driver.clickLocator(const DriverLocator.byKey('confirm-deploy'));
      final frame = await driver.capture();
      expect(frame.contains('Confirm deployment'), isFalse);
      expect(frame.contains('Deployment scheduled for noir 0.0.2.'), isTrue);
    });

    test(
      'autocomplete chooses the next suggestion through parsed keys',
      () async {
        final driver = await NoirDriver.launch(
          'example/autocomplete_demo.dart',
        );
        addTearDown(driver.quit);

        await driver.waitForText('noir_cli');
        await driver.sendKey('tab');
        await driver.sendKey('down');
        await driver.sendKey('enter');

        expect((await driver.capture()).contains('Selected  noir_cli'), isTrue);
      },
    );

    test(
      'file picker opens the next file through its closed focus loop',
      () async {
        final driver = await NoirDriver.launch('example/file_picker_demo.dart');
        addTearDown(driver.quit);

        await driver.waitFor(const DriverLocator.byKey('file-tree'));
        expect(await driver.waitStable(), isTrue);
        expect(
          (await driver.find(
            const DriverLocator.byKey('file-tree'),
          )).hasFocusedDescendant,
          isTrue,
        );

        await driver.sendKey('down');
        await driver.sendKey('tab');
        await driver.sendKey('tab');
        await driver.sendKey('enter');

        final frame = await driver.capture();
        expect(frame.contains('Open file'), isFalse);
        expect(frame.contains('Opened lib/src/widgets/overlay.dart'), isTrue);
      },
    );
  });
}

bool Function(String) _isCountLine(String count) =>
    (line) => line.trim() == count;

Future<
  ({
    int code,
    List<Map<String, Object?>> captures,
    List<Map<String, Object?>> trees,
    String stdout,
    String stderr,
  })
>
_driveCli(String name, {String size = '80x24'}) async {
  final process = await Process.start(Platform.resolvedExecutable, <String>[
    'run',
    '--verbosity=error',
    'tool/noir_drive.dart',
    'example/$name',
    '--size',
    size,
    '--json',
  ]);
  process.stdin.write('capture --plain\ntree 2\nquit\n');
  await process.stdin.close();
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(const Duration(minutes: 2));
  final stdout = await stdoutFuture;
  final stderr = await stderrFuture;
  final messages = decodeToolJsonObjects(stdout);
  return (
    code: code,
    captures: [
      for (final message in messages)
        if (message.containsKey('lines')) message,
    ],
    trees: [
      for (final message in messages)
        if (message.containsKey('root')) message,
    ],
    stdout: stdout,
    stderr: stderr,
  );
}
