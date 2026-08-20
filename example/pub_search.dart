// Run with: dart run example/pub_search.dart
import 'package:noir/noir.dart';

import 'pub_search/app.dart';
import 'pub_search/catalog.dart';

export 'pub_search/app.dart';
export 'pub_search/catalog.dart';
export 'pub_search/models.dart';
export 'pub_search/package_detail.dart';

void main() =>
    runTuiApp(PubSearchApp(catalog: PubApiCatalog()), enableMouse: true);
