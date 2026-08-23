// ignore_for_file: invalid_use_of_visible_for_testing_member
/// Drive mode: a headless, scriptable hosting path for a real Noir app.
///
/// With `NOIR_DRIVE=1` in its environment, [runTuiApp] mounts the app into a
/// headless [TuiBinding] that paints into OpenTUI's non-terminal testing
/// renderer, and publishes an `ext.noir.driver.*` VM-service surface. An
/// external driver process can then read rendered frames, inspect the widget
/// tree, inject input bytes, resize, and quit the app — with no TTY, no raw
/// mode, and no change to the app's own `main()`.
///
/// This is not a widget-test harness. It drives a live app process, reusing
/// the same composition the repository integration harness builds in-process:
/// headless binding, injected testing renderer, and an unstarted
/// [StdinInputDriver] used purely as a byte funnel into the production ANSI
/// parser.
///
/// Known limitations:
///
/// - A continuously animating app never reports `stable: true`; capture keeps
///   working regardless.
/// - An app that ends itself through `TuiApp.exit` ends the session too: the
///   host follows its binding down and the driver sees only the exit code.
/// - `ext.noir.reassemble` inherits the documented [TuiApp.reassemble] limits:
///   `main()` and `initState` bodies are never re-run. Override
///   `State.reassemble()` to refresh values those `initState` bodies computed.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io' as io;

import 'package:meta/meta.dart';

import '../core/buffer.dart';
import '../core/input.dart';
import '../core/renderer.dart';
import '../core/stdin_input_driver.dart';
import '../foundation/first_error.dart';
import '../framework/diagnostics.dart';
import '../framework/element.dart';
import '../framework/key.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import '../rendering/object.dart';
import '../widgets/rich_text.dart';
import '../widgets/text.dart';
import 'app.dart';
import 'hot_reload.dart';
import 'tui_binding.dart';

/// Serialization detail of one captured drive-mode frame.
enum DriverCaptureFormat {
  /// Right-trimmed text rows plus the cursor snapshot.
  text,

  /// Adds per-cell characters, colors, and attributes to the text rows.
  cells,
}

/// Builds the drive-mode host when [environment] asks for it, else null.
///
/// Drive mode is opt-in per process. Without `NOIR_DRIVE=1` this returns null
/// and [runTuiApp] keeps its ordinary terminal path, so shipping the branch
/// costs a map lookup. `NOIR_DRIVE_SIZE=WxH` overrides the emulated terminal
/// size and defaults to 80x24: the driver, not the app, owns the geometry it
/// is emulating. A driver that wants a different size passes `NOIR_DRIVE_SIZE`
/// or calls `ext.noir.driver.resize`.
DriverHost? createDriveModeHost(Map<String, String> environment) {
  if (environment[_driveModeKey] != '1') {
    return null;
  }
  final size = _parseDriveSize(environment[_driveModeSizeKey]);
  return DriverHost.create(width: size.width, height: size.height);
}

/// Hosts the `ext.noir.driver.*` service extensions for one driven app.
///
/// Every extension is a plain method on this class; the `dart:developer`
/// registrations in [start] are thin decode-and-encode glue, which keeps the
/// whole surface testable in-process without a VM service.
final class DriverHost {
  DriverHost._({
    required TuiBinding binding,
    required Renderer renderer,
    required StdinInputDriver inputDriver,
    required void Function(int exitCode) exitProcess,
  }) : _binding = binding,
       _renderer = renderer,
       _inputDriver = inputDriver,
       _exitProcess = exitProcess;

