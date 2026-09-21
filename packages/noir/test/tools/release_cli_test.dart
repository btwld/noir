@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

import '../../tool/release/release.dart';

/// The release gate the publish workflow calls.
///
/// These cases are the reason the workflow holds no logic of its own: the
/// ordering rule, the idempotent skip, and the retry all run here on every
/// ordinary CI run rather than first running against a real tag.
void main() {
  group('release tags', () {
    test('a tag names the package and the version it publishes', () {
      final tag = parseReleaseTag('noir-v0.0.3');

      expect(tag.package, 'noir');
      expect(tag.version, Version.parse('0.0.3'));
      expect(tag.toString(), 'noir-v0.0.3');
    });

    test('a prerelease survives the round trip', () {
      final tag = parseReleaseTag('noir_driver-v0.0.1-alpha.1');

      expect(tag.package, 'noir_driver');
      expect(tag.version, Version.parse('0.0.1-alpha.1'));
      expect(
        releaseTagFor(tag.package, tag.version),
        'noir_driver-v0.0.1-alpha.1',
      );
    });

    test('the unprefixed tag this repository used before is rejected', () {
      // `v0.0.2` names no package, so it cannot select one to publish.
      expect(() => parseReleaseTag('v0.0.2'), throwsFormatException);
    });

    test('a prerelease is decided by the version, never by the tag text', () {
      // Every release tag carries a `-` between the package and the version,
      // so the historical `contains(tag, '-')` rule would call every release
      // a prerelease, and a rule looking for `alpha`/`beta`/`dev` would miss
      // `1.0.0-rc.1` and would wrongly flag stable `0.0.3`.
      expect(parseReleaseTag('noir-v0.0.3').version.isPreRelease, isFalse);
      expect(parseReleaseTag('noir-v1.0.0').version.isPreRelease, isFalse);
      expect(parseReleaseTag('noir-v1.0.0-rc.1').version.isPreRelease, isTrue);
      expect(
        parseReleaseTag('noir_driver-v0.0.1-alpha.1').version.isPreRelease,
        isTrue,
      );
    });

    test('a tag with no usable version is rejected', () {
      expect(() => parseReleaseTag('noir-vlatest'), throwsFormatException);
      expect(() => parseReleaseTag('noir'), throwsFormatException);
    });
  });

  group('release readiness', () {
    test('a clean workspace reports nothing', () {
      final workspace = _workspace(_fixture());

      expect(releaseReadinessProblems(workspace), isEmpty);
    });

    test("Dart's caret is not npm's, so ^0.0.2 does admit 0.0.3", () {
      // `pub_semver` raises the minor for a `0.y.z` version, so `^0.0.2` is
      // `>=0.0.2 <0.1.0`. A companion declaring `^0.0.2` beside Noir 0.0.3 is
      // loose, not broken, and this gate must not cry wolf about it.
      expect(
        VersionConstraint.parse('^0.0.2').allows(Version.parse('0.0.3')),
        isTrue,
      );
      expect(
        releaseReadinessProblems(
          _workspace(_fixture(driverNoirConstraint: '^0.0.2')),
        ),
        isEmpty,
      );
    });

    test('a constraint left behind across a minor bump is reported', () {
      // The move that does strand a companion: Noir leaves 0.0.x, and
      // `^0.0.3` stops admitting it.
      final root = _fixture(noirVersion: '0.1.0');

      expect(
        releaseReadinessProblems(_workspace(root)),
        contains(
          allOf(
            contains('packages/noir_driver/pubspec.yaml'),
            contains('dependencies.noir: ^0.0.3'),
            contains('excludes the noir 0.1.0 it is built against'),
          ),
        ),
      );
    });

    test('a constraint ahead of the sibling is reported', () {
      final root = _fixture(driverNoirConstraint: '^0.0.4');

      expect(
        releaseReadinessProblems(_workspace(root)).single,
        allOf(
          contains('dependencies.noir: ^0.0.4'),
          contains('excludes the noir 0.0.3 it is built against'),
        ),
      );
    });

    test(
      'a dev-dependency constraint that excludes the sibling is reported',
      () {
        final root = _fixture(noirDriverDevConstraint: '^0.0.2');

        expect(
          releaseReadinessProblems(_workspace(root)).single,
          allOf(
            contains('dev_dependencies.noir_driver'),
            contains('excludes the noir_driver 0.0.1-alpha.1'),
          ),
        );
      },
    );

    test('a changelog that does not lead with the release is reported', () {
      final root = _fixture(noirChangelog: '# Changelog\n\n## 0.0.2\n\nOld.\n');

      expect(
        releaseReadinessProblems(_workspace(root)).single,
        allOf(
          contains('packages/noir/CHANGELOG.md leads with 0.0.2'),
          contains('not the manifest version 0.0.3'),
        ),
      );
    });

    test('a missing changelog is reported', () {
      final root = _fixture();
      File('${root.path}/packages/noir_signals/CHANGELOG.md').deleteSync();

      expect(
        releaseReadinessProblems(_workspace(root)).single,
        contains('packages/noir_signals has no CHANGELOG.md'),
      );
    });

    test('an external dependency is not mistaken for a sibling', () {
      // `signals_core` is not in the workspace, so its constraint is none of
      // this gate's business.
      final workspace = _workspace(_fixture());

      expect(
        workspace
            .firstWhere((package) => package.name == 'noir_signals')
            .dependencies
            .keys,
        containsAll(<String>['noir', 'signals_core']),
      );
      expect(releaseReadinessProblems(workspace), isEmpty);
    });
  });

  group('publish decision', () {
    test('publishes a version pub.dev does not serve yet', () async {
      final decision = await decidePublish(
        'noir',
        _workspace(_fixture()),
        lookup: _registry({
          'noir': ['0.0.2'],
        }),
      );

      expect(decision.shouldPublish, isTrue);
      expect(decision.isBlocked, isFalse);
      expect(decision.reason, 'publishing noir 0.0.3');
    });

    test('skips a version already on pub.dev, so a retry is a no-op', () async {
      // A tag re-pushed after a half-finished release must not fail the run.
      final decision = await decidePublish(
        'noir',
        _workspace(_fixture()),
        lookup: _registry({
          'noir': ['0.0.2', '0.0.3'],
        }),
      );

      expect(decision.shouldPublish, isFalse);
      expect(decision.isBlocked, isFalse);
      expect(decision.reason, contains('already on pub.dev'));
    });

    test('blocks a companion whose Noir is not published yet', () async {
      final decision = await decidePublish(
        'noir_driver',
        _workspace(_fixture()),
        lookup: _registry({
          'noir': ['0.0.2'],
          'noir_driver': ['0.0.1-alpha.0'],
        }),
      );

      expect(decision.shouldPublish, isFalse);
      expect(decision.isBlocked, isTrue);
      expect(
        decision.blockers.single,
        allOf(
          contains('noir_driver needs noir ^0.0.3'),
          contains('Publish noir first'),
        ),
      );
    });

    test('releases the companion once Noir is served', () async {
      final decision = await decidePublish(
        'noir_driver',
        _workspace(_fixture()),
        lookup: _registry({
          'noir': ['0.0.2', '0.0.3'],
          'noir_driver': ['0.0.1-alpha.0'],
        }),
      );

      expect(decision.shouldPublish, isTrue);
      expect(decision.blockers, isEmpty);
    });

    test('a checkout-only dev dependency is not an ordering edge', () async {
      // Noir dev-depends on noir_driver, and noir_driver depends on Noir.
      // Treating dev dependencies as ordering edges makes that a cycle, which
      // is how `melos publish` ends up offering to publish noir_driver first.
      final decision = await decidePublish(
        'noir',
        _workspace(_fixture()),
        lookup: _registry({
          'noir': ['0.0.2'],
          'noir_driver': ['0.0.1-alpha.0'],
        }),
      );

      expect(decision.shouldPublish, isTrue, reason: 'Noir publishes first');
      expect(decision.blockers, isEmpty);
    });

    test('a package pub.dev has never seen is publishable', () async {
      final decision = await decidePublish(
        'noir',
        _workspace(_fixture()),
        lookup: _registry(const {}),
      );

      expect(decision.shouldPublish, isTrue);
    });
  });

  group('the announcement gate', () {
    test('a version pub.dev serves may be announced', () async {
      expect(
        await isPublished(
          'noir',
          _workspace(_fixture()),
          lookup: _registry({
            'noir': ['0.0.2', '0.0.3'],
          }),
        ),
        isTrue,
      );
    });

    test('a version pub.dev does not serve may not be announced', () async {
      // The case the split workflows allowed: a GitHub release going public
      // while approval was still pending, or after the upload failed.
      expect(
        await isPublished(
          'noir',
          _workspace(_fixture()),
          lookup: _registry({
            'noir': ['0.0.2'],
          }),
        ),
        isFalse,
      );
    });

    test('another version being served is not this version', () async {
      // A newer release must not vouch for an older tag, or the reverse.
      expect(
        await isPublished(
          'noir',
          _workspace(_fixture()),
          lookup: _registry({
            'noir': ['0.0.2', '0.0.4'],
          }),
        ),
        isFalse,
      );
    });

    test('a companion is judged on its own version', () async {
      final workspace = _workspace(_fixture());
      final lookup = _registry({
        'noir': ['0.0.3'],
        'noir_driver': ['0.0.1-alpha.1'],
        'noir_signals': ['0.0.1-alpha.0'],
      });

      expect(
        await isPublished('noir_driver', workspace, lookup: lookup),
        isTrue,
      );
      expect(
        await isPublished('noir_signals', workspace, lookup: lookup),
        isFalse,
        reason: 'noir_signals 0.0.1-alpha.1 is not the alpha.0 on pub.dev',
      );
    });

    test('an empty registry announces nothing', () async {
      expect(
        await isPublished(
          'noir',
          _workspace(_fixture()),
          lookup: _registry(const {}),
        ),
        isFalse,
      );
    });

    test('the gate is not the inverse of the publish decision', () async {
      // Both are false for a blocked companion, so a workflow that reused the
      // publish decision would refuse to announce for the wrong reason — and
      // would announce whenever publishing was merely already done.
      final workspace = _workspace(_fixture());
      final lookup = _registry({
        'noir': ['0.0.2'],
        'noir_driver': ['0.0.1-alpha.1'],
      });

      final decision = await decidePublish(
        'noir_driver',
        workspace,
        lookup: lookup,
      );
      expect(decision.shouldPublish, isFalse, reason: 'blocked on noir');
      expect(
        await isPublished('noir_driver', workspace, lookup: lookup),
        isTrue,
        reason: 'yet this version is genuinely installable',
      );
    });
  });

  group('recording a publication', () {
    test('records what pub.dev serves, not what the manifests claim', () async {
      // A half-finished release leaves the manifests ahead of the registry.
      // Recording from the manifests would label an unpublished version as
      // available; recording from pub.dev cannot.
      final root = _fixture();
      final publication = File('${root.path}/publication.json')
        ..writeAsStringSync(
          '{"noir":"0.0.2",'
          '"noir_driver":"0.0.1-alpha.0","noir_signals":"0.0.1-alpha.0"}',
        );

      final changed = await recordPublication(
        _workspace(root),
        publication,
        lookup: _registry({
          'noir': ['0.0.2', '0.0.3'],
          'noir_driver': ['0.0.1-alpha.0'],
          'noir_signals': ['0.0.1-alpha.0'],
        }),
      );

      expect(changed, ['noir']);
      expect(jsonDecode(publication.readAsStringSync()), {
        'noir': '0.0.3',
        'noir_driver': '0.0.1-alpha.0',
        'noir_signals': '0.0.1-alpha.0',
      });
    });

    test('a matching record is left untouched', () async {
      final root = _fixture();
      const recorded =
          '{"noir":"0.0.3","noir_driver":"0.0.1-alpha.1",'
          '"noir_signals":"0.0.1-alpha.1"}';
      final publication = File('${root.path}/publication.json')
        ..writeAsStringSync(recorded);

      final changed = await recordPublication(
        _workspace(root),
        publication,
        lookup: _registry({
          'noir': ['0.0.3'],
          'noir_driver': ['0.0.1-alpha.1'],
          'noir_signals': ['0.0.1-alpha.1'],
        }),
      );

      expect(changed, isEmpty);
      expect(publication.readAsStringSync(), recorded, reason: 'no rewrite');
    });

    test('an unpublished package records null', () async {
      final root = _fixture();
      final publication = File('${root.path}/publication.json')
        ..writeAsStringSync(
          '{"noir":null,"noir_driver":null,'
          '"noir_signals":null}',
        );

      final changed = await recordPublication(
        _workspace(root),
        publication,
        lookup: _registry(const {}),
      );

      expect(changed, isEmpty);
    });

    test('a stable release outranks an older prerelease', () {
      // `dart pub add` resolves to the newest stable, so the label must too.
      expect(
        latestStableOrPrerelease({
          Version.parse('0.0.2'),
          Version.parse('0.0.3-dev.1'),
        }),
        Version.parse('0.0.2'),
      );
    });

    test('a prerelease wins only when nothing stable has shipped', () {
      expect(
        latestStableOrPrerelease({
          Version.parse('0.0.1-alpha.0'),
          Version.parse('0.0.1-alpha.1'),
        }),
        Version.parse('0.0.1-alpha.1'),
      );
      expect(latestStableOrPrerelease(const <Version>{}), isNull);
    });
  });

  group('registry reads', () {
    test('parses the version list pub.dev returns', () {
      final versions = parsePublishedVersions(
        jsonEncode({
          'name': 'noir',
          'versions': [
            {'version': '0.0.1-alpha.4'},
            {'version': '0.0.2'},
          ],
        }),
      );

      expect(versions, {
        Version.parse('0.0.1-alpha.4'),
        Version.parse('0.0.2'),
      });
    });

    test('a document with no version list is an error, not an empty set', () {
      // Silently reading a malformed body as "nothing is published" would let
      // an ordering blocker through.
      expect(
        () => parsePublishedVersions('{"name":"noir"}'),
        throwsFormatException,
      );
    });

    test('an unknown package is no versions, not a failure', () async {
      final server = await _RegistryServer.start((request) => _notFound);
      addTearDown(server.close);

      await expectLater(
        fetchPublishedVersions(
          'brand_new_package',
          registry: server.registry,
          delay: _noDelay,
        ),
        completion(isEmpty),
      );
      expect(server.requests, 1);
    });

    test('a transient failure is retried and then succeeds', () async {
      var served = 0;
      final server = await _RegistryServer.start((request) {
        served++;
        return served < 3 ? _serverError : _versions(const ['0.0.2']);
      });
      addTearDown(server.close);

      final versions = await fetchPublishedVersions(
        'noir',
        registry: server.registry,
        delay: _noDelay,
      );

      expect(versions, {Version.parse('0.0.2')});
      expect(served, 3, reason: 'two failures, then the answer');
    });

    test(
      'an exhausted retry throws instead of reporting no versions',
      () async {
        // The dangerous failure is a flaky read that reads as "nothing is
        // published", which would wave a dependent package through.
        final server = await _RegistryServer.start((request) => _serverError);
        addTearDown(server.close);

        await expectLater(
          fetchPublishedVersions(
            'noir',
            attempts: 2,
            registry: server.registry,
            delay: _noDelay,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('Could not read pub.dev for noir after 2 attempts'),
            ),
          ),
        );
        expect(server.requests, 2);
      },
    );

    test('the retry delay grows with each attempt', () async {
      final waits = <Duration>[];
      final server = await _RegistryServer.start((request) => _serverError);
      addTearDown(server.close);

      await expectLater(
        fetchPublishedVersions(
          'noir',
          retryDelay: const Duration(seconds: 1),
          registry: server.registry,
          delay: (duration) async => waits.add(duration),
        ),
        throwsStateError,
      );

      expect(waits, const [Duration(seconds: 1), Duration(seconds: 2)]);
    });
  });
}

