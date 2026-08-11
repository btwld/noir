import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('render objects with native handles dispose them from detach', () {
    final missingDetach = <String>[];
    final missingDispose = <String>[];

    for (final file in _dartFilesUnder('lib/src/rendering')) {
      final source = file.readAsStringSync();
      if (!_hasNativeHandleField(source)) {
        continue;
      }

      final path = _normalizePath(file.path);
      if (!RegExp(r'\bvoid\s+detach\s*\(').hasMatch(source)) {
        missingDetach.add(path);
        continue;
      }
      if (!RegExp(r'\.\s*(dispose|destroy)\s*\(').hasMatch(source)) {
        missingDispose.add(path);
      }
    }

    expect(
      missingDetach,
      isEmpty,
      reason:
          'RenderObjects that own native handles must release them deterministically.',
    );
    expect(
      missingDispose,
      isEmpty,
      reason: 'Native-handle detach overrides must call dispose/destroy.',
    );
  });

  test('core native resource owners expose deterministic dispose paths', () {
    final requiredSnippets = <String, List<String>>{
      'lib/src/core/renderer.dart': [
        'Finalizer<Pointer<Void>>',
        'void dispose({',
        '_finalizer.detach(_finalizerKey)',
        'destroyRenderer(',
        '_disposed = true',
      ],
      'lib/src/core/text_buffer.dart': [
        'Finalizer<Pointer<Void>>',
        'void dispose()',
        '_finalizer.detach(_finalizerKey)',
        '_utf8Scratch.dispose()',
        'destroyTextBuffer(',
        '_disposed = true',
      ],
      'lib/src/foundation/persistent_utf8_text.dart': [
        'Finalizer<Pointer<Void>>',
        'void dispose()',
        '_finalizer.detach(_finalizerKey)',
        'calloc.free(_pointer)',
        '_disposed = true',
      ],
    };

    for (final MapEntry(:key, :value) in requiredSnippets.entries) {
      final source = File(key).readAsStringSync();
      for (final snippet in value) {
        expect(
          source,
          contains(snippet),
          reason: '$key must retain deterministic native cleanup: $snippet',
        );
      }
    }
  });

  test('Renderer owns one disposed guard for both raw capabilities', () {
    final source = File('lib/src/core/renderer.dart').readAsStringSync();

    expect(
      RegExp(r'''StateError\('Renderer is disposed'\)''').allMatches(source),
      hasLength(1),
    );
    expect(
      RegExp(
        r'''void _checkNotDisposed\(\) \{\s*'''
        r'''if \(_disposed\) throw StateError\('Renderer is disposed'\);\s*'''
        r'\}',
      ).allMatches(source),
      hasLength(1),
    );
    expect(
      source,
      matches(
        RegExp(
          r'Pointer<RendererHandle> get handle \{\s*'
          r'_checkNotDisposed\(\);\s*return _ptr;\s*\}',
        ),
      ),
    );
    expect(
      source,
      matches(
        RegExp(
          r'OpenTuiBindings get bindings \{\s*'
          r'_checkNotDisposed\(\);\s*return _bindings;\s*\}',
        ),
      ),
    );
  });
}

Iterable<File> _dartFilesUnder(String directory) => Directory(directory)
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

bool _hasNativeHandleField(String source) =>
    RegExp(r'\b(?:TextBuffer|Renderer)\?\s+_[A-Za-z0-9_]+').hasMatch(source);

String _normalizePath(String path) =>
    path.replaceAll(Platform.pathSeparator, '/');
