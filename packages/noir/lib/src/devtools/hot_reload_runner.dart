import 'dart:convert';
import 'dart:io';

import 'package:noir/src/app/hot_reload_response.dart';
import 'package:vm_service/utils.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _pollInterval = Duration(milliseconds: 400);
const _connectTimeout = Duration(seconds: 30);

/// Runs [target] with development diagnostics kept outside its terminal UI.
Future<int> runWithHotReload(File target, List<String> arguments) async {
  final candidate = File('.dart_tool/noir/run.log').absolute;
  late final File logFile;
  try {
    candidate.parent.createSync(recursive: true);
    candidate.writeAsStringSync('');
    logFile = File(candidate.resolveSymbolicLinksSync());
  } on FileSystemException catch (error) {
    stderr.writeln('Could not create ${candidate.path}: $error');
    return 73;
  }

  stderr.writeln('Noir hot reload diagnostics: ${logFile.path}');
  _log(logFile, 'launching ${target.path}');

  final workspace = Directory.systemTemp.createTempSync('noir_hot_reload_');
  final serviceInfo = File('${workspace.path}/service_info.json');
  final Process child;
  try {
    child = await Process.start(Platform.resolvedExecutable, [
      'run',
      '--enable-vm-service=0',
      '--write-service-info=${serviceInfo.path}',
      target.path,
      ...arguments,
    ], mode: ProcessStartMode.inheritStdio);
  } on ProcessException catch (error) {
    _log(logFile, 'launch failed: $error');
    _deleteWorkspace(workspace, logFile);
    return 70;
  }

  var stopping = false;
  final childExit = child.exitCode.whenComplete(() => stopping = true);
  final interrupts = ProcessSignal.sigint.watch().listen((_) {
    stopping = true;
    child.kill(ProcessSignal.sigint);
  });

  try {
    try {
      final service = await _connect(serviceInfo, () => stopping, logFile);
      if (service != null) {
        try {
          await _watchSources(
            service,
            _watchRoots(target),
            () => stopping,
            logFile,
          );
        } finally {
          await service.dispose();
        }
      }
    } on Object catch (error) {
      _log(logFile, 'hot reload unavailable: $error');
    }
    return await childExit;
  } finally {
    await interrupts.cancel();
    child.kill(ProcessSignal.sigkill);
    _deleteWorkspace(workspace, logFile);
  }
}

