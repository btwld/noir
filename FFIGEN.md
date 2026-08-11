# FFIgen Integration

OpenTUI bindings are generated from the OpenTUI C header used by the Go package and then wrapped by the higher-level Dart API.

## Current File Layout

- `lib/src/ffi/generated_bindings.dart`: auto-generated low-level FFI bindings
- `lib/src/ffi/bindings.dart`: high-level wrapper used by the rest of the Dart codebase
- `lib/src/ffi/library.dart`: dynamic library lookup and loading
- `lib/src/ffi/types.dart`: Dart-side handle and value types
- `pubspec.yaml`: generation config under the `ffigen:` section

There is no separate manual bindings layer in the current repo state.

## Source of Truth

Bindings are generated from:

```text
external/opentui/packages/go/opentui.h
```

That keeps the Dart surface aligned with the checked-in OpenTUI submodule.

## Regenerating Bindings

```bash
dart run ffigen
dart analyze
dart test
```

## Notes

- `generated_bindings.dart` should not be edited manually.
- `bindings.dart` is where Dart-friendly behavior, validation, and convenience wrappers belong.
- If `dart run ffigen` cannot find `libclang`, set `llvm-path` locally for that run, but do not commit a host-specific path.
