# Plan: Root overlay portal and anchored menu

> Add one package-owned root overlay, a narrow Flutter-shaped portal API, and
> an integer-cell `MenuAnchor`, then migrate Pub Search from its centered local
> chooser to a root-hosted anchored menu without crossing Noir's framework or
> native ownership boundaries.

## Decision status and prerequisites

This document is the implementation contract. The companion
`overlay-portal-findings.md` remains useful background, but this plan is
authoritative wherever the two differ.

The design is ready for implementation only after both prerequisites below are
true:

1. **Release boundary:** implement this as post-`0.0.1-alpha.2` work. `TODO.md`
   records an independently reviewed exact alpha.2 candidate; changing that
   tree would invalidate its review and recovery evidence. If the release owner
   instead chooses to include overlays in alpha.2, stop first, reopen the exact
   candidate gates in `TODO.md`, and repeat every candidate-tree verification.
2. **Pub Search dependency:** begin the integrated slice only after the target
   branch contains `example/pub_search/app.dart` and
   `test/example/pub_search_test.dart`. At the 2026-08-21 planning baseline,
   `origin/main` is `cb9ba77` and does not contain those files; they exist on
   descendant branch `origin/feat/pub-search` at `e421f9f`. Recheck the refs at
   execution time. Do not copy a stale snapshot of the example into this work.

Before the resulting tree becomes a publication candidate, relocate this plan
and its findings to the already pub-ignored `docs/` tree, or add equally narrow
`.pubignore` entries. A dry run currently includes both root-level files in the
archive, so leaving them here is not an acceptable package result.

## Objective

- **Primary outcome:** a launcher can open a `Select`-backed menu immediately
  below itself. The menu paints and hit-tests above the whole application,
  follows current whole-cell geometry, avoids terminal edges, and restores the
  launcher's focus when dismissed.
- **Framework outcome:** an overlay child remains a logical descendant of its
  `OverlayPortal` while its single external render edge is owned by the private
  app-root overlay. A shown subtree cannot paint, hit-test, retain focus, or
  remain attached after its portal or any logical ancestor is removed.
- **API outcome:** applications can use the supported subset of
  `OverlayPortalController`, `OverlayPortal`, `MenuController`, and
  `MenuAnchor` with familiar Flutter-shaped call sites and explicit Noir
  differences.
- **Migration outcome:** Pub Search keeps its search, loading, selection,
  refresh, generation-guard, and focus behavior while moving Sort and Filter
  choosers from a centered results-panel `Stack` to launcher-relative menus.
- **Quality outcome:** all public validation works with assertions disabled;
  tests prove ordering and cleanup, not merely successful calls.

Success means all acceptance criteria and authorized checks in this document
pass on one coherent candidate tree.

### Out of scope

- Public `Overlay`, `OverlayState`, or `OverlayEntry` APIs.
- Nested/selectable overlays or Flutter's `OverlayChildLocation`.
- `overlayChildLayoutBuilder`, layout-time widget building, matrix transforms,
  `LayerLink`, or composited-transform APIs.
- Cascading submenus, menu groups, menu bars, animation, Material styling,
  directional text layout, or a new dropdown/select implementation.
- Pointer click-through or a `consumeOutsideTap` option. The first menu contract
  is intentionally modal at render-tree pointer priority.
- Changes to the compositor, FFI, native ABI, bundled libraries,
  `native_manifest.json`, or the read-only OpenTUI gitlink.
- Real-terminal, PTY, raw-mode, or visual-session automation. All required proof
  for this slice is headless.

## Grounded context

- `lib/src/app/app.dart`, `_mount`, is the one high-level wrapper seam used by
  both `runTuiApp` and `mountTuiAppForTesting`. The private overlay belongs
  immediately below `_TuiAppScope` so `TuiApp.of` remains available throughout
  the user's logical tree.
- `lib/src/app/tui_binding.dart`, `TuiBinding._drawFrame`, completes build before
  layout and layout before paint. A root render host can therefore lay out the
  ordinary app first and followers second in the same frame.
- `lib/src/rendering/render_view.dart`, `RenderView`, deliberately remains a
  single-child root and can adopt a non-`RenderBox` child. The new host becomes
  that one child and must preserve advanced custom-root compatibility.
- `lib/src/framework/element.dart`, `Element.insertRenderObjectChild` and
  `removeRenderObjectChild`, already let a private Element route a render edge
  differently from its logical ancestry. `MultiChildRenderObjectElement` is not
  suitable because it assumes every child render box belongs to its own render
  object and synchronizes them as one list.
- `lib/src/framework/owner.dart`, `BuildOwner.deactivateChild`, currently finds
  and detaches only the first render-object edge in a removed logical subtree.
  That is sufficient for a normal render tree but not for a portal edge hosted
  under a different render parent. The lifecycle protocol must be extended
  before a split edge is introduced.
- `lib/src/rendering/object.dart`, `RenderObject.hitTest`, walks children in
  reverse order. A root host that stores base content first and portal entries
  in show order naturally paints bottom-to-top and hit-tests top-to-bottom.
