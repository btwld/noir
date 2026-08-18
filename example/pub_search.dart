// Run with: dart run example/pub_search.dart
import 'dart:io' as io;

import 'package:noir/noir.dart';

import 'pub_search/app.dart';
import 'pub_search/catalog.dart';

export 'pub_search/app.dart';
export 'pub_search/catalog.dart';
export 'pub_search/models.dart';
export 'pub_search/package_detail.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(PubSearchApp(catalog: PubApiCatalog(), onQuit: quit));
  app.enableMouse();
}
