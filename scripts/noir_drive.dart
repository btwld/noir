#!/usr/bin/env dart
// Drive a Noir app from the command line, interactively or from a pipe.
//
//     dart run scripts/noir_drive.dart example/counter.dart [--size 100x30]
//                                      [--json] [-- app arguments...]
//
// The app starts in drive mode (`NOIR_DRIVE=1`): headless, painting into
// OpenTUI's non-terminal testing renderer, controlled only over the VM
// service. No TTY, no raw mode, and no change to the app itself.
//
// Commands are read from this script's own stdin, one per line:
//
//     capture [--ansi|--plain|--cells]   # --ansi paints the frame in color
//     tree [depth]
//     key <up|down|left|right|enter|tab|esc|backspace|pgup|pgdn|ctrl-<a-z>>
//     type <text...>
//     click <x> <y>
//     scroll <up|down|left|right> <x> <y>
//     resize <WxH>
//     reload                             # swap edited sources, then rebuild
//     watch on|off                       # re-print the frame after each command
//     quit
//
// Frames and tree output go to stdout; status and errors go to stderr, so a
// piped run captures exactly the app's rendered output:
//
//     printf 'capture --ansi\nkey up\ncapture --ansi\nquit\n' | \
//       dart run scripts/noir_drive.dart example/counter.dart
//
// The exit code is the driven app's own, or 65 when a command failed.

import 'dart:convert';
import 'dart:io';

import 'driver/ansi_keys.dart';
import 'driver/noir_driver.dart';

const _usage =
    'Usage: dart run scripts/noir_drive.dart <entry-point.dart> '
    '[--size WxH] [--json] [-- app arguments...]';

const _commands =
    'capture [--ansi|--plain|--cells] | tree [depth] | key <name> | '
    'type <text> | click <x> <y> | scroll <up|down|left|right> <x> <y> | '
    'resize <WxH> | reload | watch on|off | quit';

Future<void> main(List<String> arguments) async {
  final options = _Options.parse(arguments);
  if (options == null) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final NoirDriver driver;
  try {
    driver = await NoirDriver.launch(
      options.entryPoint,
      width: options.width,
      height: options.height,
      arguments: options.appArguments,
    );
  } on Object catch (error) {
    stderr.writeln(
      '[noir drive] could not start ${options.entryPoint}: $error',
    );
    exitCode = 70;
    return;
  }

  final session = _Session(driver, json: options.json);
  try {
    await session.run();
  } finally {
    exitCode = await session.close();
  }
}

/// One interactive or piped command session against a launched app.
class _Session {
  _Session(this._driver, {required bool json}) : _json = json;

  final NoirDriver _driver;
  final bool _json;
  bool _watch = false;
  bool _failed = false;
  bool _quit = false;
  int? _exitCode;

