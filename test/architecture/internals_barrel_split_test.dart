import 'dart:io';

import 'package:test/test.dart';

void main() {
  group('internals barrel split', () {
    test('lib/noir_internals.dart has been deleted', () {
      expect(
        File('lib/noir_internals.dart').existsSync(),
        isFalse,
        reason:
            'noir_internals.dart must be replaced by noir_low_level.dart '
            'and noir_ffi.dart. No backwards-compat shim allowed.',
      );
    });

    test('lib/noir_low_level.dart exports the advanced framework + core', () {
      final file = File('lib/noir_low_level.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'noir_low_level.dart must exist.',
      );

      final source = file.readAsStringSync();
      final exports = _parseExports(source);

      const allowedSymbolsByPath = _lowLevelAllowlist;

      final paths = exports.map((export) => export.path).toSet();
      final allowedPaths = allowedSymbolsByPath.keys.toSet();
      final unexpectedPaths = paths.difference(allowedPaths);
      final missingPaths = allowedPaths.difference(paths);
      final exportsWithoutShow = exports
          .where((export) => !export.hasShow)
          .map((export) => export.path)
          .toList();
      final symbolMismatches = <String>[];

      for (final export in exports) {
        final expectedSymbols = allowedSymbolsByPath[export.path];
        if (expectedSymbols == null) {
          continue;
        }
        if (export.symbols.length != expectedSymbols.length ||
            !export.symbols.containsAll(expectedSymbols)) {
          symbolMismatches.add(
            '${export.path}: expected ${_sorted(expectedSymbols)}, '
            'found ${_sorted(export.symbols)}',
          );
        }
      }

      expect(
        unexpectedPaths,
        isEmpty,
        reason: 'noir_low_level.dart contains unexpected exports.',
      );
      expect(
        missingPaths,
        isEmpty,
        reason: 'noir_low_level.dart is missing required exports.',
      );
      expect(
        exportsWithoutShow,
        isEmpty,
        reason: 'Every export must use show to prevent unintended exposure.',
      );
      expect(
        symbolMismatches,
        isEmpty,
        reason: 'Exports must match the exact symbol allowlist.',
      );
    });

    test('lib/noir_low_level.dart does not export FFI', () {
      final file = File('lib/noir_low_level.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'noir_low_level.dart must exist.',
      );

      final source = file.readAsStringSync();
      final exports = _parseExports(source);

      final unexpectedFfiExports = exports
          .where((export) => export.path.startsWith('src/ffi/'))
          .map((export) => export.path)
          .toList();

      expect(
        unexpectedFfiExports,
        isEmpty,
        reason:
            'noir_low_level.dart must not export from src/ffi/ — '
            'that surface lives in noir_ffi.dart.',
      );
    });

    test('lib/noir_ffi.dart exports the raw FFI surface', () {
      final file = File('lib/noir_ffi.dart');
      expect(file.existsSync(), isTrue, reason: 'noir_ffi.dart must exist.');

      final source = file.readAsStringSync();
      final exports = _parseExports(source);

      const allowedSymbolsByPath = _ffiAllowlist;

      final paths = exports.map((export) => export.path).toSet();
      final allowedPaths = allowedSymbolsByPath.keys.toSet();
      final unexpectedPaths = paths.difference(allowedPaths);
      final missingPaths = allowedPaths.difference(paths);
      final exportsWithoutShow = exports
          .where((export) => !export.hasShow)
          .map((export) => export.path)
          .toList();
      final symbolMismatches = <String>[];

      for (final export in exports) {
        final expectedSymbols = allowedSymbolsByPath[export.path];
        if (expectedSymbols == null) {
          continue;
        }
        if (export.symbols.length != expectedSymbols.length ||
            !export.symbols.containsAll(expectedSymbols)) {
          symbolMismatches.add(
            '${export.path}: expected ${_sorted(expectedSymbols)}, '
            'found ${_sorted(export.symbols)}',
          );
        }
      }

      expect(
        unexpectedPaths,
        isEmpty,
        reason: 'noir_ffi.dart contains unexpected exports.',
      );
      expect(
        missingPaths,
        isEmpty,
        reason: 'noir_ffi.dart is missing required exports.',
      );
      expect(
        exportsWithoutShow,
        isEmpty,
        reason: 'Every export must use show to prevent unintended exposure.',
      );
      expect(
        symbolMismatches,
        isEmpty,
        reason: 'Exports must match the exact symbol allowlist.',
      );
    });

    test(
      'lib/noir_ffi.dart exports only exact shared semantic core exceptions',
      () {
        final file = File('lib/noir_ffi.dart');
        expect(file.existsSync(), isTrue, reason: 'noir_ffi.dart must exist.');

        final source = file.readAsStringSync();
        final exports = _parseExports(source);
        const allowedNonFfiPaths = <String>{
          'src/core/color.dart',
          'src/core/terminal_style.dart',
        };

        final unexpectedExports = exports
            .where(
              (export) =>
                  !export.path.startsWith('src/ffi/') &&
                  !allowedNonFfiPaths.contains(export.path),
            )
            .map((export) => export.path)
            .toList();

        expect(
          unexpectedExports,
          isEmpty,
          reason:
              'noir_ffi.dart is the ABI-unstable tier — it must only '
              'export FFI owners plus the exact shared semantic values.',
        );
      },
    );

    test('both new barrels carry their stability doc comments', () {
      final lowLevel = File('lib/noir_low_level.dart').readAsStringSync();
      final ffi = File('lib/noir_ffi.dart').readAsStringSync();

      expect(
        lowLevel,
        contains('advanced'),
        reason:
            'noir_low_level.dart must document that it is the advanced tier.',
      );
      expect(
        ffi,
        contains('Unstable'),
        reason: 'noir_ffi.dart must document its ABI-unstable status.',
      );
    });
  });
}