- `lib/src/framework/focus_manager.dart` derives focus ancestry from Element
  ancestry. Keeping the overlay Element below its portal preserves inherited
  widgets, `Actions`, `Shortcuts`, focus scopes, and exact focus restoration.
- `lib/src/core/input.dart` dispatches app handlers at priority 100 and focused
  widget/pointer routing at priority 50. A menu barrier can prevent underlying
  render targets from acting, but it cannot retroactively hide an event from a
  previously invoked `TuiApp.onMouse` callback.
- `lib/src/widgets/pointer_listener.dart` makes a render box a hit-test target
  whenever any pointer callback is installed. A full-terminal barrier therefore
  intercepts every outside pointer event; its close behavior must be defined by
  event kind rather than described as generic click consumption.
- `lib/src/widgets/stack.dart` and `lib/src/rendering/stack.dart` provide useful
  local overlays but cannot escape an ancestor's bounds or clipping.
- `lib/src/widgets/select.dart`, `Select<T>`, already owns the chooser's focus,
  keyboard navigation, scrolling, pointer row mapping, highlighting, and
  confirmation. `MenuAnchor` must compose it rather than duplicate it.
- On `origin/feat/pub-search`, `_buildSearchView` hosts the chooser in a local
  results `Stack`, `_buildChooserOverlay` supplies a full-panel pointer barrier,
  and `_cancelChooser` restores the launcher. The existing test named
  `sort picker overlays mounted results and marks its launcher` expects a click
  on a covered result to do nothing **and leave the chooser open**.
- `lib/noir.dart`, `test/architecture/public_api_test.dart`,
  `test/architecture/public_member_seams_test.dart`, and
  `test/architecture/semantic_public_api_docs_test.dart` curate exports,
  internal seams, signature closure, and authored public documentation.
- `test/helpers/README.md` defines the four existing harnesses used here:
  `WidgetTester`, `BufferCapture`, `KeyDriver`, and `createTuiTestApp`. No new
  harness is required.

### Reference semantics and intentional differences

The supported call shapes are based on Flutter's current `OverlayPortal`,
`OverlayPortalController`, `MenuAnchor`, and `MenuController`, checked at
planning time against the official API documentation:

- <https://api.flutter.dev/flutter/widgets/OverlayPortal/OverlayPortal.html>
- <https://api.flutter.dev/flutter/widgets/OverlayPortalController-class.html>
- <https://api.flutter.dev/flutter/material/MenuAnchor-class.html>
- <https://api.flutter.dev/flutter/widgets/MenuController/open.html>

Noir intentionally differs where terminal constraints or missing subsystems
make Flutter behavior inappropriate. In particular, Noir uses integer-cell
geometry, only the package-owned root overlay, an always-consuming outside
barrier at render-tree priority, no menu animation/style/cascades, and
same-frame repositioning after resize or ancestor movement. Flutter currently
closes an open menu when the view size or anchor scroll position changes; Noir
will follow the anchor instead. This difference must be stated in public docs
and locked by tests.

## Recommended architecture

Install one private root-overlay widget below `_TuiAppScope`. Its render object
remains the single child of `RenderView` and owns:

1. one ordinary base render child, which may be any `RenderObject`; and
2. zero or more portal entry render boxes, stored in show order.

Each `OverlayPortal` retains both its normal child and optional overlay subtree
as logical descendants. A private portal Element routes the normal child's
render edge through its ordinary parent chain and routes one internal,
full-terminal overlay-entry wrapper directly to the private root-overlay
Element. The user-built overlay subtree remains below that wrapper.

The full-terminal wrapper gives every entry terminal constraints and clipping
without making every entry a pointer barrier. A raw `OverlayPortal` delegates
hit testing only to its visible child. `MenuAnchor` uses a private anchored
entry variant that also hit-tests itself outside the menu as the modal barrier.

Before adding that split edge, extend framework deactivation with a private
multi-render-edge protocol. `BuildOwner.deactivateChild` must preflight and
detach every externally hosted edge owned anywhere in the logical subtree as
well as the ordinary root edge, before publishing Element removal. Recursive
`deactivate` and final `unmount` remain exhaustive, idempotent safety nets; they
must not be the first normal opportunity to drop an external edge.

### Alternatives considered

- **Keep a local Pub Search `Stack`:** rejected because it remains clipped and
  sized by the results panel and makes each application reinvent popup
  lifecycle.
- **Register a widget builder in root `State`:** rejected because rebuilding
  the child under the root changes logical ancestry and loses inherited/focus
  semantics.
- **Move the child with a `GlobalKey`:** rejected because Noir deliberately
  rejects cross-parent GlobalKey placement and the move would make lifetime
  ownership harder, not easier.
- **Remove portal edges from `Element.deactivate`:** rejected as the primary
  mechanism because ancestor removal publishes structural deactivation before
  a descendant portal hook runs, violating the existing detach-before-publish
  invariant and weakening failure containment.
