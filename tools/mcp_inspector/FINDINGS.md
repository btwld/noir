# Findings from building an MCP inspector on Noir

This file records what building `noir_mcp_inspector` exposed about
`package:noir` and `package:mcp_dart`. Every entry names a reproduction, the
layer that owns it, and a classification:

- **Noir framework gap** — Noir cannot express something an ordinary
  application needs, or behaves in a way the public documentation does not
  predict.
- **Noir works as documented** — the documented behavior held under a real
  workload.
- **Noir known limitation** — already recorded in `TODO.md`.
- **mcp_dart observation** — about the SDK or the Dart tooling around it, not
  about Noir.

The inspector imports only `package:noir/noir.dart` and
`package:mcp_dart/mcp_dart.dart`. No screen needed
`package:noir/noir_low_level.dart`.

## Noir framework gaps

### 1. An application cannot measure the terminal

`ListView` occupies exactly its `height` rows
(`lib/src/widgets/list_view.dart:59-61`), and the application surface exposes
no viewport size: there is no `LayoutBuilder`, no `MediaQuery`, and no size on
the `TuiApp` handle. An application that wants a list to fill its pane has to
hard-code a row budget for the smallest grid it supports.

*Reproduction.* `lib/src/ui/primitives_pane.dart` sets `primitiveListRows` to
12, chosen for a 60x18 grid. At 100x30 the list leaves twelve rows of the pane
empty; below 80x24 the result panel loses every row it had, because the
`Expanded` that holds it is squeezed to zero.

*Layer.* Widgets and layout.

*Classification.* Noir framework gap.

### 2. A keyed `ListView` row resolves to two driver nodes

`ListView._buildRow` copies the row's own `LocalKey` onto the `SizedBox` it
wraps the row in (`lib/src/widgets/list_view.dart:323-336`), so the key exists
twice in the element tree. A strict driver locator then fails.

*Reproduction.* Give a row `key: ValueKey('primitive:calculate')` and run
`wait key primitive:calculate` through `scripts/noir_drive.dart`:

```
Bad state: Strict locator key "primitive:calculate" resolved to 2 matches.
  - SizedBox(key: primitive:calculate, ...)
  - Text(key: primitive:calculate, ...)
```

*Workaround in this tool.* The row builder returns an unkeyed `Align` and puts
the key on the inner `Text`, so only one node carries it.

*Layer.* Widgets and the drive-mode tree.

*Classification.* Noir framework gap.

### 3. Losing the focused node silently disables every `Shortcuts` binding

`Shortcuts.handleKeyEvent` walks ancestors starting at the focused element
(`lib/src/widgets/shortcuts.dart:110-124`). When nothing owns primary focus
there is no starting point, so no binding fires and no error is reported.
Noir repairs escaped focus inside a `Modal`, but the root scope does not
repair it.

Two ordinary application actions leave the tree unfocused:

- Disabling the focused control. `Button(onPressed: null)` while a request is
  in flight drops focus. `find focused` then reports *No node in this tree has
  primary focus*, and Ctrl+N stops switching tabs until the user clicks or
  presses Tab.
- Removing the region that owns focus. Switching from a tab whose detail pane
  holds focus to one that does not build that pane leaves the focused node
  detached.

*Workarounds in this tool.* The Run button stays enabled and
`InspectorController.run` ignores a second call
(`lib/src/ui/detail_pane.dart`). `_syncTabFocus` moves focus to the primitives
list on a tab change, and the list and the console take focus back through
`autofocus` when their region remounts (`lib/src/ui/inspector_app.dart`).

*Layer.* Focus manager and `Shortcuts`.

*Classification.* Noir framework gap.

The Ctrl+O schema view reproduced this twice more. Swapping the form out for
the schema removes whatever field owned focus, and every binding stopped —
Ctrl+O itself, Ctrl+N, and Ctrl+Q, leaving only Ctrl+C. Enter on a list row
then threw `FocusNode is not attached to a FocusManager`, because the code
still focused the first field awaiting input after that field left the tree.

