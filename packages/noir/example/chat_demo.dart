// Replay: dart run example/chat_demo.dart
// Live: dart run example/chat_demo.dart \
//   --claude=/absolute/path/to/disposable/project
//
// Enter sends, Ctrl+J inserts a newline when the terminal distinguishes it,
// and Tab accepts a `/` command or `@` path suggestion. Ctrl+O focuses the
// transcript for PageUp/PageDown. In replay mode, Shift+Tab changes permission
// mode, Ctrl+M opens the model picker, and Ctrl+R opens saved sessions. Escape
// or Ctrl+C interrupts active work and exits while idle.
//
// Replay is deterministic and offline. Live mode requires an explicit
// absolute path to a disposable project. It starts Claude without a PTY,
// disables tools, slash commands, MCP servers, and session persistence, and
// passes a $0.05 CLI budget cap. Noir does not measure that spend or impose a
// request timeout.

import 'src/chat/app.dart';

export 'src/chat/app.dart';

void main(List<String> arguments) => runChatDemo(arguments);
