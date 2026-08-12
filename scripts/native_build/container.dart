import 'plan.dart';

final class ContainerInvocation {
  const ContainerInvocation(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

ContainerInvocation buildTargetContainerInvocation({
  required String imageReference,
  required NativeBuildRoot root,
  required NativeBuildTarget target,
  required String sourcePath,
  required String outputPath,
  required String cachePath,
  required String globalCachePath,
  required int sourceDateEpoch,
}) {
  final command = <String>[
    'umask 022;',
    'exec /opt/zig/zig build install',
    '-Doptimize=ReleaseFast',
    '-Dtarget=${target.zigTargetQuery}',
    '--prefix ${root.prefixPath}',
    '--cache-dir ${root.cacheMount}',
    '--global-cache-dir ${root.globalCacheMount}',
  ].join(' ');
  return ContainerInvocation('docker', <String>[
    'run',
    '--rm',
    '--platform=linux/arm64',
    '--network=none',
    '--cap-drop=ALL',
    '--security-opt',
    'no-new-privileges',
    '--read-only',
    '--hostname',
    'noir-native-build',
    '--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=512m',
    '--tmpfs=/run:rw,noexec,nosuid,nodev,size=16m',
    '--env',
    'TZ=UTC',
    '--env',
    'LANG=C.UTF-8',
    '--env',
    'LC_ALL=C.UTF-8',
    '--env',
    'SOURCE_DATE_EPOCH=$sourceDateEpoch',
    '--mount',
    'type=bind,src=$sourcePath,dst=${root.sourceMount},readonly',
    '--mount',
    'type=bind,src=$outputPath,dst=${root.outputMount}',
    '--mount',
    'type=bind,src=$cachePath,dst=${root.cacheMount}',
    '--mount',
    'type=bind,src=$globalCachePath,dst=${root.globalCacheMount}',
    '--workdir',
    '${root.sourceMount}/packages/core/src/zig',
    imageReference,
    '/bin/sh',
    '-ceu',
    command,
  ]);
}
