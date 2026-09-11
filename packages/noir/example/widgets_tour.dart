// Run with: dart run example/widgets_tour.dart
//
// Combined tour of Select, ScrollBox, and TextArea.
// Press Tab / Shift+Tab to move focus. Ctrl+D submits the TextArea.
// Esc always quits. q quits unless the TextArea is focused.

import 'package:noir/noir.dart';

import 'src/shared/demo_scaffold.dart';

void main() => runTuiApp(const WidgetsTourApp(), enableMouse: true);

class WidgetsTourApp extends StatefulWidget {
  const WidgetsTourApp({super.key});

  @override
  State<WidgetsTourApp> createState() => _TourAppState();
}

class _TourAppState extends State<WidgetsTourApp> {
  final _scope = FocusScopeNode();
  final _selectFocus = FocusNode();
  final _scrollFocus = FocusNode();
  final _textFocus = FocusNode();
  late final List<FocusNode> _ring;

  String _selected = '(none)';
  int _scrollOffset = 0;
  String _typed = '';
  int? _submittedLength;

  int get _typedGraphemeCount => TextIndexMap(_typed).graphemeCount;

  void _submitText() => setState(() => _submittedLength = _typedGraphemeCount);

  static const _options = <SelectOption<String>>[
    SelectOption(name: 'Red', value: 'red'),
    SelectOption(name: 'Orange', value: 'orange'),
    SelectOption(name: 'Yellow', value: 'yellow'),
    SelectOption(name: 'Green', value: 'green'),
    SelectOption(name: 'Blue', value: 'blue'),
    SelectOption(name: 'Indigo', value: 'indigo'),
    SelectOption(name: 'Violet', value: 'violet'),
  ];

  @override
  void initState() {
    super.initState();
    _ring = [_selectFocus, _scrollFocus, _textFocus];
    for (final n in _ring) {
      n.addListener(_handleFocusChange);
    }
  }

  void _handleFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final n in _ring) {
      n.removeListener(_handleFocusChange);
      n.dispose();
    }
    _scope.dispose();
    super.dispose();
  }

  KeyEventResult _scopeKeys(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    if (_textFocus.hasFocus &&
        event.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _submitText();
      return KeyEventResult.handled;
    }
    if (event.character == 'q' && !_textFocus.hasFocus) {
      TuiApp.exit(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusScope(
      node: _scope,
      onKeyEvent: _scopeKeys,
      child: DemoScaffold(
        title: 'Noir widget tour',
        hint:
            'Tab switches panel. Ctrl+D submits text. Esc quits. q quits unless typing.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                Panel(
                  title: 'Select',
                  focused: _selectFocus.hasFocus,
                  child: SizedBox(
                    width: 18,
                    child: Select<String>(
                      key: const ValueKey<String>('fruit'),
                      focusNode: _selectFocus,
                      autofocus: true,
                      height: 5,
                      options: _options,
                      showScrollIndicator: true,
                      onSelect: (i, opt) =>
                          setState(() => _selected = opt.name),
                    ),
                  ),
                ),
                Panel(
                  title: 'ScrollBox',
                  focused: _scrollFocus.hasFocus,
                  child: SizedBox(
                    width: 24,
                    height: 6,
                    child: ScrollBox(
                      key: const ValueKey<String>('content'),
                      focusNode: _scrollFocus,
                      onScroll: (o) =>
                          setState(() => _scrollOffset = o.round()),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: List<Widget>.generate(
                          25,
                          (i) => Text('item ${i + 1}'),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Panel(
              title: 'TextArea',
              focused: _textFocus.hasFocus,
              child: TextArea(
                key: const ValueKey<String>('editor'),
                focusNode: _textFocus,
                height: 3,
                width: 44,
                placeholder: 'Type… Ctrl+D to submit',
                onChanged: (v) => setState(() => _typed = v),
                onSubmit: _submitText,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              'Selected: $_selected   ScrollY: $_scrollOffset   '
              'Typed: $_typedGraphemeCount chars',
              style: TextStyle(color: theme.info),
            ),
            if (_submittedLength case final length?)
              Text(
                'Submitted: $length chars',
                style: TextStyle(color: theme.success),
              ),
          ],
        ),
      ),
    );
  }
}
