import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('RenderView stays internal and out of public barrels', () {
    final publicSurfaces = [
      File('lib/noir.dart'),
      File('lib/noir_low_level.dart'),
      File('lib/noir_ffi.dart'),
      File('test/architecture/baselines/noir_low_level_symbols.txt'),
    ];

    for (final file in publicSurfaces) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('RenderView')), reason: file.path);
      expect(source, isNot(contains('render_view')), reason: file.path);
    }
  });

  test(
    'binding and test harness use RenderView instead of descendant root lookup',
    () {
      final bindingSource = File(
        'lib/src/app/tui_binding.dart',
      ).readAsStringSync();
      final appSource = File('lib/src/app/app.dart').readAsStringSync();
      final hostSource = File(
        'test/helpers/test_element_host.dart',
      ).readAsStringSync();

      expect(bindingSource, contains('_renderView'));
      expect(
        bindingSource,
        matches(RegExp(r'flushLayout\(\s*_renderView', multiLine: true)),
      );
      expect(bindingSource, contains('flushPaint(_renderView'));
      expect(
        bindingSource,
        isNot(contains('Element.findDescendantRenderObject')),
        reason:
            'TuiBinding frames must not pick an arbitrary render descendant.',
      );
      expect(appSource, isNot(contains('_renderView')));
      expect(appSource, isNot(contains('flushLayout')));
      expect(appSource, isNot(contains('flushPaint')));

      expect(hostSource, contains('RenderView'));
      expect(
        hostSource,
        matches(RegExp(r'flushLayout\(\s*renderView', multiLine: true)),
      );
      expect(hostSource, contains('flushPaint(renderView'));
    },
  );

  test('RenderView paint path has zero Buffer allowlist budget', () {
    final allowlistSource = File(
      'test/architecture/no_buffer_in_rendering_test.dart',
    ).readAsStringSync();
    final renderViewSource = File(
      'lib/src/rendering/render_view.dart',
    ).readAsStringSync();

    expect(
      allowlistSource,
      contains('const allowlistedBufferImports = <String>{};'),
    );
    expect(allowlistSource, contains('lib/src/widgets'));
    expect(allowlistSource, isNot(contains('render_view.dart')));
    expect(renderViewSource, isNot(contains("import '../core/buffer.dart';")));
    expect(renderViewSource, isNot(contains('src/core/buffer.dart')));
  });

  test('display-list painting is routed through binding and compositor', () {
    final bindingSource = File(
      'lib/src/app/tui_binding.dart',
    ).readAsStringSync();
    final objectSource = File(
      'lib/src/rendering/object.dart',
    ).readAsStringSync();
    final canvasSource = File(
      'lib/src/painting/tui_canvas.dart',
    ).readAsStringSync();

    expect(bindingSource, contains('createTuiCanvas'));
    expect(bindingSource, contains('PaintingContext'));
    expect(bindingSource, contains('commitTuiCanvas'));
    expect(bindingSource, isNot(contains('root.paint(buf')));
    expect(
      objectSource,
      contains('void paint(PaintingContext context, Offset offset);'),
    );
    expect(canvasSource, contains('final class _OpenTuiCompositor'));
    expect(canvasSource, isNot(contains('final class OpenTuiCompositor')));
  });
}
