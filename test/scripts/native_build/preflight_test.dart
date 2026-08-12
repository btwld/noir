import 'package:test/test.dart';

import '../../../scripts/native_build/preflight.dart';

void main() {
  group('command mode', () {
    test('accepts only the two exact modes', () {
      expect(parseNativeBuildMode(<String>['--plan']), NativeBuildMode.plan);
      expect(
        parseNativeBuildMode(<String>['--execute-native-build']),
        NativeBuildMode.execute,
      );

      for (final invalid in <List<String>>[
        <String>[],
        <String>['--execute'],
        <String>['--plan', '--execute-native-build'],
        <String>['--plan', '--unknown'],
      ]) {
        expect(
          () => parseNativeBuildMode(invalid),
          throwsA(isA<NativeBuildUsageException>()),
          reason: '$invalid must not start a native build',
        );
      }
    });
  });

  group('preflight snapshot', () {
    test('accepts the exact clean and pinned fixture', () {
      expect(
        () => validatePreflightSnapshot(_validSnapshot()),
        returnsNormally,
      );
    });

    test('rejects every repository, pin, cleanliness, and tool drift', () {
      final invalidSnapshots = <PreflightSnapshot>[
        _validSnapshot(repoRootMatches: false),
        _validSnapshot(originUrl: 'https://github.com/leoafarias/noir'),
        _validSnapshot(headContainsPreparation: false),
        _validSnapshot(worktreeClean: false),
        _validSnapshot(recipeCommitted: false),
        _validSnapshot(gitlink: 'bad-pin'),
        _validSnapshot(submoduleHead: 'bad-pin'),
        _validSnapshot(submoduleClean: false),
        _validSnapshot(dockerAvailable: false),
        _validSnapshot(contextIgnored: false),
      ];

      for (final snapshot in invalidSnapshots) {
        expect(
          () => validatePreflightSnapshot(snapshot),
          throwsA(isA<NativeBuildPreflightException>()),
        );
      }
    });
  });
}

PreflightSnapshot _validSnapshot({
  bool repoRootMatches = true,
  String originUrl = requiredNoirOrigin,
  bool headContainsPreparation = true,
  bool worktreeClean = true,
  bool recipeCommitted = true,
  String gitlink = requiredOpenTuiCommit,
  String submoduleHead = requiredOpenTuiCommit,
  bool submoduleClean = true,
  bool dockerAvailable = true,
  bool contextIgnored = true,
}) => PreflightSnapshot(
  repoRootMatches: repoRootMatches,
  originUrl: originUrl,
  headContainsPreparation: headContainsPreparation,
  worktreeClean: worktreeClean,
  recipeCommitted: recipeCommitted,
  gitlink: gitlink,
  submoduleHead: submoduleHead,
  submoduleClean: submoduleClean,
  dockerAvailable: dockerAvailable,
  contextIgnored: contextIgnored,
);
