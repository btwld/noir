import 'package:noir/src/core/color.dart';
import 'package:noir/src/core/cursor.dart';
import 'package:noir/src/core/input.dart';
import 'package:noir/src/core/terminal_style.dart' show TextAlign;
import 'package:noir/src/painting/decoration.dart';
import 'package:noir/src/painting/tui_canvas.dart';
import 'package:noir/src/render/geometry.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/constrained_box.dart';
import 'package:noir/src/rendering/decorated_box.dart';
import 'package:noir/src/rendering/flex.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/padding.dart';
import 'package:noir/src/rendering/paragraph.dart';
import 'package:noir/src/rendering/positioned_box.dart';
import 'package:noir/src/rendering/proxy_box.dart';
import 'package:noir/src/rendering/render_view.dart';
import 'package:noir/src/widgets/decorated_box.dart';
import 'package:noir/src/widgets/flexible.dart';
import 'package:noir/src/widgets/input.dart';
import 'package:noir/src/widgets/pointer_listener.dart';
import 'package:noir/src/widgets/row_column.dart';
import 'package:noir/src/widgets/scroll_box.dart';
import 'package:noir/src/widgets/select.dart';
import 'package:noir/src/widgets/text_area.dart';
import 'package:noir/src/widgets/text_span.dart';
import 'package:test/test.dart';