- **Sweep stale portal registrations during layout:** rejected because it can
  leave a ghost edge live until a later frame and makes cleanup depend on
  rendering rather than lifecycle ownership.
- **Copy Flutter's full overlay theater/menu system:** rejected because nested
  overlays, transforms, layout-time builders, routes, animation, and cascading
  groups are not needed for the first anchored consumer.
- **Call OpenTUI React `createPortal`:** rejected because it is a TypeScript
  render-tree API outside Noir's Dart Widget/Element/RenderObject and display-
  list/compositor boundary.
- **Add `DropdownSelect<T>` now:** deferred until a second application proves a
  reusable value, labeling, validation, and terminal-style contract.

## Public API contract

Add the following high-level surface through `package:noir/noir.dart`. Omitted
Flutter members and named parameters must fail at compile time; do not accept
and ignore them.

```dart
typedef WidgetBuilder = Widget Function(BuildContext context);

final class OverlayPortalController {
  OverlayPortalController({String? debugLabel});

  bool get isShowing;
  void show();
  void hide();
  void toggle();
}

class OverlayPortal extends StatefulWidget {
  const OverlayPortal({
    Key? key,
    required OverlayPortalController controller,
    required WidgetBuilder overlayChildBuilder,
    Widget? child,
  });
}

typedef MenuAnchorChildBuilder = Widget Function(
  BuildContext context,
  MenuController controller,
  Widget? child,
);

final class MenuController {
  MenuController();

  bool get isOpen;
  void open({Offset? position});
  void close();
  static MenuController? maybeOf(BuildContext context);
}

class MenuAnchor extends StatefulWidget {
  const MenuAnchor({
    Key? key,
    MenuController? controller,
    FocusNode? childFocusNode,
    Offset? alignmentOffset = Offset.zero,
    EdgeInsets? reservedPadding,
    VoidCallback? onOpen,
    VoidCallback? onClose,
    required List<Widget> menuChildren,
    MenuAnchorChildBuilder? builder,
    Widget? child,
  });
}
```

`Offset? alignmentOffset` deliberately matches Flutter's nullable call shape;
Noir treats `null` as `Offset.zero`. `EdgeInsets` is Noir's concrete integer-
cell type rather than Flutter's `EdgeInsetsGeometry` hierarchy.

Do not add `OverlayChildLocation`, `OverlayEntry`, `MenuStyle`, `LayerLink`,
`consumeOutsideTap`, `useRootOverlay`, `crossAxisUnconstrained`, animation
members, cascade methods such as `closeChildren`, or compatibility aliases in
this slice.

### Release-mode validation

- Mounting `OverlayPortal` without the private host installed by `runTuiApp`
  throws a descriptive `StateError` in all build modes. Bare
  `TuiBinding.runApp` remains unchanged for trees that do not use portals.
- One `OverlayPortalController` may be attached to at most one live portal.
  Duplicate live attachment throws before changing either portal.
- One caller-supplied `MenuController` may be attached to at most one live
  `MenuAnchor`. Duplicate live attachment throws before changing either anchor.
- A portal's external entry root must be a framework-owned `RenderBox` wrapper;
  a malformed split edge is rejected before adoption. User overlay content may
  use the ordinary supported widget/render-object protocols beneath it.
- Effective reserved padding must be non-negative. Validate at the public
  widget boundary in release mode rather than relying on `assert` in
  `EdgeInsets`.
- Every failed mount, update, controller replacement, or render adoption leaves
  the previously valid controller, Element, render-parent, pipeline-owner, and
  focus relationships authoritative.

## Controller and subtree lifecycle

### `OverlayPortalController`

| Operation | Required result |
|---|---|
| New controller | `isShowing == false`; `debugLabel` is retained for `toString` diagnostics only. |
| `show()` while unattached | Records pending visibility and makes `isShowing == true`; the next valid attachment shows the child. |
| `hide()` while unattached | Clears pending visibility and makes `isShowing == false`. |
| First `show()` while attached and hidden | Synchronously changes `isShowing` to true and schedules the overlay subtree for the next build. |
| `show()` while already shown | Retains the existing subtree/state, moves its entry to the top, and schedules paint/hit-order invalidation without duplicating it. |
| `hide()` while shown | Synchronously changes `isShowing` to false and schedules removal; finalization disposes the overlay subtree exactly once. |
| Repeated `hide()` | No-op. |
| `toggle()` | Uses the same state transition as `show()` or `hide()` from the current desired state. |
| Controller replaced on one portal | Old controller detaches and resets false; the visible subtree is removed. The new controller's own pending state determines whether a new subtree is built. Visibility/state never transfers between controllers. |
| Controller detached or moved | Resets false; prior shown state does not carry to another portal. A later unattached `show()` creates a new pending request. |
| Portal/ancestor unmounted | External edge is removed before Element removal is published; controller resets false and overlay state/focus are finalized once. |

`overlayChildBuilder` runs during the ordinary build phase only. A hidden portal
does not invoke it. Hiding destroys the built subtree and its `State`; showing
again builds fresh state. Updating the portal while shown retains compatible
Elements normally. Rebuilding or changing inherited values does not reorder the
entry; only `show()` on an already shown controller does.

