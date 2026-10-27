# Changelog

## 0.0.2

Bounds launch, service requests, and shutdown. It requires `noir: ^0.0.6`,
the version this client is built and tested against.

### Fixed

- `NoirDriver.launch` spends one `timeout` (60 seconds by default) on process
  start, VM-service connection, isolate discovery, and the first frame. When
  launch times out, the caller receives `TimeoutException`; a process or
  connection that arrives afterward is released.
- Each later service request, including input `sendBytes`, `reload`, and
  `reassemble`, is bounded by `requestTimeout` (30 seconds by default). That
  budget is separate from an input method's frame-settle window. Expiry
  throws `TimeoutException` and does not cancel work the app has already
  accepted.
- `quit`, `kill`, and `waitForExit` each spend one `timeout` (10 seconds by
  default). `quit` covers the quit request, connection cleanup, and the exit
  wait together. Expiry throws `TimeoutException`, still requests
  termination, and keeps the workspace until the process exits.
- `NoirDriver.launch` rejects a negative `timeout` or `requestTimeout` with
  `ArgumentError`. A negative `timeout` on `quit`, `kill`, or `waitForExit`
  expires with `TimeoutException`.

### Changed

- Requires `noir: ^0.0.6`, narrowed from `^0.0.5`, to name the Noir this
  client is built and tested against. `^0.0.5` still admits 0.0.6; this
  release states the version that was actually verified.

## 0.0.1

First stable release of `noir_driver`. It requires `noir: ^0.0.5`, the version
this client is built and tested against. The library, public API, and behavior
are unchanged from 0.0.1-alpha.2.

## 0.0.1-alpha.2

### Fixed

- Polling rounds positive fractional-millisecond pauses up to avoid waking
  early; other delays and durations too large to round safely are unchanged.
- `awaitDriverReady` stops probing when its deadline expires. A zero timeout
  still makes the initial probe and accepts an already-ready response.
  Timeout and service-error outcomes are unchanged.

### Changed

- Requires `noir: ^0.0.4`, the version this client is built and tested against.

## 0.0.1-alpha.1

### Fixed

- A client-side wait now ends at its own deadline even when the app stops
  answering. `pollFrameAdvance`, `waitForText`, `waitFor`, and `waitForAbsent`
  spend one budget across every request and every pause, so a response that
  never arrives can no longer keep a wait running indefinitely. Once the
  budget is spent no further request goes out and a late response is ignored,
  though the abandoned request itself is not cancelled. Outcomes are
  unchanged: a settle returns `false`, the locator and text waits throw
  `StateError`, `awaitDriverReady` throws `TimeoutException`, and a service
  error still propagates as itself.
- A wait whose first capture or tree never arrives now says so, instead of
  reporting a "last frame" it never saw.

### Changed

- A zero timeout sends one request and accepts only a response that is
  already available, so it returns immediately rather than blocking until
  that request answers.
- `noir: ^0.0.3`, which is where the drive-mode app half this client talks to
  now lives.

### Added

- `waitForDriverText`, the text wait behind `NoirDriver.waitForText`, exported
  beside `waitForDriverLocator` so it can be exercised against a supplied
  capture function without launching a process.

## 0.0.1-alpha.0

First release of the drive-mode client as its own package.

- `NoirDriver` launches any Noir entry point with `NOIR_DRIVE=1` and drives it
  over `ext.noir.driver.*`: capture frames as text or cells, snapshot the
  element tree, inject keys, text, clicks, and scrolls through the app's
  production ANSI parser, resize, hot reload, and quit.
- `DriverLocator` matches a key, type, source text, or focus exactly, and
  narrows with `descendantOf` and `at`. Strict lookups reject ambiguity, and a
  miss names the stage that emptied it alongside the tree's own inventory.
  Ambiguous ancestors fail lookups and waits rather than falsely satisfying
  an absence check, including when ancestor locators are nested.
- Locator clicks resolve a currently visible hit-tested cell through the
  production render tree, including scroll translation, clipping, and
  occlusion. An offscreen or obscured target fails instead of passing.
- `DriverFrameMatchers` asserts on a captured frame and prints it on failure.
- Input reports whether the app painted inside its settle window, so a slow
  repaint is observable rather than silently raced.
- `dart run noir_driver:drive <entry-point.dart>` drives an app from the
  command line, interactively or from a pipe.

Previously `packages/noir/tool/driver/` and `tool/noir_drive.dart` inside the
Noir repository, where it was excluded from Noir's published archive and so
unavailable to anyone outside a checkout.
