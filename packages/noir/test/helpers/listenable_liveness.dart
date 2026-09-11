import 'package:noir/noir.dart';

/// Liveness probe: [ChangeNotifier.addListener] throws once `dispose()` ran.
bool isLive(Listenable notifier) {
  try {
    notifier
      ..addListener(_probeListener)
      ..removeListener(_probeListener);
    return true;
    // ignore: avoid_catching_errors
  } on StateError {
    return false;
  }
}

void _probeListener() {}