Future<void> _noDelay(Duration duration) async {}

RegistryLookup _registry(Map<String, List<String>> published) =>
    (package) async => <Version>{
      for (final version in published[package] ?? const <String>[])
        Version.parse(version),
    };

/// A fake pub.dev that counts requests and can fail on demand.
class _RegistryServer {
  _RegistryServer(this._server, this._respond) {
    _server.listen((request) async {
      requests++;
      final response = _respond(request);
      request.response
        ..statusCode = response.status
        ..write(response.body);
      await request.response.close();
    });
  }

  static Future<_RegistryServer> start(
    _Response Function(HttpRequest request) respond,
  ) async => _RegistryServer(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    respond,
  );

  final HttpServer _server;
  final _Response Function(HttpRequest request) _respond;

  /// How many requests reached the server, which is how a retry is observed.
  int requests = 0;

  /// Redirects `pub.dev` to this server without changing the caller's URL.
  /// The base this fake serves on, passed to `fetchPublishedVersions`.
  Uri get registry =>
      Uri.parse('http://${_server.address.host}:${_server.port}');

  Future<void> close() => _server.close(force: true);
}

class _Response {
  const _Response(this.status, this.body);
  final int status;
  final String body;
}

const _notFound = _Response(HttpStatus.notFound, '{}');
const _serverError = _Response(HttpStatus.internalServerError, 'nope');

