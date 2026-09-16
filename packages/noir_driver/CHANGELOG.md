# Changelog

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
