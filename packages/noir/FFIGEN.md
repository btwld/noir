# FFI binding generation

Noir keeps generated bindings separate from the guarded Dart API.

| Output | Configuration | Input |
| --- | --- | --- |
| `lib/src/ffi/generated_bindings.dart` | `ffigen_dynamic.yaml` | `native/opentui_v0_5_1.h` |
| `lib/src/ffi/native_asset_bindings.dart` | `ffigen_native_assets.yaml` | `native/opentui_v0_5_1.h` |

`lib/src/ffi/bindings.dart` owns Dart-side validation and error translation.
`lib/src/ffi/library.dart` owns dynamic-library resolution. Generated files are
implementation details and must not be edited manually.

## Regeneration

The Noir-owned header declares only the canonical v0.5.1 exports selected by
the guarded Dart layer. The pinned Zig source under
`external/opentui/packages/core/src/zig` is the semantic source of truth.
Initialize the submodule before checking a regeneration:

    git submodule update --init --recursive
    dart pub get

Generate one surface at a time:

    dart run ffigen --config ffigen_dynamic.yaml
    dart run ffigen --config ffigen_native_assets.yaml

Then inspect the generated diff. A normal regeneration must not change the
submodule, native libraries, manifest hashes, or provenance URLs.

Verify with:

    dart format --output=none --set-exit-if-changed lib/src/ffi/
    dart analyze --fatal-infos
    dart test test/architecture/native_assets_ownership_test.dart --concurrency=1
    dart test test/ffi_smoke_test.dart test/ffi/upstream_v051_abi_test.dart test/core/buffer_validity_test.dart --concurrency=1

If FFIgen cannot find libclang, provide a local `llvm-path` override without
committing a host-specific path.
