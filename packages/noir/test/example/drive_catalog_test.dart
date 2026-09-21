@TestOn('vm')
@Tags(['safe-process-spawning'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:noir_driver/noir_driver.dart';
import 'package:test/test.dart';

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
        expect(await driver.capture(), _paints('drive-mode draft'));

        expect(await driver.resize(64, 18), (width: 64, height: 18));
        expect((await driver.find(composer)).hasFocusedDescendant, isTrue);
        expect(await driver.capture(), _paints('drive-mode draft'));

        expect(await driver.resize(120, 30), (width: 120, height: 30));
        expect(await driver.capture(), _paints('drive-mode draft'));

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

      expect(await driver.capture(), _paints('Count: 0'));
      await driver.clickLocator(const DriverLocator.byKey('add-one'));
      expect(await driver.capture(), _paints('Count: 1'));
    });

    test('select fruit key click changes the highlight', () async {
      final driver = await NoirDriver.launch('example/select_demo.dart');
      addTearDown(driver.quit);

      await driver.clickLocator(const DriverLocator.byKey('fruit'));
      expect(
        await driver.capture(),
        anyOf(_paints('Highlight:'), _paints('You picked:')),
      );
    });

    test('components step key click advances the progress', () async {
      final driver = await NoirDriver.launch('example/components_demo.dart');
      addTearDown(driver.quit);

      expect(await driver.capture(), _paints('3/10'));
      await driver.clickLocator(const DriverLocator.byKey('step'));
      expect(await driver.capture(), _paints('4/10'));
    });

    test('components modal locators confirm the overlay specimen', () async {
      final driver = await NoirDriver.launch('example/components_demo.dart');
      addTearDown(driver.quit);

      await driver.sendKey('shift-tab');
      await driver.sendKey('right');
      await driver.sendKey('right');
      await driver.waitFor(const DriverLocator.byKey('open-modal'));

      await driver.clickLocator(const DriverLocator.byKey('open-modal'));
      expect(await driver.capture(), _paints('Review changes'));

      await driver.clickLocator(const DriverLocator.byKey('modal-confirm'));
      final frame = await driver.capture();
      expect(frame, isNot(_paints('Review changes')));
      expect(frame, _paints('Result: approved'));
      expect(frame, _paints('Transitions: 1 open / 1 close'));
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
        expect(frame, _paints(text));
      }
    });

    test('focus form Save key exposes both blank-field errors', () async {
      final driver = await NoirDriver.launch('example/focus_form.dart');
      addTearDown(driver.quit);

      // The driver service can be ready before autofocus and layout finish.
      expect(await driver.waitStable(), isTrue);
      await driver.clickLocator(const DriverLocator.byKey('save'));
      final frame = await driver.capture();
      expect(frame, _paints('Name error: Enter your name.'));
      expect(
        frame,
        _paints('Email error: Enter an email like name@example.com.'),
      );
      expect(frame, isNot(_paints('Saved:')));
    });

    test('dialog locators confirm a deployment through the modal', () async {
      final driver = await NoirDriver.launch('example/dialog_demo.dart');
      addTearDown(driver.quit);

      await driver.clickLocator(const DriverLocator.byKey('open-dialog'));
      expect(await driver.capture(), _paints('Confirm deployment'));

      await driver.clickLocator(const DriverLocator.byKey('confirm-deploy'));
      final frame = await driver.capture();
      expect(frame, isNot(_paints('Confirm deployment')));
      expect(frame, _paints('Deployment scheduled for noir 0.0.3.'));
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

        expect(await driver.capture(), _paints('Selected  noir_cli'));
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
        expect(frame, isNot(_paints('Open file')));
        expect(frame, _paints('Opened lib/src/widgets/overlay.dart'));
      },
    );
  });
}

/// Short local alias; every drive assertion in this file wants the captured
/// frame printed when it fails.
Matcher _paints(String text) => DriverFrameMatchers.containsText(text);

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
    'noir_driver:drive',
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