  /// Builds a headless binding painting into a non-terminal testing renderer.
  ///
  /// The testing sink emits no terminal control sequences, so a driven app
  /// leaves the stdio it inherited untouched. The renderer is injected rather
  /// than owned by the binding's session, so this host disposes it.
  factory DriverHost.create({
    required int width,
    required int height,
    @visibleForTesting void Function(int exitCode)? exitProcess,
  }) {
    final renderer = Renderer.create(width, height, testing: true)
      ..setAutoFlush(false);
    try {
      final binding = TuiBinding(
        width: width,
        height: height,
        headless: true,
        renderer: renderer,
      );
      return DriverHost._(
        binding: binding,
        renderer: renderer,
        // Never started: a driven process has no terminal stdin to lease. It
        // exists so injected bytes reach the app through the same ANSI parser
        // a real terminal session feeds.
        inputDriver: StdinInputDriver(binding.inputManager.dispatcher),
        exitProcess: exitProcess ?? io.exit,
      );
    } on Object catch (error, stackTrace) {
      try {
        renderer.dispose();
      } on Object {
        // The construction failure remains primary after rollback.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  static const Duration _keepAliveInterval = Duration(milliseconds: 50);
  static const Duration _stabilityPollInterval = Duration(milliseconds: 25);
  static const Duration _quitDelay = Duration(milliseconds: 50);

  /// Consecutive quiet polls that count as settled.
  ///
  /// One poll is not enough: the ANSI parser holds a lone `ESC` byte for 25 ms
  /// before deciding it is an Escape key, so a single quiet observation can
  /// land in the gap between injection and dispatch.
  static const int _quietPollsRequired = 2;

  final TuiBinding _binding;
  final Renderer _renderer;
  final StdinInputDriver _inputDriver;
  final void Function(int exitCode) _exitProcess;
  Timer? _keepAlive;
  bool _disposed = false;
  bool _exiting = false;
  int _exitStatus = 0;

  /// The binding this host drives.
  TuiBinding get binding => _binding;

  /// Publishes the driver surface and holds the isolate's event loop open.
  ///
  /// A headless session owns no stdin and no signal handler, so without the
  /// keep-alive timer the isolate would drain and exit before a driver could
  /// connect. Registration happens once per isolate — `dart:developer` rejects
  /// a duplicate method name — so a later host only replaces the target.
  void start(TuiApp app) {
    _checkNotDisposed();
    _activeHost = this;
    _keepAlive ??= Timer.periodic(_keepAliveInterval, (_) {});
    registerHotReloadExtension(app);
    if (_extensionsRegistered) {
      return;
    }
    _extensionsRegistered = true;
    developer.registerExtension(_infoMethod, _handleInfo);
    developer.registerExtension(_captureMethod, _handleCapture);
    developer.registerExtension(_treeMethod, _handleTree);
    developer.registerExtension(_sendBytesMethod, _handleSendBytes);
    developer.registerExtension(_resizeMethod, _handleResize);
    developer.registerExtension(_waitStableMethod, _handleWaitStable);
    developer.registerExtension(_quitMethod, _handleQuit);
  }

  /// Reports the emulated terminal size and the frames painted so far.
  Map<String, Object?> info() {
    _checkNotDisposed();
    final buffer = _renderer.debugCurrentBuffer;
    return <String, Object?>{
      'type': 'Success',
      'driveMode': true,
      'width': buffer.width,
      'height': buffer.height,
      'frames': _binding.debugFrameCount,
    };
  }

  /// Snapshots the last rendered frame in the requested [format].
  ///
  /// `lines` is present for both formats because both walk the same cells;
  /// [DriverCaptureFormat.cells] adds the per-cell `rows` a client needs to
  /// reproduce colors and attributes.
  Map<String, Object?> capture({
    DriverCaptureFormat format = DriverCaptureFormat.text,
  }) {
    _checkNotDisposed();
    final withCells = format == DriverCaptureFormat.cells;
    final buffer = _renderer.debugCurrentBuffer;
    final direct = buffer.getDirectAccess();
    final lines = <String>[];
    final rows = <Map<String, Object?>>[];

    for (var y = 0; y < buffer.height; y++) {
      final chars = <String>[
        for (var x = 0; x < buffer.width; x++)
          debugResolveBufferCell(buffer, y * buffer.width + x),
      ];
      lines.add(chars.join().trimRight());
      if (!withCells) {
        continue;
      }
      rows.add(<String, Object?>{
        'chars': chars,
        'fg': <String>[
          for (var x = 0; x < buffer.width; x++)
            direct.getForeground(x, y).toHex(),
        ],
        'bg': <String>[
          for (var x = 0; x < buffer.width; x++)
            direct.getBackground(x, y).toHex(),
        ],
        'attrs': <int>[
          for (var x = 0; x < buffer.width; x++) direct.getAttributes(x, y),
        ],
        'links': <String?>[
          for (var x = 0; x < buffer.width; x++)
            buffer.linkForAttributes(direct.getAttributes(x, y)),
        ],
      });
    }

    return <String, Object?>{
      'type': 'Success',
      'format': format.name,
      'width': buffer.width,
      'height': buffer.height,
      'lines': lines,
      if (withCells) 'rows': rows,
      'cursor': _captureCursor(),
    };
  }

  /// Snapshots the mounted element tree down to optional [maxDepth].
  ///
  /// Omitting [maxDepth] traverses the whole tree. Focus-descendant flags are
  /// always derived from the complete mounted tree, even when output is
  /// truncated. Each hitPoint is the element's own visible pointer route.
  /// That is a production path target or a visited descendant of one, never
  /// borrowed from an ancestor or descendant. Component widgets may share a
  /// descendant render object through [Element.findRenderObject]; a layout
  /// render object does not inherit a child's hits.
  Map<String, Object?> tree({int? maxDepth}) {
    _checkNotDisposed();
    if (maxDepth != null && maxDepth < 0) {
      throw ArgumentError.value(maxDepth, 'maxDepth', 'must be non-negative');
    }
    final root = WidgetInspectorService.instance.rootElement;
    if (root == null) {
      return <String, Object?>{'type': 'Success', 'root': null};
    }

    final focusManager = _binding.buildOwner.focusManager;
    final focusedSubtrees = HashMap<Element, bool>.identity();
    bool collectFocus(Element element) {
      var containsFocus =
          focusManager.nodeForElement(element)?.hasPrimaryFocus ?? false;
      for (final child in element.children) {
        containsFocus = collectFocus(child) || containsFocus;
      }
      focusedSubtrees[element] = containsFocus;
      return containsFocus;
    }

    collectFocus(root);
    final hitPoints = _visibleHitPoints();
    Map<String, Object?> snapshot(Element element, int depth) {
      final widget = element.widget;
      final key = widget.key;
      final renderObject = element.findRenderObject();
      final point = renderObject == null ? null : hitPoints[renderObject];
      final focusNode = focusManager.nodeForElement(element);
      final includeChildren = maxDepth == null || depth < maxDepth;
      final stringKey =
          key is ValueKey<String> && key.runtimeType == _stringValueKeyType
          ? key.value
          : null;
      return <String, Object?>{
        'type': '${widget.runtimeType}',
        'key': stringKey,
        'text': _driverTextForWidget(widget),
        'focused': focusNode?.hasPrimaryFocus ?? false,
        'hasFocusedDescendant': element.children.any(
          (child) => focusedSubtrees[child] ?? false,
        ),
        'hitPoint': point == null
            ? null
            : <String, Object?>{'x': point.dx, 'y': point.dy},
        'children': <Map<String, Object?>>[
          if (includeChildren)
            for (final child in element.children) snapshot(child, depth + 1),
        ],
      };
    }

    return <String, Object?>{'type': 'Success', 'root': snapshot(root, 0)};
  }

  Map<RenderObject, Offset> _visibleHitPoints() {
    final buffer = _renderer.debugCurrentBuffer;
    final visibleCells = HashMap<RenderObject, List<Offset>>.identity();
    for (var y = 0; y < buffer.height; y++) {
      for (var x = 0; x < buffer.width; x++) {
        final result = _binding.buildOwner.hitTestAt(Offset(x, y));
        if (result == null) continue;
        final cell = Offset(x, y);
        final targets = <RenderObject>[
          for (final entry in result.path)
            if (entry.target case final RenderObject target) target,
        ];
        // Path targets receive events even when they never called
        // recordVisit — custom RenderObject HitTestTargets do that.
        // Visited descendants of those targets share the cell. Ancestors
        // and unvisited nodes do not.
        for (final target in targets) {
          visibleCells.putIfAbsent(target, () => <Offset>[]).add(cell);
        }
        for (final renderObject in result.visitedRenderObjects) {
          if (targets.any((target) => identical(target, renderObject))) {
            continue;
          }
          if (!_hasHitTargetAncestor(renderObject, targets)) continue;
          visibleCells.putIfAbsent(renderObject, () => <Offset>[]).add(cell);
        }
      }
    }

    final points = HashMap<RenderObject, Offset>.identity();
    for (final entry in visibleCells.entries) {
      final cells = entry.value;
      var minX = cells.first.dx;
      var maxX = minX;
      var minY = cells.first.dy;
      var maxY = minY;
      for (final cell in cells.skip(1)) {
        if (cell.dx < minX) minX = cell.dx;
        if (cell.dx > maxX) maxX = cell.dx;
        if (cell.dy < minY) minY = cell.dy;
        if (cell.dy > maxY) maxY = cell.dy;
      }
      final centerX = (minX + maxX) / 2;
      final centerY = (minY + maxY) / 2;
      var best = cells.first;
      var bestDistance = _distanceSquared(best, centerX, centerY);
      for (final cell in cells.skip(1)) {
        final distance = _distanceSquared(cell, centerX, centerY);
        // Cells were collected top-to-bottom, then left-to-right, so keeping
        // the first equal-distance candidate implements the stable tie break.
        if (distance < bestDistance) {
          best = cell;
          bestDistance = distance;
        }
      }
      points[entry.key] = best;
    }
    return points;
  }

  /// Feeds base64-encoded [bytes] through the production ANSI parser.
  ///
  /// Keys and mouse reports are encoded to escape sequences by the driver
  /// client, so the app side stays byte-only and every injected event travels
  /// the parser path a real terminal would use. The response's `frames` value
  /// is captured after dispatch so clients can wait past unrelated animation
  /// frames that painted before this input reached the app.
  Map<String, Object?> sendBytes(String bytes) {
    _checkNotDisposed();
    final decoded = base64Decode(bytes);
    _inputDriver.debugFeedBytes(decoded);
    return <String, Object?>{
      'type': 'Success',
      'bytes': decoded.length,
      'frames': _binding.debugFrameCount,
    };
  }

  /// Resizes the emulated terminal and reports the applied dimensions.
  ///
  /// The response's `frames` value is the post-resize repaint baseline.
  Map<String, Object?> resize(int width, int height) {
    _checkNotDisposed();
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value(
        '${width}x$height',
        'size',
        'width and height must be positive',
      );
    }
    _binding.handleResize(width, height);
    final buffer = _renderer.debugCurrentBuffer;
    return <String, Object?>{
      'type': 'Success',
      'width': buffer.width,
      'height': buffer.height,
      'frames': _binding.debugFrameCount,
    };
  }

  /// Waits until no frame is scheduled, or reports `stable: false` at timeout.
  ///
  /// Awaiting between polls is what lets the app's own frame timers run, so a
  /// driver that calls this after sending input observes the resulting frame.
  Future<Map<String, Object?>> waitStable({int timeoutMs = 2000}) async {
    _checkNotDisposed();
    final deadline = DateTime.now().add(Duration(milliseconds: timeoutMs));
    var quietPolls = 0;
    while (quietPolls < _quietPollsRequired) {
      if (!DateTime.now().isBefore(deadline)) {
        return _stability(stable: false);
      }
      await Future<void>.delayed(_stabilityPollInterval);
      _checkNotDisposed();
      quietPolls = _binding.debugHasScheduledFrame ? 0 : quietPolls + 1;
    }
    return _stability(stable: true);
  }

  /// Acknowledges a quit request, then disposes and exits the process.
  ///
  /// The shutdown is deferred because `exit` gives the VM service no chance to
  /// write this response first; a driver would see a dropped RPC instead of a
  /// clean acknowledgement.
  Map<String, Object?> quit() {
    _checkNotDisposed();
    Timer(_quitDelay, _shutdown);
    return <String, Object?>{'type': 'Success', 'quitting': true};
  }

  /// Ends the driven session after the app requested [code].
  ///
  /// The app has already disposed its binding. Shutdown is deferred like
  /// [quit] so the VM service can finish the RPC that delivered the quit key.
  void handleAppExit(int code) {
    if (_disposed || _exiting) return;
    _exiting = true;
    _exitStatus = code;
    Timer(_quitDelay, _shutdown);
  }

  /// Releases the keep-alive timer, the binding, and the borrowed renderer.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    if (identical(_activeHost, this)) {
      _activeHost = null;
    }
    final keepAlive = _keepAlive;
    _keepAlive = null;
    keepAlive?.cancel();

    final failures = FirstErrorRecorder();
    failures
      ..attempt(_inputDriver.stop)
      ..attempt(_binding.dispose)
      ..attempt(_renderer.dispose)
      ..rethrowFirst();
  }