  Future<void> run() async {
    final prompt = stdin.hasTerminal;
    if (prompt) {
      stdout.write('noir> ');
    }
    final lines = stdin.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        await _dispatch(trimmed);
      }
      if (_quit) {
        return;
      }
      if (prompt) {
        stdout.write('noir> ');
      }
    }
  }

  /// Shuts the app down if it is still running and returns the exit code.
  Future<int> close() async {
    _exitCode ??= await _driver.quit();
    return _failed ? 65 : _exitCode!;
  }

  Future<void> _dispatch(String input) async {
    final separator = input.indexOf(' ');
    final command = separator < 0 ? input : input.substring(0, separator);
    final rest = separator < 0 ? '' : input.substring(separator + 1);

    try {
      switch (command) {
        case 'capture':
          await _capture(rest.trim());
        case 'tree':
          await _tree(rest.trim());
        case 'key':
          await _driver.sendKey(rest.trim());
          await _afterAction();
        case 'type':
          await _driver.typeText(rest);
          await _afterAction();
        case 'click':
          await _click(rest.trim());
        case 'scroll':
          await _scroll(rest.trim());
        case 'resize':
          await _resize(rest.trim());
        case 'reload':
          await _reload();
        case 'watch':
          _setWatch(rest.trim());
        case 'quit':
          _exitCode = await _driver.quit();
          _quit = true;
        default:
          _fail('unknown command "$command". Try: $_commands');
      }
    } on Object catch (error) {
      _fail('$command failed: $error');
    }
  }

  Future<void> _capture(String flags) async {
    final format = flags.isEmpty ? '--plain' : flags;
    switch (format) {
      case '--plain':
        _printFrame(await _driver.capture(), ansi: false);
      case '--ansi':
        _printFrame(await _driver.captureCells(), ansi: true);
      case '--cells':
        final frame = await _driver.captureCells();
        stdout.writeln(jsonEncode(_cellsJson(frame)));
      default:
        _fail(
          'unknown capture format "$format". '
          'Try --ansi, --plain, or --cells.',
        );
    }
  }

  Future<void> _tree(String depth) async {
    final maxDepth = depth.isEmpty ? 2 : int.tryParse(depth);
    if (maxDepth == null || maxDepth < 0) {
      _fail('tree depth must be a non-negative integer.');
      return;
    }
    final lines = await _driver.tree(maxDepth: maxDepth);
    if (_json) {
      stdout.writeln(jsonEncode(<String, Object?>{'lines': lines}));
      return;
    }
    for (final line in lines) {
      stdout.writeln(line);
    }
  }

  Future<void> _click(String arguments) async {
    final point = _parsePoint(arguments, 'click <x> <y>');
    if (point == null) {
      return;
    }
    await _driver.click(point.x, point.y);
    await _afterAction();
  }

  Future<void> _scroll(String arguments) async {
    final parts = _split(arguments);
    if (parts.length != 3) {
      _fail('scroll takes <up|down|left|right> <x> <y>.');
      return;
    }
    final direction = _parseScrollDirection(parts.first);
    final point = _parsePoint('${parts[1]} ${parts[2]}', 'scroll ... <x> <y>');
    if (direction == null) {
      _fail('unknown scroll direction "${parts.first}".');
      return;
    }
    if (point == null) {
      return;
    }
    await _driver.scroll(point.x, point.y, direction);
    await _afterAction();
  }

  Future<void> _resize(String size) async {
    final parsed = _parseSize(size);
    if (parsed == null) {
      _fail('resize takes <WxH>, for example 100x30.');
      return;
    }
    final applied = await _driver.resize(parsed.width, parsed.height);
    _log('resized to ${applied.width}x${applied.height}');
    await _afterAction();
  }

  Future<void> _reload() async {
    final outcome = await _driver.reload();
    if (!outcome.reloaded) {
      // Where a compile error lands. The app stays alive on its last good
      // sources, so fixing the file and reloading again is the whole recovery.
      _fail('reload rejected: ${outcome.message}');
      return;
    }
    if (!outcome.reassembled) {
      _fail('sources reloaded, but the app was not reassembled.');
      return;
    }
    _log('reloaded');
    await _afterAction();
  }

  void _setWatch(String value) {
    switch (value) {
      case 'on':
        _watch = true;
        _log('watch on');
      case 'off':
        _watch = false;
        _log('watch off');
      default:
        _fail('watch takes on or off.');
    }
  }

  Future<void> _afterAction() async {
    if (_watch) {
      _printFrame(await _driver.capture(), ansi: false);
    }
  }

  void _printFrame(DriverFrame frame, {required bool ansi}) {
    if (_json) {
      stdout.writeln(
        jsonEncode(<String, Object?>{
          'width': frame.width,
          'height': frame.height,
          'lines': frame.lines,
          'cursor': frame.cursor.toString(),
        }),
      );
      return;
    }
    if (!ansi) {
      for (final line in frame.lines) {
        stdout.writeln(line);
      }
      return;
    }
    for (final row in frame.rows) {
      final painted = StringBuffer();
      DriverColor? foreground;
      DriverColor? background;
      for (final cell in row) {
        if (cell.char.isEmpty) {
          // Trailing half of a wide grapheme: the previous cell drew it.
          continue;
        }
        if (!_sameColor(foreground, cell.foreground)) {
          foreground = cell.foreground;
          painted.write(_sgr(38, foreground));
        }
        if (!_sameColor(background, cell.background)) {
          background = cell.background;
          painted.write(_sgr(48, background));
        }
        painted.write(cell.char);
      }
      painted.write('\x1b[0m');
      stdout.writeln(painted);
    }
  }

  ({int x, int y})? _parsePoint(String arguments, String grammar) {
    final parts = _split(arguments);
    if (parts.length != 2) {
      _fail('$grammar takes two integers.');
      return null;
    }
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null || x < 0 || y < 0) {
      _fail('$grammar takes two non-negative integers.');
      return null;
    }
    return (x: x, y: y);
  }

  void _log(String message) {
    stderr.writeln('[noir drive] $message');
  }

  void _fail(String message) {
    _failed = true;
    stderr.writeln('[noir drive] $message');
  }
}

