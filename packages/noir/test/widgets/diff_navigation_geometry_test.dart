import 'package:noir/noir.dart';
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
    super.key,
  });
  final DiffViewController navigation;
  final ScrollController scroll;
  @override
  State<_GeometryHost> createState() => _GeometryHostState();
}

class _GeometryHostState extends State<_GeometryHost> {
  final document = const UnifiedDiffParser().parse(_patch);
  int rowHeight = 3;
  void grow() => setState(() => rowHeight = 4);
  @override
  Widget build(BuildContext context) => DiffView(
    document: document,
    controller: widget.navigation,
    scrollController: widget.scroll,
    showLineNumbers: false,
    rowBuilder: (context, file, hunk, line, defaultRow) =>
        SizedBox(height: rowHeight, child: defaultRow),
  );
}