_Response _versions(List<String> versions) => _Response(
  HttpStatus.ok,
  jsonEncode({
    'versions': [
      for (final version in versions) {'version': version},
    ],
  }),
);

List<ReleasePackage> _workspace(Directory root) => loadWorkspace(root);

/// A three-member workspace shaped like this repository's.
Directory _fixture({
  String noirVersion = '0.0.3',
  String driverNoirConstraint = '^0.0.3',
  String noirDriverDevConstraint = '^0.0.1-alpha.1',
  String? noirChangelog,
}) {
  final root = Directory.systemTemp.createTempSync('noir-release-fixture');
  addTearDown(() => root.deleteSync(recursive: true));

  _write(root, 'pubspec.yaml', '''
name: noir_workspace
publish_to: none

workspace:
  - packages/noir
  - packages/noir_driver
  - packages/noir_signals
''');

  _write(root, 'packages/noir/pubspec.yaml', '''
name: noir
version: $noirVersion
resolution: workspace

dependencies:
  meta: ^1.12.0

dev_dependencies:
  noir_driver: $noirDriverDevConstraint
  test: ^1.25.0
''');
  _write(
    root,
    'packages/noir/CHANGELOG.md',
    noirChangelog ??
        '# Changelog\n\n## $noirVersion\n\nNew.\n\n## 0.0.2\n\nOld.\n',
  );

  _write(root, 'packages/noir_driver/pubspec.yaml', '''
name: noir_driver
version: 0.0.1-alpha.1
resolution: workspace

dependencies:
  noir: $driverNoirConstraint
  vm_service: ^15.2.0
''');
  _write(
    root,
    'packages/noir_driver/CHANGELOG.md',
    '# Changelog\n\n## 0.0.1-alpha.1\n\nNew.\n',
  );

  _write(root, 'packages/noir_signals/pubspec.yaml', '''
name: noir_signals
version: 0.0.1-alpha.1
resolution: workspace

dependencies:
  noir: ^0.0.3
  signals_core: ^7.0.0
''');
  _write(
    root,
    'packages/noir_signals/CHANGELOG.md',
    '# Changelog\n\n## 0.0.1-alpha.1\n\nNew.\n',
  );

  return root;
}

void _write(Directory root, String relative, String contents) {
  final file = File('${root.path}/$relative');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
}
