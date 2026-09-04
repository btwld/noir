/// The Noir MCP inspector: session boundary, state owners, and screen.
///
/// `bin/mcp_inspector.dart` and the package's tests import this barrel. The
/// session layer converts `package:mcp_dart` values into this package's own
/// value types, and the screen builds only on `package:noir/noir.dart`.
library;

export 'src/model/form_model.dart';
export 'src/model/inspector_controller.dart';
export 'src/session/live_mcp_session.dart';
export 'src/session/mcp_session.dart';
export 'src/session/protocol_log.dart';
export 'src/session/tracing_transport.dart';
export 'src/ui/console_pane.dart';
export 'src/ui/detail_pane.dart';
export 'src/ui/elicitation_modal.dart';
export 'src/ui/form_view.dart';
export 'src/ui/header.dart';
export 'src/ui/inspector_app.dart';
export 'src/ui/primitives_pane.dart';
export 'src/ui/protocol_pane.dart';
