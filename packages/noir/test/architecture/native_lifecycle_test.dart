import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('core native resource owners expose deterministic dispose paths', () {
    final requiredSnippets = <String, List<String>>{
      'lib/src/core/renderer.dart': [
        'Finalizer<RendererHandle>',
        'void dispose()',
        '_finalizer.detach(_finalizerKey)',
        'destroyRenderer(',
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

  test('renderer finalizer swallows destroy failures', () {
    final source = File('lib/src/core/renderer.dart').readAsStringSync();
    final start = source.indexOf(
      'static final Finalizer<RendererHandle> _finalizer',
    );
    final end = source.indexOf('final OpenTuiBindings _bindings');
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final body = source.substring(start, end);
    expect(body, contains('try {'));
    expect(body, contains('} on Object {'));
    expect(body, contains('destroyRenderer(handle)'));
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
          r'RendererHandle get handle \{\s*'
          r'_checkNotDisposed\(\);\s*return _handle;\s*\}',
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
