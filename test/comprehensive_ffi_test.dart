// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('Comprehensive FFI Tests', () {
    late Renderer renderer;

    setUp(() {
      renderer = Renderer.create(80, 24, testing: true);
    });

    tearDown(() {
      renderer.dispose();
    });

    test('renderer lifecycle', () {
      expect(
        renderer,
        isNotNull,
        reason: 'Renderer should be created successfully',
      );

      // Should not throw when calling methods
      expect(() => renderer.setBackgroundColor(Color.black), returnsNormally);
      expect(() => renderer.clearTerminal(), returnsNormally);
      expect(() => renderer.render(force: true), returnsNormally);
    });

    test('buffer operations', () {
      final buf = renderer.nextBuffer;
      expect(buf, isNotNull, reason: 'Buffer should be available');

      // Check buffer dimensions
      expect(
        buf.width,
        equals(80),
        reason: 'Buffer width should match renderer',
      );
      expect(
        buf.height,
        equals(24),
        reason: 'Buffer height should match renderer',
      );

      // Test buffer operations
      expect(() => buf.clear(Color.black), returnsNormally);
      expect(() => buf.drawText('Test', 0, 0, Color.white), returnsNormally);
      expect(() => buf.fillRect(0, 0, 10, 1, Color.red), returnsNormally);
    });

    test('color handling', () {
      final buf = renderer.nextBuffer;

      // Test various color formats
      final colors = [
        Color.white,
        Color.black,
        Color.red,
        Color.green,
        Color.blue,
        Color.yellow,
        Color.cyan,
        Color.magenta,
        Color.rgb(0.5, 0.5, 0.5),
        Color(1, 0, 0.5, 0.8),
      ];

      for (var i = 0; i < colors.length; i++) {
        expect(
          () => buf.drawText('Color $i', i, 0, colors[i]),
          returnsNormally,
        );
      }
    });

    test('text attributes', () {
      final buf = renderer.nextBuffer;

      // Test different text attributes
      final attributes = [
        0, // normal
        Attr.bold,
        Attr.dim,
        Attr.italic,
        Attr.underline,
        Attr.blink,
        Attr.reverse,
        Attr.strike,
        Attr.bold | Attr.underline, // combination
      ];

      for (var i = 0; i < attributes.length; i++) {
        expect(
          () => buf.drawText(
            'Attr $i',
            0,
            i,
            Color.white,
            attributes: attributes[i],
          ),
          returnsNormally,
        );
      }
    });

    test('box drawing', () {
      final buf = renderer.nextBuffer;

      // Test default box
      const defaultOptions = BoxOptions();
      expect(
        () =>
            buf.drawBox(5, 5, 20, 10, defaultOptions, Color.white, Color.blue),
        returnsNormally,
      );

      // Test box with title
      const titledOptions = BoxOptions(
        title: 'Test Box',
        titleAlignment: TextAlign.center,
        fill: true,
      );
      expect(
        () => buf.drawBox(30, 5, 25, 8, titledOptions, Color.yellow, Color.red),
        returnsNormally,
      );

      // Test custom border sides
      const customBorder = BoxOptions(
        sides: BorderSides(left: false, right: false),
      );
      expect(
        () =>
            buf.drawBox(60, 10, 15, 5, customBorder, Color.green, Color.black),
        returnsNormally,
      );
    });

    test('memory management', () {
      // Test creating and destroying multiple renderers
      final renderers = <Renderer>[];

      for (var i = 0; i < 5; i++) {
        final r = Renderer.create(40 + i, 20 + i, testing: true);
        renderers.add(r);

        // Use each renderer briefly
        final buf = r.nextBuffer;
        buf.clear(Color.black);
        buf.drawText('Renderer $i', 0, 0, Color.white);
        r.render(force: true);
      }

      // Clean up all renderers
      for (final r in renderers) {
        expect(r.dispose, returnsNormally);
      }
    });

    test('large buffer operations', () {
      // Test with larger renderer
      final largeRenderer = Renderer.create(200, 50, testing: true);
      addTearDown(largeRenderer.dispose);

      final buf = largeRenderer.nextBuffer;
      expect(buf.width, equals(200));
      expect(buf.height, equals(50));

      // Fill entire buffer
      buf.clear(Color.rgb(0.1, 0.1, 0.1));

      // Draw grid pattern
      for (var y = 0; y < 50; y += 5) {
        for (var x = 0; x < 200; x += 10) {
          buf.drawText('*', x, y, Color.white);
        }
      }

      // Large rectangle
      buf.fillRect(50, 10, 100, 20, Color.blue);

      largeRenderer.render(force: true);
    });

    test('edge cases and error conditions', () {
      final buf = renderer.nextBuffer;

      // In-domain coordinates beyond the buffer still clip safely.
      expect(
        () => buf.drawText('Outside', 1000, 1000, Color.white),
        returnsNormally,
      );
      // Negative origins leave the unsigned 32-bit ABI domain and are
      // rejected before invocation instead of wrapping.
      expect(
        () => buf.fillRect(-10, -10, 5, 5, Color.red),
        throwsA(isA<RangeError>().having((error) => error.name, 'name', 'x')),
      );

      // Test empty string
      expect(() => buf.drawText('', 0, 0, Color.white), returnsNormally);

      // Test null background
      expect(() => buf.drawText('No BG', 0, 1, Color.white), returnsNormally);

      // Test zero-size rectangle
      expect(() => buf.fillRect(10, 10, 0, 0, Color.green), returnsNormally);

      // Test zero-size box
      const zeroBox = BoxOptions();
      expect(
        () => buf.drawBox(0, 0, 0, 0, zeroBox, Color.white, Color.black),
        returnsNormally,
      );
    });
  });
}
