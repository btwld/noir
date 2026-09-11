import 'dart:async';

import 'package:args/command_runner.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

// Mirrors the published command-line arguments guide. The injected mount stays
// at the entrypoint boundary, keeping checks headless without giving a Command
// ownership of the app lifecycle.

void main() {
  test('leaf command converts CLI values before launching the app', () async {
    _ReviewApp? launched;

    await _mountSelectedApp(
      ['review', 'patch.diff', '--mode', 'split', '--staged'],
      onMount: (app) => launched = app,
      onUsageError: _failUsage,
    );

    final app = launched;
    if (app == null) fail('The review command did not launch an app.');
    expect(app.options.initialPath, 'patch.diff');
    expect(app.options.mode, _ReviewMode.split);
    expect(app.options.staged, isTrue);
  });

  test('omitted interactive value reaches the app as null', () async {
    _ReviewApp? launched;

    await _mountSelectedApp(
      ['review'],
      onMount: (app) => launched = app,
      onUsageError: _failUsage,
    );

    final app = launched;
    if (app == null) fail('The review command did not launch an app.');
    expect(app.options.initialPath, isNull);
    expect(app.options.mode, _ReviewMode.unified);
    expect(app.options.staged, isFalse);
  });

  test('help returns without mounting the app', () async {
    var launches = 0;
    UsageException? usageError;
    final printed = <String>[];

    await runZoned(
      () => _mountSelectedApp(
        ['review', '--help'],
        onMount: (_) => launches++,
        onUsageError: (error) => usageError = error,
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => printed.add(line),
      ),
    );

    expect(launches, 0);
    expect(usageError, isNull);
    expect(printed.join('\n'), contains('Review a patch interactively.'));
  });

  test('invalid explicit value fails before app launch', () async {
    var launches = 0;
    UsageException? usageError;

    await _mountSelectedApp(
      ['review', '--mode', 'sideways'],
      onMount: (_) => launches++,
      onUsageError: (error) => usageError = error,
    );

    expect(launches, 0);
    expect(usageError, isA<UsageException>());
  });

  test('invalid positional count fails before app launch', () async {
    var launches = 0;
    UsageException? usageError;

    await _mountSelectedApp(
      ['review', 'first.diff', 'second.diff'],
      onMount: (_) => launches++,
      onUsageError: (error) => usageError = error,
    );

    expect(launches, 0);
    expect(usageError, isA<UsageException>());
  });
}

Future<void> _mountSelectedApp(
  Iterable<String> arguments, {
  required void Function(_ReviewApp app) onMount,
  required void Function(UsageException error) onUsageError,
}) async {
  final _ReviewOptions? options;
  try {
    options = await _runner().run(arguments);
  } on UsageException catch (error) {
    onUsageError(error);
    return;
  }

  if (options == null) return;
  onMount(_ReviewApp(options: options));
}

Never _failUsage(UsageException error) =>
    fail('Unexpected usage error: $error');

CommandRunner<_ReviewOptions> _runner() =>
    CommandRunner<_ReviewOptions>('patcher', 'Review patches in a terminal UI.')
      ..addCommand(_ReviewCommand());

enum _ReviewMode { unified, split }

final class _ReviewOptions {
  const _ReviewOptions({
    required this.initialPath,
    required this.mode,
    required this.staged,
  });

  final String? initialPath;
  final _ReviewMode mode;
  final bool staged;
}

final class _ReviewCommand extends Command<_ReviewOptions> {
  _ReviewCommand() {
    argParser
      ..addOption(
        'mode',
        allowed: [for (final mode in _ReviewMode.values) mode.name],
        defaultsTo: _ReviewMode.unified.name,
      )
      ..addFlag('staged', negatable: false);
  }

  @override
  String get name => 'review';

  @override
  String get description => 'Review a patch interactively.';

  @override
  _ReviewOptions run() {
    final paths = argResults!.rest;
    if (paths.length > 1) {
      usageException('Expected zero or one patch path.');
    }

    return _ReviewOptions(
      initialPath: paths.isEmpty ? null : paths.single,
      mode: _ReviewMode.values.byName(argResults!.option('mode')!),
      staged: argResults!.flag('staged'),
    );
  }
}

final class _ReviewApp extends StatelessWidget {
  const _ReviewApp({required this.options});

  final _ReviewOptions options;

  @override
  Widget build(BuildContext context) {
    final path = options.initialPath ?? 'Choose a patch in the TUI';
    final source = options.staged ? 'staged changes' : 'working tree';

    return Panel(
      title: 'Review',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 1,
        children: [
          Text(path),
          Text('Mode: ${options.mode.name}'),
          Text('Source: $source'),
        ],
      ),
    );
  }
}