/// Parsed command-line options for one drive session.
class _Options {
  const _Options({
    required this.entryPoint,
    required this.width,
    required this.height,
    required this.json,
    required this.appArguments,
  });

  /// Reads the option grammar, returning null when it does not parse.
  ///
  /// Driver flags are accepted on either side of the entry point, matching the
  /// documented `<entry-point.dart> [--size WxH] [--json]` shape. An app that
  /// needs its own flags takes them after `--`.
  static _Options? parse(List<String> arguments) {
    var width = 80;
    var height = 24;
    var json = false;
    final positional = <String>[];
    final appArguments = <String>[];
    var forwarding = false;

    for (var i = 0; i < arguments.length; i++) {
      final argument = arguments[i];
      if (forwarding) {
        appArguments.add(argument);
      } else if (argument == '--') {
        forwarding = true;
      } else if (argument == '--json') {
        json = true;
      } else if (argument == '--size' || argument.startsWith('--size=')) {
        final raw = argument == '--size'
            ? (i + 1 < arguments.length ? arguments[++i] : null)
            : argument.substring('--size='.length);
        final size = raw == null ? null : _parseSize(raw);
        if (size == null) {
          return null;
        }
        width = size.width;
        height = size.height;
      } else if (argument.startsWith('-')) {
        return null;
      } else {
        positional.add(argument);
      }
    }

    if (positional.length != 1) {
      return null;
    }
    return _Options(
      entryPoint: positional.single,
      width: width,
      height: height,
      json: json,
      appArguments: appArguments,
    );
  }

  final String entryPoint;
  final int width;
  final int height;
  final bool json;
  final List<String> appArguments;
}

final RegExp _sizePattern = RegExp(r'^(\d+)x(\d+)$');

({int width, int height})? _parseSize(String value) {
  final match = _sizePattern.firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final width = int.parse(match.group(1)!);
  final height = int.parse(match.group(2)!);
  if (width <= 0 || height <= 0) {
    return null;
  }
  return (width: width, height: height);
}

List<String> _split(String value) => value.isEmpty
    ? const <String>[]
    : value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();

DriverScrollDirection? _parseScrollDirection(String name) =>
    switch (name.toLowerCase()) {
      'up' => DriverScrollDirection.up,
      'down' => DriverScrollDirection.down,
      'left' => DriverScrollDirection.left,
      'right' => DriverScrollDirection.right,
      _ => null,
    };

bool _sameColor(DriverColor? left, DriverColor right) =>
    left != null &&
    left.red == right.red &&
    left.green == right.green &&
    left.blue == right.blue;

String _sgr(int layer, DriverColor color) =>
    '\x1b[$layer;2;${color.red};${color.green};${color.blue}m';

Map<String, Object?> _cellsJson(DriverFrame frame) => <String, Object?>{
  'width': frame.width,
  'height': frame.height,
  'rows': <Object?>[
    for (final row in frame.rows)
      <Object?>[
        for (final cell in row)
          <String, Object?>{
            'char': cell.char,
            'fg': cell.foreground.toAnsiHex(),
            'bg': cell.background.toAnsiHex(),
            'attrs': cell.attributes,
          },
      ],
  ],
  'cursor': frame.cursor.toString(),
};
