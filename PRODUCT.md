# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Stack

Delegated: a dedicated `website/` application using the current Nextra Docs
Theme on Next.js App Router. The website remains isolated from the Dart package
and uses its own npm lockfile and commands.

## Users

The primary readers are Dart and Flutter developers evaluating or building
terminal applications. Secondary readers are Noir contributors and framework
authors who need to understand ownership boundaries, test behavior, or extend
the supported low-level surfaces.

## Product Purpose

Noir lets Dart developers build reactive terminal interfaces with familiar
Flutter-like widgets, retained state, integer-cell layout, focus and input
routing, animation, and native OpenTUI rendering. The documentation should let
a new reader run a real example quickly, understand the framework's mental
model, choose the right public API tier, and apply terminal-specific patterns
without learning internal framework machinery first.

## Positioning

Noir brings a Flutter-like Widget, Element, and RenderObject architecture to
Dart terminal applications while keeping native FFI and OpenTUI ownership
behind explicit supported package boundaries.

## Operating Context

Readers evaluate Noir from a browser, install it through Dart tooling, and
develop inside a terminal and editor. Application authors test owned logic
with Dart and can mount the public lifecycle headlessly. Noir contributors
also use the repository's four layer-specific harnesses and its separate,
repository-only Driver. Readers may arrive with Flutter knowledge, terminal UI
experience, or neither.

## Capabilities and Constraints

- Noir is a prerelease. APIs and platform guarantees may change before 1.0.
- The source tree can be ahead of the latest package published to pub.dev.
- Supported high-level, hooks, low-level, and raw-FFI surfaces must remain
  visibly distinct.
- The website must not imply that restricted real-terminal or native release
  gates have passed when `TODO.md` records them as open.
- Documentation examples must compile against the current public API.
- The site must remain outside the package archive and must not add web
  dependencies to the Dart package.
- The public architectural invariant is: Widgets declare; Elements preserve
  identity; RenderObjects layout and record paint; the compositor talks to
  OpenTUI; the native layer owns FFI, memory, ABI, and binaries.

## Brand Commitments

The product name is Noir. Its voice is direct, technically precise, candid
about prerelease limits, and welcoming without sounding promotional. Flutter
terminology is used where Noir intentionally mirrors Flutter; terminal and
OpenTUI behavior is described in Noir's own terms.

## Evidence on Hand

- `README.md` contains the current install path, quick starts, component
  catalog, application lifecycle, API tiers, examples, testing guidance, and
  platform support.
- `GOALS.md` defines the durable architecture, quality bar, and terminal
  component language.
- `TODO.md` records the exact alpha.3 boundary, verified behavior, release
  gates, and known native limitations.
- `CONTRIBUTING.md`, `doc/hooks.md`, the public barrels under `lib/`, examples,
  and tests provide source-backed material for guides and patterns.
- The project has no testimonials, adoption figures, performance benchmarks,
  public stable-release claim, or approved visual identity. The documentation
  must not fabricate them.

## Product Principles

- Get a real app running before teaching the whole framework.
- Explain ownership boundaries through practical choices, not internal trivia.
- Separate tutorials, task guides, concepts, and API/reference material so
  readers can navigate by intent.
- Treat terminal constraints as the medium's design rules, not browser UI
  limitations to hide.
- State version and native limitations beside the behavior they qualify.

## Accessibility & Inclusion

The website must support keyboard navigation, visible focus, reduced motion,
responsive reading, semantic heading order, accessible contrast in light and
dark themes, and code examples that do not rely on color alone.
