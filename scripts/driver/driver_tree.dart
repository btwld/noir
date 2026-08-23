/// Structured tree models and exact client-side locators for Noir drive mode.
library;

import 'dart:async';

import 'package:meta/meta.dart';

/// One zero-based terminal cell.
@immutable
final class DriverPoint {
  /// Creates a point at ([x], [y]).
  const DriverPoint(this.x, this.y);

  /// Parses a serialized driver point.
  factory DriverPoint.fromJson(Map<String, Object?> json) =>
      DriverPoint(json['x']! as int, json['y']! as int);

  /// Zero-based column.
  final int x;

  /// Zero-based row.
  final int y;

  /// Serializes this point for CLI JSON output.
  Map<String, Object?> toJson() => <String, Object?>{'x': x, 'y': y};

  @override
  bool operator ==(Object other) =>
      other is DriverPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

enum _DriverLocatorKind { key, type, text, focused }

/// An exact, case-sensitive query evaluated against a fresh [DriverTree].
final class DriverLocator {
  /// Matches a `ValueKey<String>` value exactly.
  const DriverLocator.byKey(String key)
    : _kind = _DriverLocatorKind.key,
      _value = key;

  /// Matches a widget runtime type exactly.
  const DriverLocator.byType(String type)
    : _kind = _DriverLocatorKind.type,
      _value = type;

  /// Matches framework-provided source text exactly.
  const DriverLocator.byText(String text)
    : _kind = _DriverLocatorKind.text,
      _value = text;

  /// Matches the element that directly owns primary focus.
  const DriverLocator.focused()
    : _kind = _DriverLocatorKind.focused,
      _value = null;

  final _DriverLocatorKind _kind;
  final String? _value;

  bool _matches(DriverNode node) => switch (_kind) {
    _DriverLocatorKind.key => node.key == _value,
    _DriverLocatorKind.type => node.type == _value,
    _DriverLocatorKind.text => node.text == _value,
    _DriverLocatorKind.focused => node.focused,
  };

  @override
  String toString() => switch (_kind) {
    _DriverLocatorKind.key => 'key "$_value"',
    _DriverLocatorKind.type => 'type "$_value"',
    _DriverLocatorKind.text => 'text "$_value"',
    _DriverLocatorKind.focused => 'focused',
  };
}

/// One immutable node in a structured driver snapshot.
final class DriverNode {
  DriverNode._({
    required this.type,
    required this.key,
    required this.text,
    required this.focused,
    required this.hasFocusedDescendant,
    required this.hitPoint,
    required DriverNode? parent,
  }) : _parent = parent;

  factory DriverNode._fromJson(
    Map<String, Object?> json, {
    required DriverNode? parent,
  }) {
    final pointJson = json['hitPoint'];
    final node = DriverNode._(
      type: json['type']! as String,
      key: json['key'] as String?,
      text: json['text'] as String?,
      focused: json['focused']! as bool,
      hasFocusedDescendant: json['hasFocusedDescendant']! as bool,
      hitPoint: pointJson == null
          ? null
          : DriverPoint.fromJson(Map<String, Object?>.from(pointJson as Map)),
      parent: parent,
    );
    node.children = List<DriverNode>.unmodifiable(<DriverNode>[
      for (final child in json['children']! as List<Object?>)
        DriverNode._fromJson(
          Map<String, Object?>.from(child! as Map),
          parent: node,
        ),
    ]);
    return node;
  }

  /// Exact widget runtime type.
  final String type;

  /// Stable string key, or null for every other key shape.
  final String? key;

  /// Exact framework-provided source text, when present.
  final String? text;

  /// Whether this node directly owns primary focus.
  final bool focused;

  /// Whether any descendant owns primary focus.
  final bool hasFocusedDescendant;

  /// A visible cell whose production hit test resolves through this node.
  final DriverPoint? hitPoint;

  final DriverNode? _parent;

  /// Parent in this snapshot, or null for the root.
  DriverNode? get parent => _parent;

  /// Direct children in document order.
  late final List<DriverNode> children;

  /// Serializes this node and its descendants.
  Map<String, Object?> toJson() => <String, Object?>{
    'type': type,
    'key': key,
    'text': text,
    'focused': focused,
    'hasFocusedDescendant': hasFocusedDescendant,
    'hitPoint': hitPoint?.toJson(),
    'children': <Map<String, Object?>>[
      for (final child in children) child.toJson(),
    ],
  };

  /// This node's own visible pointer cell, when one exists.
  ///
  /// Intentionally not an ancestor walk: a hidden or non-pointer node must
  /// not borrow a parent or child's route.
  DriverPoint? get actionPoint => hitPoint;

  @override
  String toString() =>
      '$type(key: ${key ?? 'null'}, text: ${text ?? 'null'}, '
      'focused: $focused, hitPoint: ${hitPoint ?? 'null'})';
}

/// One freshly parsed structured element-tree snapshot.
final class DriverTree {
  /// Creates a tree with an optional mounted [root].
  const DriverTree(this.root);

