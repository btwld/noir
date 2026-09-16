/// A flutter_driver-style client for a Noir app running in drive mode.
///
/// [NoirDriver.launch] starts any Noir entry point as an ordinary Dart process
/// with `NOIR_DRIVE=1` and a VM service, then talks to it only over
/// `ext.noir.driver.*`. The app paints into OpenTUI's non-terminal testing
/// renderer, so this needs no TTY, no raw mode, and no change to the app.
///
/// ```dart
/// final driver = await NoirDriver.launch('example/counter.dart');
/// await driver.clickLocator(const DriverLocator.byKey('increment'));
/// print((await driver.capture()).lines.join('\n'));
/// await driver.quit();
/// ```
///
/// [waitForText] polls painted capture rows for a substring. Locator
/// [DriverLocator.byText] matches `Text` / `RichText` source, not those cells.
///
/// `DriverFrameMatchers` asserts on a captured frame and prints it on failure.
///
/// This is a separate package from `noir` so an app never carries a
/// process-control channel in its production dependencies: add `noir_driver`
/// under `dev_dependencies`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'ansi_keys.dart';
import 'driver_tree.dart';

/// Polls [frames] until it is greater than [before], or [cap] expires.
///
/// Used after injected input so a continuously animating app does not pay
/// the full `waitStable` timeout. Returns whether a later frame arrived.
Future<bool> pollFrameAdvance({
  required Future<int> Function() frames,
  required int before,
  Duration cap = defaultSettle,
  Future<void> Function(Duration duration) delay = _pollDelay,
}) async {
  final deadline = DateTime.now().add(cap);
  while (true) {
    if (await frames() > before) {
      return true;
    }
    if (!DateTime.now().isBefore(deadline)) {
      return false;
    }
    await delay(const Duration(milliseconds: 10));
  }
}

Future<void> _pollDelay(Duration duration) => Future<void>.delayed(duration);

/// Waits for the driven app's extensions and its first painted frame.
///
/// Registration precedes the scheduled initial layout, so a successful service
/// response alone does not make capture or pointer locators ready. [timeout]
/// bounds both registration and the wait for a positive frame count.
Future<void> awaitDriverReady({
  required Future<int> Function() frames,
  required Duration timeout,
  Future<void> Function(Duration duration) delay = _pollDelay,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      final remaining = deadline.difference(DateTime.now());
      final count = await frames().timeout(
        remaining.isNegative ? Duration.zero : remaining,
        onTimeout: () => throw TimeoutException(
          'The driven app did not paint its first frame',
          timeout,
        ),
      );
      if (count > 0) return;
      if (!DateTime.now().isBefore(deadline)) {
        throw TimeoutException(
          'The driven app did not paint its first frame',
          timeout,
        );
      }
    } on RPCError catch (error) {
      if (error.code != _methodNotFound || !DateTime.now().isBefore(deadline)) {
        rethrow;
      }
    }
    final remaining = deadline.difference(DateTime.now());
    if (remaining > Duration.zero) {
      const pollInterval = Duration(milliseconds: 50);
      await delay(remaining < pollInterval ? remaining : pollInterval);
    }
  }
}

/// Whether [error] is the VM service disappearing with the driven isolate.
///
/// After [TuiApp.exit], in-flight input RPCs fail this way. That is the
/// app's exit, not a driver fault. The service reports the exit either as
/// the vanished-service code or, when the socket closes while a request is
/// still outstanding, as a disposed connection. `vm_service` raises the
/// latter with the generic server-error code and the disposed-connection
/// message, so both spellings are accepted. Which one arrives depends on
/// timing.
bool isDrivenServiceGone(Object error) {
  if (error is! RPCError) return false;
  if (error.code == RPCErrorKind.kServiceDisappeared.code) return true;
  if (error.code == RPCErrorKind.kConnectionDisposed.code) return true;
  return error.code == RPCErrorKind.kServerError.code &&
      error.message == RPCErrorKind.kConnectionDisposed.message;
}

/// How long input waits for the app to paint before returning.
///
/// Short on purpose: a key an app ignores paints nothing, and charging every
/// such call a long timeout would make a scripted session crawl.
const Duration defaultSettle = Duration(milliseconds: 100);

