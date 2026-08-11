#!/usr/bin/env dart

/// Health check diagnostic tool for Noir bindings.
library;

// ignore_for_file: cascade_invocations

import 'dart:io';
import 'package:noir/noir.dart';
import 'package:noir/noir_ffi.dart';
import 'package:noir/noir_low_level.dart';

/// Runs all health checks in dependency order and exits with code 0 on
/// success or 1 if any check fails.
void main() async {
  print('Noir Bindings Health Check');
  print('==================================\n');

  var allPassed = true;

  allPassed &= await _checkEnvironment();
  allPassed &= await _checkLibraryLoading();
  allPassed &= await _checkBasicOperations();
  allPassed &= await _checkAdvancedFeatures();

  // Final report
  print('\n${'=' * 50}');
  if (allPassed) {
    print('✅ ALL CHECKS PASSED');
    print('Noir bindings are working correctly!');
    exit(0);
  } else {
    print('❌ SOME CHECKS FAILED');
    print('Please review the errors above and fix the issues.');
    exit(1);
  }
}

Future<bool> _checkEnvironment() async {
  print('🔍 Checking Environment Setup...');
  var passed = true;

  final envPath = Platform.environment['OPENTUI_LIBRARY_PATH'];
  if (envPath != null && envPath.isNotEmpty) {
    _info('OPENTUI_LIBRARY_PATH is set: $envPath');
    if (File(envPath).existsSync()) {
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

Future<bool> _checkLibraryLoading() async {
  print('\n🔍 Checking Library Loading...');
  var passed = true;

  try {
    // Test high-level API which handles library loading
    final renderer = Renderer.create(10, 10);
    _pass('Successfully loaded OpenTUI library and created renderer');

    try {
      renderer.dispose();
      _pass('Successfully cleaned up renderer');
    } catch (e) {
      _warn('Warning during cleanup: $e');
    }
  } catch (e) {
    _fail('Failed to load OpenTUI library: $e');
    _suggest(
      'Check that the library path is correct and the library is compatible with your system',
    );
    passed = false;
  }

  return passed;
}

Future<bool> _checkBasicOperations() async {
  print('\n🔍 Checking Basic Operations...');
  var passed = true;

  try {
    final renderer = Renderer.create(20, 10);
    _pass('Renderer creation successful');

    try {
      final buf = renderer.nextBuffer;
      _pass('Buffer access successful');

      buf.clear(Color.black);
      _pass('Buffer clear successful');

      buf.drawText('Test', 0, 0, Color.white);
      _pass('Text drawing successful');

      buf.fillRect(0, 1, 5, 2, Color.red);
      _pass('Rectangle filling successful');

      // Test buffer dimensions before rendering. Renderer.render() invalidates
      // the current buffer by design.
      if (buf.width == 20 && buf.height == 10) {
        _pass('Buffer dimensions correct (20x10)');
      } else {
        _fail(
          'Buffer dimensions incorrect: ${buf.width}x${buf.height}, expected 20x10',
        );
        passed = false;
      }

      // Test rendering
      renderer.render(force: true);
      _pass('Rendering successful');
    } finally {
      renderer.dispose();
      _pass('Renderer cleanup successful');
    }
  } catch (e) {
    _fail('Basic operations failed: $e');
    passed = false;
  }

  return passed;
}

Future<bool> _checkAdvancedFeatures() async {
  print('\n🔍 Checking Advanced Features...');
  var passed = true;

  try {
    final renderer = Renderer.create(30, 15);
    final buf = renderer.nextBuffer;

    // Test color variations
    try {
      buf.drawText('RGB', 0, 0, Color.rgb(0.5, 0.7, 0.9));
      buf.drawText('Color', 5, 0, Color(1, 0.5, 0, 0.8));
      _pass('Color variations working');
    } catch (e) {
      _fail('Color handling failed: $e');
      passed = false;
    }

    // Test text attributes
    try {
      buf.drawText('Bold', 0, 2, Color.white, attributes: Attr.bold);
      buf.drawText('Italic', 6, 2, Color.white, attributes: Attr.italic);
      buf.drawText(
        'Combined',
        13,
        2,
        Color.white,
        attributes: Attr.bold | Attr.underline,
      );
      _pass('Text attributes working');
    } catch (e) {
      _fail('Text attributes failed: $e');
      passed = false;
    }

    // Test box drawing
    try {
      const boxOptions = BoxOptions(title: 'Test', fill: true);
      buf.drawBox(0, 4, 15, 6, boxOptions, Color.green, Color.blue);
      _pass('Box drawing working');
    } catch (e) {
      _fail('Box drawing failed: $e');
      passed = false;
    }

    // Test large operations
    try {
      for (var i = 0; i < 10; i++) {
        buf.fillRect(i * 2, 12, 2, 1, Color.rgb(i / 10.0, 0.5, 1.0 - i / 10.0));
      }
      _pass('Batch operations working');
    } catch (e) {
      _fail('Batch operations failed: $e');
      passed = false;
    }

    // Test memory management
    try {
      final renderers = <Renderer>[];
      for (var i = 0; i < 3; i++) {
        renderers.add(Renderer.create(10 + i, 10 + i));
      }
      for (final r in renderers) {
        r.dispose();
      }
      _pass('Memory management working');
    } catch (e) {
      _fail('Memory management failed: $e');
      passed = false;
    }

    renderer.dispose();
  } catch (e) {
    _fail('Advanced features test setup failed: $e');
    passed = false;
  }

  return passed;
}

void _pass(String message) {
  print('  ✅ $message');
}

void _fail(String message) {
  print('  ❌ $message');
}

void _warn(String message) {
  print('  ⚠️  $message');
}

void _info(String message) {
  print('  ℹ️  $message');
}

void _suggest(String message) {
  print('  💡 Suggestion: $message');
}
