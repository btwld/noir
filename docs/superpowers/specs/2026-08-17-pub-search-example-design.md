# Pub search example design

## Goal

Add a polished, runnable Noir example that searches live pub.dev data through
`pub_api_client` and presents the selected package in the approved **Quiet
Tabs** interface. The example must also accept an injected fake catalog so its
behavior and rendering remain deterministic in tests.

This is an application-layer example. It does not add widgets, change Noir's
rendering pipeline, or call FFI outside framework-owned code.

## Evidence from the live API

Live requests made on 2026-08-17 established the data boundary:

- Search returns ten package names and an optional next-page URL.
- Package information returns the latest release, every published version,
  archive metadata, and the latest pubspec.
- Separate endpoints return publisher, package options, score/metrics,
  documentation status, and security advisories.
- The raw metrics response includes pub points, likes, 30-day downloads, tags,
  analysis and dartdoc status, weekly download history, derived tags,
  dependency closure, licenses, screenshots, and URL problems. However,
  `pub_api_client` 3.2.0 does not model the raw `weeklyVersionDownloads` field.
  A companion upstream change will add the missing typed model before the Noir
  example consumes it.
- Pubspec fields vary by package, so absent publisher, links, topics,
  platforms, dependencies, and SDK constraints must render honestly rather
  than as empty or invented values.

The example will expose all meaningful package-facing values from those
responses. It will summarize verbose analyzer internals instead of dumping raw
JSON or the full Pana report.

## Dependency boundary

Add `pub_api_client` as a root **git dev dependency** pointing at the upstream
pull-request branch that exposes the missing metrics fields. It is required
only to run and test the source example; Noir's supported runtime dependency
surface must not acquire an HTTP or pub.dev client dependency. The lockfile
records the exact validated commit even though the pubspec names the branch.

The live adapter owns one `PubClient` and closes it deterministically when the
app is disposed. Tests inject a fake implementation and make no network calls.

## Upstream client correction

Before integrating the example, audit current pub.dev read responses against
the public `pub_api_client` models. Add every confirmed missing typed field
needed by this example, starting with `scorecard.weeklyVersionDownloads` and
its total, major-range, minor-range, patch-range, version-range, and newest-date
values. Fields absent from older or third-party pub servers remain nullable or
default empty so the addition is backwards compatible.

The upstream work includes focused failing decode tests, regenerated
`dart_mappable` output, formatting, analysis, and the repository's ordinary
tests. Update public documentation or changelog entries required by that
repository's contributor policy, but do not publish a release. Push the branch
and open a pull request against `leoafarias/pub_api_client`'s default branch.

## Components

### Application-owned catalog contract

`example/pub_search.dart` defines a small `PubCatalog` interface:

- `search(query, page, sort)` returns package names and paging state.
- `loadPackage(name)` returns one immutable package snapshot.
- `close()` releases the underlying client.

`PubApiCatalog` adapts `PubClient` to this contract. Search maps
`SearchResults`; detail loading starts the independent read-only requests
concurrently and combines their results into the application model. The widget
tree never depends directly on generated `pub_api_client` response models.

Application-owned models describe:

- search result names, page, sort, and whether another page exists;
- package identity, description, latest version, publication date, publisher,
  SDK constraint, links, topics, platforms, runtimes, and licenses;
- pub points, likes, and 30-day download count;
- direct and development dependencies;
- versions, retraction state, documentation status, and archive URL/hash;
- discontinued, replacement, and unlisted state;
- advisories and summarized analysis, dartdoc, URL, license, and download
  health available from the client's typed models.

### Stateful application shell

`PubSearchApp` owns the `PubCatalog`, `TextEditingController`, focus nodes, and
scroll controllers. It disposes every owned object. A monotonically increasing
request generation prevents a stale search or package response from replacing
newer user intent. Every async completion checks both `mounted` and generation
before calling `setState`.

The application has explicit idle, loading, results, detail, and error states.
Search text and the last successful results survive a recoverable error.

### Quiet Tabs presentation

The UI uses two calm full-screen views rather than a dense dashboard.

The search view contains:

- a restrained PUB header and live/offline status;
- one prominent `TextInput` with examples of pub.dev query expressions;
- generously spaced package names in a `Select`;
- sort and page context without extra panels;
- a one-line keyboard help footer.

Confirming a package opens its detail view. The detail header shows package
name, latest version, description, install command, and three headline metrics.
Below it, four tabs divide the remaining data:

1. **Overview** — publisher, SDK, topics, platforms, runtimes, license, links,
   and publication date.
