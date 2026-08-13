#!/usr/bin/env dart
// Development hot-reload driver for a Noir app.
//
//     dart run scripts/hot_reload_driver.dart example/counter.dart
//
// Starts the app with inherited stdio so the child owns the real terminal, and
// talks to it only over the VM service socket. Every saved `.dart` change under
// `lib/` or the entry point's own directory triggers `reloadSources`; when the
// swap succeeds the driver calls `ext.noir.reassemble`, so the widget tree
// rebuilds and repaints without a restart. A compile error is reported and the
// app keeps running on its last good sources. Ctrl-C stops both processes.
//
// The app opts in once from `main()`:
//
//     final app = runTuiApp(const CounterApp());
//     registerHotReloadExtension(app);
//
// Driver messages go to stderr, which overwrites terminal cells while the app
// holds the alternate screen. Redirect them for a clean view:
//
//     dart run scripts/hot_reload_driver.dart example/counter.dart 2>reload.log
//
// In-process alternative, if you would rather not run a second process: add
// `hotreloader` as a dev dependency and drive the same seam from the app's own
// isolate, still launched with `--enable-vm-service`.
//
//     await HotReloader.create(onAfterReload: (_) => app.reassemble());
//
// This script exists so the package itself needs no such dependency, and so the
// file watcher can never compete with the app for stdin.

import 'dart:convert';
import 'dart:io';

import 'package:noir/src/app/hot_reload_response.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _usage =
    'Usage: dart run scripts/hot_reload_driver.dart <entry-point.dart> '
    '[app arguments...]';
const _pollInterval = Duration(milliseconds: 400);
const _connectTimeout = Duration(seconds: 30);

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }

  final target = File(arguments.first);
  if (!target.existsSync()) {
    stderr.writeln('No such entry point: ${target.path}');
    exitCode = 66;
    return;
  }

  final workspace = Directory.systemTemp.createTempSync('noir_hot_reload_');
  final serviceInfo = File('${workspace.path}/service_info.json');
  final child = await Process.start(Platform.resolvedExecutable, <String>[
    'run',
    '--enable-vm-service=0',
    '--write-service-info=${serviceInfo.path}',
    target.path,
    ...arguments.skip(1),
  ], mode: ProcessStartMode.inheritStdio);

  var stopping = false;
  final interrupts = ProcessSignal.sigint.watch().listen((_) {
    stopping = true;
    child.kill();
  });
  final childExit = child.exitCode.whenComplete(() => stopping = true);

  try {
    final service = await _connect(serviceInfo, () => stopping);
    if (service != null) {
      try {
        await _watchSources(service, _watchRoots(target), () => stopping);
      } finally {
        await service.dispose();
      }
    }
    exitCode = await childExit;
  } finally {
    await interrupts.cancel();
    child.kill(ProcessSignal.sigkill);
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  }
}

/// Waits for the child VM to publish its service URI, then connects to it.
///
/// Returns null when the app stops first or never publishes one, which leaves
/// the app running unmanaged rather than tearing it down.
Future<VmService?> _connect(File serviceInfo, bool Function() stopping) async {
  final deadline = DateTime.now().add(_connectTimeout);
  while (!stopping() && DateTime.now().isBefore(deadline)) {
    final uri = _readServiceUri(serviceInfo);
    if (uri != null) {
      return vmServiceConnectUri(
        convertToWebSocketUrl(serviceProtocolUrl: uri).toString(),
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!stopping()) {
    _log('the app published no VM service URI; hot reload is unavailable');
  }
  return null;
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

/// Polls `.dart` modification stamps under [roots] and reloads on any change.
///
/// Polling keeps the package free of a file-watcher dependency, and a poll
/// interval this coarse costs a directory listing per tick.
Future<void> _watchSources(
  VmService service,
  List<Directory> roots,
  bool Function() stopping,
) async {
  final isolateId = (await service.getVM()).isolates!.first.id!;
  var stamps = _sourceStamps(roots);
  _log(
    'watching ${roots.map((root) => root.path).join(', ')} — '
    'save a .dart file to hot reload',
  );

  while (!stopping()) {
    await Future<void>.delayed(_pollInterval);
    if (stopping()) {
      return;
    }
    final next = _sourceStamps(roots);
    if (_sameStamps(stamps, next)) {
      continue;
    }
    stamps = next;
    await _reloadAndReassemble(service, isolateId);
  }
}

Future<void> _reloadAndReassemble(VmService service, String isolateId) async {
  final ReloadReport report;
  try {
    report = await service.reloadSources(isolateId);
  } on RPCError catch (error) {
    _log('reload rejected: ${error.details ?? error.message}');
    return;
  }
  if (report.success != true) {
    // Where a compile error lands. The app stays alive on its last good
    // sources, so fixing the file and saving again is the whole recovery path.
    _log('reload rejected: $report');
    return;
  }

  try {
    final response = await service.callServiceExtension(
      'ext.noir.reassemble',
      isolateId: isolateId,
    );
    if (hotReloadResponseSucceeded(response.json)) {
      _log('reloaded');
    } else {
      _log(
        'sources reloaded, but the app was not reassembled. '
        'The registered app may already be disposed.',
      );
    }
  } on RPCError catch (error) {
    _log(
      'sources reloaded, but ext.noir.reassemble is unavailable '
      '(${error.message}). Call registerHotReloadExtension(app) in main().',
    );
  }
}

/// The directories whose `.dart` files trigger a reload.
///
/// `lib/` covers the package under development; the entry point's own
/// directory covers single-file targets such as `example/counter.dart`, which
/// is the file an author edits during a manual check.
List<Directory> _watchRoots(File target) {
  final roots = <String, Directory>{};
  for (final directory in <Directory>[Directory('lib'), target.parent]) {
    roots.putIfAbsent(directory.absolute.path, () => directory);
  }
  return roots.values.toList(growable: false);
}

Map<String, DateTime> _sourceStamps(List<Directory> roots) {
  final stamps = <String, DateTime>{};
  for (final root in roots) {
    if (!root.existsSync()) {
      continue;
    }
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        stamps[entity.absolute.path] = entity.statSync().modified;
      }
    }
  }
  return stamps;
}

bool _sameStamps(Map<String, DateTime> before, Map<String, DateTime> after) {
  if (before.length != after.length) {
    return false;
  }
  for (final entry in before.entries) {
    if (after[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

void _log(String message) {
  stderr.writeln('[noir hot reload] $message');
}
