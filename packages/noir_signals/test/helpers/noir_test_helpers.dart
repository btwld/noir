/// Checkout-only bridge to the Noir repository's shared test harnesses.
///
/// The companion package has no test harness of its own: it reuses
/// `TestElementHost`, `BufferCapture`, and `createTuiTestApp` from the root
/// package by relative path, so there is one implementation and no drift.
/// Those files import Noir's private libraries and only resolve inside this
/// checkout. `.pubignore` keeps `test/` out of the published archive.
library;

export '../../../noir/test/helpers/buffer_capture.dart';
export '../../../noir/test/helpers/test_element_host.dart';
export '../../../noir/test/helpers/tui_test_app.dart';