For a raw `OverlayPortal`, the visible child is laid out at natural size within
loose terminal bounds, positioned at root origin, clipped to the terminal, and
hit-tested only within its own bounds. Anchored placement belongs to
`MenuAnchor`, not to the base portal API.

### `MenuController` and `MenuAnchor`

| Operation | Required result |
|---|---|
| `isOpen` while detached | Returns false. |
| `open()` while detached | Throws a descriptive `StateError` in all build modes; there is no pre-attach pending-open contract for menus. |
| `close()` while detached or already closed | No-op. |
| Closed → `open()` | Sets `isOpen` before invoking `onOpen`; calls `onOpen` exactly once and schedules the menu subtree. |
| `open()` while already open | Updates/clears the optional explicit position, brings the portal to top, and does not recreate state or call `onOpen` again. |
| Open → `close()` | Sets `isOpen` before invoking `onClose`; calls `onClose` exactly once and schedules subtree removal/focus restoration. |
| Controller replaced on the same keyed anchor | Detaches the old controller and attaches the new one while preserving the anchor's current open state, menu subtree, and position; no open/close callback fires. |
| Anchor deactivated/unmounted while open | Removes the menu and marks controllers closed without invoking user callbacks during teardown. |
| `maybeOf(context)` | Returns the nearest logical ancestor anchor's active controller without registering an inherited dependency; otherwise null. |

If no controller is supplied, `MenuAnchor` creates and owns an internal one for
the builder. A supplied controller remains caller-owned; neither controller
form needs a public `dispose` method, but both detach deterministically.

`menuChildren` are composed in document order as an unstyled vertical
`Column` with `MainAxisSize.min`, start cross-axis alignment, and zero implicit
spacing or padding. The caller owns width constraints, borders, background,
and all other terminal chrome. A child selects nothing implicitly: it must call
`MenuController.close()` when confirmation should dismiss the menu.

## Split-render-edge lifecycle protocol

Add a framework-internal, non-exported protocol in
`lib/src/framework/element.dart` that lets an Element report externally hosted
render edges owned by its logical subtree. Integrate it into
`BuildOwner.deactivateChild` in `lib/src/framework/owner.dart`.

The protocol must preserve this sequence:

1. **Preflight without mutation:** validate the logical removal and snapshot
   every external edge owner in the subtree. Each record identifies the child
   render object, expected external parent, and idempotent detach operation.
2. **Validate ownership:** reject duplicate edge records, a missing expected
   parent, a child attached to a different parent, or an edge owned by another
   pipeline before publishing any Element change.
3. **Detach exhaustively:** detach the ordinary first render edge and every
   external edge while old logical parents remain readable. Use the repository's
   first-error containment pattern so one callback cannot prevent cleanup of
   later edges.
