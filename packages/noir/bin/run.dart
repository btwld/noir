#!/usr/bin/env dart

import 'dart:io';

import 'package:noir/src/devtools/hot_reload_runner.dart';

const _usage = 'Usage: dart run noir:run <entry-point.dart> [app arguments...]';

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

  exitCode = await runWithHotReload(target, arguments.skip(1).toList());
}
