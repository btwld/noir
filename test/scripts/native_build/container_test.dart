import 'package:test/test.dart';

import '../../../scripts/native_build/container.dart';
import '../../../scripts/native_build/plan.dart';

void main() {
  test('build invocation is hardened, networkless, non-TTY, and isolated', () {
    final root = nativeBuildRoots.singleWhere(
      (candidate) => candidate.label == 'root-a',
    );
    final target = nativeBuildTargets.first;
    final invocation = buildTargetContainerInvocation(
      imageReference: 'noir-native@sha256:1234',
      root: root,
      target: target,
      sourcePath: '/host/run/root-a/opentui',
      outputPath: '/host/run/root-a/output',
      cachePath: '/host/run/root-a/cache',
      globalCachePath: '/host/run/root-a/global-cache',
      sourceDateEpoch: 1779265080,
    );
    final args = invocation.arguments;

    expect(invocation.executable, 'docker');
    expect(
      args,
      containsAllInOrder(<String>[
        'run',
        '--rm',
        '--platform=linux/arm64',
        '--network=none',
      ]),
    );
    expect(
      args,
      containsAll(<String>[
        '--cap-drop=ALL',
        '--security-opt',
        'no-new-privileges',
        '--read-only',
        '--hostname',
        'noir-native-build',
      ]),
    );
    expect(args, isNot(contains('-t')));
    expect(args, isNot(contains('--tty')));
    expect(args, isNot(contains('-i')));
    expect(args.where((arg) => arg.startsWith('--tmpfs=')), hasLength(2));
    expect(args, contains('TZ=UTC'));
    expect(args, contains('LANG=C.UTF-8'));
    expect(args, contains('LC_ALL=C.UTF-8'));
    expect(args, contains('SOURCE_DATE_EPOCH=1779265080'));
    expect(
      args,
      contains(
        'type=bind,src=/host/run/root-a/opentui,'
        'dst=/build/noir-root-a/opentui,readonly',
      ),
    );
    expect(
      args,
      contains(
        'type=bind,src=/host/run/root-a/output,'
        'dst=${root.outputMount}',
      ),
    );
    expect(args.join(' '), contains('--prefix ${root.prefixPath}'));
    expect(args.join(' '), contains('--cache-dir ${root.cacheMount}'));
    expect(
      args.join(' '),
      contains('--global-cache-dir ${root.globalCacheMount}'),
    );
    expect(args.join(' '), contains('-Dtarget=x86_64-linux'));
    expect(args.join(' '), contains('-Doptimize=ReleaseFast'));
    expect(args.join(' '), contains('umask 022'));
  });
}