  Map<String, Object?> _stability({required bool stable}) => <String, Object?>{
    'type': 'Success',
    'stable': stable,
    'frames': _binding.debugFrameCount,
  };

  Map<String, Object?> _captureCursor() {
    final cursor = _binding.buildOwner.cursorController;
    return <String, Object?>{
      'visible': cursor.isVisible,
      'x': cursor.x,
      'y': cursor.y,
      'style': cursor.style.name,
      'color': cursor.color.toHex(),
      'blinking': cursor.blinking,
    };
  }

  void _shutdown() {
    try {
      dispose();
    } finally {
      _exitProcess(_exitStatus);
    }
  }

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError('DriverHost is disposed.');
    }
  }
}

const String _driveModeKey = 'NOIR_DRIVE';
const String _driveModeSizeKey = 'NOIR_DRIVE_SIZE';
const int _defaultDriveWidth = 80;
const int _defaultDriveHeight = 24;

final Type _stringValueKeyType = (const ValueKey<String>(
  '_driver_type_sentinel',
)).runtimeType;

const String _infoMethod = 'ext.noir.driver.info';
const String _captureMethod = 'ext.noir.driver.capture';
const String _treeMethod = 'ext.noir.driver.tree';
const String _sendBytesMethod = 'ext.noir.driver.sendBytes';
const String _resizeMethod = 'ext.noir.driver.resize';
const String _waitStableMethod = 'ext.noir.driver.waitStable';
const String _quitMethod = 'ext.noir.driver.quit';

