/// Drives a Noir app headlessly, as a real process, over drive mode.
///
/// `NOIR_DRIVE=1` makes `runTuiApp` mount the app into a headless binding that
/// paints into OpenTUI's non-terminal testing renderer and publishes an
/// `ext.noir.driver.*` VM-service surface. That half ships in `package:noir`
/// and needs no change to the app's own `main()`. This package is the client
/// on the other end.
///
/// ```dart
/// final driver = await NoirDriver.launch('example/counter.dart');
/// await driver.clickLocator(const DriverLocator.byKey('increment'));
/// expect(await driver.capture(), DriverFrameMatchers.containsText('1'));
/// await driver.quit();
/// ```
///
/// It needs no TTY and no raw mode: keys and mouse reports are encoded to
/// escape bytes here and injected through the app's production ANSI parser,
/// and locator clicks resolve through the production render tree's hit
/// testing.
///
/// This drives a live app process rather than mounting widgets, so it does not
/// replace Noir's in-process test harnesses. It is also not evidence of
/// raw-mode cleanup or of any particular terminal emulator.
///
/// The `drive` executable exposes the same surface as a line-oriented CLI:
///
/// ```sh
/// dart run noir_driver:drive example/counter.dart --size 100x30
/// ```
library;

export 'src/ansi_keys.dart';
export 'src/driver_matchers.dart';
export 'src/driver_tree.dart';
export 'src/noir_driver.dart';
export 'src/tool_json_output.dart';
