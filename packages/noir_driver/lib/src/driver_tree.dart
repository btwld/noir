/// Structured tree models and exact client-side locators for Noir drive mode.
library;

import 'dart:async';

import 'package:meta/meta.dart';

import 'driver_polling.dart';

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
///
/// The four constructors each match one node property. [descendantOf] and
/// [at] narrow an existing locator without changing it, which is how two
/// nodes sharing a key become addressable:
///
/// ```dart
/// DriverLocator.byKey('confirm').descendantOf(DriverLocator.byKey('dialog-b'))
/// ```
final class DriverLocator {
  /// Matches a `ValueKey<String>` value exactly.
  const DriverLocator.byKey(String key)
    : _kind = _DriverLocatorKind.key,
      _value = key,
      _ancestor = null,
      _index = null;

  /// Matches a widget runtime type exactly.
  const DriverLocator.byType(String type)
    : _kind = _DriverLocatorKind.type,
      _value = type,
      _ancestor = null,
      _index = null;

  /// Matches framework-provided source text exactly.
  const DriverLocator.byText(String text)
    : _kind = _DriverLocatorKind.text,
      _value = text,
      _ancestor = null,
      _index = null;

  /// Matches the element that directly owns primary focus.
  const DriverLocator.focused()
    : _kind = _DriverLocatorKind.focused,
      _value = null,
      _ancestor = null,
      _index = null;

  const DriverLocator._({
    required _DriverLocatorKind kind,
    required String? value,
    required DriverLocator? ancestor,
    required int? index,
  }) : _kind = kind,
       _value = value,
       _ancestor = ancestor,
       _index = index;

  final _DriverLocatorKind _kind;
  final String? _value;
  final DriverLocator? _ancestor;
  final int? _index;

  /// Narrows this locator to matches sitting under [ancestor].
  ///
  /// The relationship is proper descent at any depth: a node never matches
  /// as its own ancestor, and an intermediate node between the two does not
  /// break the chain. [ancestor] resolves strictly, so an ambiguous ancestor
  /// fails rather than quietly picking one.
  DriverLocator descendantOf(DriverLocator ancestor) => DriverLocator._(
    kind: _kind,
    value: _value,
    ancestor: ancestor,
    index: _index,
  );

  /// Narrows this locator to the match at [index] in document order.
  ///
  /// The weakest locator here: it depends on tree position, so a layout
  /// change silently re-points it. Prefer a key, or [descendantOf], and reach
  /// for this only when the nodes are genuinely interchangeable.
  DriverLocator at(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must be non-negative');
    }
    return DriverLocator._(
      kind: _kind,
      value: _value,
      ancestor: _ancestor,
      index: index,
    );
  }

  bool _matchesNode(DriverNode node) => switch (_kind) {
    _DriverLocatorKind.key => node.key == _value,
    _DriverLocatorKind.type => node.type == _value,
    _DriverLocatorKind.text => node.text == _value,
    _DriverLocatorKind.focused => node.focused,
  };

  /// Describes only the node property, for a staged failure message.
  String get _baseDescription => switch (_kind) {
    _DriverLocatorKind.key => 'key "$_value"',
    _DriverLocatorKind.type => 'type "$_value"',
    _DriverLocatorKind.text => 'text "$_value"',
    _DriverLocatorKind.focused => 'focused',
  };

  @override
  String toString() {
    final ancestor = _ancestor;
    final index = _index;
    return <String>[
      _baseDescription,
      if (ancestor != null) 'inside $ancestor',
      if (index != null) 'at index $index',
    ].join(' ');
  }
}