2. **Versions** — all returned releases with published, retracted, and
   documentation status.
3. **Dependencies** — direct and development dependency constraints, followed
   by the transitive dependency closure when available.
4. **Health** — points, analysis/dartdoc state, visibility/discontinuation,
   advisories, URL/license findings, archive metadata, the available 30-day
   download count, metrics timestamp, and compact weekly download history.

Only the active tab's content is mounted in a vertical `ScrollBox`, preserving
whitespace and avoiding a wall of metadata. Missing fields render as concise
`Not provided` labels. Error, loading, and empty states occupy the content area
without changing the overall frame.

## Interaction contract

- The initial query is `noir` and runs automatically, giving the example a
  useful first frame while remaining editable.
- Typing in the search field and pressing Enter starts a fresh search.
- Tab moves between the search field and results; Select's built-in arrows,
  paging keys, Enter, and click behavior remain authoritative.
- Confirming a result loads and opens package detail.
- Left/Right or number keys 1–4 switch detail tabs.
- Up/Down, PageUp/PageDown, Home/End, and the mouse wheel scroll active detail
  content through `ScrollBox`.
- Escape returns from detail to results. On the search view, Escape invokes the
  injected quit callback. Unconsumed Ctrl+C retains Noir's normal cleanup.
- Mouse reporting is enabled once by the real entrypoint for result clicks and
  scrolling. Movement reporting is not enabled.

No app-priority bare-letter handler is registered, so search text remains fully
typeable.

## Error handling

The live adapter converts client failures into a concise application error with
an operation label. The UI never prints credentials, response bodies, or stack
traces. It offers a retry for the current search or selected package and keeps
the previous usable state visible where possible.

An empty trimmed query is rejected locally. An empty result set gets a dedicated
message and leaves the search field focused. A missing optional metrics response
does not fail package detail; unavailable sections render their absent state.

## Testing

Implementation follows red-green-refactor.

- Plain model and fake-catalog tests cover mapping, missing optional fields,
  stale-request suppression, paging, and errors.
- Upstream `pub_api_client` tests prove the live metrics shape decodes weekly
  totals and version-range series while older payloads remain compatible.
- `createTuiTestApp` tests cover the parser-backed flow from initial search to
  result confirmation, detail loading, tab switching, returning to results,
  retry, and quit behavior.
- A visual golden captures a populated Quiet Tabs detail frame with buffer,
  style, and cursor sidecars.
- Source assertions cover mouse enablement and the example's documented run
  command only where runtime testing cannot observe the real entrypoint.
- All tests close app/catalog/controllers in the ownership layer that created
  them.

## Documentation and Noir skill review

Add the example to the root and example catalogs. Update the Noir skill's
example list and state guidance with the verified async pattern used here:
inject application data sources, guard async completions with `mounted` and a
request generation, render explicit loading/error states, and close owned
clients. The skill's existing layout, focus, input-order, and disposal guidance
otherwise remains authoritative and requires no compatibility workaround.

## Expected Noir files

- `pubspec.yaml` and `pubspec.lock`
- `example/pub_search.dart`
- `example/pub_search/models.dart`
- `example/pub_search/catalog.dart`
- `example/pub_search/app.dart`
- `example/pub_search/package_detail.dart`
- `test/example/pub_search_catalog_test.dart`
- `test/example/pub_search_test.dart`
- `test/golden/pub_search_golden_test.dart`
- `test/goldens/pub_search_detail.buffer.txt`
- `test/goldens/pub_search_detail.styles.txt`
- `test/goldens/pub_search_detail.cursor.txt`
- `example/README.md`
- `README.md`
- `skills/noir/SKILL.md`
- `skills/noir/references/state-and-animation.md`

## Expected upstream files

Exact paths follow the upstream repository's conventions, and include:

- `lib/src/models/package_score_card.dart`
- the corresponding generated `dart_mappable` mapper
- a focused model test and live metrics integration assertion
- changelog or public documentation when required by upstream policy

## Verification

Run the focused example and golden tests first, followed by the authorized
format, strict analysis, architecture, and ordinary test suites. Verify the
native manifest and finish with `git diff --check`. Do not start a real terminal
session or perform release, publication, native-build, crash, or signal tests.

## Non-goals

- Authentication, liking/unliking packages, or any other write operation.
- Rendering the full README, changelog, or hosted API documentation.
- Reproducing pub.dev's web layout or every internal Pana report field.
- Bypassing `pub_api_client` with a second raw HTTP implementation.
- Publishing a new `pub_api_client` or Noir release.
- Adding a general networking abstraction or new Noir framework widget.
