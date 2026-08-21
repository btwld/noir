import 'dart:math' as math;

import 'package:meta/meta.dart';

import 'text_span.dart';

/// Serializes table cells in row-major order with tab and newline separators.
///
/// Rows are padded to the widest row so selection offsets match the render
/// table's rectangular cell model.
@internal
String serializeTextTableContent(List<List<InlineSpan?>> content) {
  final columns = content.fold<int>(
    0,
    (count, row) => math.max(count, row.length),
  );
  if (columns == 0) return '';
  return content
      .map(
        (row) => List<String>.generate(
          columns,
          (column) =>
              column < row.length ? row[column]?.toPlainText() ?? '' : '',
          growable: false,
        ).join('\t'),
      )
      .join('\n');
}