/// Whether [node] sits strictly below [ancestor].
bool _isDescendantOf(DriverNode node, DriverNode ancestor) {
  for (var walk = node.parent; walk != null; walk = walk.parent) {
    if (identical(walk, ancestor)) return true;
  }
  return false;
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

  /// Returns every match in document order, after any narrowing.
  ///
  /// An ambiguous ancestor is invalid narrowing, not an empty result, and
  /// throws even when the base locator matches nothing.
  List<DriverNode> findAll(DriverLocator locator) => _resolve(locator).matches;

  /// Returns exactly one match, failing on both zero and ambiguity.
  DriverNode find(DriverLocator locator) {
    final resolution = _resolve(locator);
    if (resolution.matches.length != 1) {
      throw _strictMatchError(locator, resolution, treeNodes: _nodes());
    }
    return resolution.matches.single;
  }

  /// Applies a locator stage by stage, keeping what each stage eliminated.
  ///
  /// The stages are recorded rather than collapsed so a failure can say which
  /// one emptied the result: a base that matched nothing, an ancestor that
  /// matched nothing, an ancestor that excluded every base match, or an index
  /// past the end. Collapsing them would cost the diagnostics that make these
  /// locators usable.
  _LocatorResolution _resolve(DriverLocator locator) {
    final base = <DriverNode>[
      for (final node in _nodes())
        if (locator._matchesNode(node)) node,
    ];

    final ancestorLocator = locator._ancestor;
    var narrowed = base;
    DriverNode? ancestor;
    if (ancestorLocator != null) {
      final ancestors = findAll(ancestorLocator);
      if (ancestors.length != 1) {
        final resolution = _LocatorResolution(
          base: base,
          matches: const <DriverNode>[],
          stage: ancestors.isEmpty
              ? _LocatorStage.ancestorMissing
              : _LocatorStage.ancestorAmbiguous,
          ancestorMatches: ancestors,
        );
        if (ancestors.length > 1) {
          throw _strictMatchError(locator, resolution, treeNodes: _nodes());
        }
        return resolution;
      }
      ancestor = ancestors.single;
      narrowed = <DriverNode>[
        for (final node in base)
          if (_isDescendantOf(node, ancestor)) node,
      ];
      if (narrowed.isEmpty && base.isNotEmpty) {
        return _LocatorResolution(
          base: base,
          matches: const <DriverNode>[],
          stage: _LocatorStage.ancestorExcluded,
        );
      }
    }

    final index = locator._index;
    if (index != null) {
      if (index >= narrowed.length) {
        return _LocatorResolution(
          base: narrowed,
          matches: const <DriverNode>[],
          stage: _LocatorStage.indexOutOfRange,
        );
      }
      narrowed = <DriverNode>[narrowed[index]];
    }

    return _LocatorResolution(
      base: base,
      matches: narrowed,
      stage: _LocatorStage.resolved,
    );
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
///
/// [timeout] bounds the whole wait, a pending [fetchTree] response included:
/// once it runs out no further snapshot is requested and a late one is not
/// accepted. The first snapshot is always requested. An ambiguous match and a
/// [fetchTree] error both propagate as themselves rather than as a timeout.
Future<DriverNode> waitForDriverLocator(
  DriverLocator locator, {
  required Future<DriverTree> Function() fetchTree,
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) => pollSnapshots<DriverTree, DriverNode>(
  fetch: fetchTree,
  timeout: timeout,
  pollInterval: pollInterval,
  resolve: (tree) {
    final resolution = tree._resolve(locator);
    if (resolution.matches.length > 1) {
      throw _strictMatchError(locator, resolution, treeNodes: tree._nodes());
    }
    return resolution.matches.singleOrNull;
  },
  onTimeout: (lastTree) => StateError(
    lastTree == null
        ? 'Timed out waiting for $locator: no tree snapshot arrived '
              'within $timeout.'
        : 'Timed out waiting for $locator: 0 matches.'
              '${_zeroMatchHint(locator, lastTree._resolve(locator), lastTree._nodes())}',
  ),
);

/// Polls fresh snapshots until [locator] has no matches.
///
/// An ambiguous ancestor throws; it does not establish absence. [timeout]
/// bounds the whole wait exactly as it does for [waitForDriverLocator].
Future<void> waitForAbsentDriverLocator(
  DriverLocator locator, {
  required Future<DriverTree> Function() fetchTree,
  Duration timeout = const Duration(seconds: 5),
  Duration pollInterval = const Duration(milliseconds: 50),
}) => pollSnapshots<DriverTree, DriverTree>(
  fetch: fetchTree,
  timeout: timeout,
  pollInterval: pollInterval,
  resolve: (tree) => tree.findAll(locator).isEmpty ? tree : null,
  onTimeout: (lastTree) {
    if (lastTree == null) {
      return StateError(
        'Timed out waiting for $locator to be absent: no tree snapshot '
        'arrived within $timeout.',
      );
    }
    final matches = lastTree.findAll(locator);
    return StateError(
      'Timed out waiting for $locator to be absent: '
      '${matches.length} matches remain.\n${_describeMatches(matches)}',
    );
  },
);

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

/// Which stage of a locator produced the result being reported.
enum _LocatorStage {
  /// Every stage ran; [_LocatorResolution.matches] is what survived.
  resolved,

  /// The `descendantOf` ancestor matched no node.
  ancestorMissing,

  /// The `descendantOf` ancestor matched more than one node.
  ancestorAmbiguous,

  /// The node property matched, but nothing sat under the ancestor.
  ancestorExcluded,

  /// `at` asked for a position past the last match.
  indexOutOfRange,
}

/// One locator applied to one snapshot, with the stage that shaped it.
final class _LocatorResolution {
  const _LocatorResolution({
    required this.base,
    required this.matches,
    required this.stage,
    this.ancestorMatches = const <DriverNode>[],
  });

  /// Matches of the node property alone, before narrowing.
  ///
  /// For [_LocatorStage.indexOutOfRange] this is the post-ancestor list, which
  /// is the one whose length the index was compared against.
  final List<DriverNode> base;

  /// What survived every stage.
  final List<DriverNode> matches;

  /// The stage that produced [matches].
  final _LocatorStage stage;

  /// Ancestor candidates, when the ancestor stage is the one that failed.
  final List<DriverNode> ancestorMatches;
}

StateError _strictMatchError(
  DriverLocator locator,
  _LocatorResolution resolution, {
  Iterable<DriverNode> treeNodes = const <DriverNode>[],
}) {
  if (resolution.matches.isNotEmpty) {
    return StateError(
      'Strict locator $locator resolved to ${resolution.matches.length} '
      'matches.\n${_describeMatches(resolution.matches)}',
    );
  }
  return StateError(
    'Strict locator $locator resolved to 0 matches.'
    '${_zeroMatchHint(locator, resolution, treeNodes)}',
  );
}

String _zeroMatchHint(
  DriverLocator locator,
  _LocatorResolution resolution,
  Iterable<DriverNode> nodes,
) {
  final hint = switch (resolution.stage) {
    _LocatorStage.ancestorMissing =>
      'No node matches the ancestor ${locator._ancestor}.\n'
          '${_baseZeroMatchHint(locator._ancestor!, nodes)}',
    _LocatorStage.ancestorAmbiguous =>
      'The ancestor ${locator._ancestor} is itself ambiguous: '
          '${resolution.ancestorMatches.length} matches. Narrow it first.\n'
          '${_describeMatches(resolution.ancestorMatches)}',
    _LocatorStage.ancestorExcluded =>
      '${locator._baseDescription} matched ${resolution.base.length}, but '
          'none is inside ${locator._ancestor}.\n'
          '${_describeMatches(resolution.base)}',
    _LocatorStage.indexOutOfRange =>
      '${locator._ancestor == null ? locator._baseDescription : '${locator._baseDescription} inside ${locator._ancestor}'} '
          'matched ${resolution.base.length}; index ${locator._index} is out '
          'of range.\n${_describeMatches(resolution.base)}',
    _LocatorStage.resolved => _baseZeroMatchHint(locator, nodes),
  };
  return hint.isEmpty ? '' : '\n$hint';
}

/// Explains a node property that matched nothing, with a tree inventory.
String _baseZeroMatchHint(DriverLocator locator, Iterable<DriverNode> nodes) =>
    switch (locator._kind) {
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
