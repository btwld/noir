import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import '../helpers/tui_test_app.dart';

const _patch = '''
--- a.txt
+++ a.txt
@@ -1 +1 @@ first
-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
+bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
@@ -10 +10 @@ second
-c
+d
''';

void main() {
  test('rebuilds retain custom-row layout and hunk measurements', () {
    var layouts = 0;
    final navigation = DiffViewController();
    final scroll = ScrollController();
    final key = GlobalKey<_GeometryHostState>();
    final app = createTuiTestApp(
      _GeometryHost(
        key: key,
        navigation: navigation,
        scroll: scroll,
        row: _CountedRow(() => layouts++),
      ),
      width: 40,
      height: 2,
    );
    addTearDown(navigation.dispose);
    addTearDown(scroll.dispose);
    addTearDown(app.dispose);
    app.pumpFrame();
    final initialLayouts = layouts;
    expect(initialLayouts, greaterThan(0));

    key.currentState!.rebuild();
    app.pumpFrame();
    expect(layouts, initialLayouts);

    // A fresh presentation clears hunk geometry even when the replacement
    // rows themselves have not changed or requested another layout.
    key.currentState!.replaceDocument();
    app.pumpFrame();
    navigation.jumpToHunk(1);
    app.pumpFrame();
    expect(scroll.offset, 9);
  });

  test('custom row height changes replace previous hunk geometry', () async {
    final navigation = DiffViewController();
    final scroll = ScrollController();
    final key = GlobalKey<_GeometryHostState>();
    final app = createTuiTestApp(
      _GeometryHost(key: key, navigation: navigation, scroll: scroll),
      width: 40,
      height: 2,
    );
    addTearDown(navigation.dispose);
    addTearDown(scroll.dispose);
    addTearDown(app.dispose);
    app.pumpFrame();
    navigation.jumpToHunk(1);
    app.pumpFrame();
    expect(scroll.offset, 9);

    key.currentState!.grow();
    app.pumpFrame();
    navigation.jumpToHunk(1);
    app.pumpFrame();
    expect(scroll.offset, 12);
    expect(app.captureFrame().toText(), contains('second'));
  });

  for (final customRows in [false, true]) {
    test(
      'hunk jumps follow actual layout (custom rows: $customRows)',
      () async {
        final navigation = DiffViewController()..jumpToHunk(1);
        final scroll = ScrollController();
        final app = createTuiTestApp(
          DiffView(
            document: const UnifiedDiffParser().parse(_patch),
            controller: navigation,
            scrollController: scroll,
            wrap: true,
            showLineNumbers: false,
            rowBuilder: customRows
                ? (context, file, hunk, line, defaultRow) =>
                      SizedBox(height: 3, child: defaultRow)
                : null,
          ),
          width: 40,
          height: 2,
        );
        addTearDown(navigation.dispose);
        addTearDown(scroll.dispose);
        addTearDown(app.dispose);
        app.pumpFrame();
        await Future<void>.delayed(Duration.zero);
        app.pumpFrame();
        expect(app.captureFrame().toText(), contains('second'));
        if (customRows) expect(scroll.offset, 9);

        app.resize(20, 2);
        app.pumpFrame();
        navigation.jumpToHunk(1);
        app.pumpFrame();
        expect(app.captureFrame().toText(), contains('second'));
        if (customRows) expect(scroll.offset, 9);
      },
    );
  }
}

class _GeometryHost extends StatefulWidget {
  const _GeometryHost({
    required this.navigation,
    required this.scroll,
    this.row,
    super.key,
  });
  final DiffViewController navigation;
  final ScrollController scroll;
  final Widget? row;
  @override
  State<_GeometryHost> createState() => _GeometryHostState();
}

class _GeometryHostState extends State<_GeometryHost> {
  DiffDocument document = const UnifiedDiffParser().parse(_patch);
  int rowHeight = 3;
  void grow() => setState(() => rowHeight = 4);
  void rebuild() => setState(() {});
  void replaceDocument() =>
      setState(() => document = const UnifiedDiffParser().parse(_patch));
  @override
  Widget build(BuildContext context) => DiffView(
    document: document,
    controller: widget.navigation,
    scrollController: widget.scroll,
    showLineNumbers: false,
    rowBuilder: (context, file, hunk, line, defaultRow) =>
        widget.row ?? SizedBox(height: rowHeight, child: defaultRow),
  );
}

class _CountedRow extends SingleChildRenderObjectWidget {
  const _CountedRow(this.onLayout) : super(child: const SizedBox(height: 3));

  final void Function() onLayout;

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _RenderCountedRow(onLayout);
}

class _RenderCountedRow extends RenderProxyBox {
  _RenderCountedRow(this.onLayout);

  final void Function() onLayout;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    onLayout();
    super.performBoxLayout(constraints);
  }
}