The working pattern is the one `_syncTabFocus` already uses: the incoming
region takes focus through `autofocus`, and the outgoing swap hands focus to a
widget that is mounted in both states. Any widget that replaces a focused
subtree needs both halves.

### 4. Disposing an attached `FocusNode` throws on the next dispatch

An application that generates one field per selection wants to dispose the
focus nodes of fields that disappeared. Disposing a node the tree still
references throws on the next key event:

```
Bad state: FocusNode is not attached to a FocusManager
```

The `FocusNode` documentation says to always dispose; it does not say that
disposal must wait until the node is detached, and there is no public
`isAttached` to test.

*Workaround in this tool.* `_syncFieldNodes` keeps one node per field for the
life of the state, only surrendering focus when a field disappears, and
disposes every node in `State.dispose`.

*Layer.* Focus manager.

*Classification.* Noir framework gap.

### 5. `scripts/noir_drive.dart` cannot send Ctrl with a digit or Ctrl+Enter

`encodeKey` accepts the named keys plus `ctrl-<a-z>`
(`scripts/driver/ansi_keys.dart:63-77`). A keyboard contract that uses
`Ctrl+1..5` or `Ctrl+Enter` is therefore not scriptable from the shipped
driver, even though a Kitty-protocol terminal can send both.

*Workaround in this tool.* Ctrl+N and Ctrl+P step the tab strip from anywhere,
and `[` and `]` step it in regions that never accept typing. Ctrl+1..5 and
Ctrl+Enter remain for people.

*Layer.* Drive-mode driver.

*Classification.* Noir framework gap.

### 6. Ctrl+Enter cannot reach an app that does not opt into Kitty keys

A terminal reports Ctrl with Enter only through the Kitty keyboard protocol.
`runTuiApp` never calls `enableKittyKeyboard`; it is an opt-in method on the
`TuiApp` handle (`lib/src/app/app.dart:222`). An application that binds
`SingleActivator(LogicalKeyboardKey.enter, control: true)` therefore has a
shortcut that works in drive mode's synthetic parser and in a Kitty-enabled
app, but not in an ordinary iTerm2 session.

*Reproduction.* Route N1 of the authorized terminal run reached the Run button
with Tab and pressed Enter, because `\x1b[13;5u` produced nothing. The
`Ctrl+Enter` binding stays in the app for hosts that opt in.

*Layer.* Terminal session and input.

*Classification.* Noir framework gap.

### 7. Document-widget content is invisible to `DriverLocator.byText`

`CodeView` renders through its own document viewport, so `find text` and
`wait text` never see the result body. Only a painted-frame wait
(`NoirDriver.waitForText`) finds it.

This matches the documented contract — text locators read `Text` and
`RichText` source — but it is the first thing that surprises a driver author
whose result view is a document widget.

*Layer.* Drive-mode driver.

*Classification.* Noir works as documented.

## Noir works as documented

### 8. A server-initiated `Modal` opens correctly from a notifier callback

`McpClient` calls `onElicitRequest` while it processes an incoming request.
The session turns that into a controller notification, and the screen opens
the `Modal` from its listener. `ModalController.open()` is safe there because
the listener runs outside build. Accept, Decline, and Cancel each complete the
`Completer` that the suspended request awaits.

*Reproduction.* `test/inspector_controller_test.dart`, group *server-initiated
input over a live session*, and the two elicitation tests in
`test/tools/mcp_inspector_drive_test.dart`.

### 9. `Modal` lays overlay content out at its natural size

A `Column` with the default `MainAxisSize.max` inside `modalBuilder` claims
every row the terminal has, so the modal panel filled the screen. Adding
`MainAxisSize.min` restored a centred, shrink-wrapped panel. The behavior
follows the documented "natural size" rule; the failure mode is just easy to
miss.

### 10. Noir has no schema-driven form primitive, and that is the right boundary

