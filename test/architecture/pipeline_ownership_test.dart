import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('TuiBinding delegates layout and paint to PipelineOwner', () {
    final source = File('lib/src/app/tui_binding.dart').readAsStringSync();
    final appSource = File('lib/src/app/app.dart').readAsStringSync();

    expect(source, contains('_owner.pipelineOwner.flushLayout'));
    expect(source, contains('_owner.pipelineOwner.flushPaint'));
    expect(source, isNot(contains('renderObject.layout(')));
    expect(source, isNot(contains('renderObject.paint(')));
    expect(appSource, isNot(contains('pipelineOwner')));
    expect(appSource, isNot(contains('flushLayout')));
    expect(appSource, isNot(contains('flushPaint')));
  });

  test('PipelineOwner remains internal to source libraries', () {
    final publicBarrels = [
      File('lib/noir.dart'),
      File('lib/noir_low_level.dart'),
      File('lib/noir_ffi.dart'),
      File('test/architecture/baselines/noir_low_level_symbols.txt'),
    ];

    for (final file in publicBarrels) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('PipelineOwner')), reason: file.path);
      expect(source, isNot(contains('pipeline_owner')), reason: file.path);
    }
  });

  test('PipelineOwner flushes display-list painting through root callback', () {
    final bindingSource = File(
      'lib/src/app/tui_binding.dart',
    ).readAsStringSync();
    final objectSource = File(
      'lib/src/rendering/object.dart',
    ).readAsStringSync();

    expect(bindingSource, contains('_owner.pipelineOwner.flushPaint'));
    expect(bindingSource, contains('commitTuiCanvas'));
    expect(bindingSource, contains('PaintingContext'));
    expect(objectSource, contains('TuiCanvas'));
    expect(objectSource, isNot(contains("import '../core/buffer.dart';")));
  });

  test(
    'no Buffer rendering allowlist growth is required for PipelineOwner',
    () {
      final source = File(
        'test/architecture/no_buffer_in_rendering_test.dart',
      ).readAsStringSync();

      expect(source, contains('const allowlistedBufferImports = <String>{};'));
      expect(source, isNot(contains('pipeline_owner.dart')));
    },
  );

  test('RenderObjectElement delegates invalidation to render setters', () {
    final source = File('lib/src/framework/element.dart').readAsStringSync();
    const classStartMarker = 'class RenderObjectElement extends Element {';
    const classEndMarker = 'class _BuildContextImpl extends BuildContext {';
    final classStart = source.indexOf(classStartMarker);
    final classEnd = source.indexOf(classEndMarker, classStart);
    expect(classStart, isNonNegative);
    expect(classEnd, greaterThan(classStart));
    final classSource = source.substring(classStart, classEnd);

    const updateMarker = 'void update(Widget newWidget)';
    const rebuildMarker = 'void performRebuild()';
    final updateDeclaration = classSource.indexOf(updateMarker);
    final updateOverride = classSource.lastIndexOf(
      '@override',
      updateDeclaration,
    );
    final rebuildDeclaration = classSource.indexOf(
      rebuildMarker,
      updateDeclaration,
    );
    final rebuildOverride = classSource.lastIndexOf(
      '@override',
      rebuildDeclaration,
    );
    expect(updateDeclaration, isNonNegative);
    expect(updateOverride, isNonNegative);
    expect(rebuildDeclaration, greaterThan(updateDeclaration));
    expect(rebuildOverride, greaterThan(updateDeclaration));
    final updateSource = classSource.substring(updateOverride, rebuildOverride);

    expect(updateSource, contains('updateRenderObject'));
    expect(updateSource, isNot(contains('markNeedsLayout')));
    expect(updateSource, isNot(contains('markNeedsPaint')));
  });

  test('attachment notification remains an annotated internal hook', () {
    final source = File('lib/src/rendering/object.dart').readAsStringSync();
    const declaration = 'void didAttach(PipelineOwner owner)';
    final method = source.indexOf(declaration);
    expect(method, isNonNegative);
    final annotationStart = source.lastIndexOf('@internal', method);
    final protectedAnnotation = source.lastIndexOf('@protected', method);
    expect(annotationStart, isNonNegative);
    expect(protectedAnnotation, greaterThan(annotationStart));
    final declarationSource = source.substring(annotationStart, method);
    expect(declarationSource.trim(), '@internal\n  @protected');
  });
}
