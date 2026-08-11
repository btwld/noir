import 'dart:io';

import 'package:noir/noir.dart';
import 'package:noir/src/app/tui_binding.dart' show runTuiAppForTesting;
import 'package:noir/src/core/cursor.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/constrained_box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/padding.dart';
import 'package:noir/src/rendering/render_view.dart';
import 'package:noir/src/widgets/select.dart';
import 'package:noir/src/widgets/text_area.dart';
import 'package:test/test.dart';

import '../helpers/widget_tester.dart';

void main() {
  test('public dimension widgets reject negative values in debug mode', () {
    expect(() => SizedBox(width: -1), throwsA(isA<AssertionError>()));
    expect(
      () => SizedBox.square(dimension: -1),
      throwsA(isA<AssertionError>()),
    );
    expect(() => Container(height: -1), throwsA(isA<AssertionError>()));
    expect(() => TextArea(height: -1), throwsA(isA<AssertionError>()));
    expect(
      () => Select<String>(options: const [], height: -1),
      throwsA(isA<AssertionError>()),
    );
    expect(() => EdgeInsets(left: -1), throwsA(isA<AssertionError>()));
  });

  test('render configuration rejects invalid values before mutation', () {
    final constrained = RenderConstrainedBox(
      additionalConstraints: const BoxConstraints(maxWidth: 4),
    );
    expect(
      () => constrained.additionalConstraints = _BadBoxConstraints(),
      throwsArgumentError,
    );
    expect(constrained.additionalConstraints.maxWidth, 4);

    final constrainedChild = _ProbeRenderBox();
    expect(
      () => RenderConstrainedBox(
        additionalConstraints: _BadBoxConstraints(),
        child: constrainedChild,
      ),
      throwsArgumentError,
    );
    expect(constrainedChild.parent, isNull);

    final padding = RenderPadding(padding: EdgeInsets.zero);
    expect(() => padding.padding = _BadInsets(), throwsArgumentError);
    expect(padding.padding, EdgeInsets.zero);

    final paddedChild = _ProbeRenderBox();
    expect(
      () => RenderPadding(padding: _BadInsets(), child: paddedChild),
      throwsArgumentError,
    );
    expect(paddedChild.parent, isNull);

    final view = RenderView(width: 4, height: 2);
    expect(() => view.updateTerminalSize(-1, 2), throwsArgumentError);
    expect(view.terminalConstraints.maxWidth, 4);
    expect(view.terminalConstraints.maxHeight, 2);

    final zeroView = RenderView()
      ..layout(const BoxConstraints.tight(width: 0, height: 0));
    expect(zeroView.size, Size.zero);

    final textArea = RenderTextArea(
      cursorController: CursorController(),
      lines: const [''],
      cursorLine: 0,
      cursorColumn: 0,
      placeholder: null,
      heightLines: 2,
      explicitWidth: 4,
      color: Color.white,
      backgroundColor: null,
      cursorColor: Color.white,
      cursorStyle: CursorStyle.block,
      focused: false,
      scrollLine: 0,
      scrollCell: 0,
    );
    expect(() => textArea.heightLines = -1, throwsArgumentError);
    expect(() => textArea.explicitWidth = -1, throwsArgumentError);

    final select = RenderSelect<String>(
      options: const [],
      highlighted: 0,
      scrollOffset: 0,
      visibleRows: 2,
      showScrollIndicator: false,
      color: Color.white,
      backgroundColor: null,
      selectedBackgroundColor: Color.black,
      selectedTextColor: Color.white,
      descriptionColor: Color.white,
    );
    expect(() => select.visibleRows = -1, throwsArgumentError);
  });

  test(
    'controllers reject invalid extents before mutation or notification',
    () {
      final viewport = ViewportController(
        contentExtent: 10,
        viewportExtent: 2,
        scrollOffset: 4,
      );
      expect(() => viewport.contentExtent = -1, throwsArgumentError);
      expect(() => viewport.viewportExtent = -1, throwsArgumentError);
      expect(viewport.contentExtent, 10);
      expect(viewport.viewportExtent, 2);
      expect(viewport.scrollOffset, 4);

      final scroll = ScrollController()
        ..updateMaxScrollExtent(10)
        ..jumpTo(4);
      var calls = 0;
      scroll.addListener(() => calls++);
      for (final invalid in <double>[-1, double.infinity, double.nan]) {
        expect(
          () => scroll.updateMaxScrollExtent(invalid),
          throwsArgumentError,
        );
      }
      expect(scroll.maxScrollExtent, 10);
      expect(scroll.offset, 4);
      expect(calls, 0);

      scroll.updateMaxScrollExtent(0);
      expect(scroll.maxScrollExtent, 0);
    },
  );

  test('zero-sized ScrollBox and Select layout and paint stay safe', () {
    final cases = <({Axis axis, int width, int height, int expectedViewport})>[
      (axis: Axis.vertical, width: 0, height: 2, expectedViewport: 2),
      (axis: Axis.vertical, width: 2, height: 0, expectedViewport: 0),
      (axis: Axis.horizontal, width: 0, height: 2, expectedViewport: 0),
      (axis: Axis.horizontal, width: 2, height: 0, expectedViewport: 2),
    ];
    for (final item in cases) {
      final controller = ScrollController();
      final tester = WidgetTester(maxWidth: item.width, maxHeight: item.height);
      addTearDown(tester.dispose);
      tester.pumpWidget(
        ScrollBox(
          controller: controller,
          scrollDirection: item.axis,
          child: const SizedBox(width: 3, height: 3),
        ),
      );
      expect(controller.viewportExtent, item.expectedViewport);
      expect(controller.maxScrollExtent, greaterThanOrEqualTo(0));
    }

    final select = RenderSelect<String>(
      options: const [SelectOption(value: 'a', name: 'A')],
      highlighted: 0,
      scrollOffset: 0,
      visibleRows: 0,
      showScrollIndicator: true,
      color: Color.white,
      backgroundColor: Color.black,
      selectedBackgroundColor: Color.black,
      selectedTextColor: Color.white,
      descriptionColor: Color.white,
    )..layout(const BoxConstraints.tight(width: 0, height: 0));
    final canvas = _CountingCanvas();
    select.paint(PaintingContext(canvas), Offset.zero);
    expect(select.size, Size.zero);
    expect(canvas.calls, 0);
  });

  test('headless zero binding never invokes its renderer factory', () {
    var creates = 0;
    final binding = runTuiAppForTesting(
      const SizedBox.shrink(),
      width: 0,
      height: 0,
      headless: true,
      rendererFactory: (width, height) {
        creates++;
        throw StateError('headless binding requested $width x $height');
      },
    );
    addTearDown(binding.dispose);

    binding.debugFlushFrame();

    expect(creates, 0);
    expect(binding.renderer, isNull);
  });

  test(
    'assertion-disabled boundaries reject before invalid state enters layout',
    () async {
      final result = await Process.run(Platform.resolvedExecutable, [
        'run',
        '--no-enable-asserts',
        'test/fixtures/p9_016_release_probe.dart',
      ], workingDirectory: Directory.current.path);

      expect(
        result.exitCode,
        0,
        reason: 'stdout:\n${result.stdout}\nstderr:\n${result.stderr}',
      );
      final labels = RegExp('PASS:[a-z-]+')
          .allMatches(result.stdout as String)
          .map((match) => match.group(0)!)
          .toList();
      final expectedLabels = <String>{
        'PASS:constraints',
        'PASS:size',
        'PASS:constrained-widget',
        'PASS:container-constraints',
        'PASS:padding-widget',
        'PASS:container-margin',
        'PASS:sized-widget',
        'PASS:textarea-widget',
        'PASS:select-widget',
        'PASS:viewport',
        'PASS:scroll-controller',
        'PASS:render-view',
        'PASS:scroll-vertical-zero-width',
        'PASS:scroll-vertical-zero-height',
        'PASS:scroll-horizontal-zero-width',
        'PASS:scroll-horizontal-zero-height',
      };
      expect(labels.toSet(), expectedLabels);
      expect(labels.length, expectedLabels.length);
    },
    tags: const ['process-spawning'],
  );
}

final class _BadBoxConstraints extends BoxConstraints {
  _BadBoxConstraints() : super(maxWidth: 2);

  @override
  int get minWidth => 3;
}

final class _BadInsets extends EdgeInsets {
  _BadInsets() : super(left: 0);

  @override
  int get left => -1;
}

final class _ProbeRenderBox extends RenderBox {}

final class _CountingCanvas implements TuiCanvas {
  int calls = 0;

  @override
  void save() => calls++;

  @override
  void restore() => calls++;

  @override
  void clipRect(Rect rect) => calls++;

  @override
  void fillRect(Rect rect, Color color) => calls++;

  @override
  void drawText(
    String text,
    Offset offset,
    Color foreground, {
    Color? background,
    int attributes = 0,
  }) => calls++;

  @override
  void drawBox(
    Rect rect,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) => calls++;

  @override
  void setCell(
    Offset offset,
    String char,
    Color foreground,
    Color background,
    int attributes,
  ) => calls++;

  @override
  void drawTextLayout(
    TextLayout layout,
    Offset offset, {
    Rect? sourceRect,
    TextHighlight? selection,
  }) => calls++;
}
