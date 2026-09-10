import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('visual text paths do not index strings by code unit', () {
    const files = <String>[
      'lib/src/rendering/paragraph.dart',
      'lib/src/painting/tui_canvas.dart',
      'lib/src/widgets/input.dart',
      'lib/src/widgets/text_area.dart',
      'lib/src/widgets/select.dart',
      'lib/src/widgets/text.dart',
      'lib/src/widgets/rich_text.dart',
      'lib/src/widgets/text_layout.dart',
      'lib/src/core/buffer.dart',
      'lib/src/foundation/text_editing_controller.dart',
    ];
    final violations = <String>[];
    final forbidden = <RegExp>[
      RegExp(r'\bcodeUnitAt\s*\('),
      RegExp(r'\.substring\s*\('),
      RegExp(r'\btext\.length\s*[<>+\-]'),
      RegExp(r'[<>+\-]\s*\btext\.length'),
      RegExp(r'\btext\s*\['),
      RegExp(r'\bellipsis\s*\['),
      RegExp(r'\blineText\s*\['),
      RegExp(r'\bdisplayText\s*\['),
      RegExp(r'\bdisplayRaw\s*\['),
      RegExp(r'\bbufferText\s*\['),
    ];

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final pattern in forbidden) {
        if (pattern.hasMatch(source)) {
          violations.add('$path: ${pattern.pattern}');
        }
      }
    }

    expect(violations, isEmpty);
  });
}
