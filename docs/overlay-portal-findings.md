# Overlay portal and anchored menu findings

## Goal under investigation

Provide a popup that is anchored to a launcher, paints above the rest of the
terminal UI, preserves Noir widget semantics, and uses a familiar Flutter-like
API without copying Flutter's complete overlay, route, layer, or Material menu
systems.

## Repository findings

- `lib/src/app/app.dart`, `_mount`: every high-level application already passes
  through one package-owned wrapper before `TuiBinding.runApp`. This is the
  narrowest place to install one private root overlay without changing the
  public `runTuiApp` call or bare advanced-host behavior.
- `lib/src/app/tui_binding.dart`, `TuiBinding._drawFrame`: build completes before
  layout, and layout completes before paint. A root overlay render object can
  therefore lay out ordinary content first and anchored entries second in the
  same frame, using current terminal geometry without a layout-time widget
  build or a one-frame position lag.
- `lib/src/rendering/render_view.dart`, `RenderView`: the binding intentionally
  owns one single render child. The overlay should be that child beneath the
  existing non-render app scope; `RenderView` does not need to become a
  multi-child root.
- `lib/src/framework/element.dart`, `RenderObjectElement`: render insertion and
  removal already route through overridable parent hooks. A private portal
  element can keep both subtrees as logical children while routing the normal
  child's render box locally and the overlay child's render box to the root
  overlay.
- `lib/src/framework/key.dart`, `GlobalKey`: cross-parent GlobalKey movement is
  deliberately unsupported. A portal must not simulate reparenting with a
  GlobalKey. Keeping Element ancestry unchanged avoids that conflict.
- `lib/src/framework/owner.dart`, `BuildOwner.deactivateChild`: render detachment
  happens before Element deactivation and final unmount. The portal's custom
  removal hook must remove the overlay render edge through this existing path,
  so overlay state cannot outlive its logical portal.
- `lib/src/rendering/object.dart`, `RenderObject.hitTest`: children are hit-tested
  in reverse paint order. If root overlay entries are stored in show order,
  last-shown entries naturally paint last and receive pointer input first.
- `lib/src/rendering/box.dart`, `RenderBox.hitTest`: bounds are enforced before
  child/self hit testing. A full-terminal anchored follower can implement an
  outside-click barrier while its popup child still receives local pointer
  coordinates.
- `lib/src/framework/pointer_router.dart`, `PointerRouter.route`: routing stops at
  the topmost hit render subtree. An outside click can close and consume a menu,
  but v1 cannot truthfully offer Flutter's click-through
  `consumeOutsideTap: false` behavior without a separate tap-region change.
- `lib/src/framework/focus_manager.dart` and `lib/src/widgets/focus.dart`: focus
  ancestry follows the Element tree. Keeping the menu's Element under its
  launcher preserves shortcut/action lookup and lets a supplied launcher
  `FocusNode` regain focus after dismissal.
- `lib/src/widgets/stack.dart` and `lib/src/rendering/stack.dart`: `Stack` and
  `Positioned` already provide local whole-cell overlays, clipping, reverse
  hit-testing, and document-order paint. They are useful inside an overlay but
  cannot escape the current results-panel render subtree by themselves.
- `lib/src/widgets/select.dart`, `Select<T>`: the existing selector already owns
  focus, keyboard navigation, pointer-local row mapping, scrolling, highlight,
  and confirmation. The menu work should compose it rather than introduce a
  second selector implementation.
- `example/pub_search/app.dart`, `_buildSearchView` and
  `_buildChooserOverlay`: the current chooser is inserted into a `Stack` around
  the results panel and centered with `Align`. Its state, refresh behavior,
  keyboard dismissal, selection, and focus restoration are already well tested;
  migration should change presentation ownership, not search behavior.
- `test/example/pub_search_test.dart`: existing coverage already asserts mouse
  launch, keyboard launch, cancellation, selection, retained results, loading,
  failures, focus restoration, and 80-column help. New assertions should focus
  on anchored coordinates, edge handling, and outside dismissal.
- `lib/noir.dart` and `test/architecture/public_api_test.dart`: every added public
  type must be explicitly curated. Public member documentation and signature
  closure are also enforced by the architecture suite.
- `GOALS.md`: Flutter semantics are required where Noir intentionally mirrors
  Flutter, while widgets, Elements, render objects, compositor, and native code
  must retain their existing ownership boundaries.
- `TODO.md`: the current candidate has no overlay item, and real-terminal checks
  remain separately authorized. This feature can be proven headlessly without
  changing the pinned OpenTUI dependency or native artifacts.

## Reference findings

- Flutter's `OverlayPortal` keeps its overlay child logically below the portal,
  so it can use the same inherited widgets and cannot outlive the portal. Its
  `OverlayPortalController` exposes `show`, `hide`, `toggle`, and `isShowing`.
- Current Flutter also has `OverlayPortal.overlayChildLayoutBuilder`, but that
  invokes a widget builder during layout and exposes matrix transforms. Noir has
  no general layout-builder protocol or transform matrix, and terminal anchors
  need only integer rectangles. Copying that constructor now would add a large
  subsystem for one use case.
- Flutter's `MenuAnchor`/`MenuController` are the closest high-level API for a
  button-relative menu. Their common call shape can be mirrored as a supported
  subset without Material style, cascading submenus, animation, `LayerLink`,
  nested/root-overlay selection, or click-through behavior.
- Pinned OpenTUI v0.5.1 provides React `createPortal`, root renderables,
  absolute positioning, screen coordinates, z-index ordering, focus, and hit
  testing, but no complete popover/menu-anchor component. Noir cannot consume
  the TypeScript portal directly because its normal bridge is the Dart display
  list/native buffer compositor.

## Prior art

- Commit `18f586e` introduced the Pub Search chooser and its current local
  overlay behavior.
- Commit `cb9ba77` introduced Noir's Dart-native `Stack`/`Positioned` and the
  existing `Select` parity surface.
- Commits `5200bf0` and `2d2a1c9` hardened focus ownership during relocation.
  The portal design should preserve that work by never relocating Elements.
- No local issue, PR, or earlier commit defines a Noir overlay, portal, or menu
  anchor contract.

## Design conclusion

The smallest coherent slice is a private root render overlay plus two narrow
public layers:

1. A Flutter-shaped `OverlayPortalController` and basic `OverlayPortal`.
2. A Flutter-shaped subset of `MenuController` and `MenuAnchor`, implemented
   with a private integer-cell anchor/follower.

Do not add `OverlayEntry`, `OverlayState`, public `LayerLink`, composited
transforms, nested overlays, cascading menus, animation, or a new dropdown
selector in this slice.