final RegExp _driveSizePattern = RegExp(r'^(\d+)x(\d+)$');

String? _driverTextForWidget(Widget widget) => switch (widget) {
  Text(:final data, :final textSpan) => data ?? textSpan!.toPlainText(),
  RichText(:final text) => text.toPlainText(),
  _ => null,
};

bool _hasHitTargetAncestor(
  RenderObject candidate,
  Iterable<RenderObject> hitTargets,
) {
  for (final target in hitTargets) {
    if (_isRenderAncestor(target, candidate)) return true;
  }
  return false;
}

bool _isRenderAncestor(RenderObject ancestor, RenderObject node) {
  RenderObject? current = node;
  while (current != null) {
    if (identical(current, ancestor)) return true;
    current = current.parent;
  }
  return false;
}

/// The host the registered handlers target. Last started host wins.
DriverHost? _activeHost;

/// Whether this isolate already owns the `ext.noir.driver.*` method names.
bool _extensionsRegistered = false;

({int width, int height}) _parseDriveSize(String? raw) {
  const fallback = (width: _defaultDriveWidth, height: _defaultDriveHeight);
  if (raw == null) {
    return fallback;
  }
  final match = _driveSizePattern.firstMatch(raw.trim());
  if (match == null) {
    return fallback;
  }
  final width = int.parse(match.group(1)!);
  final height = int.parse(match.group(2)!);
  if (width <= 0 || height <= 0) {
    return fallback;
  }
  return (width: width, height: height);
}

