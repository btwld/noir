// The item builder keeps `selected` positional beside the node it describes.
// ignore_for_file: avoid_positional_boolean_parameters

import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/listenable_liveness.dart';
import '../helpers/tui_test_app.dart';

void main() {
  group('TreeNode and TreeViewController', () {
    test('snapshot collections and reject duplicate IDs across the tree', () {
      final mutableChildren = <TreeNode<String>>[
        TreeNode<String>.leaf(id: 'leaf', value: 'same'),
      ];
      final branch = TreeNode<String>.branch(
        id: 'branch',
        value: 'same',
        children: mutableChildren,
      );
      final emptyBranch = TreeNode<String>.branch(id: 'empty', value: 'empty');
      final roots = <TreeNode<String>>[branch, emptyBranch];
      final controller = TreeViewController<String>(roots: roots);

      mutableChildren.add(TreeNode<String>.leaf(id: 'late', value: 'late'));
      roots.clear();

      expect(branch.children.map((node) => node.id), ['leaf']);
      expect(branch.isBranch, isTrue);
      expect(emptyBranch.isBranch, isTrue);
      expect(emptyBranch.children, isEmpty);
      expect(branch.children.single.isBranch, isFalse);
      expect(controller.roots, [branch, emptyBranch]);
      expect(() => branch.children.add(emptyBranch), throwsUnsupportedError);
      expect(() => controller.roots.clear(), throwsUnsupportedError);
      expect(
        () => controller.expandedIds.add('branch'),
        throwsUnsupportedError,
      );
      controller.dispose();

      expect(
        () => TreeViewController<String>(
          roots: [
            TreeNode<String>.branch(
              id: 'duplicate',
              value: 'one',
              children: [TreeNode<String>.leaf(id: 'duplicate', value: 'two')],
            ),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('flattens expanded branches and selects the first visible root', () {
      final root = TreeNode<String>.branch(
        id: 'root',
        value: 'Root',
        children: [
          TreeNode<String>.leaf(id: 'child', value: 'Child'),
          TreeNode<String>.branch(id: 'empty', value: 'Empty'),
        ],
      );
      final tail = TreeNode<String>.leaf(id: 'tail', value: 'Tail');
      final controller = TreeViewController<String>(
        roots: [root, tail],
        initiallyExpanded: const ['root', 'child', 'missing'],
        initialSelection: 'child',
      );

      expect(controller.visibleNodes.map((node) => node.id), [
        'root',
        'child',
        'empty',
        'tail',
      ]);
      expect(controller.expandedIds, {'root'});
      expect(controller.selectedId, 'child');
      expect(controller.selectedNode?.value, 'Child');
      expect(controller.selectedIndex, 1);
      expect(controller.isExpanded('root'), isTrue);
      expect(controller.isExpanded('child'), isFalse);
      controller.dispose();

      final hiddenSelection = TreeViewController<String>(
        roots: [root, tail],
        initialSelection: 'child',
      );
      expect(hiddenSelection.selectedId, 'root');
      expect(hiddenSelection.selectedIndex, 0);
      hiddenSelection.dispose();

      final empty = TreeViewController<String>(roots: const []);
      expect(empty.visibleNodes, isEmpty);
      expect(empty.selectedId, isNull);
      expect(empty.selectedNode, isNull);
      expect(empty.selectedIndex, -1);
      empty.dispose();
    });

    test(
      'mutations notify once, ignore no-ops, and repair collapsed selection',
      () {
        final controller = TreeViewController<String>(
          roots: [_nestedTree()],
          initiallyExpanded: const ['root', 'folder'],
          initialSelection: 'file',
        );
        var notifications = 0;
        controller.addListener(() => notifications++);

        expect(controller.select('hidden'), isFalse);
        expect(controller.select('file'), isFalse);
        expect(controller.setExpanded('file', expanded: true), isFalse);
        expect(controller.setExpanded('folder', expanded: true), isFalse);
        expect(notifications, 0);

        expect(controller.setExpanded('folder', expanded: false), isTrue);
        expect(controller.selectedId, 'folder');
        expect(notifications, 1);
        expect(controller.setExpanded('folder', expanded: false), isFalse);
        expect(notifications, 1);

        expect(controller.toggle('folder'), isTrue);
        expect(controller.isExpanded('folder'), isTrue);
        expect(notifications, 2);
        expect(controller.toggle('missing'), isFalse);
        expect(notifications, 2);

        expect(controller.select('file'), isTrue);
        expect(controller.selectedId, 'file');
        expect(notifications, 3);
        controller.dispose();
      },
    );

    test(
      'root replacement preserves, repairs, clamps, and prunes atomically',
      () {
        final controller = TreeViewController<String>(
          roots: [_nestedTree()],
          initiallyExpanded: const ['root', 'folder'],
          initialSelection: 'file',
        );
        var notifications = 0;
        controller.addListener(() => notifications++);

        final replacement = _nestedTree(fileValue: 'Replacement');
        controller.updateRoots([replacement]);
        expect(controller.selectedId, 'file');
        expect(controller.selectedNode?.value, 'Replacement');
        expect(controller.expandedIds, {'root', 'folder'});
        expect(notifications, 1);

        final wrapper = TreeNode<String>.branch(
          id: 'wrapper',
          value: 'Wrapper',
          children: [TreeNode<String>.leaf(id: 'file', value: 'Moved')],
        );
        controller.updateRoots([wrapper]);
        expect(controller.selectedId, 'wrapper');
        expect(controller.expandedIds, isEmpty);
        expect(notifications, 2);

        final beforeRoots = controller.roots;
        final beforeVisible = controller.visibleNodes;
        expect(
          () => controller.updateRoots([
            TreeNode<String>.leaf(id: 'duplicate', value: 'one'),
            TreeNode<String>.leaf(id: 'duplicate', value: 'two'),
          ]),
          throwsArgumentError,
        );
        expect(controller.roots, same(beforeRoots));
        expect(controller.visibleNodes, same(beforeVisible));
        expect(controller.selectedId, 'wrapper');
        expect(notifications, 2);
        controller.dispose();

        final clamped = TreeViewController<String>(
          roots: [
            TreeNode<String>.leaf(id: 'a', value: 'A'),
            TreeNode<String>.leaf(id: 'b', value: 'B'),
            TreeNode<String>.leaf(id: 'c', value: 'C'),
          ],
          initialSelection: 'b',
        );
        clamped.updateRoots([
          TreeNode<String>.leaf(id: 'x', value: 'X'),
          TreeNode<String>.leaf(id: 'y', value: 'Y'),
        ]);
        expect(clamped.selectedId, 'y');
        expect(clamped.selectedIndex, 1);
        clamped.dispose();
      },
    );

    test('validation and flattening do not recurse on deep trees', () {
      const depth = 5000;
      var node = TreeNode<int>.leaf(id: 0, value: 0);
      final expanded = <int>[];
      for (var id = 1; id <= depth; id++) {
        expanded.add(id);
        node = TreeNode<int>.branch(id: id, value: id, children: [node]);
      }

      final controller = TreeViewController<int>(
        roots: [node],
        initiallyExpanded: expanded,
        initialSelection: 0,
      );
      expect(controller.visibleNodes, hasLength(depth + 1));
      expect(controller.visibleNodes.first.id, depth);
      expect(controller.visibleNodes.last.id, 0);
      expect(controller.selectedIndex, depth);
      controller.dispose();
    });
  });

  group('TreeView interaction', () {
    test(
      'arrows expand, move, collapse, and report only user selection',
      () async {
        final controller = TreeViewController<String>(roots: [_simpleTree()]);
        final focusNode = FocusNode(debugLabel: 'tree');
        final selections = <Object>[];
        var ancestorRights = 0;
        final app = createTuiTestApp(
          Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event.isPress &&
                  event.logicalKey == LogicalKeyboardKey.arrowRight) {
                ancestorRights++;
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TreeView<String>(
              controller: controller,
              itemBuilder: _labelBuilder,
              focusNode: focusNode,
              autofocus: true,
              onSelectionChanged: (node) => selections.add(node.id),
            ),
          ),
          width: 24,
          height: 8,
        );

        try {
          await _settle(app);
          expect(focusNode.hasFocus, isTrue);
          expect(app.captureFrame().toText(), contains('› ▸ Root'));

          app.mockInput.pressArrow(ArrowDirection.right);
          await _settle(app);
          expect(controller.isExpanded('root'), isTrue);
          expect(app.captureFrame().toText(), contains('› ▾ Root'));
          expect(app.captureFrame().toText(), contains('Child'));

          app.mockInput.pressArrow(ArrowDirection.right);
          await _settle(app);
          expect(
            ancestorRights,
            0,
            reason: 'expanded Right is a handled no-op',
          );

          app.mockInput.pressArrow(ArrowDirection.down);
          await _settle(app);
          expect(controller.selectedId, 'child');
          expect(selections, ['child']);

          app.mockInput.pressArrow(ArrowDirection.right);
          await _settle(app);
          expect(ancestorRights, 1, reason: 'a leaf does not claim Right');

          app.mockInput.pressArrow(ArrowDirection.left);
          await _settle(app);
          expect(controller.selectedId, 'root');
          expect(selections, ['child', 'root']);

          app.mockInput.pressArrow(ArrowDirection.left);
          await _settle(app);
          expect(controller.isExpanded('root'), isFalse);
          expect(selections, ['child', 'root']);

          controller.select('root');
          await _settle(app);
          expect(
            selections,
            ['child', 'root'],
            reason: 'external controller changes do not report as user input',
          );
        } finally {
          app.dispose();
          controller.dispose();
          focusNode.dispose();
        }
      },
    );

    test('Enter and primary click share branch and leaf activation', () async {
      final controller = TreeViewController<String>(roots: [_simpleTree()]);
      final selections = <Object>[];
      final activations = <Object>[];
      final app = createTuiTestApp(
        TreeView<String>(
          controller: controller,
          itemBuilder: _labelBuilder,
          autofocus: true,
          onSelectionChanged: (node) => selections.add(node.id),
          onActivate: (node) => activations.add(node.id),
        ),
        width: 24,
        height: 8,
      );

      try {
        await _settle(app);
        app.mockMouse.click(4, 0);
        await _settle(app);
        expect(controller.isExpanded('root'), isTrue);
        expect(activations, isEmpty, reason: 'branches toggle, not activate');

        app.mockMouse.click(6, 1);
        await _settle(app);
        expect(controller.selectedId, 'child');
        expect(selections, ['child']);
        expect(activations, ['child']);

        app.mockInput.pressEnter();
        await _settle(app);
        expect(activations, ['child', 'child']);
      } finally {
        app.dispose();
        controller.dispose();
      }
    });

    test(
      'activation keeps the chosen node if selection replaces roots',
      () async {
        final controller = TreeViewController<String>(
          roots: [
            TreeNode<String>.leaf(id: 'first', value: 'First'),
            TreeNode<String>.leaf(id: 'second', value: 'Second'),
          ],
        );
        final activations = <Object>[];
        final app = createTuiTestApp(
          TreeView<String>(
            controller: controller,
            itemBuilder: _labelBuilder,
            autofocus: true,
            onSelectionChanged: (node) {
              controller.updateRoots([
                TreeNode<String>.leaf(id: 'replacement', value: 'Replacement'),
              ]);
            },
            onActivate: (node) => activations.add(node.id),
          ),
        );

        try {
          await _settle(app);
          app.mockMouse.click(5, 1);
          await _settle(app);
          expect(activations, ['second']);
          expect(controller.selectedId, 'replacement');
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'null leaf activation is disabled but consumed while branches toggle',
      () async {
        final controller = TreeViewController<String>(roots: [_simpleTree()]);
        var ancestorEnters = 0;
        var ancestorClicks = 0;
        final app = createTuiTestApp(
          PointerListener(
            onPointerDown: (event) => ancestorClicks++,
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (event.isPress &&
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  ancestorEnters++;
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TreeView<String>(
                controller: controller,
                itemBuilder: _labelBuilder,
                autofocus: true,
              ),
            ),
          ),
        );

        try {
          await _settle(app);
          app.mockInput.pressEnter();
          await _settle(app);
          expect(controller.isExpanded('root'), isTrue);

          app.mockInput
            ..pressArrow(ArrowDirection.down)
            ..pressEnter();
          await _settle(app);
          expect(controller.selectedId, 'child');
          expect(ancestorEnters, 0);

          final leafClick = MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 6,
            y: 1,
          );
          app.binding.inputManager.dispatchMouse(leafClick);
          await _settle(app);
          expect(leafClick.isConsumed, isTrue);
          expect(ancestorClicks, 0);

          final blankClick = MouseEvent(
            type: MouseEventType.down,
            button: MouseButton.left,
            x: 6,
            y: 7,
          );
          app.binding.inputManager.dispatchMouse(blankClick);
          await _settle(app);
          expect(blankClick.isConsumed, isFalse);
          expect(ancestorClicks, 1);
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'borrowed controller, focus, and viewport survive replacement',
      () async {
        final key = GlobalKey<_TreeHarnessState>();
        final firstController = TreeViewController<String>(
          roots: [TreeNode<String>.leaf(id: 'first', value: 'First')],
        );
        final secondController = TreeViewController<String>(
          roots: [TreeNode<String>.leaf(id: 'second', value: 'Second')],
        );
        final firstFocus = FocusNode(debugLabel: 'first tree');
        final secondFocus = FocusNode(debugLabel: 'second tree');
        final firstViewport = ViewportController();
        final secondViewport = ViewportController();
        final app = createTuiTestApp(
          _TreeHarness(
            key: key,
            controller: firstController,
            focusNode: firstFocus,
            viewportController: firstViewport,
          ),
        );

        try {
          await _settle(app);
          expect(app.captureFrame().toText(), contains('First'));

          key.currentState!.replaceResources(
            controller: secondController,
            focusNode: secondFocus,
            viewportController: secondViewport,
          );
          await _settle(app);
          expect(app.captureFrame().toText(), contains('Second'));
          expect(firstFocus.isAttached, isFalse);
          expect(secondFocus.isAttached, isTrue);

          firstController.updateRoots([
            TreeNode<String>.leaf(id: 'first', value: 'Stale'),
          ]);
          await _settle(app);
          expect(app.captureFrame().toText(), isNot(contains('Stale')));

          secondController.updateRoots([
            TreeNode<String>.leaf(id: 'second', value: 'Current'),
          ]);
          await _settle(app);
          expect(app.captureFrame().toText(), contains('Current'));
        } finally {
          app.dispose();
        }

        for (final resource in <Listenable>[
          firstController,
          secondController,
          firstFocus,
          secondFocus,
          firstViewport,
          secondViewport,
        ]) {
          expect(isLive(resource), isTrue);
        }
        firstController.dispose();
        secondController.dispose();
        firstFocus.dispose();
        secondFocus.dispose();
        firstViewport.dispose();
        secondViewport.dispose();
      },
    );

    test(
      'empty trees remain focusable and owned focus detaches and disposes',
      () async {
        final key = GlobalKey<_OptionalTreeState>();
        final controller = TreeViewController<String>(roots: const []);
        final app = createTuiTestApp(
          _OptionalTree(key: key, controller: controller),
          width: 8,
          height: 1,
        );

        try {
          await _settle(app);
          final owned = app.binding.buildOwner.focusManager.traversalOrder();
          expect(owned, hasLength(1));
          expect(owned.single.hasFocus, isTrue);

          key.currentState!.hide();
          await _settle(app);
          expect(app.binding.buildOwner.focusManager.traversalOrder(), isEmpty);
          expect(isLive(owned.single), isFalse);
          expect(isLive(controller), isTrue);
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test(
      'compact rows clip long builder content and delegate colors',
      () async {
        final controller = TreeViewController<String>(
          roots: [
            TreeNode<String>.branch(
              id: 'root',
              value: 'Root',
              children: [
                TreeNode<String>.leaf(
                  id: 'long',
                  value: 'this-label-is-much-too-long',
                ),
              ],
            ),
          ],
          initiallyExpanded: const ['root'],
          initialSelection: 'long',
        );
        final app = createTuiTestApp(
          SizedBox(
            width: 12,
            height: 2,
            child: TreeView<String>(
              controller: controller,
              height: 2,
              autofocus: true,
              backgroundColor: Color.magenta,
              selectedBackgroundColor: Color.cyan,
              itemBuilder: (context, node, selected) => Text(
                node.value,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          width: 12,
          height: 2,
        );

        try {
          await _settle(app);
          final frame = app.captureFrame();
          final lines = frame.toText().split('\n');
          expect(lines, hasLength(2));
          expect(lines.every((line) => line.length <= 12), isTrue);
          expect(lines.join(), contains('...'));
          expect(frame.getBackgroundColor(0, 0), Color.magenta);
          expect(frame.getBackgroundColor(0, 1), Color.cyan);
        } finally {
          app.dispose();
          controller.dispose();
        }
      },
    );

    test('stable node IDs preserve row state when positions move', () async {
      var nextInstance = 0;
      final first = TreeNode<String>.leaf(id: 'first', value: 'First');
      final second = TreeNode<String>.leaf(id: 'second', value: 'Second');
      final controller = TreeViewController<String>(roots: [first, second]);
      final app = createTuiTestApp(
        TreeView<String>(
          controller: controller,
          height: 3,
          itemBuilder: (context, node, selected) => _StatefulTreeLabel(
            key: ValueKey<Object>(node.id),
            label: node.value,
            allocateInstance: () => nextInstance++,
          ),
        ),
        width: 24,
        height: 3,
      );

      try {
        await _settle(app);
        expect(app.captureFrame().toText(), contains('First:0'));
        expect(app.captureFrame().toText(), contains('Second:1'));

        controller.updateRoots([
          TreeNode<String>.leaf(id: 'inserted', value: 'Inserted'),
          TreeNode<String>.leaf(id: 'first', value: 'First updated'),
          TreeNode<String>.leaf(id: 'second', value: 'Second updated'),
        ]);
        await _settle(app);

        final frame = app.captureFrame().toText();
        expect(frame, contains('Inserted:2'));
        expect(frame, contains('First updated:0'));
        expect(frame, contains('Second updated:1'));
      } finally {
        app.dispose();
        controller.dispose();
      }
    });
  });
}

TreeNode<String> _nestedTree({String fileValue = 'File'}) =>
    TreeNode<String>.branch(
      id: 'root',
      value: 'Root',
      children: [
        TreeNode<String>.branch(
          id: 'folder',
          value: 'Folder',
          children: [TreeNode<String>.leaf(id: 'file', value: fileValue)],
        ),
      ],
    );

TreeNode<String> _simpleTree() => TreeNode<String>.branch(
  id: 'root',
  value: 'Root',
  children: [TreeNode<String>.leaf(id: 'child', value: 'Child')],
);

Widget _labelBuilder(
  BuildContext context,
  TreeNode<String> node,
  bool selected,
) => Text(node.value);

class _StatefulTreeLabel extends StatefulWidget {
  const _StatefulTreeLabel({
    required this.label,
    required this.allocateInstance,
    super.key,
  });

  final String label;
  final int Function() allocateInstance;

  @override
  State<_StatefulTreeLabel> createState() => _StatefulTreeLabelState();
}

class _StatefulTreeLabelState extends State<_StatefulTreeLabel> {
  late final int _instance = widget.allocateInstance();

  @override
  Widget build(BuildContext context) => Text('${widget.label}:$_instance');
}

class _TreeHarness extends StatefulWidget {
  const _TreeHarness({
    required this.controller,
    required this.focusNode,
    required this.viewportController,
    super.key,
  });

  final TreeViewController<String> controller;
  final FocusNode focusNode;
  final ViewportController viewportController;

  @override
  State<_TreeHarness> createState() => _TreeHarnessState();
}

class _TreeHarnessState extends State<_TreeHarness> {
  late TreeViewController<String> controller = widget.controller;
  late FocusNode focusNode = widget.focusNode;
  late ViewportController viewportController = widget.viewportController;

  void replaceResources({
    required TreeViewController<String> controller,
    required FocusNode focusNode,
    required ViewportController viewportController,
  }) {
    setState(() {
      this.controller = controller;
      this.focusNode = focusNode;
      this.viewportController = viewportController;
    });
  }

  @override
  Widget build(BuildContext context) => TreeView<String>(
    controller: controller,
    focusNode: focusNode,
    viewportController: viewportController,
    autofocus: true,
    itemBuilder: _labelBuilder,
  );
}

class _OptionalTree extends StatefulWidget {
  const _OptionalTree({required this.controller, super.key});

  final TreeViewController<String> controller;

  @override
  State<_OptionalTree> createState() => _OptionalTreeState();
}

class _OptionalTreeState extends State<_OptionalTree> {
  bool visible = true;

  void hide() => setState(() => visible = false);

  @override
  Widget build(BuildContext context) => visible
      ? TreeView<String>(
          controller: widget.controller,
          itemBuilder: _labelBuilder,
          height: 0,
          autofocus: true,
        )
      : const Text('removed');
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}
