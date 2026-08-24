// ignore_for_file: cascade_invocations
import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

void main() {
  group('BuildContext diagnostics helpers', () {
    test(
      'visitAncestorElements and visitChildElements traverse expected nodes',
      () {
        final owner = BuildOwner();
        owner.setFrameCallback(() {});

        final leafKey = GlobalKey<_LeafState>();
        final widget = _Root(
          child: _Intermediate(child: _Leaf(key: leafKey)),
        );

        final element = widget.createElement();
        element.mount(null, owner);

        final leafContext = leafKey.currentContext!;
        final ancestors = <String>[];
        leafContext.visitAncestorElements((element) {
          ancestors.add(element.widget.runtimeType.toString());
          return true;
        });

        expect(ancestors, containsAllInOrder(['_Intermediate', '_Root']));

        final rootContext = element.buildContext;
        final childWidgets = <String>[];
        rootContext.visitChildElements(
          (child) => childWidgets.add(child.widget.runtimeType.toString()),
        );

        expect(childWidgets, ['_Intermediate']);

        element.unmount();
      },
    );
  });

  group('WidgetInspectorService', () {
    test('registers and describes widget tree', () {
      final inspector = WidgetInspectorService.instance;
      inspector.clear();

      final widget = _Root(child: _Intermediate(child: const _Leaf()));

      final app = runTuiApp(widget, headless: true);
      final tree = inspector.describeTree(maxDepth: 10);

      expect(inspector.rootElement, isNotNull);
      expect(tree, isNotEmpty);
      // runTuiApp mounts its app scope and private root overlay above the
      // caller's root, so the scope is the tree root and the caller's widgets
      // hang below the overlay theater.
      expect(tree.first.startsWith('_TuiAppScope'), isTrue);
      expect(tree.any((line) => line.contains('RootOverlay')), isTrue);
      expect(tree.any((line) => line.trim().startsWith('_Root')), isTrue);
      expect(tree.any((line) => line.trim().startsWith('_Leaf')), isTrue);

      app.dispose();
      expect(inspector.rootElement, isNull);
      inspector.clear();
    });
  });
}

class _Root extends StatelessWidget {
  const _Root({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Intermediate extends StatelessWidget {
  const _Intermediate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(child: child);
}

class _Leaf extends StatefulWidget {
  const _Leaf({super.key});

  @override
  State<_Leaf> createState() => _LeafState();
}

class _LeafState extends State<_Leaf> {
  @override
  Widget build(BuildContext context) => Container();
}
