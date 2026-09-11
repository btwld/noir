import 'package:noir/noir.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import '../../../test/helpers/tui_test_app.dart';
import 'fake_mcp_session.dart';

void main() {
  for (final (tab, label) in [
    (InspectorTab.tools, 'Run'),
    (InspectorTab.resources, 'Read'),
    (InspectorTab.prompts, 'Get'),
  ]) {
    test(
      '$label uses the action icon while instructions keep its plain name',
      () async {
        final controller = InspectorController(
          session: FakeMcpSession(
            tools: const [McpToolInfo(name: 'tool', form: FormSpec([]))],
            resources: const [
              McpResourceInfo(uri: 'file:///data', name: 'data'),
            ],
            prompts: const [McpPromptInfo(name: 'prompt', form: FormSpec([]))],
          ),
        );
        await controller.connect();
        controller.selectTab(tab);
        final run = FocusNode();
        final result = FocusNode();
        final schema = FocusNode();
        final app = createTuiTestApp(
          Theme(
            data: ThemeData.dark,
            child: DetailPane(
              controller: controller,
              focusNodeFor: (_) =>
                  throw StateError('These primitives have no fields'),
              runFocusNode: run,
              resultFocusNode: result,
              schemaFocusNode: schema,
              onChanged: () {},
            ),
          ),
        );
        try {
          app.pumpFrame();
          final frame = app.captureFrame();
          expect(frame.findText('${Icons.pointerRight} $label'), hasLength(1));
          expect(frame.toText(), contains('Press $label or Ctrl+R'));
        } finally {
          app.dispose();
          run.dispose();
          result.dispose();
          schema.dispose();
          controller.dispose();
        }
      },
    );
  }
}
