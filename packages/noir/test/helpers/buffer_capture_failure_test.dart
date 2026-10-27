import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:test/test.dart';

import 'buffer_capture.dart';

void main() {
  test('capture preserves a paint failure when state disposal also fails', () {
    final capture = BufferCapture(width: 2, height: 1);
    addTearDown(capture.dispose);
    final primary = StateError('paint failed');
    final primaryStack = StackTrace.fromString('original paint stack');
    final cleanup = StateError('dispose failed');
    var disposed = false;
    Object? caught;
    StackTrace? stack;

    try {
      capture.capture(
        _FailureWidget(
          primary: primary,
          primaryStack: primaryStack,
          onDispose: () {
            disposed = true;
            throw cleanup;
          },
        ),
      );
    } on Object catch (error, trace) {
      caught = error;
      stack = trace;
    }

    expect(disposed, isTrue);
    expect(caught, same(primary));
    expect(stack.toString(), primaryStack.toString());
  });
}

class _FailureWidget extends StatefulWidget {
  const _FailureWidget({
    required this.primary,
    required this.primaryStack,
    required this.onDispose,
  });

  final Object primary;
  final StackTrace primaryStack;
  final void Function() onDispose;

  @override
  State<_FailureWidget> createState() => _FailureState();
}

class _FailureState extends State<_FailureWidget> {
  @override
  Widget build(BuildContext context) =>
      _PaintFailure(primary: widget.primary, primaryStack: widget.primaryStack);

  @override
  void dispose() {
    super.dispose();
    widget.onDispose();
  }
}

class _PaintFailure extends RenderObjectWidget {
  const _PaintFailure({required this.primary, required this.primaryStack});

  final Object primary;
  final StackTrace primaryStack;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintFailure(primary, primaryStack);
}

class _RenderPaintFailure extends RenderBox {
  _RenderPaintFailure(this.primary, this.primaryStack);

  final Object primary;
  final StackTrace primaryStack;

  @override
  void performBoxLayout(BoxConstraints constraints) => size = const Size(1, 1);

  @override
  void paint(PaintingContext context, Offset offset) =>
      Error.throwWithStackTrace(primary, primaryStack);
}
