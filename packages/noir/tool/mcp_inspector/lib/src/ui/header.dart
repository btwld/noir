import 'package:noir/noir.dart';

import '../model/inspector_controller.dart';

/// The one-row identity and status line at the top of the inspector.
///
/// It names the connected server, the negotiated protocol version, and the
/// capabilities the server advertised, then ends with a status [Badge] and a
/// [Spinner] while a request is in flight.
class InspectorHeader extends StatelessWidget {
  /// Creates the header over [controller].
  const InspectorHeader({required this.controller, super.key});

  /// The state owner this header reads.
  final InspectorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final server = controller.serverInfo;
    final capabilities = controller.capabilities.toList()..sort();
    return Row(
      spacing: 1,
      children: <Widget>[
        Expanded(
          flex: 2,
          child: Text(
            server == null
                ? 'MCP Inspector'
                : '${server.name} ${server.version}',
            style: TextStyles.bold,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          controller.protocolVersion ?? '-',
          style: TextStyle(color: theme.textMuted),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        Expanded(
          child: Text(
            capabilities.join(' '),
            style: TextStyle(color: theme.textMuted),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (controller.isRunning) Spinner(color: theme.accent),
        Badge(label: _status.label, variant: _status.variant),
      ],
    );
  }

  ({String label, BadgeVariant variant}) get _status =>
      switch (controller.connectionState) {
        InspectorConnectionState.connecting => (
          label: '${Icons.hourglass} connecting',
          variant: BadgeVariant.info,
        ),
        InspectorConnectionState.connected => (
          label: '${Icons.check} connected',
          variant: BadgeVariant.success,
        ),
        InspectorConnectionState.failed => (
          label: '${Icons.close} failed',
          variant: BadgeVariant.danger,
        ),
        InspectorConnectionState.closed => (
          label: '${Icons.rectangle} closed',
          variant: BadgeVariant.neutral,
        ),
      };
}
