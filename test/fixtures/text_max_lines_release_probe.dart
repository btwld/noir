import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';

import '../helpers/test_element_host.dart';

/// Assertions-disabled probe for positive-or-null maxLines.
void main() {
  _expectArgument('render-construct-zero', () {
    RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 0);
  });
  _expectArgument('render-construct-neg', () {
    RenderParagraph(text: const TextSpan(text: 'a'), maxLines: -1);
  });
  _expectArgument('render-set-zero', () {
    RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 1).maxLines = 0;
  });
  _expectArgument('render-set-neg', () {
    RenderParagraph(text: const TextSpan(text: 'a'), maxLines: 1).maxLines = -2;
  });

  _expectWidgetUpdatePreservesConfig(
    'text-update-zero',
    initial: const Text('old', maxLines: 2),
    invalidMaxLines: 0,
    expectedMaxLines: 2,
    kind: _WidgetKind.text,
  );
  _expectWidgetUpdatePreservesConfig(
    'text-rich-update-neg',
    initial: const Text.rich(TextSpan(text: 'old'), maxLines: 1),
    invalidMaxLines: -1,
    expectedMaxLines: 1,
    kind: _WidgetKind.textRich,
  );
  _expectWidgetUpdatePreservesConfig(
    'richtext-update-zero',
    initial: const RichText(text: TextSpan(text: 'old'), maxLines: 3),
    invalidMaxLines: 0,
    expectedMaxLines: 3,
    kind: _WidgetKind.richText,
  );

  for (final value in [0, -1]) {
    _expectArgument('text-create-$value', () {
      final host = TestElementHost();
      try {
        // Runtime-derived invalid maxLines so const evaluation is skipped.
        host
          ..mount(Text('x', maxLines: value))
          ..pumpFrame();
      } finally {
        _disposeQuietly(host);
      }
    });
    _expectArgument('text-rich-create-$value', () {
      final host = TestElementHost();
      try {
        host
          ..mount(Text.rich(const TextSpan(text: 'x'), maxLines: value))
          ..pumpFrame();
      } finally {
        _disposeQuietly(host);
      }
    });
    _expectArgument('richtext-create-$value', () {
      final host = TestElementHost();
      try {
        host
          ..mount(
            RichText(
              text: const TextSpan(text: 'x'),
              maxLines: value,
            ),
          )
          ..pumpFrame();
      } finally {
        _disposeQuietly(host);
      }
    });
  }
}

enum _WidgetKind { text, textRich, richText }

void _expectArgument(String label, void Function() body) {
  var threw = false;
  try {
    body();
  } catch (error) {
    if (error is! ArgumentError) {
      rethrow;
    }
    threw = true;
  }
  if (!threw) {
    throw StateError('UNEXPECTED_SUCCESS:$label');
  }
  print('PASS:$label');
}

void _expectWidgetUpdatePreservesConfig(
  String label, {
  required Widget initial,
  required int invalidMaxLines,
  required int expectedMaxLines,
  required _WidgetKind kind,
}) {
  final host = TestElementHost()..mount(initial);
  try {
    final paragraph = host.renderObject! as RenderParagraph
      ..layout(const BoxConstraints(maxWidth: 20, maxHeight: 5));
    final cached = paragraph.debugTextLayout;
    final oldText = paragraph.text;
    final oldAlign = paragraph.alignment;

    final invalid = switch (kind) {
      _WidgetKind.text => Text(
        'new-text',
        maxLines: invalidMaxLines,
        textAlign: TextAlign.right,
        style: const TextStyle(color: Color.red),
      ),
      _WidgetKind.textRich => Text.rich(
        const TextSpan(text: 'new'),
        maxLines: invalidMaxLines,
        textAlign: TextAlign.right,
      ),
      _WidgetKind.richText => RichText(
        text: const TextSpan(text: 'new'),
        maxLines: invalidMaxLines,
        textAlign: TextAlign.center,
      ),
    };

    var threw = false;
    try {
      host.root!.update(invalid);
      host.owner.buildScope();
    } catch (error) {
      if (error is! ArgumentError) {
        rethrow;
      }
      threw = true;
    }
    if (!threw) {
      throw StateError('UNEXPECTED_SUCCESS:$label');
    }

    _same(paragraph.maxLines, expectedMaxLines, '$label maxLines');
    _same(identical(paragraph.debugTextLayout, cached), true, '$label cache');
    _same(identical(paragraph.text, oldText), true, '$label text');
    _same(paragraph.alignment, oldAlign, '$label alignment');
    _same(paragraph.debugNeedsLayout, false, '$label dirty');
    print('PASS:$label');
  } finally {
    _disposeQuietly(host);
  }
}

void _same(Object? actual, Object? expected, String label) {
  if (actual != expected) {
    throw StateError('FAIL:$label actual=$actual expected=$expected');
  }
}

void _disposeQuietly(TestElementHost host) {
  try {
    host.dispose();
  } catch (_) {}
}
