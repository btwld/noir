import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/listenable_liveness.dart';
import '../helpers/tui_test_app.dart';

void main() {
  test('controlled status selects exactly one attached presentation', () async {
    final key = GlobalKey<_AutocompleteHarnessState>();
    final controller = TextEditingController();
    final app = createTuiTestApp(
      _AutocompleteHarness(key: key, controller: controller),
      width: 32,
      height: 8,
    );

    try {
      await _settle(app);
      expect(app.captureFrame().toText(), isNot(contains('Loading…')));

      key.currentState!.present(AutocompleteStatus.loading);
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Loading…'));

      key.currentState!.present(AutocompleteStatus.empty);
      await _settle(app);
      expect(app.captureFrame().toText(), contains('No options.'));
      expect(app.captureFrame().toText(), isNot(contains('Loading…')));

      key.currentState!.present(AutocompleteStatus.error);
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Options unavailable.'));

      key.currentState!.showOptions(const ['alpha', 'beta']);
      await _settle(app);
      final text = app.captureFrame().toText();
      expect(text, contains('alpha'));
      expect(text, contains('beta'));
      expect(text, isNot(contains('Options unavailable.')));

      key.currentState!.present(AutocompleteStatus.idle);
      await _settle(app);
      expect(app.captureFrame().toText(), isNot(contains('alpha')));
    } finally {
      app.dispose();
      controller.dispose();
    }
  });

  test(
    'Tab, arrows, field Enter, list Enter, and click share selection',
    () async {
      final key = GlobalKey<_AutocompleteHarnessState>();
      final controller = TextEditingController();
      final field = FocusNode(debugLabel: 'field');
      final options = FocusNode(debugLabel: 'options');
      final app = createTuiTestApp(
        _AutocompleteHarness(
          key: key,
          controller: controller,
          focusNode: field,
          optionsFocusNode: options,
          initialStatus: AutocompleteStatus.ready,
          initialOptions: const ['alpha', 'beta', 'gamma'],
          autofocus: true,
        ),
        width: 32,
        height: 8,
      );

      try {
        await _settle(app);
        expect(field.hasFocus, isTrue);

        app.mockInput.pressEnter();
        await _settle(app);
        expect(key.currentState!.selected, ['alpha']);
        expect(field.hasFocus, isTrue);

        key.currentState!.showOptions(const ['alpha', 'beta', 'gamma']);
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..pressArrow(ArrowDirection.down)
          ..pressEnter();
        await _settle(app);
        expect(key.currentState!.selected, ['alpha', 'beta']);
        expect(field.hasFocus, isTrue);

        key.currentState!.showOptions(const ['alpha', 'beta', 'gamma']);
        await _settle(app);
        final gamma = app.captureFrame().findText('gamma').single;
        app.mockMouse.click(gamma.x, gamma.y);
        await _settle(app);
        expect(key.currentState!.selected, ['alpha', 'beta', 'gamma']);
        expect(field.hasFocus, isTrue);

        app.mockInput.typeText('z');
        await _settle(app);
        expect(key.currentState!.changes.last, controller.text);
      } finally {
        app.dispose();
        controller.dispose();
        field.dispose();
        options.dispose();
      }
    },
  );

  test(
    'Escape dismisses only a visible presentation and restores the field',
    () async {
      final key = GlobalKey<_AutocompleteHarnessState>();
      final controller = TextEditingController();
      final field = FocusNode(debugLabel: 'field');
      final options = FocusNode(debugLabel: 'options');
      var ancestorEscapes = 0;
      final app = createTuiTestApp(
        Focus(
          canRequestFocus: false,
          onKeyEvent: (node, event) {
            if (event.isPress &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              ancestorEscapes++;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _AutocompleteHarness(
            key: key,
            controller: controller,
            focusNode: field,
            optionsFocusNode: options,
            initialStatus: AutocompleteStatus.ready,
            initialOptions: const ['alpha', 'beta'],
            autofocus: true,
          ),
        ),
      );

      try {
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        expect(options.hasFocus, isTrue);

        app.mockInput.pressEscape();
        await _settle(app);
        expect(key.currentState!.dismisses, 1);
        expect(field.hasFocus, isTrue);
        expect(ancestorEscapes, 0);

        app.mockInput.pressEscape();
        await _settle(app);
        expect(key.currentState!.dismisses, 1);
        expect(ancestorEscapes, 1);
      } finally {
        app.dispose();
        controller.dispose();
        field.dispose();
        options.dispose();
      }
    },
  );

  test(
    'option updates clamp highlight and non-ready updates repair focus',
    () async {
      final key = GlobalKey<_AutocompleteHarnessState>();
      final controller = TextEditingController();
      final field = FocusNode(debugLabel: 'field');
      final options = FocusNode(debugLabel: 'options');
      final app = createTuiTestApp(
        _AutocompleteHarness(
          key: key,
          controller: controller,
          focusNode: field,
          optionsFocusNode: options,
          initialStatus: AutocompleteStatus.ready,
          initialOptions: const ['alpha', 'beta', 'gamma'],
          autofocus: true,
        ),
      );

      try {
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..pressArrow(ArrowDirection.down)
          ..pressArrow(ArrowDirection.down);
        await _settle(app);
        expect(options.hasFocus, isTrue);

        key.currentState!.showOptions(const ['only']);
        await _settle(app);
        app.mockInput.pressEnter();
        await _settle(app);
        expect(key.currentState!.selected, ['only']);

        key.currentState!.showOptions(const ['first', 'second']);
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        expect(options.hasFocus, isTrue);

        key.currentState!.present(AutocompleteStatus.loading);
        await _settle(app);
        expect(field.hasFocus, isTrue);
      } finally {
        app.dispose();
        controller.dispose();
        field.dispose();
        options.dispose();
      }
    },
  );

  test(
    'ready updates preserve a numeric highlight and re-entry resets it',
    () async {
      final key = GlobalKey<_AutocompleteHarnessState>();
      final controller = TextEditingController();
      final app = createTuiTestApp(
        _AutocompleteHarness(
          key: key,
          controller: controller,
          initialStatus: AutocompleteStatus.ready,
          initialOptions: const ['alpha', 'beta', 'gamma'],
          autofocus: true,
        ),
      );

      try {
        await _settle(app);
        app.mockInput
          ..pressTab()
          ..pressArrow(ArrowDirection.down);
        await _settle(app);

        key.currentState!.showOptions(const ['first', 'second', 'third']);
        await _settle(app);
        app.mockInput.pressEnter();
        await _settle(app);
        expect(key.currentState!.selected, ['second']);

        key.currentState!.showOptions(const ['reset', 'other']);
        await _settle(app);
        app.mockInput.pressEnter();
        await _settle(app);
        expect(key.currentState!.selected, ['second', 'reset']);
      } finally {
        app.dispose();
        controller.dispose();
      }
    },
  );

  test('custom builders replace only their matching status surface', () async {
    final key = GlobalKey<_AutocompleteHarnessState>();
    final controller = TextEditingController();
    final app = createTuiTestApp(
      _AutocompleteHarness(
        key: key,
        controller: controller,
        initialStatus: AutocompleteStatus.loading,
        loadingBuilder: (context) => const Text('Custom loading'),
        emptyBuilder: (context) => const Text('Custom empty'),
        errorBuilder: (context) => const Text('Custom error'),
      ),
    );

    try {
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Custom loading'));
      expect(app.captureFrame().toText(), isNot(contains('Custom empty')));

      key.currentState!.present(AutocompleteStatus.empty);
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Custom empty'));
      expect(app.captureFrame().toText(), isNot(contains('Custom loading')));

      key.currentState!.present(AutocompleteStatus.error);
      await _settle(app);
      expect(app.captureFrame().toText(), contains('Custom error'));
      expect(app.captureFrame().toText(), isNot(contains('Custom empty')));
    } finally {
      app.dispose();
      controller.dispose();
    }
  });

  test(
    'colors fall back through the nearest theme and dark palette before explicit values',
    () async {
      const palette = ThemeData(
        surface: Color.green,
        surfaceVariant: Color.red,
        selectedBackground: Color.blue,
      );
      final dark = await _captureAutocompleteColors();
      expect(dark.option, _painted(ThemeData.dark.surfaceVariant));
      expect(dark.selected, _painted(ThemeData.dark.selectedBackground));

      final themed = await _captureAutocompleteColors(theme: palette);
      expect(themed.input, palette.surface);
      expect(themed.option, palette.surfaceVariant);
      expect(themed.selected, palette.selectedBackground);

      final explicit = await _captureAutocompleteColors(
        theme: palette,
        inputBackgroundColor: Color.yellow,
        optionsBackgroundColor: Color.magenta,
        selectedBackgroundColor: Color.cyan,
      );
      expect(explicit.input, Color.yellow);
      expect(explicit.option, Color.magenta);
      expect(explicit.selected, Color.cyan);
    },
  );

  test(
    'borrowed controller and focus replacements stay live and transfer option focus',
    () async {
      final key = GlobalKey<_AutocompleteHarnessState>();
      final firstController = TextEditingController();
      final firstField = FocusNode(debugLabel: 'first field');
      final firstOptions = FocusNode(debugLabel: 'first options');
      final secondController = TextEditingController();
      final secondField = FocusNode(debugLabel: 'second field');
      final secondOptions = FocusNode(debugLabel: 'second options');
      final app = createTuiTestApp(
        _AutocompleteHarness(
          key: key,
          controller: firstController,
          focusNode: firstField,
          optionsFocusNode: firstOptions,
          initialStatus: AutocompleteStatus.ready,
          initialOptions: const ['alpha', 'beta'],
          autofocus: true,
        ),
      );

      try {
        await _settle(app);
        app.mockInput.pressTab();
        await _settle(app);
        expect(firstOptions.hasFocus, isTrue);

        key.currentState!.replaceResources(
          controller: secondController,
          focusNode: secondField,
          optionsFocusNode: secondOptions,
        );
        await _settle(app);

        expect(secondOptions.hasFocus, isTrue);
        expect(firstField.isAttached, isFalse);
        expect(firstOptions.isAttached, isFalse);
        expect(isLive(firstController), isTrue);
        expect(isLive(firstField), isTrue);
        expect(isLive(firstOptions), isTrue);

        secondController.text = 'replacement';
        await _settle(app);
        expect(app.captureFrame().toText(), contains('replacement'));
        expect(firstController.text, isEmpty);
      } finally {
        app.dispose();
      }

      for (final resource in <Listenable>[
        firstController,
        firstField,
        firstOptions,
        secondController,
        secondField,
        secondOptions,
      ]) {
        expect(isLive(resource), isTrue);
      }
      firstController.dispose();
      firstField.dispose();
      firstOptions.dispose();
      secondController.dispose();
      secondField.dispose();
      secondOptions.dispose();
    },
  );

  test(
    'borrowed resources survive teardown and duplicate node roles reject',
    () async {
      final controller = _TrackingTextEditingController();
      final field = _TrackingFocusNode('field');
      final options = _TrackingFocusNode('options');
      final app = createTuiTestApp(
        Autocomplete<String>(
          controller: controller,
          options: const ['alpha'],
          status: AutocompleteStatus.ready,
          optionBuilder: _optionBuilder,
          onChanged: (_) {},
          onSelected: (_) {},
          onDismiss: () {},
          focusNode: field,
          optionsFocusNode: options,
        ),
      );

      await _settle(app);
      app.dispose();

      expect(controller.wasDisposed, isFalse);
      expect(field.wasDisposed, isFalse);
      expect(options.wasDisposed, isFalse);
      controller.text = 'still-owned';

      expect(
        () => Autocomplete<String>(
          controller: controller,
          options: const ['alpha'],
          status: AutocompleteStatus.ready,
          optionBuilder: _optionBuilder,
          onChanged: (_) {},
          onSelected: (_) {},
          onDismiss: () {},
          focusNode: field,
          optionsFocusNode: field,
        ),
        throwsA(isA<AssertionError>()),
      );

      controller.dispose();
      field.dispose();
      options.dispose();
    },
  );

  test('internally owned focus nodes detach with the component', () async {
    final key = GlobalKey<_OptionalAutocompleteState>();
    final controller = TextEditingController();
    final app = createTuiTestApp(
      _OptionalAutocomplete(key: key, controller: controller),
    );

    try {
      await _settle(app);
      final ownedNodes = List<FocusNode>.of(
        app.binding.buildOwner.focusManager.traversalOrder(),
      );
      expect(ownedNodes, hasLength(2));

      key.currentState!.hide();
      await _settle(app);
      expect(app.binding.buildOwner.focusManager.traversalOrder(), isEmpty);
      for (final node in ownedNodes) {
        expect(isLive(node), isFalse);
      }
    } finally {
      app.dispose();
      controller.dispose();
    }
  });

  test('long option content remains bounded in a compact layout', () async {
    final controller = TextEditingController();
    final app = createTuiTestApp(
      SizedBox(
        width: 12,
        height: 2,
        child: Autocomplete<String>(
          controller: controller,
          options: const [
            'an-option-name-that-is-far-too-long',
            'second-long-option',
          ],
          status: AutocompleteStatus.ready,
          optionBuilder: _optionBuilder,
          onChanged: (_) {},
          onSelected: (_) {},
          onDismiss: () {},
        ),
      ),
      width: 12,
      height: 2,
    );

    try {
      await _settle(app);
      final lines = app.captureFrame().toText().split('\n');
      expect(lines, hasLength(2));
      expect(lines.every((line) => line.length <= 12), isTrue);
      expect(lines.join(), contains('...'));
    } finally {
      app.dispose();
      controller.dispose();
    }
  });
}

Widget _optionBuilder(BuildContext context, String option, bool highlighted) =>
    Text(
      option,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: highlighted ? FontWeight.bold : FontWeight.normal,
      ),
    );

class _AutocompleteHarness extends StatefulWidget {
  const _AutocompleteHarness({
    required this.controller,
    super.key,
    this.focusNode,
    this.optionsFocusNode,
    this.initialStatus = AutocompleteStatus.idle,
    this.initialOptions = const [],
    this.autofocus = false,
    this.loadingBuilder,
    this.emptyBuilder,
    this.errorBuilder,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final FocusNode? optionsFocusNode;
  final AutocompleteStatus initialStatus;
  final List<String> initialOptions;
  final bool autofocus;
  final WidgetBuilder? loadingBuilder;
  final WidgetBuilder? emptyBuilder;
  final WidgetBuilder? errorBuilder;

  @override
  State<_AutocompleteHarness> createState() => _AutocompleteHarnessState();
}

class _AutocompleteHarnessState extends State<_AutocompleteHarness> {
  late TextEditingController controller = widget.controller;
  late FocusNode? focusNode = widget.focusNode;
  late FocusNode? optionsFocusNode = widget.optionsFocusNode;
  late AutocompleteStatus status = widget.initialStatus;
  late List<String> options = widget.initialOptions;
  final selected = <String>[];
  final changes = <String>[];
  int dismisses = 0;

  void present(AutocompleteStatus value) {
    setState(() => status = value);
  }

  void showOptions(List<String> value) {
    setState(() {
      options = value;
      status = AutocompleteStatus.ready;
    });
  }

  void replaceResources({
    required TextEditingController controller,
    required FocusNode? focusNode,
    required FocusNode? optionsFocusNode,
  }) {
    setState(() {
      this.controller = controller;
      this.focusNode = focusNode;
      this.optionsFocusNode = optionsFocusNode;
    });
  }

  @override
  Widget build(BuildContext context) => Autocomplete<String>(
    controller: controller,
    options: options,
    status: status,
    optionBuilder: _optionBuilder,
    onChanged: changes.add,
    onSelected: (option) {
      selected.add(option);
      controller.text = option;
      setState(() => status = AutocompleteStatus.idle);
    },
    onDismiss: () {
      dismisses++;
      setState(() => status = AutocompleteStatus.idle);
    },
    focusNode: focusNode,
    optionsFocusNode: optionsFocusNode,
    autofocus: widget.autofocus,
    loadingBuilder: widget.loadingBuilder,
    emptyBuilder: widget.emptyBuilder,
    errorBuilder: widget.errorBuilder,
  );
}

class _OptionalAutocomplete extends StatefulWidget {
  const _OptionalAutocomplete({required this.controller, super.key});

  final TextEditingController controller;

  @override
  State<_OptionalAutocomplete> createState() => _OptionalAutocompleteState();
}

class _OptionalAutocompleteState extends State<_OptionalAutocomplete> {
  bool visible = true;

  void hide() => setState(() => visible = false);

  @override
  Widget build(BuildContext context) => visible
      ? Autocomplete<String>(
          controller: widget.controller,
          options: const ['alpha'],
          status: AutocompleteStatus.ready,
          optionBuilder: _optionBuilder,
          onChanged: (_) {},
          onSelected: (_) {},
          onDismiss: () {},
        )
      : const Text('removed');
}

class _TrackingFocusNode extends FocusNode {
  _TrackingFocusNode(String label) : super(debugLabel: label);

  bool wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

class _TrackingTextEditingController extends TextEditingController {
  bool wasDisposed = false;

  @override
  void dispose() {
    wasDisposed = true;
    super.dispose();
  }
}

Future<void> _settle(TuiTestApp app) async {
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
  await Future<void>.delayed(Duration.zero);
  app.pumpFrame();
}

Color _painted(Color color) => Color.fromHex(color.toHex());

typedef _AutocompleteColors = ({Color input, Color option, Color selected});

Future<_AutocompleteColors> _captureAutocompleteColors({
  ThemeData? theme,
  Color? inputBackgroundColor,
  Color? optionsBackgroundColor,
  Color? selectedBackgroundColor,
}) async {
  final controller = TextEditingController(text: 'query');
  final field = FocusNode(debugLabel: 'field');
  final options = FocusNode(debugLabel: 'options');
  Widget child = Autocomplete<String>(
    controller: controller,
    options: const ['alpha', 'beta'],
    status: AutocompleteStatus.ready,
    optionBuilder: _optionBuilder,
    onChanged: (_) {},
    onSelected: (_) {},
    onDismiss: () {},
    focusNode: field,
    optionsFocusNode: options,
    autofocus: true,
    inputBackgroundColor: inputBackgroundColor,
    optionsBackgroundColor: optionsBackgroundColor,
    selectedBackgroundColor: selectedBackgroundColor,
  );
  if (theme != null) child = Theme(data: theme, child: child);
  final app = createTuiTestApp(child, width: 24, height: 6);

  try {
    await _settle(app);
    var frame = app.captureFrame();
    final query = frame.findText('query').single;
    final beta = frame.findText('beta').single;
    final input = frame.getBackgroundColor(query.x, query.y);
    final option = frame.getBackgroundColor(beta.x, beta.y);

    app.mockInput.pressTab();
    await _settle(app);
    frame = app.captureFrame();
    final alpha = frame.findText('alpha').single;
    final selected = frame.getBackgroundColor(alpha.x, alpha.y);
    return (input: input, option: option, selected: selected);
  } finally {
    app.dispose();
    controller.dispose();
    field.dispose();
    options.dispose();
  }
}
