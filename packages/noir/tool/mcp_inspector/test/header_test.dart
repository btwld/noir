import 'package:noir/noir.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import '../../../test/helpers/tui_test_app.dart';
import 'fake_mcp_session.dart';

void main() {
  for (final (state, icon) in [
    (InspectorConnectionState.connecting, Icons.hourglass),
    (InspectorConnectionState.failed, Icons.close),
    (InspectorConnectionState.closed, Icons.rectangle),
  ]) {
    test(
      '${state.name} status keeps its text beside the catalog icon',
      () async {
        final session = FakeMcpSession()..connectFailure = 'unavailable';
        final controller = InspectorController(session: session);
        if (state == InspectorConnectionState.failed) {
          await controller.connect();
        }
        if (state == InspectorConnectionState.closed) controller.dispose();
        final app = createTuiTestApp(
          InspectorHeader(controller: controller),
          height: 1,
        );
        try {
          app.pumpFrame();
          expect(
            app.captureFrame().findText('$icon ${state.name}'),
            hasLength(1),
          );
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );
  }

  for (final width in [60, 80, 100]) {
    test('long server identity preserves status at $width columns', () async {
      final session = FakeMcpSession(
        identity: McpServerInfo(name: 'server_' * 20, version: '1.0.0'),
      );
      final controller = InspectorController(session: session);
      await controller.connect();
      final app = createTuiTestApp(
        Theme(
          data: ThemeData.dark,
          child: InspectorHeader(controller: controller),
        ),
        width: width,
        height: 1,
      );
      try {
        app.pumpFrame();
        final frame = app.captureFrame();
        expect(frame.findText('${Icons.check} connected'), hasLength(1));
        expect(frame.findText('2026-07-28'), hasLength(1));
        expect(frame.findText('server_'), isNotEmpty);
      } finally {
        app.dispose();
        controller.dispose();
      }
    });
  }
}
