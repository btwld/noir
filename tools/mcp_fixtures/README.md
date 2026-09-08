# `noir_mcp_fixtures`

MCP servers for the Noir MCP inspector's tests. `lib/` builds each server
without a transport, so a test can drive it in process over
`IOStreamTransport`. `bin/` starts the same server on stdio.

This package depends on `package:mcp_dart` and nothing else. A fixture that
depended on `noir` would inherit its native-assets build hook, and `dart run`
writes hook progress to **stdout**, which is the MCP protocol channel. The
inspector's `FINDINGS.md` entry 16 records that failure and its version
boundary.

| Server | Profile | What it exposes |
| --- | --- | --- |
| `calculate_server` | default | `calculate` with an enum and two numbers, `file:///logs`, and the `analyze-code` prompt |
| `constrained_server` | default | `schedule` declares numeric and string constraints, plus `if` / `then` and `dependentRequired` |
| `greeting_server` | `--protocol 2026` | `personalized_greeting` answers with `input_required`, then returns a greeting |
| `legacy_elicit_server` | `--protocol legacy` | `register_user` calls `elicitation/create` from inside its tool callback |
| `selection_server` | `--protocol legacy` | Two tools with distinct fields, for focus across form replacement |
| `long_form_server` | default | One tool with eight fields, for a scrolling modal |
