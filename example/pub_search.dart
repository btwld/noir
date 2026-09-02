// Run with: dart run example/pub_search.dart
// Requires network access. Type at least three characters for completion;
// Enter searches or opens the selected package. Tab crosses the query, sort,
// filter, and results. Sort and filter open with Enter, Space, or a click. From
// the results list, `s` and `f` open them and `n` and `p` change result pages.
//
// Package detail uses Left/Right or 1-4 for sections. The active section
// scrolls with arrows, paging keys, Home/End, or the mouse wheel. `/` returns
// to the query; Escape returns to results and then exits.
import 'package:noir/noir.dart';

import 'src/pub_search/app.dart';
import 'src/pub_search/catalog.dart';

export 'src/pub_search/app.dart';
export 'src/pub_search/catalog.dart';
export 'src/pub_search/models.dart';
export 'src/pub_search/package_detail.dart';

void main() =>
    runTuiApp(PubSearchApp(catalog: PubApiCatalog()), enableMouse: true);
