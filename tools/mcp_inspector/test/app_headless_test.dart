import 'package:noir/noir.dart';
import 'package:noir_mcp_inspector/noir_mcp_inspector.dart';
import 'package:test/test.dart';

import 'fake_mcp_session.dart';

const _calculate = McpToolInfo(
  name: 'calculate',
  form: FormSpec(<FormFieldSpec>[
    FormFieldSpec(
      name: 'operation',
      kind: FormFieldKind.select,
      isRequired: true,
      options: <String>['add', 'subtract'],
    ),
    FormFieldSpec(name: 'a', kind: FormFieldKind.number, isRequired: true),
  ]),
  description: 'Perform basic arithmetic operations',
);

void main() {
  test('the screen mounts, connects, and disposes idempotently', () async {
    final session = FakeMcpSession(
      tools: const <McpToolInfo>[_calculate],
      resources: const <McpResourceInfo>[
        McpResourceInfo(uri: 'file:///logs', name: 'Application Logs'),
      ],
      prompts: const <McpPromptInfo>[
        McpPromptInfo(name: 'analyze-code', form: FormSpec(<FormFieldSpec>[])),
      ],
    );
    final app = runTuiApp(InspectorApp(session: session), headless: true);

    expect(app.isHeadless, isTrue);
    // The handshake and the inventory load are asynchronous, so let the
    // controller settle before checking that the session came up.
    await Future<void>.delayed(Duration.zero);
    expect(session.listToolsCount, 1);

    app.dispose();
    app.dispose();

    expect(session.closeCount, 1);
  });

  test('a failed connect still mounts and disposes', () async {
    final session = FakeMcpSession()..connectFailure = 'no such command';
    final app = runTuiApp(InspectorApp(session: session), headless: true);
    await Future<void>.delayed(Duration.zero);

    app.dispose();

    expect(session.closeCount, 1);
  });
}
