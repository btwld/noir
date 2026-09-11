import 'dart:async';

import 'package:noir/noir.dart' show AutocompleteStatus;
import 'package:test/test.dart';

import '../../example/autocomplete_demo.dart';
import '../../example/dialog_demo.dart';
import '../../example/file_picker_demo.dart';
import '../helpers/buffer_capture.dart';
import '../helpers/tui_test_app.dart';

void main() {
  group('package autocomplete controller', () {
    test('debounces work before calling the suggestion source', () async {
      final source = _ControlledSuggestionSource();
      final controller = PackageAutocompleteController(
        source: source,
        debounce: const Duration(days: 1),
      );
      addTearDown(controller.dispose);

      controller.updateQuery('noir');
      await _flushAsync();

      expect(source.hasRequestFor('noir'), isFalse);
      expect(controller.status, AutocompleteStatus.loading);
    });

    test('ignores a stale completion from an older query', () async {
      final source = _ControlledSuggestionSource();
      final controller = PackageAutocompleteController(
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.updateQuery('no');
      await _flushAsync();
      final older = source.requestFor('no');

      controller.updateQuery('noi');
      await _flushAsync();
      final newer = source.requestFor('noi');

      newer.complete(const [
        PackageSuggestion(
          name: 'noir',
          description: 'Reactive terminal UI framework',
        ),
      ]);
      await _flushAsync();
      expect(controller.suggestions.map((item) => item.name), ['noir']);

      older.complete(const [
        PackageSuggestion(name: 'noise', description: 'An obsolete response'),
      ]);
      await _flushAsync();

      expect(controller.query, 'noi');
      expect(controller.suggestions.map((item) => item.name), ['noir']);
      expect(controller.status, AutocompleteStatus.ready);
    });

    test('clears suggestions below the two-character threshold', () async {
      final controller = PackageAutocompleteController(
        source: const DemoPackageSuggestionSource(),
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.updateQuery('noi');
      await _flushAsync();
      expect(controller.suggestions, isNotEmpty);

      controller.updateQuery(' n ');

      expect(controller.query, 'n');
      expect(controller.suggestions, isEmpty);
      expect(controller.status, AutocompleteStatus.idle);
    });

    test('editing a chosen package clears the stale selection', () async {
      final controller = PackageAutocompleteController(
        source: const DemoPackageSuggestionSource(),
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.updateQuery('noi');
      await _flushAsync();
      final selected = controller.choose(controller.suggestions.first);
      expect(selected?.name, 'noir');
      expect(controller.selected?.name, 'noir');

      controller.updateQuery('noir_');

      expect(controller.selected, isNull);
    });
  });

  test(
    'confirmation dialog traps focus, blocks its base, and restores focus',
    () async {
      final app = createTuiTestApp(const DialogDemoApp());
      try {
        await _settle(app);
        var frame = app.captureFrame();
        final refresh = frame.findText('Refresh').single;

        app.mockInput.pressEnter();
        await _settle(app);

        frame = app.captureFrame();
        expect(frame.toText(), contains('Confirm deployment'));
        expect(frame.toText(), contains('Deploy noir 0.0.1'));
        _expectBold(frame, 'Cancel');
        final titleAt80 = frame.findText('Confirm deployment').single;

        app.resize(100, 30);
        await _settle(app);
        final titleAt100 = app
            .captureFrame()
            .findText('Confirm deployment')
            .single;
        expect(titleAt100.x - titleAt80.x, 10);
        expect(titleAt100.y - titleAt80.y, 3);

        app.resize(64, 18);
        await _settle(app);
        expect(app.captureFrame().toText(), contains('Cancel   Deploy'));

        app.resize(80, 24);
        await _settle(app);

        app.mockInput.pressTab();
        await _settle(app);
        _expectBold(app.captureFrame(), 'Deploy');

        app.mockInput.pressTab();
        await _settle(app);
        _expectBold(app.captureFrame(), 'Cancel');

        app.mockInput.pressShiftTab();
        await _settle(app);
        _expectBold(app.captureFrame(), 'Deploy');

        app.mockMouse.click(refresh.x, refresh.y);
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          contains('Production remains unchanged.'),
          reason:
              'the transparent modal barrier blocks the base Refresh button',
        );

        app.mockInput.pressEscape();
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          isNot(contains('Confirm deployment')),
        );

        app.mockInput.pressEnter();
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          contains('Confirm deployment'),
          reason: 'dismissal restores focus to Review deploy',
        );
        _expectBold(app.captureFrame(), 'Cancel');

        app.mockInput.pressTab();
        await _settle(app);
        _expectBold(app.captureFrame(), 'Deploy');

        app.mockInput.pressEnter();
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          contains('Deployment scheduled for noir 0.0.1.'),
        );
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'autocomplete attaches suggestions and chooses with Tab and Enter',
    () async {
      final app = createTuiTestApp(
        const AutocompleteDemoApp(
          source: DemoPackageSuggestionSource(),
          debounce: Duration.zero,
        ),
      );
      try {
        await _settle(app);
        var frame = app.captureFrame();
        expect(frame.toText(), contains('Package autocomplete'));
        expect(frame.toText(), contains('› Package'));
        expect(frame.toText(), contains('Reactive terminal UI framework'));

        final inputBorder = frame.findText('› Package').single;
        final firstSuggestion = frame.findText('› noir').single;
        expect(
          firstSuggestion.x,
          inputBorder.x,
          reason:
              'the borderless suggestion surface shares the input title edge',
        );

        app.mockInput
          ..pressTab()
          ..pressArrow(ArrowDirection.down)
          ..pressEnter();
        await _settle(app);

        frame = app.captureFrame();
        expect(frame.toText(), contains('Selected  noir_cli'));
        expect(
          frame.toText(),
          isNot(contains('Reactive terminal UI framework')),
        );

        for (var index = 0; index < 4; index++) {
          app.mockInput.pressBackspace();
        }
        app.mockInput.typeText('_test');
        await _settle(app);
        expect(app.captureFrame().toText(), contains('noir_test'));
      } finally {
        app.dispose();
      }
    },
  );

  test(
    'tree picker flattens folders, previews files, and opens a path',
    () async {
      final app = createTuiTestApp(const FilePickerDemoApp());
      try {
        await _settle(app);
        var frame = app.captureFrame();
        expect(frame.toText(), contains('Open file'));
        expect(frame.toText(), contains('› Project'));
        expect(frame.toText(), contains('menu_anchor.dart'));
        expect(frame.toText(), contains('lib/src/widgets/menu_anchor.dart'));

        app.mockInput.pressArrow(ArrowDirection.left);
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          contains('lib/src/widgets'),
          reason: 'Left on a file moves the highlight to its parent folder',
        );

        app.mockInput.pressArrow(ArrowDirection.left);
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          isNot(contains('menu_anchor.dart')),
          reason: 'Left on the expanded parent collapses it',
        );

        app.mockInput.pressArrow(ArrowDirection.right);
        await _settle(app);
        expect(app.captureFrame().toText(), contains('menu_anchor.dart'));

        app.mockInput
          ..pressArrow(ArrowDirection.down)
          ..pressArrow(ArrowDirection.down);
        await _settle(app);
        expect(app.captureFrame().toText(), contains('widgets/overlay.dart'));

        app.mockInput
          ..pressTab()
          ..pressTab();
        await _settle(app);
        _expectBold(app.captureFrame(), 'Open');

        app.mockInput.pressEnter();
        await _settle(app);
        frame = app.captureFrame();
        expect(frame.toText(), isNot(contains('┌─ Open file')));
        expect(frame.toText(), contains('Opened lib/src/widgets/overlay.dart'));

        app.mockInput.pressEnter();
        await _settle(app);
        expect(
          app.captureFrame().toText(),
          contains('┌─ Open file'),
          reason: 'closing the picker restores focus to its launcher',
        );
      } finally {
        app.dispose();
      }
    },
  );
}

final class _ControlledSuggestionSource implements PackageSuggestionSource {
  final _requests = <String, Completer<List<PackageSuggestion>>>{};

  @override
  Future<List<PackageSuggestion>> suggest(String query) {
    final completer = Completer<List<PackageSuggestion>>();
    _requests[query] = completer;
    return completer.future;
  }

  Completer<List<PackageSuggestion>> requestFor(String query) {
    final request = _requests[query];
    if (request == null) {
      throw StateError('No request for $query');
    }
    return request;
  }

  bool hasRequestFor(String query) => _requests.containsKey(query);
}

void _expectBold(CapturedBuffer frame, String text) {
  final locations = frame.findText(text);
  expect(locations, isNotEmpty, reason: text);
  expect(
    locations.any((location) => frame.getCell(location.x, location.y).isBold),
    isTrue,
    reason: text,
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

Future<void> _settle(TuiTestApp app) async {
  await _flushAsync();
  app.pumpFrame();
  await _flushAsync();
  app.pumpFrame();
}