Generating controls from a JSON Schema is application code.
`lib/src/session/mcp_session.dart` converts the schema into a `FormSpec`, and
`lib/src/ui/form_view.dart` maps each field to `Select`, `TextInput`,
`Checkbox`, or `TextArea`. The catalog covered every shape the MCP fixtures
produce without a new widget.

### 11. JSON display has no shipped highlighter

Noir ships only `PlainTextCodeHighlighter`, so the protocol pane renders JSON
without syntax color. A language engine stays an application dependency, which
is the documented boundary. The inspector prints indented JSON and relies on
structure rather than color.

### 12. A `list_changed` notice can refresh a live `ListView`

`InspectorController` reloads the inventory when a `notifications/*/
list_changed` notice arrives, and the list rebuilds with the new item count.
Covered by *a list_changed notice reloads the tool list* in
`test/inspector_controller_test.dart` with an injected notice. No fixture
server emits one yet, so the live path is untested.

### 13. `TuiApp.exit` ends the app and its child cleanly

Ctrl+Q reaches an `Actions` handler that calls `TuiApp.exit(context)`. The
controller disposes, the session closes, and the stdio child exits. The drive
test asserts that no process matching the fixture path survives the quit.

### 14. `TextInput` numeric entry is plain text entry

There is no numeric field. `FormModel.toArguments` parses `num` and `int` from
the text and reports `not a number` or `not an integer` next to the field
name. That is enough for a form, but every numeric tool argument needs the
same application-side coercion.

## Real-terminal observations

### 15. The screen holds up in iTerm2 at three grids

One authorized iTerm2 run at 100x40, 80x24, and 60x18 confirmed the layout,
the generated form, the paired protocol log, the console, and the elicitation
modal. At 60x18 the result region loses every row, which is entry 1 seen from
the outside. Every session closed cleanly on Ctrl+C with no cursor or mode
damage, so the iTerm cursor restoration limitation in `TODO.md` did not
appear. Evidence and the side-by-side comparison with the official MCP
Inspector TUI live in an untracked run folder under
`.context/terminal-evidence/`.

## mcp_dart and Dart tooling observations

### 16. `dart run` writes build-hook progress to stdout

In a package whose dependency graph has a native-assets build hook — which is
every package that depends on `noir` — `dart run` prints
`Running build hooks...` to **stdout**. For an MCP server on stdio that is the
protocol channel, and the client rejects the stream:

```
StdioClientTransport: Error processing read buffer: ... Skipping data.
```

`dart run --verbosity=error <server>.dart` fixes it. Every fixture command in
this package and in the two root tests carries that flag.

### 17. The SDK's runtime logger writes to stderr and would corrupt a frame

`package:mcp_dart` logs transport and protocol diagnostics through its own
`Logger`, whose default handler writes to stderr. In a terminal application
that lands on top of the rendered frame. `setMcpLogHandler` is the supported
fix; `LiveMcpSession(captureSdkLogs: true)` routes the lines into the console
pane instead, and `close()` restores the default handler.

The client also logs, on every construction,
`Setting request handler for potentially custom method 'ping'. Ensure client
capabilities match.` at INFO. A host has to expect that line.

### 18. `notifications/progress` never reaches `fallbackNotificationHandler`

`Protocol` registers default handlers for `notifications/cancelled` and
`notifications/progress` (`shared/protocol.dart:632,647`), so a client that
watches `fallbackNotificationHandler` sees the list-changed, message, and
resource-updated notices but not progress. The inspector shows progress only
in the protocol log, which records every message the transport carries.

### 19. `StdioClientTransport` hides the child process

The transport exposes `stderr` when `stderrMode` is `ProcessStartMode.normal`,
but not the process, its pid, or its exit code. A host cannot report why a
server died or report its termination status. Both lifetime checks in this
repository therefore inspect the process table with `pgrep -f <fixture path>`
rather than reading an exit code.

### 20. A transport decorator cannot forward the optional capabilities

`Transport` and the optional capability interfaces are unrelated class types,
so `is` does not promote and a decorator needs explicit casts —
`package:mcp_dart` casts the same way in `client/client.dart:489` and
`shared/protocol.dart:1375`.