  /// Parses an `ext.noir.driver.tree` response.
  factory DriverTree.fromJson(Map<String, Object?> json) {
    final rootJson = json['root'];
    return DriverTree(
      rootJson == null
          ? null
          : DriverNode._fromJson(
              Map<String, Object?>.from(rootJson as Map),
              parent: null,
            ),
    );
  }

  /// Mounted root, or null before an app is mounted or after it is removed.
  final DriverNode? root;

  /// Serializes the tree using the VM-service wire shape.
  Map<String, Object?> toJson() => <String, Object?>{'root': root?.toJson()};

  /// Returns every exact match in document order.
  List<DriverNode> findAll(DriverLocator locator) => <DriverNode>[
    for (final node in _nodes())
      if (locator._matches(node)) node,
  ];

  /// Returns exactly one match, failing on both zero and ambiguity.
  DriverNode find(DriverLocator locator) {
    final matches = findAll(locator);
    if (matches.length != 1) {
      throw _strictMatchError(locator, matches, treeNodes: _nodes());
    }
    return matches.single;
  }

  Iterable<DriverNode> _nodes() sync* {
    final root = this.root;
    if (root == null) return;
    final pending = <DriverNode>[root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      yield node;
      pending.addAll(node.children.reversed);
    }
  }
}

/// Polls fresh snapshots until [locator] has exactly one match.
Future<DriverNode> waitForDriverLocator(
  DriverLocator locator, {
  required Future<DriverTree> Function() fetchTree,
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  DriverTree? lastTree;
  while (true) {
    lastTree = await fetchTree();
    final matches = lastTree.findAll(locator);
    if (matches.length > 1) {
      throw _strictMatchError(locator, matches, treeNodes: lastTree._nodes());
    }
    if (matches.length == 1) {
      return matches.single;
    }
    if (!DateTime.now().isBefore(deadline)) {
      throw StateError(
        'Timed out waiting for $locator: 0 matches.'
        '${_zeroMatchHint(locator, lastTree._nodes())}',
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// Polls fresh snapshots until [locator] has no matches.
Future<void> waitForAbsentDriverLocator(
  DriverLocator locator, {
  required Future<DriverTree> Function() fetchTree,
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final matches = (await fetchTree()).findAll(locator);
    if (matches.isEmpty) return;
    if (!DateTime.now().isBefore(deadline)) {
      throw StateError(
        'Timed out waiting for $locator to be absent: '
        '${matches.length} matches remain.\n${_describeMatches(matches)}',
      );
    }
    await Future<void>.delayed(pollInterval);
  }
}

/// Resolves [locator] from one fresh snapshot and clicks its actionable point.
Future<void> clickDriverLocator(
  DriverLocator locator, {
  required Future<DriverTree> Function() fetchTree,
  required FutureOr<void> Function(DriverPoint point) click,
}) async {
  final node = (await fetchTree()).find(locator);
  final point = node.actionPoint;
  if (point == null) {
    throw StateError(
      'Cannot click $locator: the match is offscreen, fully obscured, or '
      'has no visible pointer route. Match: $node',
    );
  }
  await click(point);
}

StateError _strictMatchError(
  DriverLocator locator,
  List<DriverNode> matches, {
  Iterable<DriverNode> treeNodes = const <DriverNode>[],
}) {
  if (matches.isNotEmpty) {
    return StateError(
      'Strict locator $locator resolved to ${matches.length} matches.\n'
      '${_describeMatches(matches)}',
    );
  }
  return StateError(
    'Strict locator $locator resolved to 0 matches.'
    '${_zeroMatchHint(locator, treeNodes)}',
  );
}

String _zeroMatchHint(DriverLocator locator, Iterable<DriverNode> nodes) {
  final hint = switch (locator._kind) {
    _DriverLocatorKind.type =>
      'Type locators match runtimeType exactly. Types in this tree:\n'
          '${_describeInventory(_distinct(nodes.map((node) => node.type)))}',
    _DriverLocatorKind.key =>
      'Keys in this tree:\n'
          '${_describeInventory(_distinct(nodes.map((node) => node.key)))}',
    _DriverLocatorKind.text =>
      'Text locators read Text and RichText source, not painted cells.\n'
          'Keys in this tree:\n'
          '${_describeInventory(_distinct(nodes.map((node) => node.key)))}',
    _DriverLocatorKind.focused => 'No node in this tree has primary focus.',
  };
  return hint.isEmpty ? '' : '\n$hint';
}

String _describeMatches(List<DriverNode> matches) =>
    matches.map((node) => '  - $node').join('\n');

String _describeInventory(Iterable<String> values) {
  final items = values.toList()..sort();
  if (items.isEmpty) {
    return '  (none)';
  }
  return items.map((value) => '  - $value').join('\n');
}

Iterable<String> _distinct(Iterable<String?> values) {
  final seen = <String>{};
  return <String>[
    for (final value in values)
      if (value != null && value.isNotEmpty && seen.add(value)) value,
  ];
}
