import 'dart:io';

import 'package:test/test.dart';

import '../../example/chat_demo.dart';
import '../helpers/golden_testing.dart';
import '../helpers/tui_test_app.dart';

final _updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

void main() {
  group('Agent chat goldens', () {
    test('80x24 transcript and focused draft', () async {
      await _expectScene('chat_demo', width: 80, height: 24);
    });

    test('64x18 permission stress state', () async {
      await _expectScene(
        'chat_demo_64x18',
        width: 64,
        height: 18,
        showPermission: true,
      );
    });

    test('120x30 expanded tool state', () async {
      await _expectScene(
        'chat_demo_120x30',
        width: 120,
        height: 30,
        expandTool: true,
      );
    });
  });
}

Future<void> _expectScene(
  String name, {
  required int width,
  required int height,
  bool showPermission = false,
  bool expandTool = false,
}) async {
  final backend = ReplayAgentBackend();
  final controller = AgentSessionController(backend: backend);
  await controller.start();
  controller.submit('Inspect the current change.');
  final requestId = controller.activeRequestId!;
  backend
    ..emit(
      AgentTextFinalEvent(
        id: 'golden-answer',
        requestId: requestId,
        blockId: 'answer',
        text: 'I found **one focused improvement** and no release blocker.',
      ),
    )
    ..emit(
      AgentToolStartedEvent(
        id: 'golden-tool-start',
        requestId: requestId,
        blockId: 'read',
        name: 'Read',
        summary: 'lib/src/widgets/text_area.dart',
      ),
    )
    ..emit(
      AgentToolResultEvent(
        id: 'golden-tool-result',
        requestId: requestId,
        blockId: 'read',
        output: 'Verified grapheme-aware wrapping and visual cursor movement.',
      ),
    );
  if (expandTool) {
    controller.toggleToolExpanded('block:$requestId:read');
  }
  if (showPermission) {
    backend.emit(
      AgentPermissionRequestEvent(
        id: 'golden-permission',
        requestId: requestId,
        permissionId: 'golden-edit',
        toolName: 'Edit',
        reason: 'Update the focused regression test',
      ),
    );
  } else {
    backend.emit(
      AgentRequestCompletedEvent(
        id: 'golden-complete',
        requestId: requestId,
        inputTokens: 84,
        outputTokens: 36,
        costUsd: 0.012,
      ),
    );
  }

  final app = createTuiTestApp(
    ChatDemoApp(controller: controller, enableAnimation: false),
    width: width,
    height: height,
    kittyKeyboard: true,
  );
  final tester = GoldenTester(width: width, height: height);
  try {
    await _settle(app);
    if (!showPermission) {
      app.mockInput.typeText('Draft with @lib/noir.dart');
      app.pumpFrame();
    }
    await tester.expectCapturedGolden(
      app.captureFrame(),
      name,
      updateGoldens: _updateGoldens,
    );
  } finally {
    tester.dispose();
    app.dispose();
    await controller.close();
  }
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
