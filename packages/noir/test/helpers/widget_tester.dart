import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/framework/element.dart';
import 'package:test/test.dart';

import 'test_element_host.dart';

/// A testing utility that provides convenient methods for testing widgets.
///
/// Inspired by Flutter's WidgetTester, this class allows you to:
/// - Mount widgets in a test environment
/// - Find widgets and render objects by type
/// - Inspect layout properties
/// - Simulate widget updates
///
/// Mount / layout boilerplate is delegated to [TestElementHost]; this class
/// only adds the find/expect convenience layer.
class WidgetTester {
  /// Creates a new WidgetTester with the specified terminal size.
  WidgetTester({int maxWidth = 100, int maxHeight = 100})
    : _maxWidth = maxWidth,
      _maxHeight = maxHeight,
      _inputManager = InputManager();

  final int _maxWidth;
  final int _maxHeight;
  final InputManager _inputManager;
  TestElementHost? _host;

  /// Mounts a widget in the test environment and performs layout.
  ///
  /// This is similar to Flutter's pumpWidget - it creates the element tree
  /// and runs a complete layout pass.
  void pumpWidget(Widget widget) {
    _host = TestElementHost(inputManager: _inputManager)..mount(widget);
    _host!.pumpFrame(
      constraints: BoxConstraints(maxWidth: _maxWidth, maxHeight: _maxHeight),
    );
  }

  /// Finds the first widget of the specified type in the element tree.
  ///
  /// Returns null if no widget of the specified type is found.
  T? widget<T extends Widget>(Type type) =>
      _findWidget(_host?.root, type) as T?;

  /// Finds the first render object of the specified type in the render tree.
  ///
  /// Returns null if no render object of the specified type is found.
  T? renderObject<T extends RenderObject>(Type type) =>
      _findRenderObject(_host?.root, type) as T?;

  /// Gets the root element that was mounted.
  Element? get element => _host?.root;

  /// Provides access to the shared InputManager used for this tester.
  InputManager get inputManager => _inputManager;

  /// Gets the current layout width of the root element.
  int get width {
    final renderObject = _host?.renderObject;
    if (renderObject is RenderBox) {
      return renderObject.size.width;
    }
    return 0;
  }

  /// Gets the current layout height of the root element.
  int get height {
    final renderObject = _host?.renderObject;
    if (renderObject is RenderBox) {
      return renderObject.size.height;
    }
    return 0;
  }

  /// Disposes of the test environment.
  void dispose() {
    _host?.dispose();
    _host = null;
  }

  // Helper methods for tree traversal

  Widget? _findWidget(Element? element, Type type) {
    if (element == null) return null;

    if (element.widget.runtimeType == type) {
      return element.widget;
    }

    for (final child in element.children) {
      final found = _findWidget(child, type);
      if (found != null) return found;
    }

    return null;
  }

  RenderObject? _findRenderObject(Element? element, Type type) {
    if (element == null) return null;

    if (element is RenderObjectElement) {
      final renderObject = element.renderObject;
      if (renderObject?.runtimeType == type) {
        return renderObject;
      }
    }

    for (final child in element.children) {
      final found = _findRenderObject(child, type);
      if (found != null) return found;
    }

    return null;
  }
}

/// Extension methods to make widget testing more convenient.
extension WidgetTesterExtensions on WidgetTester {
  /// Expects to find exactly one widget of the specified type.
  T expectWidget<T extends Widget>(Type type, {String? reason}) {
    final found = widget<T>(type);
    expect(
      found,
      isNotNull,
      reason: reason ?? 'Expected to find widget of type $type',
    );
    return found!;
  }
}