const Map<String, Set<String>> _lowLevelAllowlist = <String, Set<String>>{
  'src/animation/ticker.dart': {'TickerScheduler'},
  'src/app/tui_binding.dart': {'TuiBinding'},
  'src/core/buffer.dart': {'Buffer', 'DirectBufferAccess'},
  'src/core/capabilities.dart': {'CapabilitiesDetection'},
  'src/core/cursor.dart': {'CursorController', 'CursorManagement'},
  'src/core/input.dart': {
    'InputManager',
    'InputPriority',
    'InputSubscription',
    'KeyboardSupport',
    'MouseSupport',
  },
  'src/core/renderer.dart': {'Renderer'},
  'src/framework/diagnostics.dart': {
    'WidgetInspectorService',
    'describeIdentity',
  },
  'src/framework/element.dart': {'MultiChildRenderObjectWidget'},
  'src/framework/focus_manager.dart': {'FocusManager'},
  'src/framework/owner.dart': {'BuildOwner', 'FrameCallback'},
  'src/framework/widget.dart': {
    'RenderObjectWidget',
    'SingleChildRenderObjectWidget',
  },
  'src/rendering/box.dart': {'RenderBox'},
  'src/rendering/constrained_box.dart': {'RenderConstrainedBox'},
  'src/rendering/decorated_box.dart': {'RenderDecoratedBox'},
  'src/render/geometry.dart': {'Axis'},
  'src/rendering/flex.dart': {'RenderFlex'},
  'src/rendering/object.dart': {
    'HitTestEntry',
    'HitTestResult',
    'HitTestTarget',
    'PaintingContext',
    'RenderObject',
    'RenderObjectWithSingleChild',
  },
  'src/rendering/padding.dart': {'RenderPadding'},
  'src/rendering/paragraph.dart': {'RenderParagraph'},
  'src/rendering/positioned_box.dart': {'RenderPositionedBox'},
  'src/rendering/proxy_box.dart': {'RenderProxyBox'},
  'src/widgets/scroll_box.dart': {'RenderScrollBox'},
  'src/widgets/text_area.dart': {'RenderTextArea'},
  'src/widgets/text_layout.dart': {'TextLayoutEngine'},
};

const Map<String, Set<String>> _ffiAllowlist = <String, Set<String>>{
  'src/core/color.dart': {'Color'},
  'src/core/terminal_style.dart': {
    'Attr',
    'BorderSides',
    'BoxOptions',
    'TextAlign',
  },
  'src/ffi/bindings.dart': {
    'FFIException',
    'OpenTuiBindings',
    'OpenTuiRenderStatus',
  },
  'src/ffi/library.dart': {'OpenTuiLibraryLoadException'},
  'src/ffi/types.dart': {
    'OpenTuiHandle',
    'OptimizedBufferHandle',
    'RendererHandle',
  },
};

List<_ExportDirective> _parseExports(String source) {
  final exportPattern = RegExp(
    r"export\s+'([^']+)'\s*(?:show\s*([^;]+))?;",
    multiLine: true,
    dotAll: true,
  );
  return exportPattern
      .allMatches(source)
      .map((match) {
        final symbols = (match.group(2) ?? '')
            .split(',')
            .map((symbol) => symbol.trim())
            .where((symbol) => symbol.isNotEmpty)
            .toSet();
        return _ExportDirective(
          path: match.group(1)!,
          symbols: symbols,
          hasShow: match.group(2) != null,
        );
      })
      .toList(growable: false);
}

List<String> _sorted(Iterable<String> values) =>
    values.toList(growable: false)..sort();

class _ExportDirective {
  const _ExportDirective({
    required this.path,
    required this.symbols,
    required this.hasShow,
  });

  final String path;
  final Set<String> symbols;
  final bool hasShow;
}
