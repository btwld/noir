// ignore_for_file: use_setters_to_change_properties
import 'package:meta/meta.dart';

import 'element.dart';

/// A short identity string: the object's runtime type plus a hex identity hash.
String describeIdentity(Object object) =>
    '${object.runtimeType}#${identityHashCode(object).toRadixString(16)}';

/// Debug inspector that snapshots the mounted element tree as text.
class WidgetInspectorService {
  WidgetInspectorService._();

  /// The shared singleton inspector instance.
  static final WidgetInspectorService instance = WidgetInspectorService._();

  Element? _root;

  /// The currently registered root element, or null when none is registered.
  @internal
  Element? get rootElement => _root;

  /// Registers [element] as the inspected tree root.
  @internal
  void registerRoot(Element element) {
    _root = element;
  }

  /// Clears the registered root if it is [element].
  @internal
  void unregisterRoot(Element element) {
    if (identical(_root, element)) {
      _root = null;
    }
  }

  /// Clears the registered root.
  void clear() {
    _root = null;
  }

  /// Returns the mounted tree as indented lines, descending up to [maxDepth].
  List<String> describeTree({int maxDepth = 2}) {
    final root = _root;
    if (root == null) {
      return const <String>[];
    }

    final lines = <String>[];
    void traverse(Element element, int depth) {
      lines.add('${'  ' * depth}${element.debugDescribeWidget()}');
      if (depth >= maxDepth) {
        return;
      }
      for (final child in element.children) {
        traverse(child, depth + 1);
      }
    }

    traverse(root, 0);
    return lines;
  }
}
