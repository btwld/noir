# Noir

[![pub package](https://img.shields.io/pub/v/noir.svg)](https://pub.dev/packages/noir)
[![CI](https://github.com/btwld/noir/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/btwld/noir/actions/workflows/ci.yml?query=branch%3Amain)
[![BSD-3-Clause license](https://img.shields.io/github/license/btwld/noir)](https://github.com/btwld/noir/blob/main/LICENSE)

A Flutter-like reactive terminal UI framework for Dart, powered by OpenTUI.

- Website and documentation: <https://btwld.github.io/noir/>
- Package: [`noir` on pub.dev](https://pub.dev/packages/noir)

```sh
dart pub add noir
```

## Repository layout

| Path | Contents |
| --- | --- |
| [`packages/noir/`](packages/noir/) | The `noir` package: library, tests, examples, bundled native artifacts, and development tooling in `tool/`. Its [README](packages/noir/README.md) is the package guide. |
| [`packages/noir_signals/`](packages/noir_signals/) | The optional companion package for lifecycle hooks and Signals. |
| [`website/`](website/) | The documentation site. |
| [`skills/`](skills/) | Agent skills for building with Noir and maintaining this repository. |
| [`external/opentui/`](external/opentui/) | The read-only OpenTUI reference submodule. |

The repository is one Pub workspace:

```sh
git clone --recurse-submodules https://github.com/btwld/noir.git
cd noir
dart pub get
cd packages/noir
dart run example/counter.dart
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the required checks and
[GOALS.md](GOALS.md) for the architecture and quality bar.

## License

BSD 3-Clause. See [LICENSE](LICENSE) and
[the third-party notices](packages/noir/THIRD_PARTY_NOTICES.md).