/// Drives one Noir app process over its `ext.noir.driver.*` surface.
///
/// Input methods return whether the app painted within their settle window.
/// False means no frame arrived in time — which happens both when the app
/// ignored the input and when it is still working on it — so a following
/// [capture] may still show the pre-input frame. When an app can be slow to
/// respond, either raise `settle` or assert through [waitForText] or
/// [waitFor] rather than a bare [capture].
class NoirDriver {
  NoirDriver._({
    required Process process,
    required VmService service,
    required String isolateId,
    required Directory workspace,
    required Future<int> exitCode,
  }) : _process = process,
       _service = service,
       _isolateId = isolateId,
       _workspace = workspace,
       _exitCode = exitCode;

  /// Starts [entryPoint] in drive mode and connects to its VM service.
  ///
  /// [width] and [height] set the emulated terminal size. The child's stdout
  /// and stderr are captured rather than inherited so the driving terminal
  /// stays clean for rendered frames; each line goes to [onAppOutput], which
  /// defaults to a prefixed line on this process's stderr.
  static Future<NoirDriver> launch(
    String entryPoint, {
    int width = 80,
    int height = 24,
    List<String> arguments = const <String>[],
    void Function(String line)? onAppOutput,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final target = File(entryPoint);
    if (!target.existsSync()) {
      throw ArgumentError.value(entryPoint, 'entryPoint', 'No such file');
    }

    final workspace = Directory.systemTemp.createTempSync('noir_drive_');
    final serviceInfo = File('${workspace.path}/service_info.json');
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[
        'run',
        '--enable-vm-service=0',
        '--write-service-info=${serviceInfo.path}',
        target.path,
        ...arguments,
      ],
      environment: <String, String>{
        'NOIR_DRIVE': '1',
        'NOIR_DRIVE_SIZE': '${width}x$height',
      },
    );

    var exited = false;
    final exitCode = process.exitCode.whenComplete(() => exited = true);
    final report = onAppOutput ?? _reportAppOutput;
    for (final stream in <Stream<List<int>>>[process.stdout, process.stderr]) {
      stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(report);
    }

    VmService? service;
    try {
      service = await _connect(serviceInfo, () => exited, timeout);
      final isolateId = (await service.getVM()).isolates!.first.id!;
      final driver = NoirDriver._(
        process: process,
        service: service,
        isolateId: isolateId,
        workspace: workspace,
        exitCode: exitCode,
      );
      await driver._awaitDriverSurface(timeout);
      return driver;
    } on Object {
      await service?.dispose();
      process.kill(ProcessSignal.sigkill);
      await exitCode;
      _deleteWorkspace(workspace);
      rethrow;
    }
  }

  final Process _process;
  final VmService _service;
  final String _isolateId;
  final Directory _workspace;
  final Future<int> _exitCode;

  /// The emulated terminal size and the frames the app has painted.
  Future<({int width, int height, int frames})> info() async {
    final json = await _call('info');
    return (
      width: json['width']! as int,
      height: json['height']! as int,
      frames: json['frames']! as int,
    );
  }

  /// Captures the last rendered frame as text rows plus the cursor.
  Future<DriverFrame> capture() async =>
      DriverFrame.fromJson(await _call('capture'));

  /// Captures the last rendered frame with per-cell colors and attributes.
  Future<DriverFrame> captureCells() async => DriverFrame.fromJson(
    await _call('capture', args: <String, Object?>{'format': 'cells'}),
  );

  /// Fetches a structured element snapshot, unbounded when depth is omitted.
  Future<DriverTree> tree({int? maxDepth}) async {
    final json = await _call(
      'tree',
      args: maxDepth == null
          ? null
          : <String, Object?>{'maxDepth': '$maxDepth'},
    );
    return DriverTree.fromJson(json);
  }

  /// Fetches a fresh tree and returns every exact [locator] match.
  Future<List<DriverNode>> findAll(DriverLocator locator) async =>
      (await tree()).findAll(locator);

  /// Fetches a fresh tree and requires exactly one [locator] match.
  Future<DriverNode> find(DriverLocator locator) async =>
      (await tree()).find(locator);

  /// Polls fresh trees until [locator] resolves to exactly one node.
  Future<DriverNode> waitFor(
    DriverLocator locator, {
    Duration timeout = const Duration(seconds: 5),
  }) => waitForDriverLocator(locator, fetchTree: tree, timeout: timeout);