Future<developer.ServiceExtensionResponse> _handleInfo(
  String method,
  Map<String, String> parameters,
) => _run((host) => host.info());

Future<developer.ServiceExtensionResponse> _handleCapture(
  String method,
  Map<String, String> parameters,
) async {
  final requested = parameters['format'] ?? DriverCaptureFormat.text.name;
  final format = DriverCaptureFormat.values.asNameMap()[requested];
  if (format == null) {
    return _invalidParams('Unknown capture format "$requested".');
  }
  return _run((host) => host.capture(format: format));
}

Future<developer.ServiceExtensionResponse> _handleTree(
  String method,
  Map<String, String> parameters,
) async {
  final rawMaxDepth = parameters['maxDepth'];
  final maxDepth = rawMaxDepth == null ? null : int.tryParse(rawMaxDepth);
  if (rawMaxDepth != null && (maxDepth == null || maxDepth < 0)) {
    return _invalidParams('maxDepth must be a non-negative integer.');
  }
  return _run((host) => host.tree(maxDepth: maxDepth));
}

Future<developer.ServiceExtensionResponse> _handleSendBytes(
  String method,
  Map<String, String> parameters,
) async {
  final bytes = parameters['bytes'];
  if (bytes == null) {
    return _invalidParams('bytes is required and must be base64-encoded.');
  }
  return _run((host) => host.sendBytes(bytes));
}

