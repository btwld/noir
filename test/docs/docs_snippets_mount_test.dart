import 'dart:async';

import 'package:noir/hooks.dart';
import 'package:noir/noir.dart';
import 'package:test/test.dart';

import '../helpers/buffer_capture.dart';

// These widgets copy published documentation snippets, including their
// block-bodied build methods.
// ignore_for_file: prefer_expression_function_bodies

void applyEnvironment(String value) {}

void onSelect(Offset position) {}

class StatusRegion extends StatelessWidget {
  const StatusRegion({required this.progress, super.key});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        Row(
          spacing: 1,
          children: [
            const Badge(label: 'BUILD', variant: BadgeVariant.info),
            const Expanded(
              child: Text(
                'Compiling package graph',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('${(progress * 100).round()}%'),
          ],
        ),
        ProgressBar(value: progress, width: 32),
      ],
    );
  }
}

class FilterField extends StatefulWidget {
  const FilterField({super.key});

  @override
  State<FilterField> createState() => _FilterFieldState();
}

class _FilterFieldState extends State<FilterField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  String _applied = 'No filter';

  void _apply() {
    final value = _controller.text.trim();
    setState(() {
      _applied = value.isEmpty ? 'No filter' : value;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 1,
      children: [
        TextInput(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          placeholder: 'package name',
          onSubmit: _apply,
        ),
        Button(label: 'Apply filter', onPressed: _apply),
        Text('Filter: $_applied'),
      ],
    );
  }
}

class PollingBadge extends HookWidget {
  const PollingBadge({required this.interval, super.key});

  final Duration interval;

  @override
  Widget build(BuildContext context) {
    final ticks = useState<int>(0);

    useEffect(() {
      final timer = Timer.periodic(interval, (_) {
        ticks.value++;
      });
      return timer.cancel;
    }, <Object?>[interval]);

    return Row(
      spacing: 1,
      children: [
        const Badge(label: 'POLLING', variant: BadgeVariant.info),
        Text('${ticks.value} checks'),
      ],
    );
  }
}

final class SaveIntent extends Intent {
  const SaveIntent();
}

class SaveShortcut extends StatelessWidget {
  const SaveShortcut({required this.onSave, required this.child, super.key});

  final VoidCallback onSave;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyS, control: true): SaveIntent(),
      },
      child: Actions(
        actions: {
          SaveIntent: CallbackAction<SaveIntent>((intent, context) {
            onSave();
            return KeyEventResult.handled;
          }),
        },
        child: child,
      ),
    );
  }
}

class DismissOnEscape extends StatelessWidget {
  const DismissOnEscape({
    required this.onDismiss,
    required this.child,
    super.key,
  });

  final VoidCallback onDismiss;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (!event.isPress || event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        onDismiss();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

void main() {
  late BufferCapture capture;

  setUp(() {
    capture = BufferCapture(width: 48, height: 12);
  });

  tearDown(() {
    capture.dispose();
  });

  test('StatusRegion paints the badge and progress', () {
    expect(
      capture.capture(const StatusRegion(progress: 0.4)).toText(),
      contains('BUILD'),
    );
  });

  test('Panel paints the border title', () {
    expect(
      capture
          .capture(
            const Panel(title: 'Build log', width: 24, child: Text('ok')),
          )
          .toText(),
      contains('Build log'),
    );
  });

  test('FilterField paints the unapplied label', () {
    expect(capture.capture(const FilterField()).toText(), contains('filter'));
  });

  test('PollingBadge paints its status', () {
    expect(
      capture
          .capture(const PollingBadge(interval: Duration(hours: 1)))
          .toText(),
      contains('POLLING'),
    );
  });

  test('SaveShortcut paints its child', () {
    expect(
      capture
          .capture(SaveShortcut(onSave: () {}, child: const Text('saved')))
          .toText(),
      contains('saved'),
    );
  });

  test('DismissOnEscape paints its child', () {
    expect(
      capture
          .capture(DismissOnEscape(onDismiss: () {}, child: const Text('open')))
          .toText(),
      contains('open'),
    );
  });

  test('Select paints the visible options at height 2', () {
    expect(
      capture
          .capture(
            Select<String>(
              options: const [
                SelectOption(name: 'Development', value: 'dev'),
                SelectOption(name: 'Production', value: 'prod'),
              ],
              height: 2,
              autofocus: true,
              onSelect: (_, option) {
                final environment = option.value;
                if (environment != null) applyEnvironment(environment);
              },
            ),
          )
          .toText(),
      contains('Development'),
    );
  });

  test('MarkdownView paints the heading text', () {
    expect(
      capture
          .capture(const MarkdownView(markdown: '# Notes', autofocus: true))
          .toText(),
      contains('Notes'),
    );
  });

  test('PointerListener paints its child', () {
    expect(
      capture
          .capture(
            PointerListener(
              onPointerDown: (event) {
                if (event.button == MouseButton.left) {
                  onSelect(event.localPosition);
                }
              },
              child: const Text('hit'),
            ),
          )
          .toText(),
      contains('hit'),
    );
  });
}