  /// Polls fresh trees until [locator] has no matches.
  Future<void> waitForAbsent(
    DriverLocator locator, {
    Duration timeout = const Duration(seconds: 5),
  }) => waitForAbsentDriverLocator(locator, fetchTree: tree, timeout: timeout);

  /// Waits for the app to stop scheduling frames.
  ///
  /// This is an explicit idle query. Input and resize settle on a later
  /// frame count instead, because a continuously animating app never goes
  /// quiet. Returns false when [timeout] expires first; capture still works.
  Future<bool> waitStable({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final json = await _call(
      'waitStable',
      args: <String, Object?>{'timeoutMs': '${timeout.inMilliseconds}'},
    );
    return json['stable'] == true;
  }

  /// Polls painted capture rows until one contains [text], then returns that frame.
  ///
  /// This is a painted-frame substring wait, not a [DriverLocator.byText]
  /// lookup. Polling is client-side on purpose: the app side stays a small
  /// set of stateless queries, so a driver can define any wait it needs
  /// without growing the extension surface.
  Future<DriverFrame> waitForText(
    String text, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var frame = await capture();
    while (!frame.contains(text)) {
      if (!DateTime.now().isBefore(deadline)) {
        throw StateError(
          'Timed out waiting for "$text". Last frame:\n'
          '${frame.lines.join('\n')}',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      frame = await capture();
    }
    return frame;
  }

  /// Sends the key [name] and waits up to [settle] for the resulting frame.
  ///
  /// Returns whether a frame arrived. See [defaultSettle] for what a false
  /// return does and does not mean.
  Future<bool> sendKey(String name, {Duration settle = defaultSettle}) =>
      _sendBytes(encodeKey(name), settle);

  /// Types [text] as one UTF-8 byte run and waits up to [settle] for a frame.
  Future<bool> typeText(String text, {Duration settle = defaultSettle}) =>
      _sendBytes(encodeText(text), settle);

  /// Presses and releases [button] at the zero-based cell (x, y).
  Future<bool> click(
    int x,
    int y, {
    DriverMouseButton button = DriverMouseButton.left,
    Duration settle = defaultSettle,
  }) => _sendBytes(encodeClick(x, y, button: button), settle);

  /// Re-resolves [locator], then clicks its current visible hit-tested point.
  Future<bool> clickLocator(
    DriverLocator locator, {
    DriverMouseButton button = DriverMouseButton.left,
    Duration settle = defaultSettle,
  }) async {
    var painted = false;
    await clickDriverLocator(
      locator,
      fetchTree: tree,
      click: (point) async {
        painted = await click(point.x, point.y, button: button, settle: settle);
      },
    );
    return painted;
  }

  /// Sends one wheel notch in [direction] at the zero-based cell (x, y).
  Future<bool> scroll(
    int x,
    int y,
    DriverScrollDirection direction, {
    Duration settle = defaultSettle,
  }) => _sendBytes(encodeScroll(x, y, direction), settle);

  /// Resizes the emulated terminal and reports the applied dimensions.
  Future<({int width, int height})> resize(int width, int height) async {
    final json = await _call(
      'resize',
      args: <String, Object?>{'width': '$width', 'height': '$height'},
    );
    final frameBaseline = json['frames']! as int;
    await pollFrameAdvance(frames: _frames, before: frameBaseline);
    return (width: json['width']! as int, height: json['height']! as int);
  }

  /// Rebuilds the whole widget tree through `ext.noir.reassemble`.
  Future<bool> reassemble() async {
    final response = await _service.callServiceExtension(
      'ext.noir.reassemble',
      isolateId: _isolateId,
    );
    return response.json?['reassembled'] == true;
  }

  /// Swaps edited sources into the live isolate, then rebuilds the tree.
  ///
  /// A rejected swap leaves the app running on its last good sources, so the
  /// recovery path is to fix the file and reload again.
  ///
  /// With no watcher to judge timestamps, the driver forces recompilation so
  /// the VM cannot skip a stale-timestamped edit and report success anyway.
  Future<({bool reloaded, bool reassembled, String? message})> reload() async {
    final ReloadReport report;
    try {
      report = await _service.reloadSources(_isolateId, force: true);
    } on RPCError catch (error) {
      return (
        reloaded: false,
        reassembled: false,
        message: error.details ?? error.message,
      );
    }
    if (report.success != true) {
      return (reloaded: false, reassembled: false, message: '$report');
    }
    final reassembled = await reassemble();
    return (reloaded: true, reassembled: reassembled, message: null);
  }

  /// The driven process's exit code, once it has ended.
  Future<int> waitForExit() => _exitCode;

  /// Asks the app to shut down, then returns its exit code.
  ///
  /// A request that fails means the app cannot acknowledge, so it is killed
  /// instead. Drive mode holds the isolate open with a keep-alive timer, so
  /// waiting on an app that will never quit itself would hang the driver.
  Future<int> quit() async {
    try {
      await _call('quit');
    } on Object {
      _process.kill(ProcessSignal.sigkill);
    }
    return _finish();
  }

  /// Kills the app process, then returns its exit code.
  Future<int> kill() {
    _process.kill(ProcessSignal.sigkill);
    return _finish();
  }

  Future<bool> _sendBytes(List<int> bytes, Duration settle) async {
    final response = await _call(
      'sendBytes',
      args: <String, Object?>{'bytes': base64Encode(bytes)},
    );
    final frameBaseline = response['frames']! as int;
    // Wait for a paint, not for the scheduler to go idle. A pulsing app
    // never reports stable. If the input ended the app, the service is
    // gone and there will never be another frame.
    try {
      return await pollFrameAdvance(
        frames: _frames,
        before: frameBaseline,
        cap: settle,
      );
    } on Object catch (error) {
      if (isDrivenServiceGone(error)) {
        return false;
      }
      rethrow;
    }
  }

  Future<int> _frames() async => (await info()).frames;

  Future<Map<String, dynamic>> _call(
    String method, {
    Map<String, Object?>? args,
  }) async {
    final response = await _service.callServiceExtension(
      'ext.noir.driver.$method',
      isolateId: _isolateId,
      args: args,
    );
    final json = response.json;
    if (json == null || json['type'] != 'Success') {
      throw StateError('ext.noir.driver.$method failed: $json');
    }
    return json;
  }

  Future<void> _awaitDriverSurface(Duration timeout) =>
      awaitDriverReady(frames: _frames, timeout: timeout);

  Future<int> _finish() async {
    try {
      await _service.dispose();
    } on Object {
      // A socket dropped by the exiting app is not a driver failure.
    }
    final code = await _exitCode;
    _deleteWorkspace(_workspace);
    return code;
  }
}

/// One captured drive-mode frame.
class DriverFrame {
  /// Holds the captured rows, optional per-cell detail, and cursor snapshot.
  const DriverFrame({
    required this.width,
    required this.height,
    required this.lines,
    required this.rows,
    required this.cursor,
  });

  /// Reads one `ext.noir.driver.capture` response.
  factory DriverFrame.fromJson(Map<String, dynamic> json) => DriverFrame(
    width: json['width']! as int,
    height: json['height']! as int,
    lines: (json['lines']! as List<Object?>).cast<String>(),
    rows: <List<DriverCell>>[
      for (final row in (json['rows'] as List<Object?>?) ?? const <Object?>[])
        _parseRow(row! as Map<String, Object?>),
    ],
    cursor: DriverCursor.fromJson(json['cursor']! as Map<String, Object?>),
  );

  /// Emulated terminal columns.
  final int width;

  /// Emulated terminal rows.
  final int height;

  /// Right-trimmed text of each row.
  final List<String> lines;

  /// Per-cell detail, empty unless the frame came from [NoirDriver.captureCells].
  final List<List<DriverCell>> rows;

  /// Cursor state observed when the frame was captured.
  final DriverCursor cursor;

  /// Whether any row contains [text].
  bool contains(String text) => lines.any((line) => line.contains(text));

  static List<DriverCell> _parseRow(Map<String, Object?> row) {
    final chars = (row['chars']! as List<Object?>).cast<String>();
    final foregrounds = (row['fg']! as List<Object?>).cast<String>();
    final backgrounds = (row['bg']! as List<Object?>).cast<String>();
    final attributes = (row['attrs']! as List<Object?>).cast<int>();
    return <DriverCell>[
      for (var x = 0; x < chars.length; x++)
        DriverCell(
          char: chars[x],
          foreground: DriverColor.parse(foregrounds[x]),
          background: DriverColor.parse(backgrounds[x]),
          attributes: attributes[x],
        ),
    ];
  }
}

/// One captured terminal cell.
class DriverCell {
  /// Holds one cell's resolved text, colors, and attribute bits.
  const DriverCell({
    required this.char,
    required this.foreground,
    required this.background,
    required this.attributes,
  });

  /// Resolved cell text; empty for the trailing half of a wide grapheme.
  final String char;

  /// Foreground color.
  final DriverColor foreground;

  /// Background color.
  final DriverColor background;

  /// Raw OpenTUI attribute bits.
  final int attributes;
}

/// Cursor state captured alongside a frame.
class DriverCursor {
  /// Holds the cursor's visibility, position, shape, color, and blink state.
  const DriverCursor({
    required this.visible,
    required this.x,
    required this.y,
    required this.style,
    required this.color,
    required this.blinking,
  });

  /// Reads the `cursor` object of a capture response.
  factory DriverCursor.fromJson(Map<String, Object?> json) => DriverCursor(
    visible: json['visible']! as bool,
    x: json['x']! as int,
    y: json['y']! as int,
    style: json['style']! as String,
    color: DriverColor.parse(json['color']! as String),
    blinking: json['blinking']! as bool,
  );

  /// Whether the app showed the cursor.
  final bool visible;

  /// Cursor column, zero-based.
  final int x;

  /// Cursor row, zero-based.
  final int y;

  /// Cursor shape name.
  final String style;

  /// Cursor color.
  final DriverColor color;

  /// Whether the cursor blinks.
  final bool blinking;

  @override
  String toString() => visible
      ? 'cursor visible at ($x,$y) style=$style '
            'color=${color.toAnsiHex()} blinking=$blinking'
      : 'cursor hidden';
}

/// An 8-bit-per-channel color parsed from a capture response.
class DriverColor {
  /// Holds one color's channels in the range 0–255.
  const DriverColor(this.red, this.green, this.blue, this.alpha);

  /// Parses `#rrggbb` or `#rrggbbaa`.
  factory DriverColor.parse(String hex) {
    final digits = hex.startsWith('#') ? hex.substring(1) : hex;
    if (digits.length != 6 && digits.length != 8) {
      throw FormatException('Expected 6 or 8 hex digits, received "$hex"');
    }
    int channel(int index) =>
        int.parse(digits.substring(index * 2, index * 2 + 2), radix: 16);
    return DriverColor(
      channel(0),
      channel(1),
      channel(2),
      digits.length == 8 ? channel(3) : 255,
    );
  }

  /// Red channel, 0–255.
  final int red;

  /// Green channel, 0–255.
  final int green;

  /// Blue channel, 0–255.
  final int blue;

  /// Alpha channel, 0–255.
  final int alpha;

  /// Returns `#rrggbb` for this color.
  String toAnsiHex() =>
      '#${red.toRadixString(16).padLeft(2, '0')}'
      '${green.toRadixString(16).padLeft(2, '0')}'
      '${blue.toRadixString(16).padLeft(2, '0')}';
}

const int _methodNotFound = -32601;

void _reportAppOutput(String line) {
  stderr.writeln('[app] $line');
}

/// Waits for the child VM to publish its service URI, then connects to it.
Future<VmService> _connect(
  File serviceInfo,
  bool Function() exited,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (exited()) {
      throw StateError('The app exited before publishing a VM service URI.');
    }
    final uri = _readServiceUri(serviceInfo);
    if (uri != null) {
      return vmServiceConnectUri(
        convertToWebSocketUrl(serviceProtocolUrl: uri).toString(),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('The app never published ${serviceInfo.path}');
}

Uri? _readServiceUri(File serviceInfo) {
  if (!serviceInfo.existsSync()) {
    return null;
  }
  final contents = serviceInfo.readAsStringSync();
  if (contents.isEmpty) {
    return null;
  }
  try {
    // `--write-service-info` writes `{"uri":"http://host:port/token/"}`.
    final uri = (jsonDecode(contents) as Map<String, Object?>)['uri'];
    return uri is String && uri.isNotEmpty ? Uri.parse(uri) : null;
  } on FormatException {
    // The VM is still writing the file; retry on the next tick.
    return null;
  }
}

void _deleteWorkspace(Directory workspace) {
  try {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  } on FileSystemException {
    // A temp directory that outlives the run is not worth failing over.
  }
}
