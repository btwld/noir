// The sort callback takes `ascending` positionally, beside the positional
// `columnIndex`: both are coordinates of the same click.
// ignore_for_file: avoid_positional_boolean_parameters

import 'dart:math' as math;

import '../core/color.dart';
import '../core/input.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import '../render/geometry.dart';
import 'align.dart';
import 'container.dart';
import 'divider.dart';
import 'flexible.dart';
import 'input.dart';
import 'list_view.dart';
import 'pointer_listener.dart';
import 'row_column.dart';
import 'sized_box.dart';
import 'text.dart';
import 'text_layout.dart';
import 'text_style.dart';
import 'theme.dart';
import 'viewport.dart';

/// Glyphs marking which way the sorted column is ordered, matching the ones
/// `Select` uses for its scroll indicator.
const String _ascending = '▲';
const String _descending = '▼';

/// One column of a [DataTable].
///
/// A column is either fixed ([width] set) or proportional ([flex]); a set
/// [width] wins. The same list of columns sizes the header and every body row,
/// which is what keeps their cell boundaries on the same terminal columns.
class DataColumn {
  /// Configures a column titled [label], fixed at [width] or else sharing the
  /// leftover cells in proportion to [flex].
  const DataColumn({
    required this.label,
    this.flex = 1,
    this.width,
    this.alignment = Alignment.centerLeft,
    this.sortable = false,
  }) : assert(flex >= 1),
       assert(width == null || width >= 0);

  /// Header text for the column.
  final String label;

  /// Share of the leftover width this column takes. Ignored when [width] is
  /// set.
  final int flex;

  /// Exact width in cells. Overrides [flex] when set.
  final int? width;

  /// Placement of each cell inside its column box. Use [Alignment.centerRight]
  /// for numbers.
  final Alignment alignment;

  /// Whether clicking this column's header reports a sort request.
  final bool sortable;
}

/// Signature for building the cell at [row] and [column] of a [DataTable].
///
/// Called only for rows in the visible window.
typedef DataTableCellBuilder =
    Widget Function(BuildContext context, int row, int column);

/// Signature for a sort request raised by clicking a sortable column header.
///
/// [ascending] is the direction the table is asking for, which is the opposite
/// of the current one when the same column is clicked again.
typedef DataTableSort = void Function(int columnIndex, bool ascending);

/// A scrolling table of rows and columns with an aligned header.
///
/// Every row — the header and each visible body row — is a `Row` built from
/// the *same* ordered [columns] list, so `RenderFlex` resolves identical cell
/// boundaries for all of them. That is the whole alignment mechanism; a future
/// per-row column override would silently break it.
///
/// The body is a [ListView], so it inherits windowed building (only visible
/// rows are built), selection, keyboard navigation, click-to-select, and wheel
/// scrolling from one implementation rather than a second copy.
///
/// Sorting is presentational: clicking a header marked
/// [DataColumn.sortable] fires [onSort] and paints an arrow on
/// [sortColumnIndex]; reordering the data is the caller's job. Header
/// activation is mouse-only in this release.
///
/// Cell widgets should clamp their own overflow — `Text(maxLines: 1,
/// softWrap: false, overflow: TextOverflow.ellipsis)` is the usual choice,
/// since a cell wider than its column would otherwise wrap into the next row.
class DataTable extends StatefulWidget {
  /// Configures a table of [rowCount] rows across [columns], selectable when
  /// [selectedIndex] is non-null.
  const DataTable({
    required this.columns,
    required this.rowCount,
    required this.cellBuilder,
    super.key,
    this.height = 10,
    this.controller,
    this.selectedIndex,
    this.sortColumnIndex,
    this.sortAscending = true,
    this.onSort,
    this.headerColor,
    this.selectedBackgroundColor,
    this.showScrollIndicator = false,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSelect,
  }) : assert(rowCount >= 0),
       assert(height >= 2);

  /// Ordered column specifications, shared by the header and every body row.
  final List<DataColumn> columns;

  /// Total number of body rows.
  final int rowCount;

  /// Builds one cell; called only for rows in the visible window.
  final DataTableCellBuilder cellBuilder;

  /// Rows of terminal height for the whole table, header and separator
  /// included.
  final int height;

