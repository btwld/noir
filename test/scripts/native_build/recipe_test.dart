import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('runner bootstraps certificates from the signed snapshot over HTTP', () {
    final dockerfile = File(
      'scripts/native_build/recipe/Dockerfile',
    ).readAsStringSync();

    expect(
      dockerfile,
      contains(r'http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}'),
    );
    expect(
      dockerfile,
      isNot(
        contains(
          r'https://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}',
        ),
      ),
    );
  });

  test('runner installs the decompressor before extracting Zig', () {
    final dockerfile = File(
      'scripts/native_build/recipe/Dockerfile',
    ).readAsStringSync();

    final xzPackage = dockerfile.indexOf(r'      xz-utils \');
    final zigExtraction = dockerfile.indexOf('tar --extract --xz');

    expect(xzPackage, isNonNegative);
    expect(zigExtraction, isNonNegative);
    expect(xzPackage, lessThan(zigExtraction));
  });

  test('runner recipe pins every network and toolchain input', () {
    final dockerfile = File(
      'scripts/native_build/recipe/Dockerfile',
    ).readAsStringSync();
    final seed = File(
      'scripts/native_build/recipe/seed_zig_cache.sh',
    ).readAsStringSync();

    expect(
      dockerfile,
      contains(
        'debian:bookworm-slim@sha256:'
        '817e6cf99d6fc127ff4ffe8580049b60deba0adfbbb2bd65ddc3ef8fbb7aade0',
      ),
    );
    expect(dockerfile, contains('20260801T000000Z'));
    expect(dockerfile, contains('ca-certificates'));
    expect(dockerfile, contains('minisign'));
    expect(dockerfile, contains('llvm'));
    expect(dockerfile, contains('zig-aarch64-linux-0.14.1.tar.xz'));
    expect(
      dockerfile,
      contains(
        'f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b',
      ),
    );
    expect(
      dockerfile,
      contains('RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U'),
    );
    expect(dockerfile, contains('.tar.xz.minisig'));
    expect(dockerfile, contains('minisign -V'));
    expect(
      dockerfile,
      contains('https://codeberg.org/atman/zg/archive/v0.14.1.tar.gz'),
    );
    expect(dockerfile, isNot(contains('apt-get upgrade')));
    expect(dockerfile, isNot(contains('curl ')));
    expect(dockerfile, isNot(contains('wget ')));

    expect(seed, contains('set -eu'));
    expect(seed, contains('/opt/zig/zig fetch'));
    expect(
      seed,
      contains('zg-0.14.1-oGqU3IQ_tALZIiBN026_NTaPJqU-Upm8P_C7QED2Rzm8'),
    );
    expect(seed, contains('/opt/zig-global-cache'));
  });
}
