import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  test('raw handle access fails after dispose', () {
    final renderer = Renderer.create(2, 1, testing: true);
    addTearDown(renderer.dispose);

    expect(renderer.handle.value, isNonZero);
    renderer.dispose();

    expect(() => renderer.handle, _throwsRendererDisposed);
  });

  test('raw bindings access fails after dispose', () {
    final renderer = Renderer.create(2, 1, testing: true);
    addTearDown(renderer.dispose);

    expect(renderer.bindings, isNotNull);
    renderer.dispose();

    expect(() => renderer.bindings, _throwsRendererDisposed);
  });

  final disposedNativeCalls = <String, void Function(Renderer)>{
    'setupTerminal': (renderer) => renderer.setupTerminal(),
    'resize': (renderer) => renderer.resize(2, 1),
    'nextBuffer': (renderer) => renderer.nextBuffer,
    'debugCurrentBuffer': (renderer) => renderer.debugCurrentBuffer,
    'render': (renderer) => renderer.render(autoFlush: false),
    'setBackgroundColor': (renderer) =>
        renderer.setBackgroundColor(Color.black),
    'clearTerminal': (renderer) => renderer.clearTerminal(),
    'addToHitGrid': (renderer) => renderer.addToHitGrid(0, 0, 1, 1, 1),
    'checkHit': (renderer) => renderer.checkHit(0, 0),
    'handle': (renderer) => renderer.handle,
    'bindings': (renderer) => renderer.bindings,
    'setCursorPosition': (renderer) => renderer.setCursorPosition(0, 0),
    'setCursorStyle': (renderer) => renderer.setCursorStyle(CursorStyle.block),
    'setCursorColor': (renderer) => renderer.setCursorColor(Color.white),
    'hideCursor': (renderer) => renderer.hideCursor(),
    'enableMouse': (renderer) => renderer.enableMouse(),
    'disableMouse': (renderer) => renderer.disableMouse(),
    'enableKittyKeyboard': (renderer) => renderer.enableKittyKeyboard(),
    'disableKittyKeyboard': (renderer) => renderer.disableKittyKeyboard(),
  };

  for (final entry in disposedNativeCalls.entries) {
    test('${entry.key} fails before native access after dispose', () {
      final renderer = Renderer.create(2, 1, testing: true);
      addTearDown(renderer.dispose);
      renderer.dispose();

      expect(() => entry.value(renderer), _throwsRendererDisposed);
    });
  }

  test('dispose remains idempotent', () {
    final renderer = Renderer.create(2, 1, testing: true);
    addTearDown(renderer.dispose);

    renderer.dispose();

    expect(renderer.dispose, returnsNormally);
  });

  test(
    'Dart-owned auto-flush configuration remains available after dispose',
    () {
      final renderer = Renderer.create(2, 1, testing: true);
      addTearDown(renderer.dispose);
      renderer.dispose();

      expect(() => renderer.setAutoFlush(false), returnsNormally);
      expect(renderer.autoFlush, isFalse);
    },
  );
}

final Matcher _throwsRendererDisposed = throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'message',
    'Renderer is disposed',
  ),
);