Future<developer.ServiceExtensionResponse> _handleResize(
  String method,
  Map<String, String> parameters,
) async {
  final width = int.tryParse(parameters['width'] ?? '');
  final height = int.tryParse(parameters['height'] ?? '');
  if (width == null || height == null) {
    return _invalidParams('width and height must be integers.');
  }
  if (width <= 0 || height <= 0) {
    return _invalidParams('width and height must be positive.');
  }
  return _run((host) => host.resize(width, height));
}

Future<developer.ServiceExtensionResponse> _handleWaitStable(
  String method,
  Map<String, String> parameters,
) async {
  final timeoutMs = _parseCount(parameters['timeoutMs'], 2000);
  if (timeoutMs == null) {
    return _invalidParams('timeoutMs must be a non-negative integer.');
  }
  return _run((host) => host.waitStable(timeoutMs: timeoutMs));
}

Future<developer.ServiceExtensionResponse> _handleQuit(
  String method,
  Map<String, String> parameters,
) => _run((host) => host.quit());

Future<developer.ServiceExtensionResponse> _run(
  FutureOr<Map<String, Object?>> Function(DriverHost host) handler,
) async {
  final host = _activeHost;
  if (host == null) {
    return _extensionError('No drive-mode host is active.');
  }
  try {
    return developer.ServiceExtensionResponse.result(
      jsonEncode(await handler(host)),
    );
  } on Object catch (error) {
    return _extensionError('$error');
  }
}

int? _parseCount(String? raw, int fallback) {
  if (raw == null) {
    return fallback;
  }
  final value = int.tryParse(raw);
  return value == null || value < 0 ? null : value;
}

double _distanceSquared(Offset point, double x, double y) {
  final dx = point.dx - x;
  final dy = point.dy - y;
  return dx * dx + dy * dy;
}

developer.ServiceExtensionResponse _invalidParams(String message) =>
    developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.invalidParams,
      jsonEncode(<String, Object?>{'type': 'Error', 'message': message}),
    );

developer.ServiceExtensionResponse _extensionError(String message) =>
    developer.ServiceExtensionResponse.error(
      developer.ServiceExtensionResponse.extensionError,
      jsonEncode(<String, Object?>{'type': 'Error', 'message': message}),
    );