Future<VmService?> _connect(
  File serviceInfo,
  bool Function() stopping,
  File logFile,
) async {
  final deadline = DateTime.now().add(_connectTimeout);
  while (!stopping() && DateTime.now().isBefore(deadline)) {
    final uri = _readServiceUri(serviceInfo);
    if (uri != null) {
      final service = await vmServiceConnectUri(
        convertToWebSocketUrl(serviceProtocolUrl: uri).toString(),
      );
      _log(logFile, 'connected to the app VM service');
      return service;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  if (!stopping()) {
    _log(
      logFile,
      'the app published no VM service URI; hot reload is disabled',
    );
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
    final json = jsonDecode(contents);
    if (json is! Map<String, Object?>) {
      return null;
    }
    final uri = json['uri'];
    return uri is String && uri.isNotEmpty ? Uri.parse(uri) : null;
  } on FormatException {
    return null;
  }
}

Future<void> _watchSources(
  VmService service,
  List<Directory> roots,
  bool Function() stopping,
  File logFile,
) async {
  final isolateId = (await service.getVM()).isolates!.first.id!;
  var stamps = _sourceStamps(roots);
  // Rejected edits remain pending even when another file triggers the retry.
  var acceptedStamps = stamps;
  // The VM recompiles a source only when its mtime is newer than the start of
  // its last successful reload, a baseline it first took when the isolate
  // group was created. This one is later, so anything not newer than it is
  // forced rather than trusted to that filter.
  var baseline = DateTime.now();
  _log(logFile, 'watching ${roots.map((root) => root.path).join(', ')}');

  while (!stopping()) {
    await Future<void>.delayed(_pollInterval);
    if (stopping()) {
      return;
    }
    final next = _sourceStamps(roots);
    if (_sameStamps(stamps, next)) {
      continue;
    }
    final stale = _stalePaths(acceptedStamps, next, baseline);
    stamps = next;
    final completed = await _reloadAndReassemble(
      service,
      isolateId,
      logFile,
      staleCount: stale.length,
    );
    if (completed != null) {
      acceptedStamps = next;
      baseline = completed;
    }
  }
}

/// Reloads and reassembles, returning when the VM accepted the sources, or
/// null when it rejected them and therefore kept its previous baseline.
Future<DateTime?> _reloadAndReassemble(
  VmService service,
  String isolateId,
  File logFile, {
  required int staleCount,
}) async {
  final force = staleCount > 0;
  final ReloadReport report;
  try {
    // Without `force`, a stale timestamp makes the VM skip the edit and still
    // report success, so the app would reassemble old code.
    report = await service.reloadSources(isolateId, force: force);
  } on RPCError catch (error) {
    _log(logFile, 'reload rejected: ${error.details ?? error.message}');
    return null;
  }
  final completed = DateTime.now();
  if (report.success != true) {
    _log(logFile, 'reload rejected: $report');
    return null;
  }

  final mode = force
      ? 'forced: $staleCount stale timestamp${staleCount == 1 ? '' : 's'}'
      : 'incremental';
  try {
    final response = await service.callServiceExtension(
      'ext.noir.reassemble',
      isolateId: isolateId,
    );
    if (hotReloadResponseSucceeded(response.json)) {
      _log(logFile, 'reloaded ($mode)');
    } else {
      _log(
        logFile,
        'sources reloaded ($mode), but the app was not reassembled',
      );
    }
  } on RPCError catch (error) {
    _log(
      logFile,
      'sources reloaded ($mode), but ext.noir.reassemble is unavailable '
      '(${error.message})',
    );
  }
  return completed;
}

/// Changed sources whose mtime is not newer than [baseline]. A removed source
/// needs no force: the VM treats a missing file as modified.
List<String> _stalePaths(
  Map<String, _SourceStamp> before,
  Map<String, _SourceStamp> after,
  DateTime baseline,
) {
  final stale = <String>[];
  for (final entry in after.entries) {
    if (before[entry.key] == entry.value) {
      continue;
    }
    if (!entry.value.modified.isAfter(baseline)) {
      stale.add(entry.key);
    }
  }
  return stale;
}

List<Directory> _watchRoots(File target) {
  final roots = <String, Directory>{};
  for (final directory in [Directory('lib'), target.parent]) {
    final absolute = directory.absolute;
    roots.putIfAbsent(absolute.path, () => absolute);
  }
  return roots.values.toList(growable: false);
}

typedef _SourceStamp = ({DateTime modified, int size});

Map<String, _SourceStamp> _sourceStamps(List<Directory> roots) {
  final stamps = <String, _SourceStamp>{};
  for (final root in roots) {
    if (!root.existsSync()) {
      continue;
    }
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        final stat = entity.statSync();
        stamps[entity.absolute.path] = (
          modified: stat.modified,
          size: stat.size,
        );
      }
    }
  }
  return stamps;
}

bool _sameStamps(
  Map<String, _SourceStamp> before,
  Map<String, _SourceStamp> after,
) {
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

void _deleteWorkspace(Directory workspace, File logFile) {
  try {
    if (workspace.existsSync()) {
      workspace.deleteSync(recursive: true);
    }
  } on FileSystemException catch (error) {
    _log(logFile, 'temporary workspace cleanup failed: $error');
  }
}

void _log(File file, String message) {
  final timestamp = DateTime.now().toUtc().toIso8601String();
  try {
    file.writeAsStringSync('[$timestamp] $message\n', mode: FileMode.append);
  } on FileSystemException {
    // Logging must never stop the application the runner owns.
  }
}