void main() {
  group('existing-correct controls', () {
    test('RenderView terminal size owns layout and equal size is a no-op', () {
      final view = RenderView(width: 12, height: 6);
      final harness = _Harness(view);

      _expectLayout(harness, () => view.updateTerminalSize(11, 6));
      _expectNoWork(harness, () => view.updateTerminalSize(11, 6));
    });

    test('single-child replacement owns layout and identity is a no-op', () {
      final first = _ProbeBox();
      final proxy = RenderProxyBox(first);
      final harness = _Harness(proxy);
      final second = _ProbeBox();

      _expectLayout(harness, () => proxy.child = second, expectedUpdates: 2);
      _expectNoWork(harness, () => proxy.child = second);
    });

    test('validation rejects before dirty work', () {
      final constrained = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(maxWidth: 8),
      );
      final harness = _Harness(constrained);

      expect(
        () => constrained.additionalConstraints = _InvalidConstraints(),
        throwsArgumentError,
      );
      harness.expectClean();
    });

    test('RenderParagraph preserves its existing layout/paint split', () {
      final paragraph = RenderParagraph(text: const TextSpan(text: 'a'));
      final harness = _Harness(paragraph);

      _expectLayout(harness, () => paragraph.text = const TextSpan(text: 'b'));
      _expectPaint(harness, () => paragraph.alignment = TextAlign.right);
    });

    test('pointer callback replacement is callback-only and immediate', () {
      final calls = <String>[];
      final listener = RenderPointerListener(
        onPointerDown: (_) => calls.add('old'),
      );
      final harness = _Harness(listener);
      listener.updateCallbacks(onPointerDown: (_) => calls.add('replacement'));
      harness.expectClean();
      expect(harness.visualUpdates, 0);

      final event = MouseEvent(
        type: MouseEventType.down,
        button: MouseButton.left,
        x: 0,
        y: 0,
      );
      listener.handleEvent(event, HitTestEntry(listener, Offset.zero));

      expect(calls, ['replacement']);
      harness.expectClean();
      expect(harness.visualUpdates, 0);
    });
  });

  group('layout-invalidating render configuration', () {
    test('core layout setters own layout invalidation and no-ops', () {
      final constrained = RenderConstrainedBox(
        additionalConstraints: const BoxConstraints(maxWidth: 8),
      );
      final constrainedHarness = _Harness(constrained);
      _expectLayout(
        constrainedHarness,
        () => constrained.additionalConstraints = const BoxConstraints(
          maxWidth: 7,
        ),
      );
      _expectNoWork(
        constrainedHarness,
        () => constrained.additionalConstraints = const BoxConstraints(
          maxWidth: 7,
        ),
      );

      // Non-const, field-equal instances (runtime-computed values defeat
      // const canonicalization) must also be recognized as no-ops.
      _expectLayout(
        constrainedHarness,
        () => constrained.additionalConstraints = BoxConstraints(
          maxWidth: 6 + 1,
          maxHeight: 4 + 1,
        ),
      );
      _expectNoWork(
        constrainedHarness,
        () => constrained.additionalConstraints = BoxConstraints(
          maxWidth: 6 + 1,
          maxHeight: 4 + 1,
        ),
      );

      final padding = RenderPadding(padding: const EdgeInsets.all(1));
      final paddingHarness = _Harness(padding);
      _expectLayout(
        paddingHarness,
        () => padding.padding = const EdgeInsets.all(2),
      );
      _expectNoWork(
        paddingHarness,
        () => padding.padding = const EdgeInsets.all(2),
      );

      final positioned = RenderPositionedBox(alignment: Alignment.topLeft);
      final positionedHarness = _Harness(positioned);
      _expectLayout(
        positionedHarness,
        () => positioned.alignment = Alignment.bottomRight,
      );
      _expectNoWork(
        positionedHarness,
        () => positioned.alignment = Alignment.bottomRight,
      );
    });

    test('every RenderFlex geometry setter and child metadata owns layout', () {
      final child = _ProbeBox();
      final flex = RenderFlex(direction: Axis.horizontal, children: [child]);
      final harness = _Harness(flex);

      _expectLayout(harness, () => flex.direction = Axis.vertical);
      _expectNoWork(harness, () => flex.direction = Axis.vertical);
      _expectLayout(
        harness,
        () => flex.mainAxisAlignment = MainAxisAlignment.end,
      );
      _expectNoWork(
        harness,
        () => flex.mainAxisAlignment = MainAxisAlignment.end,
      );
      _expectLayout(harness, () => flex.mainAxisSize = MainAxisSize.min);
      _expectNoWork(harness, () => flex.mainAxisSize = MainAxisSize.min);
      _expectLayout(
        harness,
        () => flex.crossAxisAlignment = CrossAxisAlignment.end,
      );
      _expectNoWork(
        harness,
        () => flex.crossAxisAlignment = CrossAxisAlignment.end,
      );
      _expectLayout(harness, () => flex.spacing = 2);
      _expectNoWork(harness, () => flex.spacing = 2);
      _expectLayout(
        harness,
        () => flex.add(child, flex: 2, fit: FlexFit.tight),
      );
      _expectNoWork(
        harness,
        () => flex.add(child, flex: 2, fit: FlexFit.tight),
      );
      _expectLayout(
        harness,
        () => flex.add(child, flex: 3, fit: FlexFit.tight),
      );
      _expectLayout(
        harness,
        () => flex.add(child, flex: 3, fit: FlexFit.loose),
      );
    });

    test('Select layout setters use their specified equality', () {
      final originalOptions = <SelectOption<String>>[
        const SelectOption(name: 'a', value: 'a'),
      ];
      final select = _select(options: originalOptions);
      final harness = _Harness(select);

      _expectNoWork(harness, () => select.options = originalOptions);
      _expectLayout(
        harness,
        () => select.options = <SelectOption<String>>[
          const SelectOption(name: 'a', value: 'a'),
        ],
      );
      _expectLayout(harness, () => select.visibleRows = 3);
      _expectNoWork(harness, () => select.visibleRows = 3);
      _expectLayout(harness, () => select.showScrollIndicator = true);
      _expectNoWork(harness, () => select.showScrollIndicator = true);
    });

    test('TextInput and TextArea size setters own layout', () {
      final input = _textInput();
      final inputHarness = _Harness(input);
      _expectLayout(inputHarness, () => input.value = 'longer');
      _expectNoWork(inputHarness, () => input.value = 'longer');
      _expectLayout(inputHarness, () => input.placeholder = 'placeholder');
      _expectNoWork(inputHarness, () => input.placeholder = 'placeholder');
      _expectLayout(inputHarness, () => input.obscureText = true);
      _expectNoWork(inputHarness, () => input.obscureText = true);

      final area = _textArea();
      final areaHarness = _Harness(area);
      _expectLayout(areaHarness, () => area.heightLines = 4);
      _expectNoWork(areaHarness, () => area.heightLines = 4);
      _expectLayout(areaHarness, () => area.explicitWidth = 9);
      _expectNoWork(areaHarness, () => area.explicitWidth = 9);
    });

    test(
      'ScrollBox geometry setters and controller replacement own layout',
      () {
        final controller = ScrollController();
        final scroll = _scrollBox(controller);
        final harness = _Harness(scroll);

        final replacement = ScrollController();
        _expectLayout(harness, () => scroll.controller = replacement);
        _expectNoWork(harness, () => scroll.controller = replacement);
        _expectLayout(harness, () => scroll.scrollDirection = Axis.horizontal);
        _expectNoWork(harness, () => scroll.scrollDirection = Axis.horizontal);
        _expectLayout(harness, () => scroll.showScrollbar = false);
        _expectNoWork(harness, () => scroll.showScrollbar = false);
      },
    );
  });

  group('paint-invalidating render configuration', () {
    test('ScrollBox cursor controller owns paint only', () {
      final scroll = _scrollBox(ScrollController());
      final harness = _Harness(scroll);
      final cursor = CursorController();

      _expectPaint(harness, () => scroll.cursorController = cursor);
      _expectNoWork(harness, () => scroll.cursorController = cursor);
      _expectPaint(harness, () => scroll.cursorController = null);
    });

    test('decoration setters own paint only', () {
      final first = _ProbeDecoration(1);
      final second = _ProbeDecoration(2);
      final decorated = RenderDecoratedBox(decoration: first);
      final harness = _Harness(decorated);

      _expectPaint(harness, () => decorated.decoration = second);
      _expectNoWork(harness, () => decorated.decoration = second);
      _expectPaint(
        harness,
        () => decorated.position = DecorationPosition.foreground,
      );
      _expectNoWork(
        harness,
        () => decorated.position = DecorationPosition.foreground,
      );
    });

    test('Select visual setters own paint only', () {
      final select = _select();
      final harness = _Harness(select);

      _expectPaint(harness, () => select.highlighted = 1);
      _expectNoWork(harness, () => select.highlighted = 1);
      _expectPaint(harness, () => select.scrollOffset = 1);
      _expectNoWork(harness, () => select.scrollOffset = 1);
      _expectPaint(harness, () => select.color = Color.black);
      _expectNoWork(harness, () => select.color = Color.black);
      _expectPaint(harness, () => select.backgroundColor = Color.white);
      _expectNoWork(harness, () => select.backgroundColor = Color.white);
      _expectPaint(harness, () => select.selectedBackgroundColor = Color.white);
      _expectNoWork(
        harness,
        () => select.selectedBackgroundColor = Color.white,
      );
      _expectPaint(harness, () => select.selectedTextColor = Color.black);
      _expectNoWork(harness, () => select.selectedTextColor = Color.black);
      _expectPaint(harness, () => select.descriptionColor = Color.black);
      _expectNoWork(harness, () => select.descriptionColor = Color.black);
    });

    test('TextInput visual setters own paint and validate before work', () {
      final input = _textInput(value: 'secret');
      final harness = _Harness(input);

      _expectPaint(harness, () => input.color = Color.black);
      _expectNoWork(harness, () => input.color = Color.black);
      _expectPaint(harness, () => input.backgroundColor = Color.white);
      _expectNoWork(harness, () => input.backgroundColor = Color.white);
      _expectPaint(harness, () => input.cursorColor = Color.black);
      _expectNoWork(harness, () => input.cursorColor = Color.black);
      _expectPaint(harness, () => input.cursorStyle = CursorStyle.bar);
      _expectNoWork(harness, () => input.cursorStyle = CursorStyle.bar);
      _expectPaint(harness, () => input.cursorPosition = 2);
      _expectNoWork(harness, () => input.cursorPosition = 2);
      _expectPaint(harness, () => input.focused = true);
      _expectNoWork(harness, () => input.focused = true);
      _expectPaint(harness, () => input.obscuringCharacter = '#');
      _expectNoWork(harness, () => input.obscuringCharacter = '#');
      expect(() => input.obscuringCharacter = 'wide界', throwsArgumentError);
      harness.expectClean();
    });

    test('TextArea visual setters own paint and lines are non-aliased', () {
      final sourceLines = <String>['one', 'two'];
      final area = _textArea(lines: sourceLines);
      final harness = _Harness(area);

      sourceLines[0] = 'mutated outside';
      _expectNoWork(harness, () => area.lines = <String>['one', 'two']);
      _expectPaint(harness, () => area.lines = <String>['changed', 'two']);
      _expectNoWork(harness, () => area.lines = <String>['changed', 'two']);
      _expectPaint(harness, () => area.cursorLine = 1);
      _expectNoWork(harness, () => area.cursorLine = 1);
      _expectPaint(harness, () => area.cursorColumn = 1);
      _expectNoWork(harness, () => area.cursorColumn = 1);
      _expectPaint(harness, () => area.placeholder = 'hint');
      _expectNoWork(harness, () => area.placeholder = 'hint');
      _expectPaint(harness, () => area.color = Color.black);
      _expectNoWork(harness, () => area.color = Color.black);
      _expectPaint(harness, () => area.backgroundColor = Color.white);
      _expectNoWork(harness, () => area.backgroundColor = Color.white);
      _expectPaint(harness, () => area.cursorColor = Color.black);
      _expectNoWork(harness, () => area.cursorColor = Color.black);
      _expectPaint(harness, () => area.cursorStyle = CursorStyle.bar);
      _expectNoWork(harness, () => area.cursorStyle = CursorStyle.bar);
      _expectPaint(harness, () => area.focused = true);
      _expectNoWork(harness, () => area.focused = true);
      _expectPaint(harness, () => area.scrollLine = 1);
      _expectNoWork(harness, () => area.scrollLine = 1);
      _expectPaint(harness, () => area.scrollCell = 1);
      _expectNoWork(harness, () => area.scrollCell = 1);
    });

    test('ScrollBox colors own paint only', () {
      final scroll = _scrollBox(ScrollController());
      final harness = _Harness(scroll);

      _expectPaint(harness, () => scroll.scrollbarColor = Color.black);
      _expectNoWork(harness, () => scroll.scrollbarColor = Color.black);
      _expectPaint(harness, () => scroll.trackColor = Color.white);
      _expectNoWork(harness, () => scroll.trackColor = Color.white);
    });
  });

  group('ScrollBox controller listener lifecycle', () {
    test(
      'same-owner attach, detach, and reattach keep one active listener',
      () {
        final controller = ScrollController();
        final scroll = _scrollBox(controller);
        final harness = _Harness(scroll);

        scroll.attach(harness.owner);
        expect(harness.visualUpdates, 0);
        _expectPaint(harness, () => controller.updateMaxScrollExtent(10));

        scroll.detach();
        controller.updateMaxScrollExtent(11);
        expect(harness.visualUpdates, 0);
        harness.expectClean();

        scroll.attach(harness.owner);
        harness.flush();
        _expectPaint(harness, () => controller.updateMaxScrollExtent(12));
      },
    );

    test('attached replacement listens only to the new controller', () {
      final oldController = ScrollController();
      final newController = ScrollController();
      final scroll = _scrollBox(oldController);
      final harness = _Harness(scroll);

      _expectLayout(harness, () => scroll.controller = newController);
      oldController.updateMaxScrollExtent(10);
      expect(harness.visualUpdates, 0);
      harness.expectClean();
      _expectPaint(harness, () => newController.updateMaxScrollExtent(10));
    });

    test('detached replacement waits for reattachment', () {
      final oldController = ScrollController();
      final newController = ScrollController();
      final scroll = _scrollBox(oldController);
      final harness = _Harness(scroll);
      scroll.detach();

      scroll.controller = newController;
      oldController.updateMaxScrollExtent(10);
      newController.updateMaxScrollExtent(10);
      expect(harness.visualUpdates, 0);

      scroll.attach(harness.owner);
      harness.flush();
      oldController.updateMaxScrollExtent(11);
      expect(harness.visualUpdates, 0);
      _expectPaint(harness, () => newController.updateMaxScrollExtent(11));
    });

    test('nested and adopted ScrollBoxes receive attachment notification', () {
      final nestedController = ScrollController();
      final nested = _scrollBox(nestedController);
      final root = RenderProxyBox(nested);
      final nestedHarness = _Harness(root);
      _expectPaint(
        nestedHarness,
        () => nestedController.updateMaxScrollExtent(10),
        target: nested,
      );

      final adoptedController = ScrollController();
      final adopted = _scrollBox(adoptedController);
      final adoptingRoot = RenderProxyBox();
      final adoptedHarness = _Harness(adoptingRoot);
      _expectLayout(
        adoptedHarness,
        () => adoptingRoot.child = adopted,
        expectedUpdates: 2,
      );
      _expectPaint(
        adoptedHarness,
        () => adoptedController.updateMaxScrollExtent(10),
        target: adopted,
      );
    });

    test('detach preflight rejection preserves listener registration', () {
      final controller = ScrollController();
      final child = _ProbeBox();
      final scroll = _scrollBox(controller)..child = child;
      final harness = _Harness(scroll);
      child.detach();

      expect(scroll.detach, throwsStateError);
      expect(scroll.pipelineOwner, same(harness.owner));
      _expectPaint(harness, () => controller.updateMaxScrollExtent(10));

      child.attach(harness.owner);
      scroll.detach();
    });

    test('post-clear descendant detach failure removes listener', () {
      final error = StateError('descendant detach');
      final controller = ScrollController();
      final child = _ThrowingDetachBox(error);
      final scroll = _scrollBox(controller)..child = child;
      final harness = _Harness(scroll);

      expect(scroll.detach, throwsA(same(error)));
      expect(scroll.pipelineOwner, isNull);
      expect(child.pipelineOwner, same(harness.owner));
      controller.updateMaxScrollExtent(10);
      expect(harness.visualUpdates, 0);
      expect(scroll.debugNeedsLayout, isFalse);
      expect(scroll.debugNeedsPaint, isFalse);
    });

    test('controller notification during layout remains paint-only', () {
      final controller = ScrollController();
      final scroll = _scrollBox(controller)..child = _ProbeBox();
      var visualUpdates = 0;
      final owner = PipelineOwner(onNeedVisualUpdate: () => visualUpdates++);
      scroll.attach(owner);
      owner
        ..flushLayout(scroll, const BoxConstraints.tight(width: 12, height: 6))
        ..flushPaint(scroll, (_) {});
      visualUpdates = 0;

      owner.flushLayout(
        scroll,
        const BoxConstraints.tight(width: 12, height: 5),
      );

      expect(controller.viewportExtent, 5);
      expect(scroll.debugNeedsLayout, isFalse);
      expect(scroll.debugNeedsPaint, isTrue);
      expect(owner.debugNeedsLayout, isFalse);
      expect(owner.debugNeedsPaint, isTrue);
      expect(visualUpdates, 1);
    });
  });
}