4. **Confirm postconditions:** every planned child has `parent == null` (or is
   absent from the expected parent's identity store) before structural
   publication. A callback that throws after completing its detach may be
   deferred; an edge that remains attached is a hard invariant failure.
5. **Publish and deactivate:** only after render cleanup, clear Element
   parent/depth/dirty ownership, recursively call `deactivate`, queue the root
   in inactive elements, and rethrow the first recorded error.
6. **Finalize idempotently:** `unmount` retries safe cleanup, detaches pipeline
   ownership, unregisters controller/overlay bookkeeping, and disposes every
   state/focus owner once even when a lifecycle callback throws.

The private portal Element contributes only its one root-hosted overlay entry
to this protocol. Its normal child continues through the ordinary render edge.
Direct `hide()` removal still calls `BuildOwner.deactivateChild` for the overlay
logical child; ancestor removal discovers the same external edge through the
new subtree preflight. Do not add a second registry of live Elements or expose
this protocol through `noir.dart` or `noir_low_level.dart`.

Failure tests must cover direct hide, direct portal removal, removal of an
ancestor whose first render object is above the portal, mount/update rollback,
and throwing `deactivate`/`dispose` hooks. After every exit path assert:

- no external child remains in root overlay children;
- no removed child has a render parent or `PipelineOwner` after finalization;
- no removed entry paints or receives a hit;
- its focus nodes are detached and cannot remain primary focus;
- controller state is false and user `State.dispose` ran exactly once; and
- the original error remains primary after exhaustive cleanup.

Add an architecture fitness test so future Element owners cannot bypass the
preflight → all-render-edges-detach → structural-publication order.

## Root overlay rendering contract

Create a private root host in `lib/src/rendering/overlay.dart` with a distinct
base slot and identity-ordered portal-entry slots.

- The base slot accepts any `RenderObject`, preserving `RenderView`'s current
  non-box custom-root support. Portal entry roots are `RenderBox` instances.
- The host fills the tight terminal constraints supplied by `RenderView`.
- Layout always visits the base first with the full terminal constraints, then
  visits entry wrappers in show order with tight full-terminal constraints.
- Paint visits the base first, then visible entries in show order. Wrap each
  entry paint in `PaintingContext`/`TuiCanvas.clipRect` for the terminal rect.
- Hit testing visits entries in reverse show order before the base. A hit in the
  top entry stops routing to lower entries and base content.
- `show()` on an already shown portal moves only that identity to the end of the
  entry list. Rebuilds, inherited changes, and layout do not change order.
- Adopt/drop/move operations are identity-based, validate parent and pipeline
  ownership before mutation, and are idempotent only for an already-correct
  state. Invalid cross-parent adoption throws in release mode.
- Removing the base during normal app teardown also drains any residual entry
  registrations as a final safety net, without replacing the portal lifecycle
  protocol as primary owner.

### Current-frame anchor geometry

Noir has no general transform matrix or `localToGlobal` API. Add a private
integer helper that walks a target `RenderBox`'s render parents, summing each
child's `x`/`y`, until it reaches the root overlay base. It returns the target
rect in root terminal coordinates and fails closed if the target is detached,
belongs to another pipeline, or is not below the expected base.

Because the root host lays out the base before entries on every dirty layout
flush, an anchored follower reads the current frame's target size and offsets.
Resize or ancestor movement repositions an open menu in that same frame; it
does not close and does not reuse a previous-frame rectangle.

## Menu placement contract

Resolve placement entirely in integer terminal cells:

1. Resolve effective padding as `reservedPadding ?? EdgeInsets.zero` and
   effective alignment offset as `alignmentOffset ?? Offset.zero`.
2. Deflate the terminal rect by the padding without permitting negative
   extents. For terminal width `w`, use
   `safeLeft = min(padding.left, w)` and
   `safeRight = max(safeLeft, w - padding.right)`; apply the equivalent formula
   to height. Excess padding therefore collapses that safe axis at a
   deterministic edge rather than creating negative constraints.
3. Lay out the unstyled menu column once with loose constraints bounded by the
   safe rect. Oversized content must accept those bounds; the follower clips any
   remaining paint to the safe and terminal rects.
4. Without an explicit position, compute bottom-start from the current anchor:
   `left = anchor.left + offset.dx` and
   `belowTop = anchor.bottom + offset.dy`. The above candidate is
   `anchor.top - menu.height + offset.dy`.
5. With `open(position: p)`, transform `p` from anchor-local to root coordinates
   and ignore `alignmentOffset`, matching Flutter's override rule. Treat the
   root point as the below candidate and `point.dy - menu.height` as the above
   candidate.
6. Prefer below when the full menu fits. Otherwise prefer above when it fits.
   If neither fits, choose the side with more non-negative available rows;
   break a tie in favor of below.
7. Clamp final left and top so the laid-out menu lies inside the safe rect.
   This covers negative offsets, partially offscreen anchors, zero-sized
   terminals, oversized padding, and menus as large as the safe area.

The popup's final render position, paint origin, hit-test coordinates, and
`MouseEvent.localPosition` must all use the same resolved integer offset.

## Input and focus contract

- Escape, Tab, and Shift+Tab on key press close an open menu, consume the key at
  focus priority, and restore focus. Tab traversal does not advance on that
  dismissal event; a later Tab resumes ordinary traversal.
- Opening records the focus-restoration target before menu content autofocuses.
  `childFocusNode` is authoritative when supplied. Otherwise capture
  `FocusManager.primaryFocus` at the accepted closed → open transition.
- Closing requests focus only if the target is still attached to the same
  `FocusManager` and can request focus. Otherwise leave the manager's fallback
  result untouched; never throw merely because the original node disappeared.
- The menu does not choose or focus a menu child automatically. Pub Search's
  existing `Select.autofocus` and chooser `FocusNode` continue to own that.
- A full-terminal entry barrier consumes all pointer events outside the popup
  at pointer-routing priority so they cannot reach lower render targets while
  the menu is open. Only a left-button down closes the top menu; right/middle
  down, button-up, movement, and wheel events are consumed without closing it.
- The outside left-button down is consumed, closes only the topmost open menu,
  and cannot activate the underlying launcher/result in the same event.
- `TuiApp.onMouse` remains app-priority and may already have observed the raw
  event before pointer routing. Public docs must describe consumption as
  preventing lower-priority/render-tree dispatch, not global observation.
- Pointer events inside the menu route normally to its child. They do not close
  the menu unless the child calls `MenuController.close()`.
- Independent `MenuAnchor`s do not form a menu group and do not implicitly
  close one another. Applications coordinate multiple controllers; Pub Search's
  existing chooser state permits only one open chooser.

The Pub Search outside-click behavior is an intentional migration change:
clicking a covered result continues not to load details, but now closes the
chooser. Update the existing test that previously required the chooser to stay
open; do not claim all mouse behavior is unchanged.

## Compatibility and migration

- **Framework compatibility:** additive public API, with one private wrapper on
  the high-level app path. Existing applications should render and route input
  identically when no portal is shown.
- **Advanced-host compatibility:** bare `TuiBinding.runApp` is unchanged and
  does not silently install a host. Existing non-box custom roots under
  `runTuiApp` remain supported through the generic base slot.
- **API compatibility:** only the declared Flutter-shaped subset is supported.
  Constructor/member omissions are compile-time errors, and documented semantic
  differences are intentional prerelease behavior rather than shims.
- **Example migration:** hard-switch the private Pub Search chooser after its
  branch is present. There is no public legacy overlay API to deprecate.
- **Behavior change:** outside left click changes from “blocked and remains
  open” to “blocked, closes, and restores launcher focus.” Keyboard cancellation,
  option selection, requests, loading, and error behavior remain unchanged.
- **Data/native migration:** none. Do not update OpenTUI, native artifacts,
  hashes, URLs, or ABI declarations.
- **Reversibility:** commit-level rollback restores the local Stack chooser and
  removes the additive exports; there is no persisted data to recover.

## Work breakdown

Follow Noir's contributor workflow: audit/contract (this document), focused red
proof, smallest coherent implementation, independent review, then focused →
architecture → full verification.

### 0. Establish an eligible base and clean package boundary

- Recheck `origin/main`, the alpha.2 release state, and the Pub Search branch.
- Base the implementation on a post-alpha.2 target that already contains Pub
  Search. Stop if either prerequisite in this plan is false.
- Relocate the two overlay planning artifacts under `docs/` or add narrow
  `.pubignore` exclusions; verify neither appears in the publish dry-run.
- Record the rechecked branch facts in the implementation review, not as
  permanent claims in user-facing docs.

### 1. Add failing split-edge lifecycle contracts

Create `test/framework/external_render_edge_lifecycle_test.dart` and extend
`test/architecture/render_object_attachment_ownership_test.dart`.

- Model a logical child with one ordinary edge and one external edge.
- Prove direct removal, ancestor removal, incompatible replacement, mount
  rollback, and lifecycle exceptions initially expose the missing cleanup.
- Assert detach-before-publication, exhaustive cleanup, first-error retention,
  idempotent finalization, and no parent/pipeline/focus residue.
- Run only these tests and record that they fail for the intended missing
  multi-edge behavior before changing production code.

### 2. Implement the private multi-edge deactivation protocol

Change `lib/src/framework/element.dart` and
`lib/src/framework/owner.dart`.

- Add the non-exported external-edge ownership/preflight hook.
- Extend the existing deactivation plan to snapshot, validate, detach, and
  verify all external edges before structural publication.
- Preserve current behavior and error ordering for ordinary one-edge trees.
- Keep every new framework member `@internal`/`@protected` as appropriate and
  update `test/architecture/public_member_seams_test.dart` if its exact internal
  allowlist requires it.
- Turn the focused lifecycle tests green before proceeding.

### 3. Add the root render host and entry geometry

Create `lib/src/rendering/overlay.dart` and
`test/rendering/overlay_layout_test.dart`.

- Implement the generic base slot, ordered entry slots, adoption/removal,
  base-first layout, show-order paint, reverse-order hit testing, and clipping.
- Add the full-terminal entry wrapper and private current-root-rect traversal.
- Test raw entry origin/natural sizing, non-box base adoption, empty terminal,
  multiple entry reorder, clipping, current-frame geometry, and failure on an
  anchor outside the expected base/pipeline.
- Keep rendering imports below widgets and FFI: use `PaintingContext` and
  `TuiCanvas`, never `Buffer`.

### 4. Implement `OverlayPortal` and root registration

Create `lib/src/widgets/overlay.dart` and
`test/widgets/overlay_portal_test.dart`.

- Implement controller pending state, diagnostics, exclusive attachment,
  controller replacement, show-to-top, and idempotent hide/toggle behavior.
- Implement the private logical two-child Element and its one external entry
  record without reparenting Elements.
- Prove inherited `Theme`, `Actions`, `Shortcuts`, focus-scope ancestry, normal
  keyed rebuild retention, hide disposal, ancestor teardown, and exception
  rollback.
- Add a release-validation subprocess case for duplicate controllers, missing
  root host, and malformed edge ownership with assertions disabled.

### 5. Install exactly one high-level root overlay

Change `lib/src/app/app.dart` and add/extend the narrow binding tests under
`test/app/` and `test/rendering/single_child_transition_test.dart`.

- Make `_mount` pass
  `_TuiAppScope(handle: handle, child: _RootOverlay(child: app))` to the binding.
- Ensure both `runTuiApp` and `mountTuiAppForTesting` receive one host.
- Prove bare `TuiBinding.runApp` remains host-free, ordinary apps retain their
  output, and a low-level non-box root remains valid beneath the high-level
  wrapper.
- Prove binding disposal drains shown entries even after an injected teardown
  failure.

### 6. Implement `MenuController` and `MenuAnchor`

Create `lib/src/widgets/menu_anchor.dart` and
`test/widgets/menu_anchor_test.dart`.

- Compose the private anchor target, anchored follower, modal pointer barrier,
  `OverlayPortal`, `Focus`, `Shortcuts`, `Actions`, and `DismissIntent`.
- Implement the exact transition/callback, controller replacement,
  `maybeOf`, focus capture/restore, keyboard dismissal, and pointer behavior in
  this contract.
- Implement the placement algorithm exactly once in the render layer; the
  widget layer must not rebuild or compute terminal coordinates during layout.
- Cover bottom-start, alignment offset, explicit-position override, vertical
  flip, both-axes clamp, reserved padding, oversized content/padding, zero-size
  terminal, partial offscreen anchors, same-frame movement/resize, and
  inside/outside hit coordinates.
- Add release-mode validation for detached `open`, duplicate attachment, and
  negative effective padding.

### 7. Migrate Pub Search deliberately

Change `example/pub_search/app.dart` and
`test/example/pub_search_test.dart` after those files are present on the target
branch.

- Give Sort and Filter their own `MenuController`s or use builder-provided
  controllers consistently; keep `_chooser` as the single source of which
  chooser is active.
- Replace only the centered `_buildChooserOverlay` presentation with
  `MenuAnchor + Button + Select`. Retain `_chooserFocus`, `Select.autofocus`,
  highlighted-index initialization, request generation guards, refresh rules,
  active launcher styling, and confirmation callbacks.
- Pass the exact Sort/Filter launcher `FocusNode` as `childFocusNode`.
- Close through `MenuController` from Escape/Tab/outside dismissal and after a
  confirmed value. Avoid competing `_chooser == null` and controller states by
  centralizing open/close synchronization in one pair of state methods.
- Replace the existing “covered result leaves chooser open” expectation with
  the intentional new contract: no detail request, chooser closes, launcher
  regains focus.
- Add coordinate assertions that Sort opens below its launcher, Filter remains
  inside the right safe edge, a short terminal flips above or clamps, movement
  and resize update in the same frame, and results remain mounted underneath.
- Preserve every existing search, paging, suggestion, loading, error, async
  winner, keyboard selection, and 80-column help test except the explicitly
  changed outside-dismissal assertion.

### 8. Export and document only the supported surface

Change `lib/noir.dart`, `README.md`, `CHANGELOG.md`, `example/README.md`,
`skills/noir/SKILL.md`, the relevant files under `skills/noir/references/`, and
the public API architecture tests.

- Export only `WidgetBuilder`, `OverlayPortalController`, `OverlayPortal`,
  `MenuAnchorChildBuilder`, `MenuController`, and `MenuAnchor` from their
  owning files. Do not export the root host, custom Elements, follower, edge
  protocol, or render overlay.
- Add a source-package consumer probe in
  `test/fixtures/source_package_consumer/bin/high_level.dart` that constructs
  the supported signatures from `package:noir/noir.dart` only.
- Document ownership, integer geometry, root-only hosting, state destruction on
  hide, controller rules, modal outside pointer behavior, app-priority mouse
  observation, focus restoration, same-frame following, and every omitted
  Flutter subsystem.
- State the Flutter resize/scroll difference explicitly and avoid “parity” or
  click-through claims.
- Add the feature under the next unreleased version; do not rewrite alpha.2's
  recorded exact-candidate evidence.

### 9. Review, verify, and commit one coherent slice

- Obtain an independent behavior and full-diff review after focused tests are
  green. The reviewer must specifically audit split-edge cleanup, controller
  transition tables, public signature closure, Pub Search's one-state-owner
  migration, and package contents.
- Address review findings, then run the focused, architecture, and full gates
  below in that order.
- Commit only when the public portal, anchored consumer, tests, docs, and
  package boundary are coherent. Do not leave an exported portal without its
  anchored consumer or commit generated/native changes.

## Test strategy and acceptance matrix

| Layer | Harness/file | Required proof |
|---|---|---|
| Framework lifecycle | `WidgetTester`; new external-edge lifecycle test | Direct and ancestor removal detach every edge before publication; rollback and throwing hooks leave no ghost ownership. |
| Render layout | Direct render tests in `test/rendering/overlay_layout_test.dart` | Generic base, base-first layout, entry order, clipping, current-frame root coordinates, flip/clamp/padding edge cases. |
| Portal widgets | `WidgetTester` and focused portal tests | Logical inheritance, controller exclusivity/pending state/replacement, fresh state after hide, reorder without recreation, teardown. |
| Menu behavior | `WidgetTester`, `BufferCapture`, and `KeyDriver` | Exact callbacks, `maybeOf`, focus restore, Escape/Tab/Shift+Tab, explicit position, modal pointer event matrix, no implicit close on child action. |
| Binding/input integration | `createTuiTestApp` | One installed host, parsed key/mouse input, resize, topmost dispatch, app-priority observation caveat, ordinary-app compatibility. |
| Example integration | Existing Pub Search suite | Anchored coordinates and deliberate outside-close change while search/async/loading/focus behavior otherwise remains green. |
| Public/package architecture | Architecture tests and source consumer | Exact exports and docs, no internal seam leakage, assertion-independent errors, intended publish archive. |

### Acceptance criteria

1. Two simultaneously shown raw portals paint in show order; calling `show()`
   again on the lower portal moves it to top without recreating its state.
2. Removing any logical ancestor of a shown portal synchronously detaches the
   external render edge before Element removal is published and disposes state
   exactly once by finalization.
3. Overlay content resolves inherited widgets, actions, shortcuts, and focus
   ancestry through its portal, not through the root host.
4. Existing high-level apps render identically with no shown entries, bare
   advanced binding behavior remains unchanged, and non-box custom roots still
   mount through `runTuiApp`.
5. `MenuAnchor` implements the exact transition, callback, placement, pointer,
   and focus contracts above in release and debug modes.
6. Sort opens below its launcher in ordinary space; Filter clamps inside the
   right edge; insufficient space flips or clamps deterministically; resize and
   ancestor movement update in the same frame.
7. An outside left click cannot activate a covered result, closes only the
   topmost menu, and restores its launcher. Other outside pointer events are
   blocked without closing.
8. Pub Search's existing behavior remains green except for the explicitly
   replaced “outside click keeps chooser open” expectation.
9. Public imports compile from the source-package consumer, all new invalid
   states throw with assertions disabled, and no private implementation type is
   exported.
10. The publish dry-run has zero warnings and excludes both overlay planning
    artifacts, tests, skills, workspace state, and other development-only files.

## Verification commands

### Dependency preflight at execution time

```sh
git status --short --branch
git merge-base --is-ancestor origin/main HEAD
test -f example/pub_search/app.dart
test -f test/example/pub_search_test.dart
```

Do not proceed merely because the commands run: verify the checked-out target
is post-alpha.2 and the Pub Search files are their landed versions.

### Red/green focused checks

First run the newly added lifecycle tests before production changes and record
the intended failure. After each implementation phase, run the smallest
relevant subset, culminating in:

```sh
dart test \
  test/framework/external_render_edge_lifecycle_test.dart \
  test/rendering/overlay_layout_test.dart \
  test/widgets/overlay_portal_test.dart \
  test/widgets/menu_anchor_test.dart \
  test/example/pub_search_test.dart \
  --concurrency=1
```

### Final authorized gates

```sh
dart format --output=none --set-exit-if-changed lib/ test/ example/ bin/ hook/ scripts/
dart analyze --fatal-infos
dart test test/architecture/ --concurrency=1
dart test --concurrency=1
dart run scripts/fetch_opentui_binaries.dart --verify-only
dart pub publish --dry-run
git diff --check
```

Inspect the dry-run file list, not only its exit code: the archive must contain
the new public Dart sources and migrated example while excluding the planning
artifacts and all internal development guidance. No real publication, native
build, artifact refresh, tag, release, manual workflow dispatch, or
real-terminal automation is authorized by this plan.

## Risks and mitigations

- **Core lifecycle regression:** multi-edge deactivation touches the framework's
  most sensitive structural path. Keep the default one-edge path behaviorally
  identical, test first-error ordering and atomic preflight, and add an
  architecture fitness rule.
- **Ghost overlay after ancestor failure:** exhaustive pre-publication detach
  plus idempotent unmount cleanup and parent/pipeline/focus assertions cover
  both normal and exceptional exits.
- **Root wrapper compatibility:** the host affects every high-level app even
  when empty. Preserve a generic base slot and add no-entry output, input, and
  non-box-root regressions.
- **Stale anchor geometry:** derive root coordinates after base layout in every
  dirty frame; never cache a prior-frame rectangle or build widgets in layout.
- **Input overclaim:** the barrier cannot prevent app-priority observation.
  Document the priority boundary and test both app observation and suppression
  of underlying render targets.
- **Two open independent menus:** no group semantics exist. Last shown is top;
  an outside event closes only it. Document application-level coordination and
  keep Pub Search on one chooser state.
- **Flutter resemblance overpromises parity:** maintain an explicit differences
  section, compile-fail omitted parameters, and avoid exporting speculative
  helpers.
- **Pub Search state drift:** centralize synchronization between `_chooser` and
  menu controllers, retain async generation guards, and run the complete
  example suite rather than only new geometry tests.
- **Release evidence drift:** keep the work post-alpha.2. If that decision
  changes, reopen exact-candidate review/recovery gates before implementation.
- **Unexpected package contents:** relocate or ignore the plan artifacts and
  inspect the full `dart pub publish --dry-run` archive listing.

## Rollout and rollback

- No feature flag or compatibility shim. The public API is additive and the
  private Pub Search composition uses a hard cut.
- Land after alpha.2 and after Pub Search is on the target branch. Add release
  notes under the next unreleased package version.
- Roll back the coherent overlay/menu/example slice if a blocker appears. The
  rollback restores Pub Search's local `Stack` chooser and removes the new
  exports; no data or native artifacts require recovery.
- If framework foundation and consumer work are reviewed as separate commits,
  keep every commit buildable and focused-test green, but do not merge/export a
  public portal until the anchored consumer, docs, and complete verification
  are present on the final tree.
