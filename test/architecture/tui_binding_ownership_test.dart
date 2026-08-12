import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TuiBinding owns the app lifecycle graph', () {
    final source = File('lib/src/app/tui_binding.dart').readAsStringSync();
    final body = _classBody(source, 'TuiBinding');

    expect(source, isNot(contains('TuiBinding runTuiApp(')));
    expect(body, contains('SchedulerBinding'));
    expect(body, contains('BuildOwner'));
    expect(body, contains('RenderView'));
    expect(body, contains('TerminalSession'));
    expect(body, contains('WidgetInspectorService'));
    expect(
      body,
      contains('_inputDispatcher.setEventDispatch(_scheduler.scheduleFrame)'),
    );
    expect(body, contains('_owner.pipelineOwner.flushLayout'));
    expect(body, contains('_owner.pipelineOwner.flushPaint'));
    expect(body, contains('void _drawFrame(Duration timestamp)'));
  });

  test('TuiApp is the narrow owning facade returned by runTuiApp', () {
    final source = File('lib/src/app/app.dart').readAsStringSync();
    final body = _classBody(source, 'TuiApp');

    expect(source, contains('TuiApp runTuiApp('));
    expect(source, contains('return TuiApp._(binding);'));
    expect(body, contains('TuiApp._(this._binding)'));
    expect(body, contains('final TuiBinding _binding'));
    expect(body, contains('final Set<InputSubscription> _subscriptions'));
    expect(body, contains('bool get isHeadless'));
    expect(body, contains('VoidCallback onKey'));
    expect(body, contains('VoidCallback onMouse'));
    expect(body, contains('VoidCallback onPaste'));
    expect(body, contains('void enableMouse'));
    expect(body, contains('void disableMouse'));
    expect(body, contains('void enableKittyKeyboard'));
    expect(body, contains('void disableKittyKeyboard'));
    for (final registration in const <String>{'onKey', 'onMouse', 'onPaste'}) {
      expect(
        body,
        contains(
          '_binding.inputManager.$registration(handler, '
          'priority: InputPriority.app)',
        ),
        reason: '$registration must retain app-priority dispatch.',
      );
    }
    expect(
      RegExp(r'priority:\s*InputPriority\.app').allMatches(body),
      hasLength(3),
    );

    for (final forbidden in [
      'InputManager get inputManager',
      'Renderer? get renderer',
      'BuildOwner get buildOwner',
      'void runApp',
      'handleResize',
      'SchedulerBinding',
      'TerminalSession',
      'BuildOwner(',
      'InputDispatcher',
      'RenderView',
      'Element?',
      '_root',
      '_drawFrame',
      'WidgetInspectorService',
      'pipelineOwner',
      'flushLayout',
      'flushPaint',
      'handleBeginFrame',
      'setEventDispatch',
    ]) {
      expect(body, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('examples and non-facade tests use runTuiApp for app handles', () {
    final allowedTuiAppFiles = {
      'test/architecture/tui_binding_ownership_test.dart',
      'test/app/tui_app_facade_test.dart',
    };

    final offenders = <String>[];
    for (final root in [Directory('example'), Directory('test')]) {
      for (final file in _dartFilesUnder(root)) {
        final path = file.path.replaceAll(Platform.pathSeparator, '/');
        if (allowedTuiAppFiles.contains(path)) {
          continue;
        }
        final source = file.readAsStringSync();
        if (RegExp(r'(^|[^A-Za-z0-9_])TuiApp\(').hasMatch(source)) {
          offenders.add(path);
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'TuiApp has no public constructor. Advanced tests and embedders use '
          'TuiBinding; ordinary apps receive the facade from runTuiApp.',
    );
  });

  test('app lifecycle layer does not own widget semantics', () {
    final forbidden = [
      _symbol('Media', 'Query'),
      'Shortcuts',
      'Actions',
      'Intent',
    ];
    final roots = [Directory('lib/src/app'), Directory('test/app')];

    for (final root in roots) {
      for (final file in _dartFilesUnder(root)) {
        final source = file.readAsStringSync();
        for (final symbol in forbidden) {
          expect(
            RegExp('\\b$symbol\\b').hasMatch(source),
            isFalse,
            reason: file.path,
          );
        }
      }
    }
  });
}

Iterable<File> _dartFilesUnder(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

String _symbol(String first, String second) => '$first$second';

String _classBody(String source, String className) {
  final classIndex = source.indexOf('class $className');
  if (classIndex < 0) {
    throw StateError('Class $className not found');
  }
  final start = source.indexOf('{', classIndex);
  if (start < 0) {
    throw StateError('Class $className has no body');
  }
  var depth = 0;
  for (var i = start; i < source.length; i++) {
    final code = source.codeUnitAt(i);
    if (code == 0x7b) depth++;
    if (code == 0x7d) {
      depth--;
      if (depth == 0) {
        return source.substring(start, i + 1);
      }
    }
  }
  throw StateError('Class $className body is unterminated');
}
