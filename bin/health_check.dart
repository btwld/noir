#!/usr/bin/env dart

/// Health check diagnostic tool for Noir bindings.
library;

import 'dart:io' as io;

import 'package:noir/noir.dart';
import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';

/// Runs the packaged health check and records its result as the process exit
/// code.
Future<void> main() async {
  io.exitCode = await HealthCheckRunner().run();
}

/// Exercises packaged native loading and headless renderer operations.
///
/// Renderers created by the default factory use native testing mode, so this
/// diagnostic does not write terminal control sequences or validate real
/// terminal escape rendering.
class HealthCheckRunner {
  /// Creates a health-check runner with injectable resource and output seams.
  HealthCheckRunner({
    Renderer Function(int width, int height)? createRenderer,
    void Function(Renderer renderer)? disposeRenderer,
    void Function(String message)? emit,
  }) : _createRenderer = createRenderer ?? _createTestingRenderer,
       _disposeRenderer = disposeRenderer ?? _defaultDisposeRenderer,
       _emit = emit ?? print;

  final Renderer Function(int width, int height) _createRenderer;
  final void Function(Renderer renderer) _disposeRenderer;
  final void Function(String message) _emit;

  /// Runs every check and returns zero on success or one after any failure.
  Future<int> run() async {
    _emit('Noir Bindings Health Check');
    _emit('==================================');

    final environmentPassed = _checkEnvironment();
    final libraryLoadingPassed = _checkLibraryLoading();
    final basicOperationsPassed = _checkBasicOperations();
    final advancedFeaturesPassed = _checkAdvancedFeatures();
    final allPassed =
        environmentPassed &&
        libraryLoadingPassed &&
        basicOperationsPassed &&
        advancedFeaturesPassed;

    _emit('');
    _emit('=' * 50);
    if (allPassed) {
      _emit('[PASS] ALL CHECKS PASSED');
      _emit('Noir bindings are working correctly!');
      return 0;
    }

    _emit('[FAIL] SOME CHECKS FAILED');
    _emit('Please review the errors above and fix the issues.');
    return 1;
  }

  bool _checkEnvironment() {
    _emit('');
    _emit('[CHECK] Environment Setup');
    var passed = true;

    final envPath = io.Platform.environment['OPENTUI_LIBRARY_PATH'];
    if (envPath != null && envPath.isNotEmpty) {
      _info('OPENTUI_LIBRARY_PATH is set: $envPath');
      if (io.File(envPath).existsSync()) {
        _pass('Environment override library exists');
      } else {
        _fail('Environment override library does not exist');
        passed = false;
      }
    } else {
      _pass('Using bundled Dart native asset resolution');
    }

    return passed;
  }

  bool _checkLibraryLoading() {
    _emit('');
    _emit('[CHECK] Library Loading');
    var passed = true;
    final renderers = <Renderer>[];

    try {
      renderers.add(_createRenderer(10, 10));
      _pass('Successfully loaded OpenTUI library and created renderer');
    } on Object catch (error) {
      _fail('Failed to load OpenTUI library: $error');
      _suggest(
        'Check that the library path is correct and the library is compatible with your system',
      );
      passed = false;
    } finally {
      if (!_disposeOwned(renderers, 'Library renderer')) {
        passed = false;
      }
    }

    return passed;
  }

