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
    stamps = next;
    await _reloadAndReassemble(service, isolateId, logFile);
  }
}

Future<void> _reloadAndReassemble(
  VmService service,
  String isolateId,
  File logFile,
) async {
  final ReloadReport report;
  try {
    report = await service.reloadSources(isolateId);
  } on RPCError catch (error) {
    _log(logFile, 'reload rejected: ${error.details ?? error.message}');
    return;
  }
  if (report.success != true) {
    _log(logFile, 'reload rejected: $report');
    return;
  }

  try {
    final response = await service.callServiceExtension(
      'ext.noir.reassemble',
      isolateId: isolateId,
    );
    if (hotReloadResponseSucceeded(response.json)) {
      _log(logFile, 'reloaded');
    } else {
      _log(logFile, 'sources reloaded, but the app was not reassembled');
    }
  } on RPCError catch (error) {
    _log(
      logFile,
      'sources reloaded, but ext.noir.reassemble is unavailable '
      '(${error.message})',
    );
  }
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
