// ignore_for_file: cascade_invocations
// Run with: dart run example/widgets_tour.dart
//
// Combined tour of Select, ScrollBox, and TextArea — the Ink-equivalent
// showcase. Press Tab to move focus between widgets. Ctrl+D submits the
// TextArea. Press q (when no TextArea is focused) or Esc to quit.

import 'dart:io' as io;

import 'package:noir/noir.dart';

void main() {
  late final TuiApp app;
  void quit() {
    app.dispose();
    io.exit(0);
  }

  app = runTuiApp(WidgetsTourApp(onQuit: quit));
}

class WidgetsTourApp extends StatefulWidget {
  const WidgetsTourApp({required this.onQuit, super.key});

  final void Function() onQuit;

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
      n.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _scope.dispose();
    for (final n in _ring) {
      n.dispose();
    }
    super.dispose();
  }

  KeyEventResult _scopeKeys(FocusNode node, KeyEvent event) {
    if (!event.isPress) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    if (_textFocus.hasFocus &&
        event.isControlPressed &&
        event.logicalKey == LogicalKeyboardKey.keyD) {
      _submitText();
      return KeyEventResult.handled;
    }
    if (event.character == 'q' && !_textFocus.hasFocus) {
      widget.onQuit();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final i = _ring.indexWhere((n) => n.hasFocus);
      final next = _ring[(i + 1) % _ring.length];
      next.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _box({
    required String title,
    required bool focused,
    required Widget child,
    int? width,
    int? height,
  }) {
    final border = focused
        ? const Color(0.3, 0.8, 1)
        : const Color(0.3, 0.3, 0.4);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(border: Border.all(color: border)),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: focused ? const Color(0.3, 0.8, 1) : border,
              fontWeight: FontWeight.bold,
            ),
          ),
          child,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => FocusScope(
    node: _scope,
    onKeyEvent: _scopeKeys,
    child: Container(
      padding: const EdgeInsets.all(1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'OpenTUI-Dart widget tour',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const Text(
            'Tab switches panel. Ctrl+D submits text. Esc/q quits.',
            style: TextStyle(color: Color(0.7, 0.7, 0.7)),
          ),
          const SizedBox(height: 1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _box(
                title: 'Select',
                focused: _selectFocus.hasFocus,
                width: 22,
                height: 8,
                child: SizedBox(
                  width: 18,
                  child: Select<String>(
                    focusNode: _selectFocus,
                    autofocus: true,
                    height: 5,
                    options: _options,
                    showScrollIndicator: true,
                    onSelect: (i, opt) => setState(() => _selected = opt.name),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              _box(
                title: 'ScrollBox',
                focused: _scrollFocus.hasFocus,
                width: 28,
                height: 9,
                child: SizedBox(
                  width: 24,
                  height: 6,
                  child: ScrollBox(
                    focusNode: _scrollFocus,
                    onScroll: (o) => setState(() => _scrollOffset = o.round()),
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
          _box(
            title: 'TextArea',
            focused: _textFocus.hasFocus,
            width: 48,
            height: 6,
            child: SizedBox(
              width: 44,
              child: TextArea(
                focusNode: _textFocus,
                height: 3,
                width: 44,
                placeholder: 'Type… Ctrl+D to submit',
                onChanged: (v) => setState(() => _typed = v),
                onSubmit: _submitText,
              ),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            'Selected: $_selected   ScrollY: $_scrollOffset   '
            'Typed: $_typedGraphemeCount chars',
            style: const TextStyle(color: Color(0.7, 0.9, 1)),
          ),
          if (_submittedLength case final length?)
            Text(
              'Submitted: $length chars',
              style: const TextStyle(color: Color(0.4, 1, 0.4)),
            ),
        ],
      ),
    ),
  );
}
