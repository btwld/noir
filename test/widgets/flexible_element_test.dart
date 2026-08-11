import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart'
    show RenderBox, RenderFlex, RenderObject, RenderObjectWidget;
import 'package:test/test.dart';

import '../helpers/test_element_host.dart';

void main() {
  group('FlexibleElement rebuilds', () {
    test('replaces a stateful child with a stateless child', () {
      final log = <String>[];
      final key = GlobalKey<_SwapFlexibleChildState>();
      final host = TestElementHost();
      try {
        host
          ..mount(_SwapFlexibleChild(key: key, log: log))
          ..pumpFrame(
            constraints: const BoxConstraints(maxWidth: 40, maxHeight: 10),
          );

        expect(log, contains('stateful build'));

        log.clear();
        key.currentState!.showStatelessChild();

        expect(
          () => host.pumpFrame(
            constraints: const BoxConstraints(maxWidth: 40, maxHeight: 10),
          ),
          returnsNormally,
        );
        expect(log, contains('stateful dispose'));
        expect(log, contains('stateless build'));
      } finally {
        host.dispose();
      }
    });

    test('replaces one render-object child type with another', () {
      final key = GlobalKey<_SwapFlexibleChildState>();
      final host = TestElementHost();
      try {
        host
          ..mount(_SwapFlexibleChild(key: key, log: const [], renderSwap: true))
          ..pumpFrame(
            constraints: const BoxConstraints(maxWidth: 40, maxHeight: 10),
          );

        key.currentState!.showStatelessChild();

        expect(
          () => host.pumpFrame(
            constraints: const BoxConstraints(maxWidth: 40, maxHeight: 10),
          ),
          returnsNormally,
        );
        expect(
          (host.renderObject! as RenderFlex).childrenBoxes.single,
          isA<_RenderLeafBBox>(),
        );
      } finally {
        host.dispose();
      }
    });
  });
}

class _SwapFlexibleChild extends StatefulWidget {
  const _SwapFlexibleChild({
    required this.log,
    this.renderSwap = false,
    super.key,
  });

  final List<String> log;
  final bool renderSwap;

  @override
  State<_SwapFlexibleChild> createState() => _SwapFlexibleChildState();
}

class _SwapFlexibleChildState extends State<_SwapFlexibleChild> {
  bool _showSecond = false;

  void showStatelessChild() {
    setState(() => _showSecond = true);
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.renderSwap
        ? (_showSecond ? const _RenderLeafB() : const _RenderLeafA())
        : (_showSecond
              ? _StatelessLeaf(widget.log)
              : _StatefulLeaf(widget.log));
    return Row(children: [Flexible(child: child)]);
  }
}

class _StatefulLeaf extends StatefulWidget {
  const _StatefulLeaf(this.log);

  final List<String> log;

  @override
  State<_StatefulLeaf> createState() => _StatefulLeafState();
}

class _StatefulLeafState extends State<_StatefulLeaf> {
  @override
  Widget build(BuildContext context) {
    widget.log.add('stateful build');
    return const SizedBox(width: 2, height: 1);
  }

  @override
  void dispose() {
    widget.log.add('stateful dispose');
    super.dispose();
  }
}

class _StatelessLeaf extends StatelessWidget {
  const _StatelessLeaf(this.log);

  final List<String> log;

  @override
  Widget build(BuildContext context) {
    log.add('stateless build');
    return const SizedBox(width: 3, height: 1);
  }
}

class _RenderLeafA extends RenderObjectWidget {
  const _RenderLeafA();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeafABox();
}

class _RenderLeafB extends RenderObjectWidget {
  const _RenderLeafB();

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLeafBBox();

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderLeafBBox renderObject,
  ) {}
}

class _RenderLeafABox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(2, 1);
  }
}

class _RenderLeafBBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const Size(3, 1);
  }
}
