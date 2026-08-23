import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('PointerRouter owns render-tree pointer dispatch', () {
    final router = File('lib/src/framework/pointer_router.dart');
    expect(router.existsSync(), isTrue);
    final source = router.readAsStringSync();

    expect(source, contains('final class PointerRouter'));
    expect(source, contains('inputManager.dispatcher.onMouse'));
    expect(source, contains('hitRoot.hitTest'));
    expect(source, isNot(contains('addToHitGrid')));
    expect(source, isNot(contains('checkHit')));
    expect(source, isNot(contains('updateRegion')));
    expect(source, isNot(contains('PointerHandle')));
  });

  test('driver visibility reuses hit testing without paint transforms', () {
    final driver = File('lib/src/app/driver.dart').readAsStringSync();
    final owner = File('lib/src/framework/owner.dart').readAsStringSync();
    final renderObject = File(
      'lib/src/rendering/object.dart',
    ).readAsStringSync();
    final renderBox = File('lib/src/rendering/box.dart').readAsStringSync();

    expect(owner, contains('HitTestResult? hitTestAt(Offset position)'));
    expect(renderObject, contains('visitedRenderObjects'));
    expect(renderBox, contains('result.recordVisit(this)'));
    expect(driver, contains('_binding.buildOwner.hitTestAt'));
    expect(driver, contains('for (final target in targets)'));
    expect(driver, contains('result.visitedRenderObjects'));
    expect(driver, contains('_hasHitTargetAncestor'));
    expect(driver, isNot(contains('applyPaintTransform')));
  });

  test('old region manager contract is deleted', () {
    expect(
      File('lib/src/framework/pointer_manager.dart').existsSync(),
      isFalse,
    );

    for (final file in _dartFiles('lib')) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains("import 'pointer_manager.dart'")),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains("import '../framework/pointer_manager.dart'")),
        reason: file.path,
      );
      expect(source, isNot(contains('updateRegion(')), reason: file.path);
      expect(source, isNot(contains('class PointerHandle')), reason: file.path);
      expect(
        source,
        isNot(contains('PointerListenerCallbacks')),
        reason: file.path,
      );
    }

    for (final file in _dartFiles('lib/src')) {
      if (_nativeHitGridPrimitiveFile(file)) {
        continue;
      }
      final source = file.readAsStringSync();
      expect(source, isNot(contains('.addToHitGrid')), reason: file.path);
      expect(source, isNot(contains('.checkHit')), reason: file.path);
    }
  });

  test('PointerListener is a render-tree hit-test target', () {
    final source = File(
      'lib/src/widgets/pointer_listener.dart',
    ).readAsStringSync();

    expect(source, contains('implements HitTestTarget'));
    expect(source, contains('hitTestSelf'));
    expect(source, contains('handleEvent'));
    expect(source, isNot(contains('void paint(PaintingContext')));
    expect(source, isNot(contains('PointerManager')));
    expect(source, isNot(contains('updateRegion')));
  });

  test('Select click mapping does not walk the element tree', () {
    final source = File('lib/src/widgets/select.dart').readAsStringSync();

    for (final forbidden in [
      "import '../framework/element.dart'",
      'RenderObjectElement',
      'visitChildren',
      '_findLeafRenderObject',
      '_absoluteY',
      'context.element',
    ]) {
      expect(source, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(source, contains('event.localPosition'));
  });
}

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

bool _nativeHitGridPrimitiveFile(File file) {
  final path = file.path.replaceAll(Platform.pathSeparator, '/');
  return path == 'lib/src/core/renderer.dart' ||
      path.startsWith('lib/src/ffi/');
}
