# Phase 8 — Native assets (build hooks + ABI validation)

> **Status:** ✅ DONE
> **Cadence:** per-phase review (M)
> **Depends on:** SDK floor `>=3.10.0` (already landed in Phase 0) and the completed Phase 7 baseline.

## Goal

Ship `libopentui` as a Dart native asset via `hook/build.dart`. The hook uses
bundled-only CodeAsset selection with SHA-256 verification and ABI
validation. A missing library or checksum mismatch means the package is
incomplete or corrupt and fails loudly. `OPENTUI_LIBRARY_PATH` survives only
as the exact development override for a compatible custom library.

## References

- [`GOALS.md`](../GOALS.md) §7 Distribution audit gate
- [`tasks/reference-implementation-plan.md`](./reference-implementation-plan.md) §11 (FFI/native review), §12 (native distribution review)
- Dart docs: build hooks (introduced in Dart 3.10); `CodeAsset` as dynamic-library asset type accessed through `@Native`.

## Surfaces to introduce

- `hook/build.dart` — emits `CodeAsset` for the platform's `libopentui.{dylib|so|dll}`.
- `native_manifest.json` — checked-in registry of binary URLs + SHA-256 per platform/arch.
- `lib/src/ffi/abi.dart` — `OpenTuiNativeAbi(...).validateAbi()` called from
  `OpenTuiNativeLibrary.open()`. Startup reads the first two metadata functions
  below, checks the version, then resolves the canonical 60-export guarded ABI
  inventory by address without invoking feature or error-channel behavior:
  - `uint32_t otui_dart_abi_version(void);`
  - `const char* otui_dart_build_info(void);`
  - `const char* otui_dart_last_error(void);`
  - `void otui_dart_clear_error(void);`
- `OpenTuiAbiMismatchException` — thrown at startup on ABI mismatch with a clear remediation message.
- Native-asset runtime binding strategy — generated/runtime FFI must resolve the bundled `CodeAsset` through Dart native assets (`@Native` / default asset ID or an explicitly documented equivalent) rather than through packaged-root, project-root, `node_modules`, or system-loader fallback search.
- Architecture guard proving the old locator path stays deleted and the FFI export allowlist shrinks.

## Tasks (to be decomposed at architect time)

- [x] **Compatibility drift audit** — recorded to workspace scratch (not retained). Specifically inspect: `lib/src/ffi/library.dart`, `lib/src/ffi/native_library_locator.dart`, `scripts/fetch_opentui_binaries.dart`.
- [x] 8.1 — Add `hooks: any` and `code_assets: any` to `pubspec.yaml` `dependencies:` (per Dart docs, hook helper packages must be in `dependencies`, not `dev_dependencies`).
- [x] 8.2 — `hook/build.dart` MVP: hardcoded for current platform; emits `CodeAsset` pointing at the existing bundled binary using bundled dynamic-library loading.
- [x] 8.3 — Add SHA-256 verification step in the hook against `native_manifest.json`.
- [x] 8.4 — Historical manifest-download work, superseded by `72657aa`, which removed runtime download from the hook.
- [x] 8.5 — Historical source-build fallback work, superseded by `72657aa`, which removed fallback and missing-toolchain behavior from the hook.
- [x] 8.6 — ABI validation: add the four metadata/error entry points to the
  native library/header, regenerate or otherwise cover the bindings, and call
  `validateAbi()` before normal renderer creation. Validation now also resolves
  every address in the canonical 60-export guarded ABI inventory.
- [x] 8.7 — Runtime native-asset binding migration: ensure Dart resolves the bundled `CodeAsset` through `@Native`/default asset ID or an explicitly documented native-assets-compatible equivalent; avoid per-symbol asset-id hardcoding unless the design justifies it.
- [x] 8.8 — Delete the ad-hoc binary locator path (the multi-search-location loader in `native_library_locator.dart`). Keep `OPENTUI_LIBRARY_PATH` env-var as the only dev override.
- [x] 8.9 — Add an architecture guard proving `NativeLibraryLocator`, packaged-root lookup, project-root lookup, `node_modules` lookup, and system-loader fallback do not return as runtime loading paths; shrink `noir_ffi.dart` allowlists accordingly.
- [x] 8.10 — Convert `scripts/fetch_opentui_binaries.dart` into manifest-refresh/verification tooling or remove it from the runtime distribution path.
- [x] 8.11 — Verify the hook-aware AOT CLI bundle correctly includes and loads the native library (`dart build cli`). `dart compile exe` is not the Phase 8 gate because Dart 3.11 documents that it does not run build hooks.

## Hard-rule application

- The manual binary locator path is **deleted**, not preserved as a fallback.
- `OPENTUI_LIBRARY_PATH` survives as the *single* documented override for development.
- System-loader fallback by bare library name is not a supported production path after Phase 8; native assets own bundled loading.

## Audit gate

- [x] Bundled CodeAsset selection works without manual native setup or an `OPENTUI_LIBRARY_PATH` override.
- [x] A missing or tampered bundled asset, including a checksum mismatch, fails loudly as an incomplete or corrupt package.
- [x] AOT CLI bundle (`dart build cli`) includes `bundle/lib/libopentui.*` and loads the bundled library.
- [x] ABI mismatch throws a clear error with the expected vs found version.
- [x] Architecture guard proves the deleted locator and fallback search paths cannot return.
- [x] `dart format` / `dart analyze --fatal-infos` / `dart test test/architecture/` / `dart test` all green.

## What landed

- `hook/build.dart` selects a bundled-only `CodeAsset` target, validates
  `native_manifest.json` against the Dart ABI contract, and SHA-256 verifies
  the selected checked-in library. A missing library or checksum mismatch fails
  loudly as an incomplete or corrupt package.
- Runtime loading now uses generated `@Native` native-asset bindings by
  default, with `OPENTUI_LIBRARY_PATH` retained only as the
  exact development override. The old multi-location locator file and search
  paths were deleted and guarded by architecture tests.
- Manifest URLs are provenance-only metadata for maintainers to refresh the
  checked-in assets; the hook does not use them as runtime recovery paths.
- Commit `72657aa` superseded and removed the historical manifest download and source-build fallback.
- `libopentui` now exposes Dart ABI metadata/error symbols; startup checks the
  ABI version and eagerly resolves the complete 60-export guarded surface by
  address. The Dart, Go, and Bun/OpenTUI reference bindings are aligned to the
  same renderer ABI.
- The checked-in native binaries were rebuilt and recorded in
  `native_manifest.json`.