final class _Harness {
  _Harness(this.renderObject) {
    owner = PipelineOwner(onNeedVisualUpdate: () => visualUpdates++);
    renderObject.attach(owner);
    flush();
  }

  final RenderBox renderObject;
  late final PipelineOwner owner;
  int visualUpdates = 0;

  void flush() {
    owner.flushLayout(
      renderObject,
      const BoxConstraints.tight(width: 12, height: 6),
    );
    owner.flushPaint(renderObject, (_) {});
    visualUpdates = 0;
  }

  void expectClean() {
    expect(renderObject.debugNeedsLayout, isFalse);
    expect(renderObject.debugNeedsPaint, isFalse);
    expect(owner.debugNeedsLayout, isFalse);
    expect(owner.debugNeedsPaint, isFalse);
  }
}

void _expectLayout(
  _Harness harness,
  void Function() mutate, {
  RenderObject? target,
  int expectedUpdates = 1,
}) {
  harness.expectClean();
  mutate();
  expect((target ?? harness.renderObject).debugNeedsLayout, isTrue);
  expect((target ?? harness.renderObject).debugNeedsPaint, isTrue);
  expect(harness.owner.debugNeedsLayout, isTrue);
  expect(harness.owner.debugNeedsPaint, isTrue);
  expect(harness.visualUpdates, expectedUpdates);
  harness.flush();
}