Worse, a decorator has to decide at compile time which optional interfaces it
implements. `TracingTransport` forwards `RequestIdAwareTransport` and
`ProtocolVersionAwareTransport`, because both degrade correctly on a transport
that lacks them. It deliberately does not claim
`SubscriptionReplayAcknowledgmentTransport`,
`RequestCancellationAwareTransport`, or `ToolParameterHeaderAwareTransport`:
answering those for a transport that cannot honor them would change protocol
behavior. Wrapping `StdioClientTransport` therefore loses subscription replay,
and wrapping `StreamableHttpClientTransport` loses per-request cancellation
and tool-parameter headers. A `Transport` mixin that forwards every optional
capability by delegation would remove the trade-off.

### 21. `ping` on the 2026-07-28 profile

The plan listed this as a candidate. The inspector never sends `ping`, so this
build neither confirms nor refutes it. It stays open.

### 22. `JsonObject.extra` preserves the wire keywords

The typed builder hierarchy models `oneOf`, `anyOf`, `allOf`, and `not`, but
not `if` / `then` / `else`. Those keywords still survive a round trip:
`JsonObject.extra` holds every object-level keyword the typed API does not
model, and `json_schema.dart` names `$schema`, `$defs`, `allOf`, `if`, `then`,
and `else` in its documentation. `json_schema_engine.dart` validates them.

So a conditional tool schema arrives fully described. Anything a client drops
after that, the client dropped on its own.

`Tool.fromJson` also calls `_validateObjectRootSchema`, which rejects any
`inputSchema` whose root type is not `object`. A root `oneOf` never reaches a
client.

### 23. `compileJsonSchemaValidator` is hidden from the public API

`json_schema_validator.dart` exposes
`compileJsonSchemaValidator(JsonSchema) -> void Function(dynamic)`, backed by a
complete draft 2020-12 engine. It is exactly what a client needs to check tool
arguments before `tools/call`.

`shared/module.dart` re-exports the file with
`hide JsonSchemaDefinitionException, compileJsonSchemaValidator`, so only
`JsonSchemaValidationException` reaches a consumer. A client on the public SDK
cannot validate arguments locally; it can only send them and read the server's
error. Exporting the compile function would remove a round trip.

## Inspector limitations

### 24. The generated form cannot express conditional keywords

`FormSpec.fromJsonSchema` reads `properties` and `required`. It ignores
`JsonObject.extra` and `JsonObject.dependentRequired`, so a schema that
constrains its arguments with `if` / `then` or `allOf` generates controls for
the unconditional properties only.

Value constraints are the common case, and the form now shows them:
`minimum`, `maximum`, `exclusiveMinimum`, `exclusiveMaximum`, `multipleOf`,
`minLength`, `maxLength`, `pattern`, and `format` all render as hint text
under the control, beside the property description.

Conditional keywords remain unrendered. Ctrl+O shows the raw schema beside the
tool so the reader can see them: the view autofocuses as it mounts, so it
scrolls immediately, and `test/tools/mcp_inspector_drive_test.dart` proves it
reaches `"if"` in the constrained fixture's 64-line schema.

Evaluating those keywords to drive the form live is a deliberate non-goal:
real servers rarely send them, and a form that silently applies a condition
incorrectly is worse than one that does not try.

Both forms are wrapped in `Flexible`. Noir cannot measure the terminal, which
is entry 1, so the form cannot decide how many rows it may take; bounding it
keeps Run, and the modal's Accept row, on the pane at the 60x18 floor.

### 25. The stdio lifecycle test counts processes machine-wide

`test/stdio_lifecycle_test.dart` asserts that `close()` leaves no child, and
counts with `pgrep -f fixtures/calculate_server.dart`. The pattern matches
every process on the machine, so an interactive
`dart run bin/mcp_inspector.dart -- dart run ... fixtures/calculate_server.dart`
session running beside the suite fails the test. The reading is correct for
the machine and wrong for the test. Scoping the count to the child the session
started would fix it.
