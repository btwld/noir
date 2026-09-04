# Noir MCP inspector

A terminal inspector for Model Context Protocol servers, written with
[`package:noir`](../../README.md) and the public
[`package:mcp_dart`](https://pub.dev/packages/mcp_dart) client SDK.

It keeps one live `McpClient` session open, lists the server's tools,
resources, and prompts, generates a form from each input schema, records every
JSON-RPC message, shows the server's standard error output, and answers
server-initiated input requests from a modal.

This package is not published. It lives in `tools/`, which `.pubignore`
excludes from the Noir archive.

## Run it

```sh
cd tools/mcp_inspector
dart pub get

# Start a server as a child process.
dart run bin/mcp_inspector.dart -- \
  dart run --verbosity=error fixtures/calculate_server.dart

# Or connect to a Streamable HTTP endpoint.
dart run bin/mcp_inspector.dart --url http://localhost:3000/mcp
```

Options:

| Option | Meaning |
| --- | --- |
| `--protocol stable\|legacy\|2026` | MCP compatibility profile. Defaults to `stable`. |
| `--url <uri>` | Streamable HTTP endpoint of a running server. |
| `-- <command> [args...]` | Everything after `--` starts a server as a child process. |

`--verbosity=error` on the child matters. In a package whose dependency graph
has a native-assets build hook, `dart run` writes `Running build hooks...` to
stdout, and for a stdio server stdout is the protocol channel. See
[`FINDINGS.md`](FINDINGS.md), entry 16.

## Keys

| Key | Action |
| --- | --- |
| Tab, Shift+Tab | Move focus: tab strip, list, form fields, Run, result |
| Enter on a row | Select it, then move to the first field awaiting a value; a row with no fields sends its request |
| Enter or Space on Run | Send the request |
| Ctrl+R | Send the request from anywhere in the form |
| Ctrl+G | Show the tool's raw input schema in place of the form, and back |
| Ctrl+N, Ctrl+P | Next and previous tab, from anywhere |
| `[`, `]` | Previous and next tab, from the list, protocol, and console regions |
| Escape in the modal | Cancel the server's request |
| Ctrl+X | Quit through `TuiApp.exit` |
| Ctrl+C | Copy a document selection, or quit through Noir's fallback when unhandled |

`[` and `]` are bound only where nothing accepts typing: `Shortcuts` outranks
the printable-character stage, so a bare `[` bound above a `TextInput` would
make that character untypable. Ctrl+N and Ctrl+P cover the form, because
neither the shipped drive-mode driver nor most terminals can send Ctrl with a
digit. Ctrl+Enter and Ctrl+1..5 remain bound for custom hosts that enable Kitty
keyboard reporting; the normal CLI does not enable it. Use Ctrl+R and Ctrl+N/P
with the commands above. Ctrl+G and Ctrl+X also avoid terminal discard
(Ctrl+O) and software flow control (Ctrl+Q), which can consume those keys before
Noir receives them.

## Tabs

- **Tools** — the input schema as a form, a Run action, and the result.
  Descriptions and value constraints appear below each field. Tab and Shift+Tab
  scroll focused fields into view; the mouse wheel scrolls the form too.
  Ctrl+G opens the selected tool's full schema and focuses it for scrolling.
  It leaves other tabs and server-request modals alone.
- **Resources** — Enter reads the selected URI.
- **Prompts** — the declared arguments as a form; Enter gets the prompt.
- **Protocol** — every JSON-RPC message, paired `-> tools/call #3` with
  `<- result #3 12ms`; the selected message is shown as indented JSON.
- **Console** — the child server's standard error, the SDK's own diagnostics,
  and one line per `notifications/*` the client did not handle itself.

The form checks required fields and basic value conversion. Constraint hints
describe the server's schema; the server still validates those constraints.
Conditional schemas do not change the form dynamically. Read the full schema
with Ctrl+G, or in the Protocol tab's `tools/list` response. At narrow widths,
the full schema also supplies the text truncated from field hints.

## Fixtures

| Fixture | Profile | What it shows |
| --- | --- | --- |
| `fixtures/calculate_server.dart` | default | `calculate` with an enum and two numbers, `file:///logs`, and the `analyze-code` prompt |
| `fixtures/constrained_server.dart` | default | `schedule` declares numeric and string constraints, plus `if` / `then` and `dependentRequired`, which generate no controls |
| `fixtures/greeting_server.dart` | `--protocol 2026` | `personalized_greeting` answers with `input_required`, then returns a greeting |
| `fixtures/legacy_elicit_server.dart` | `--protocol legacy` | `register_user` calls `elicitation/create` from inside its tool callback |

The two elicitation fixtures exist to prove that one handler and one modal
serve both the MCP 2026-07-28 `input_required` retry loop and the 2025-11-25
`elicitation/create` request.

## Architecture

```
bin/mcp_inspector.dart      reads the command line, starts the screen
lib/src/session/            the boundary: McpSession, LiveMcpSession,
                            TracingTransport, ProtocolLog
lib/src/model/              FormModel and InspectorController
lib/src/ui/                 the screen; imports package:noir only
fixtures/                   four MCP servers written with package:mcp_dart
```

`McpSession` plays the role `PubCatalog` plays in
`example/src/pub_search/catalog.dart`: the screen never touches `McpClient`,
and every value that crosses the boundary is a type this package owns. Tests
substitute `FakeMcpSession` for it.

## Gates

From this directory:

```sh
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test --concurrency=1
```

From the repository root, two ordinary tests cover this package so no workflow
change is needed:

```sh
dart test test/tools/mcp_inspector_package_test.dart --concurrency=1
dart test test/tools/mcp_inspector_drive_test.dart --concurrency=1
```

The first runs the commands above as subprocesses. The second drives the real
screen in drive mode against the fixtures: tool calls, the paired protocol
log, field and schema scrolling, the 80x24 and 60x18 floors, both elicitation
profiles, and the fixture child ending with the app. Lifecycle counts use a
unique process argument, so an interactive inspector may stay open beside them.

Look at the screen at three sizes from the repository root:

```sh
printf 'wait key primitive:calculate\nkey enter\ntype 5\nkey tab\ntype 3\nclick key run\ncapture --plain\nresize 80x24\ncapture --plain\nresize 60x18\ncapture --plain\nquit\n' | \
  dart run --verbosity=error scripts/noir_drive.dart \
    "$PWD/tools/mcp_inspector/bin/mcp_inspector.dart" --size 100x30 -- \
    -- dart run --verbosity=error \
      "$PWD/tools/mcp_inspector/fixtures/calculate_server.dart"
```

## What the build exposed

[`FINDINGS.md`](FINDINGS.md) records every Noir gap, documented behavior, and
mcp_dart observation this tool produced.

One authorized iTerm2 run captured this inspector and the official MCP
Inspector TUI on the same server surface at a 100x40 grid, plus the 80x24 and
60x18 floors and the elicitation modal. The screenshots, `COMPARISON.md`, and
`NOTES.md` live in an untracked run folder under
`.context/terminal-evidence/`, because `.context/` is workspace state rather
than repository source.