void _expectPaint(
  _Harness harness,
  void Function() mutate, {
  RenderObject? target,
}) {
  harness.expectClean();
  mutate();
  expect((target ?? harness.renderObject).debugNeedsLayout, isFalse);
  expect((target ?? harness.renderObject).debugNeedsPaint, isTrue);
  expect(harness.owner.debugNeedsLayout, isFalse);
  expect(harness.owner.debugNeedsPaint, isTrue);
  expect(harness.visualUpdates, 1);
  harness.flush();
}

void _expectNoWork(_Harness harness, void Function() mutate) {
  harness.expectClean();
  mutate();
  harness.expectClean();
  expect(harness.visualUpdates, 0);
}

RenderSelect<String> _select({List<SelectOption<String>>? options}) =>
    RenderSelect<String>(
      options:
          options ??
          const [
            SelectOption(name: 'a', value: 'a'),
            SelectOption(name: 'b', value: 'b'),
          ],
      highlighted: 0,
      scrollOffset: 0,
      visibleRows: 2,
      showScrollIndicator: false,
      color: Color.white,
      backgroundColor: Color.black,
      selectedBackgroundColor: Color.black,
      selectedTextColor: Color.white,
      descriptionColor: Color.white,
    );

RenderTextInput _textInput({String value = 'a'}) => RenderTextInput(
  cursorController: CursorController(),
  value: value,
  color: Color.white,
  cursorColor: Color.white,
  cursorStyle: CursorStyle.block,
  cursorPosition: 0,
  focused: false,
  obscureText: false,
  obscuringCharacter: '*',
);