  bool _checkBasicOperations() {
    _emit('');
    _emit('[CHECK] Basic Operations');
    var passed = true;
    final renderers = <Renderer>[];

    try {
      final renderer = _createRenderer(20, 10);
      renderers.add(renderer);
      _pass('Renderer creation successful');

      final buffer = renderer.nextBuffer;
      _pass('Buffer access successful');

      buffer.clear(Color.black);
      _pass('Buffer clear successful');

      buffer.drawText('Test', 0, 0, Color.white);
      _pass('Text drawing successful');

      buffer.fillRect(0, 1, 5, 2, Color.red);
      _pass('Rectangle filling successful');

      // Renderer.render() invalidates the current buffer by design, so inspect
      // its dimensions before rendering.
      if (buffer.width == 20 && buffer.height == 10) {
        _pass('Buffer dimensions correct (20x10)');
      } else {
        _fail(
          'Buffer dimensions incorrect: ${buffer.width}x${buffer.height}, expected 20x10',
        );
        passed = false;
      }

      renderer.render(force: true);
      _pass('Headless rendering successful');
    } on Object catch (error) {
      _fail('Basic operations failed: $error');
      passed = false;
    } finally {
      if (!_disposeOwned(renderers, 'Basic renderer')) {
        passed = false;
      }
    }

    return passed;
  }

  bool _checkAdvancedFeatures() {
    _emit('');
    _emit('[CHECK] Advanced Features');
    var passed = true;
    final renderers = <Renderer>[];

    try {
      final renderer = _createRenderer(30, 15);
      renderers.add(renderer);
      final buffer = renderer.nextBuffer;

      try {
        buffer.drawText('RGB', 0, 0, Color.rgb(0.5, 0.7, 0.9));
        buffer.drawText('Color', 5, 0, const Color(1, 0.5, 0, 0.8));
        _pass('Color variations working');
      } on Object catch (error) {
        _fail('Color handling failed: $error');
        passed = false;
      }

      try {
        buffer.drawText('Bold', 0, 2, Color.white, attributes: Attr.bold);
        buffer.drawText('Italic', 6, 2, Color.white, attributes: Attr.italic);
        buffer.drawText(
          'Combined',
          13,
          2,
          Color.white,
          attributes: Attr.bold | Attr.underline,
        );
        _pass('Text attributes working');
      } on Object catch (error) {
        _fail('Text attributes failed: $error');
        passed = false;
      }

      try {
        final boxOptions = BoxOptions(title: 'Test', fill: true);
        buffer.drawBox(0, 4, 15, 6, boxOptions, Color.green, Color.blue);
        _pass('Box drawing working');
      } on Object catch (error) {
        _fail('Box drawing failed: $error');
        passed = false;
      }

      try {
        for (var i = 0; i < 10; i++) {
          buffer.fillRect(
            i * 2,
            12,
            2,
            1,
            Color.rgb(i / 10.0, 0.5, 1.0 - i / 10.0),
          );
        }
        _pass('Batch operations working');
      } on Object catch (error) {
        _fail('Batch operations failed: $error');
        passed = false;
      }

      try {
        for (var i = 0; i < 3; i++) {
          renderers.add(_createRenderer(10 + i, 10 + i));
        }
        _pass('Renderer lifecycle creation successful');
      } on Object catch (error) {
        _fail('Renderer lifecycle creation failed: $error');
        passed = false;
      }
    } on Object catch (error) {
      _fail('Advanced features test setup failed: $error');
      passed = false;
    } finally {
      if (!_disposeOwned(renderers, 'Advanced renderers')) {
        passed = false;
      }
    }

    return passed;
  }

  bool _disposeOwned(List<Renderer> renderers, String label) {
    var passed = true;

    for (final renderer in renderers.reversed) {
      try {
        _disposeRenderer(renderer);
      } on Object catch (error) {
        _fail('$label cleanup failed: $error');
        passed = false;
      }
    }

    if (passed && renderers.isNotEmpty) {
      _pass('$label cleanup successful');
    }
    return passed;
  }

  void _pass(String message) {
    _emit('  [PASS] $message');
  }

  void _fail(String message) {
    _emit('  [FAIL] $message');
  }

  void _info(String message) {
    _emit('  [INFO] $message');
  }

  void _suggest(String message) {
    _emit('  [SUGGEST] $message');
  }
}

Renderer _createTestingRenderer(int width, int height) =>
    Renderer.create(width, height, testing: true);

void _defaultDisposeRenderer(Renderer renderer) {
  renderer.dispose();
}