  /// Scroll position of the body, shared with the caller. One is created
  /// internally when null.
  final ViewportController? controller;

  /// Body row highlighted when the table is first built, or null for a table
  /// with no selection.
  final int? selectedIndex;

  /// Column currently marked as sorted, or null for none.
  final int? sortColumnIndex;

  /// Direction of the arrow drawn on [sortColumnIndex].
  final bool sortAscending;

  /// Called when the user clicks a sortable column header.
  final DataTableSort? onSort;

  /// Fill painted behind the header row. Falls back to
  /// [ThemeData.surfaceVariant] under a [Theme].
  final Color? headerColor;

  /// Fill painted behind the highlighted body row. Falls back to
  /// [ThemeData.selectedBackground] under a [Theme].
  final Color? selectedBackgroundColor;

  /// Whether the body reserves its last column for scroll-direction arrows.
  final bool showScrollIndicator;

  /// Focus node controlling body navigation. One is created if null.
  final FocusNode? focusNode;

  /// Whether the body requests focus when first mounted.
  final bool autofocus;

  /// Called with the new index whenever the highlighted body row moves.
  final ValueChanged<int>? onChanged;

  /// Called with the highlighted index when the user presses Enter or clicks a
  /// body row.
  final ValueChanged<int>? onSelect;

  @override
  State<DataTable> createState() => _DataTableState();
}

class _DataTableState extends State<DataTable> {
  /// Distributes [cells] across [DataTable.columns]. The header and every body
  /// row go through this one function, which is what makes their cell
  /// boundaries identical rather than merely intended to be.
  Row _columnedRow(List<Widget> cells) => Row(
    children: [
      for (var i = 0; i < widget.columns.length; i++)
        if (widget.columns[i].width case final int fixed)
          SizedBox(
            width: fixed,
            child: Align(
              alignment: widget.columns[i].alignment,
              child: cells[i],
            ),
          )
        else
          Expanded(
            flex: widget.columns[i].flex,
            child: Align(
              alignment: widget.columns[i].alignment,
              child: cells[i],
            ),
          ),
    ],
  );

  void _handleHeaderClick(int columnIndex) {
    final onSort = widget.onSort;
    if (onSort == null || !widget.columns[columnIndex].sortable) return;
    // Clicking the already-sorted column reverses it; a new column starts
    // ascending.
    final ascending =
        widget.sortColumnIndex != columnIndex || !widget.sortAscending;
    onSort(columnIndex, ascending);
  }

  Widget _headerCell(int index, ThemeData? theme) {
    final column = widget.columns[index];
    final sorted = widget.sortColumnIndex == index;
    final arrow = sorted
        ? (widget.sortAscending ? _ascending : _descending)
        : '';
    return PointerListener(
      onPointerDown: (event) {
        if (event.button == MouseButton.left) _handleHeaderClick(index);
      },
      child: Text(
        '${column.label}$arrow',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: theme?.text ?? Color.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.maybeOf(context);
    // The header and its separator each cost a row; the rest is body.
    final bodyHeight = math.max(0, widget.height - 2);

    Widget headerRow = _columnedRow([
      for (var i = 0; i < widget.columns.length; i++) _headerCell(i, theme),
    ]);
    if (widget.showScrollIndicator) {
      // The body gives its trailing column to the indicator gutter. The header
      // has to give up the same column or the two stop lining up.
      headerRow = Row(
        children: [
          Expanded(child: headerRow),
          const SizedBox(width: 1),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: widget.headerColor ?? theme?.surfaceVariant,
          child: headerRow,
        ),
        const Divider(),
        ListView(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          controller: widget.controller,
          itemCount: widget.rowCount,
          height: bodyHeight,
          selectedIndex: widget.selectedIndex,
          showScrollIndicator: widget.showScrollIndicator,
          selectedBackgroundColor: widget.selectedBackgroundColor,
          onChanged: widget.onChanged,
          onSelect: widget.onSelect,
          itemBuilder: (context, row, selected) => _columnedRow([
            for (var i = 0; i < widget.columns.length; i++)
              widget.cellBuilder(context, row, i),
          ]),
        ),
      ],
    );
  }
}
