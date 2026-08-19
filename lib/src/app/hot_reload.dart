import 'dart:convert';
import 'dart:developer' as developer;

import 'app.dart';

/// VM-service method a hot-reload driver calls after `reloadSources` succeeds.
const String _reassembleMethod = 'ext.noir.reassemble';

/// The app the registered handler rebuilds. Last registration wins.
TuiApp? _hotReloadApp;

/// Whether this isolate already owns [_reassembleMethod].
///
/// `dart:developer.registerExtension` throws on a duplicate method name, and
/// an isolate can host several apps over its lifetime, so registration is
/// separated from the app it targets.
bool _extensionRegistered = false;

/// Lets a hot-reload driver rebuild [app] over the VM service.
///
/// Call this once from `main()` with the handle [runTuiApp] returned. After a
/// driver's `reloadSources` request succeeds, invoking the `ext.noir.reassemble`
/// service extension calls [TuiApp.reassemble], so edited `build()`,
/// `performLayout`, and `paint` bodies show up on the next frame without
/// restarting the process or recreating any native resource.
///
/// ```dart
/// void main() {
///   final app = runTuiApp(const CounterApp());
///   registerHotReloadExtension(app);
/// }
/// ```
///
/// Calling this again replaces the target app; the underlying registration
/// happens only once per isolate. Shipping the call is harmless: without a
/// running VM service — an ahead-of-time build, for instance — nothing can
/// invoke the extension.
///
/// Source changes the Dart VM cannot swap into a live isolate still need a
/// restart: `main()` bodies, `initState` bodies for already-mounted state,
/// signatures referenced by frames on the stack, enum-to-class conversions,
/// and any change to the bundled OpenTUI native library. Override
/// `State.reassemble()` to re-derive whatever an `initState` body computed
/// from code the reload may have just changed.
void registerHotReloadExtension(TuiApp app) {
  _hotReloadApp = app;
  if (_extensionRegistered) {
    return;
  }
  _extensionRegistered = true;
  developer.registerExtension(_reassembleMethod, _handleReassemble);
}

Future<developer.ServiceExtensionResponse> _handleReassemble(
  String method,
  Map<String, String> parameters,
) async {
  final app = _hotReloadApp;
  var reassembled = false;
  if (app != null) {
    try {
      app.reassemble();
      reassembled = true;
      // ignore: avoid_catching_errors
    } on StateError {
      // Disposal between the source swap and this callback is a benign race,
      // not a driver fault. `TuiApp` reports it the only way it can — by
      // throwing — so catch it here and report the no-op in `reassembled`
      // rather than failing the RPC.
    }
  }
  return developer.ServiceExtensionResponse.result(
    jsonEncode(<String, Object?>{
      'type': 'Success',
      'reassembled': reassembled,
    }),
  );
}
