import 'package:noir/noir.dart';
import 'package:noir/src/rendering/box.dart';
import 'package:noir/src/rendering/object.dart';
import 'package:noir/src/rendering/render_view.dart';

import '../helpers/test_element_host.dart';

void main() {
  _expect<ArgumentError>('constraints', () {
    _ProbeBox().layout(_BadConstraints());
  });
  _expect<StateError>('size', () {
    _BadSizeBox().layout(const BoxConstraints());
  });
  _expect<ArgumentError>('constrained-widget', () {
    final host = TestElementHost();
    try {
      host
        ..mount(ConstrainedBox(constraints: _BadBoxConstraints()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('container-constraints', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Container(constraints: _BadBoxConstraints()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('padding-widget', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Padding(padding: _BadInsets()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('container-margin', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Container(margin: _BadInsets()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('sized-widget', () {
    final host = TestElementHost();
    try {
      host
        ..mount(SizedBox(width: -1))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('panel-width', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Panel(width: -1, child: const SizedBox.shrink()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('panel-height', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Panel(height: -1, child: const SizedBox.shrink()))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('textarea-widget', () {
    final host = TestElementHost();
    try {
      host
        ..mount(TextArea(height: -1))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('textarea-max-height', () {
    final host = TestElementHost();
    try {
      host
        ..mount(TextArea(height: 2, maxHeight: 1))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('select-widget', () {
    final host = TestElementHost();
    try {
      host
        ..mount(Select<String>(options: const [], height: -1))
        ..pumpFrame();
    } finally {
      _disposeQuietly(host);
    }
  });
  _expect<ArgumentError>('viewport', () {
    ViewportController(contentExtent: -1);
  });
  _expect<ArgumentError>('scroll-controller', () {
    ScrollController().updateMaxScrollExtent(double.nan);
  });
  _expect<ArgumentError>('render-view', () {
    RenderView(width: -1);
  });
  _expectZeroScroll(
    'scroll-vertical-zero-width',
    axis: Axis.vertical,
    width: 0,
    height: 2,
    expectedViewport: 2,
  );
  _expectZeroScroll(
    'scroll-vertical-zero-height',
    axis: Axis.vertical,
    width: 2,
    height: 0,
    expectedViewport: 0,
  );
  _expectZeroScroll(
    'scroll-horizontal-zero-width',
    axis: Axis.horizontal,
    width: 0,
    height: 2,
    expectedViewport: 0,
  );
  _expectZeroScroll(
    'scroll-horizontal-zero-height',
    axis: Axis.horizontal,
    width: 2,
    height: 0,
    expectedViewport: 2,
  );
}

void _expect<T extends Object>(String label, void Function() body) {
  try {
    body();
  } on T {
    print('PASS:$label');
    return;
  }
  throw StateError('unexpected success: $label');
}

void _disposeQuietly(TestElementHost host) {
  try {
    host.dispose();
  } on Object {
    // The expected construction error can leave the host only partly mounted.
  }
}

void _expectZeroScroll(
  String label, {
  required Axis axis,
  required int width,
  required int height,
  required int expectedViewport,
}) {
  final controller = ScrollController();
  final host = TestElementHost();
  try {
    host
      ..mount(
        ScrollBox(
          controller: controller,
          scrollDirection: axis,
          child: const SizedBox(width: 3, height: 3),
        ),
      )
      ..pumpFrame(
        constraints: BoxConstraints.tight(width: width, height: height),
      );
    if (controller.viewportExtent != expectedViewport) {
      throw StateError(
        '$label viewport=${controller.viewportExtent}, '
        'expected=$expectedViewport',
      );
    }
    final renderObject = host.renderObject;
    if (renderObject is! RenderBox) {
      throw StateError('$label has no RenderBox');
    }
    final canvas = _CountingCanvas();
    renderObject.paint(PaintingContext(canvas), Offset.zero);
    if (canvas.callCount != 0) {
      throw StateError('$label recorded ${canvas.callCount} paint calls');
    }
    if (renderObject.hitTest(HitTestResult(), Offset.zero)) {
      throw StateError('$label unexpectedly hit');
    }
    print('PASS:$label');
  } finally {
    _disposeQuietly(host);
  }
}

final class _CountingCanvas implements TuiCanvas {
  int callCount = 0;

  void _record() {
    callCount++;
  }

  @override
  void save() => _record();

  @override
  void restore() => _record();

  @override
  void clipRect(Rect rect) => _record();

  @override
  void fillRect(Rect rect, Color color) => _record();

  @override
  void drawText(
    String text,
    Offset offset,
    Color foreground, {
    Color? background,
    int attributes = 0,
  }) => _record();

  @override
  void drawBox(
    Rect rect,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) => _record();

  @override
  void setCell(
    Offset offset,
    String char,
    Color foreground,
    Color background,
    int attributes,
  ) => _record();

  @override
  void drawTextLayout(
    TextLayout layout,
    Offset offset, {
    Rect? sourceRect,
    TextHighlight? selection,
  }) => _record();

  @override
  void drawImage(
    TerminalImage image,
    Rect destination, {
    int pixelWidth = 0,
    int pixelHeight = 0,
    Rect? sourceRect,
    ImageProtocol protocol = ImageProtocol.auto,
  }) => _record();
}

final class _BadConstraints extends Constraints {
  _BadConstraints() : super(maxWidth: 1);

  @override
  int? get maxWidth => -1;
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

final class _BadSize extends Size {
  const _BadSize() : super(0, 0);

  @override
  int get height => -1;
}

final class _ProbeBox extends RenderBox {}

final class _BadSizeBox extends RenderBox {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = const _BadSize();
  }
}