RenderTextArea _textArea({List<String>? lines}) => RenderTextArea(
  cursorController: CursorController(),
  lines: lines ?? <String>['one', 'two'],
  cursorLine: 0,
  cursorColumn: 0,
  placeholder: null,
  heightLines: 2,
  explicitWidth: null,
  color: Color.white,
  backgroundColor: Color.black,
  cursorColor: Color.white,
  cursorStyle: CursorStyle.block,
  focused: false,
  scrollLine: 0,
  scrollCell: 0,
);

RenderScrollBox _scrollBox(ScrollController controller) => RenderScrollBox(
  controller: controller,
  scrollDirection: Axis.vertical,
  showScrollbar: true,
  scrollbarColor: Color.white,
  trackColor: Color.black,
);

class _ProbeBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(constraints.constrainWidth(1), constraints.constrainHeight(1));
  }
}

final class _ProbeDecoration extends Decoration {
  const _ProbeDecoration(this.id);

  final int id;

  @override
  void paint(TuiCanvas canvas, Rect rect) {}
}

final class _ThrowingDetachBox extends _ProbeBox {
  _ThrowingDetachBox(this.error);

  final Error error;

  @override
  void detach() {
    throw error;
  }
}

final class _InvalidConstraints extends BoxConstraints {
  _InvalidConstraints() : super(maxWidth: 2);

  @override
  int get minWidth => 3;
}
