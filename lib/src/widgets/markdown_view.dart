import 'dart:convert';

import 'package:markdown/markdown.dart' as md;
import 'package:meta/meta.dart';

import '../core/color.dart';
import '../core/terminal_style.dart';
import '../foundation/selected_text.dart';
import '../foundation/text_selection.dart';
import '../framework/build_context.dart';
import '../framework/focus_manager.dart';
import '../framework/widget.dart';
import 'code_view.dart';
import 'divider.dart';
import 'document_view.dart';
import 'focus.dart';
import 'focus_node_owner_mixin.dart';
import 'row_column.dart';
import 'scroll_box.dart';
import 'sized_box.dart';
import 'text_span.dart';
import 'text_style.dart';
import 'text_table.dart';
import 'text_table_model.dart';
import 'theme.dart';

/// Builds one Markdown block, optionally delegating to [buildDefault].
typedef MarkdownBlockRenderer =
    Widget Function(
      BuildContext context,
      Object node,
      Widget Function() buildDefault,
    );

/// Immutable style palette for [MarkdownView].
@immutable
final class MarkdownThemeData {
  /// Creates a Markdown palette from explicit terminal text styles.
  const MarkdownThemeData({
    required this.paragraph,
    required this.heading1,
    required this.heading2,
    required this.heading3,
    required this.emphasis,
    required this.strong,
    required this.link,
    required this.quote,
    required this.inlineCode,
    required this.ruleColor,
  });

  /// Derives document styles from a Noir application [theme].
  factory MarkdownThemeData.fromTheme(ThemeData theme) => MarkdownThemeData(
    paragraph: TextStyle(color: theme.text),
    heading1: TextStyle(
      color: theme.accent,
      attributes: Attr.bold | Attr.underline,
    ),
    heading2: TextStyle(color: theme.accent, attributes: Attr.bold),
    heading3: TextStyle(color: theme.text, attributes: Attr.bold),
    emphasis: TextStyle(color: theme.text, attributes: Attr.italic),
    strong: TextStyle(color: theme.text, attributes: Attr.bold),
    link: TextStyle(color: theme.accent, attributes: Attr.underline),
    quote: TextStyle(color: theme.textMuted, attributes: Attr.italic),
    inlineCode: TextStyle(
      color: theme.text,
      backgroundColor: theme.surfaceVariant,
    ),
    ruleColor: theme.border,
  );

  /// Ordinary paragraph and list content.
  final TextStyle paragraph;

  /// Level-one heading style.
  final TextStyle heading1;

  /// Level-two heading style.
  final TextStyle heading2;

  /// Level-three and deeper heading style.
  final TextStyle heading3;

  /// Emphasis style.
  final TextStyle emphasis;

  /// Strong-emphasis style.
  final TextStyle strong;

  /// Link and linked-image-alt style.
  final TextStyle link;

  /// Blockquote style.
  final TextStyle quote;

  /// Inline-code style.
  final TextStyle inlineCode;

  /// Horizontal-rule foreground.
  final Color ruleColor;

  /// Copies this palette, replacing only the provided fields.
  MarkdownThemeData copyWith({
    TextStyle? paragraph,
    TextStyle? heading1,
    TextStyle? heading2,
    TextStyle? heading3,
    TextStyle? emphasis,
    TextStyle? strong,
    TextStyle? link,
    TextStyle? quote,
    TextStyle? inlineCode,
    Color? ruleColor,
  }) => MarkdownThemeData(
    paragraph: paragraph ?? this.paragraph,
    heading1: heading1 ?? this.heading1,
    heading2: heading2 ?? this.heading2,
    heading3: heading3 ?? this.heading3,
    emphasis: emphasis ?? this.emphasis,
    strong: strong ?? this.strong,
    link: link ?? this.link,
    quote: quote ?? this.quote,
    inlineCode: inlineCode ?? this.inlineCode,
    ruleColor: ruleColor ?? this.ruleColor,
  );
}

/// GitHub-flavoured Markdown document.
///
/// The default is a focused selectable [ScrollBox]. Set [embedded] to size
/// to the parsed blocks so a parent viewport can own scrolling.
class MarkdownView extends StatefulWidget {
  /// Configures parsing, block customization, highlighting, and selection.
  const MarkdownView({
    required this.markdown,
    super.key,
    this.theme,
    this.codeHighlighter = const PlainTextCodeHighlighter(),
    this.blockRenderer,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.embedded = false,
    this.selectable = true,
    this.selectionForegroundColor,
    this.selectionBackgroundColor,
    this.onSelectionChanged,
    this.onCopy,
    this.onHighlightError,
  });

  /// Markdown source reparsed whenever it changes.
  final String markdown;

  /// Explicit document palette, or one derived from [Theme].
  final MarkdownThemeData? theme;

  /// Highlighter used by fenced [CodeView] blocks.
  final CodeHighlighter codeHighlighter;

  /// Optional AST block renderer with a default-render callback.
  ///
  /// Replacement widgets retain the parsed block's default text for document
  /// selection and copy, because arbitrary widgets do not expose plain text.
  final MarkdownBlockRenderer? blockRenderer;

  /// Caller-owned vertical scroll controller.
  final ScrollController? controller;

  /// Caller-owned viewport focus node.
  final FocusNode? focusNode;

  /// Whether the outer document requests focus after mounting.
  final bool autofocus;

  /// Whether this document sizes to its blocks and omits the inner [ScrollBox].
  ///
  /// Standalone documents keep a focused selectable viewport. Embedded
  /// documents are for a parent that already owns scrolling, such as a
  /// [ScrollBox] mixing chrome with markdown. [controller] is unused when
  /// this is true.
  final bool embedded;

  /// Whether textual blocks and fenced code allow selection.
  final bool selectable;

  /// Selected text foreground override.
  final Color? selectionForegroundColor;

  /// Selected text background override.
  final Color? selectionBackgroundColor;

  /// Receives selection changes from selectable text/code blocks.
  final void Function(SelectedText? selection)? onSelectionChanged;

  /// Receives explicit selection copy results.
  final SelectionCopyCallback? onCopy;

  /// Receives fenced-code highlighting failures.
  final HighlightErrorCallback? onHighlightError;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

final class _MarkdownViewState extends State<MarkdownView>
    with FocusNodeOwnerStateMixin<MarkdownView> {
  late List<md.Node> _nodes;
  String _documentText = '';
  TextSelection? _selection;
  bool _dragging = false;

  @override
  FocusNode? get widgetFocusNode => widget.focusNode;

  @override
  void initState() {
    super.initState();
    _nodes = _parseMarkdown(widget.markdown);
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncFocusNode(oldWidget.focusNode);
    if (widget.markdown != oldWidget.markdown) {
      _nodes = _parseMarkdown(widget.markdown);
      if (_selection != null) {
        _selection = null;
        widget.onSelectionChanged?.call(null);
      }
    }
  }

  void _setSelection(TextSelection? selection) {
    if (_selection == selection) return;
    setState(() => _selection = selection);
    widget.onSelectionChanged?.call(_selectedText);
  }

  SelectedText? get _selectedText {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;
    return SelectedText(
      selection: selection,
      text: _documentText.substring(selection.start, selection.end),
    );
  }

  void _setDragging({required bool dragging}) {
    if (_dragging == dragging) return;
    setState(() => _dragging = dragging);
  }

  @override
  Widget build(BuildContext context) {
    final documentTheme =
        widget.theme ?? MarkdownThemeData.fromTheme(Theme.of(context));
    final blocks = <_MarkdownBlock>[
      for (final node in _nodes)
        _renderBlockWithHook(context, documentTheme, node),
    ];
    _documentText = blocks.map((block) => block.plainText).join('\n\n');
    final children = <Widget>[];
    var sourceBase = 0;
    var previousIsHeading = false;
    for (final block in blocks) {
      if (children.isNotEmpty && !previousIsHeading) {
        children.add(const SizedBox(height: 1));
      }
      children.add(
        DocumentSelectionScope(
          documentText: _documentText,
          sourceBase: sourceBase,
          selection: _selection,
          dragging: _dragging,
          readSelection: () => _selection,
          readDragging: () => _dragging,
          onSelectionChanged: _setSelection,
          onDraggingChanged: _setDragging,
          onCopy: widget.onCopy,
          leafCanRequestFocus: !widget.embedded,
          child: block.widget,
        ),
      );
      sourceBase += block.plainText.length + 2;
      previousIsHeading = block.isHeading;
    }
    final document = DocumentScrollScope(
      handlesScrolling: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    return DocumentSelectionControls(
      documentText: _documentText,
      selectable: widget.selectable,
      readSelection: () => _selection,
      onSelectionChanged: _setSelection,
      onCopy: widget.onCopy,
      focusNode: focusNode,
      child: widget.embedded
          ? Focus(
              focusNode: focusNode,
              autofocus: widget.autofocus,
              canRequestFocus: !widget.embedded,
              child: document,
            )
          : ScrollBox(
              controller: widget.controller,
              focusNode: focusNode,
              autofocus: widget.autofocus,
              child: document,
            ),
    );
  }

  _MarkdownBlock _renderBlockWithHook(
    BuildContext context,
    MarkdownThemeData theme,
    md.Node node,
  ) {
    final defaultBlock = _renderBlock(theme, node);
    Widget buildDefault() => defaultBlock.widget;
    return _MarkdownBlock(
      widget:
          widget.blockRenderer?.call(context, node, buildDefault) ??
          defaultBlock.widget,
      plainText: defaultBlock.plainText,
      isHeading: defaultBlock.isHeading,
    );
  }

  _MarkdownBlock _renderBlock(MarkdownThemeData theme, md.Node node) {
    if (node is md.Text) {
      return _textBlock(TextSpan(text: node.text, style: theme.paragraph));
    }
    if (node is! md.Element) {
      return _textBlock(
        TextSpan(text: node.textContent, style: theme.paragraph),
      );
    }
    return switch (node.tag) {
      'h1' => _textBlock(_inline(theme, node, theme.heading1), isHeading: true),
      'h2' => _textBlock(_inline(theme, node, theme.heading2), isHeading: true),
      'h3' ||
      'h4' ||
      'h5' ||
      'h6' => _textBlock(_inline(theme, node, theme.heading3), isHeading: true),
      'p' => _textBlock(_inline(theme, node, theme.paragraph)),
      'blockquote' => _textBlock(
        TextSpan(
          style: theme.quote,
          children: <InlineSpan>[
            const TextSpan(text: '│ '),
            _inline(theme, node, theme.quote),
          ],
        ),
      ),
      'ul' => _listBlock(theme, node, ordered: false),
      'ol' => _listBlock(theme, node, ordered: true),
      'hr' => _MarkdownBlock(
        widget: Divider(color: theme.ruleColor),
        plainText: '',
      ),
      'pre' => _codeBlock(node),
      'table' => _tableBlock(theme, node),
      _ => _textBlock(_inline(theme, node, theme.paragraph)),
    };
  }

  _MarkdownBlock _textBlock(InlineSpan span, {bool isHeading = false}) {
    final plainText = span.toPlainText();
    return _MarkdownBlock(
      widget: DocumentView(
        text: span,
        plainText: plainText,
        selectable: widget.selectable,
        selectionForegroundColor: widget.selectionForegroundColor,
        selectionBackgroundColor:
            widget.selectionBackgroundColor ??
            Theme.of(context).selectedBackground,
      ),
      plainText: plainText,
      isHeading: isHeading,
    );
  }

  _MarkdownBlock _codeBlock(md.Element pre) {
    final child = pre.children?.whereType<md.Element>().firstOrNull;
    final className = child?.attributes['class'];
    final language = className?.startsWith('language-') ?? false
        ? className!.substring('language-'.length)
        : null;
    final code = child?.textContent ?? pre.textContent;
    return _MarkdownBlock(
      widget: CodeView(
        code: code,
        language: language,
        highlighter: widget.codeHighlighter,
        showLineNumbers: false,
        wrap: true,
        selectable: widget.selectable,
        selectionForegroundColor: widget.selectionForegroundColor,
        selectionBackgroundColor: widget.selectionBackgroundColor,
        onHighlightError: widget.onHighlightError,
      ),
      plainText: code,
    );
  }

  _MarkdownBlock _listBlock(
    MarkdownThemeData theme,
    md.Element list, {
    required bool ordered,
  }) => _textBlock(_listSpan(theme, list, ordered: ordered, depth: 0));

  InlineSpan _listSpan(
    MarkdownThemeData theme,
    md.Element list, {
    required bool ordered,
    required int depth,
  }) {
    final items = list.children?.whereType<md.Element>().toList() ?? const [];
    final children = <InlineSpan>[];
    final orderedStart = ordered
        ? int.tryParse(list.attributes['start'] ?? '') ?? 1
        : 1;
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      final checked = _taskState(item);
      final prefix = _listPrefix(
        index,
        ordered: ordered,
        orderedStart: orderedStart,
        checked: checked,
      );
      if (index > 0) children.add(const TextSpan(text: '\n'));
      children.add(
        TextSpan(text: '${''.padLeft(depth * 2)}$prefix', style: theme.strong),
      );
      for (final child in item.children ?? const <md.Node>[]) {
        if (child is md.Element && (child.tag == 'ul' || child.tag == 'ol')) {
          children
            ..add(const TextSpan(text: '\n'))
            ..add(
              _listSpan(
                theme,
                child,
                ordered: child.tag == 'ol',
                depth: depth + 1,
              ),
            );
        } else {
          children.add(_inline(theme, child, theme.paragraph));
        }
      }
    }
    return TextSpan(style: theme.paragraph, children: children);
  }

  _MarkdownBlock _tableBlock(MarkdownThemeData theme, md.Element table) {
    final rows = <List<InlineSpan?>>[];
    void visit(md.Node node) {
      if (node is md.Element && node.tag == 'tr') {
        rows.add(<InlineSpan?>[
          for (final cell
              in node.children?.whereType<md.Element>() ?? const <md.Element>[])
            _inline(
              theme,
              cell,
              cell.tag == 'th' ? theme.strong : theme.paragraph,
            ),
        ]);
        return;
      }
      if (node is md.Element) {
        for (final child in node.children ?? const <md.Node>[]) {
          visit(child);
        }
      }
    }

    visit(table);
    final content = _dropEmptyTableColumns(rows);
    final plainText = serializeTextTableContent(content);
    return _MarkdownBlock(
      widget: TextTable(
        content: content,
        borderColor: theme.ruleColor,
        columnWidthMode: TextTableColumnWidthMode.content,
        selectable: widget.selectable,
        selectionForegroundColor: widget.selectionForegroundColor,
        selectionBackgroundColor: widget.selectionBackgroundColor,
      ),
      plainText: plainText,
    );
  }

  InlineSpan _inline(
    MarkdownThemeData theme,
    md.Node node,
    TextStyle inherited,
  ) {
    if (node is md.Text) return TextSpan(text: node.text, style: inherited);
    if (node is! md.Element) {
      return TextSpan(text: node.textContent, style: inherited);
    }
    if (node.tag == 'img') {
      final source = node.attributes['src'];
      final alt = node.attributes['alt'] ?? node.textContent;
      return TextSpan(
        text: alt.isEmpty ? source ?? '' : alt,
        style: theme.link,
        uri: _semanticHttpUri(source),
      );
    }
    if (node.tag == 'br') return const TextSpan(text: '\n');
    if (node.tag == 'input') return const TextSpan(text: '');
    final style = switch (node.tag) {
      'em' => _mergeInlineStyle(inherited, theme.emphasis),
      'strong' => _mergeInlineStyle(inherited, theme.strong),
      'del' => inherited.copyWith(
        attributes: inherited.computedAttributes | Attr.strike,
      ),
      'code' => _mergeInlineStyle(inherited, theme.inlineCode),
      'a' => _mergeInlineStyle(inherited, theme.link),
      _ => inherited,
    };
    final uri = node.tag == 'a'
        ? _semanticHttpUri(node.attributes['href'])
        : null;
    return TextSpan(
      style: style,
      uri: uri,
      children: <InlineSpan>[
        for (final child in node.children ?? const <md.Node>[])
          _inline(theme, child, style),
      ],
    );
  }
}

Uri? _semanticHttpUri(String? value) {
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.scheme == 'http' || uri.scheme == 'https' ? uri : null;
}

TextStyle _mergeInlineStyle(TextStyle inherited, TextStyle overlay) =>
    overlay.copyWith(
      backgroundColor: overlay.backgroundColor ?? inherited.backgroundColor,
      attributes: inherited.computedAttributes | overlay.attributes,
    );

final class _MarkdownBlock {
  const _MarkdownBlock({
    required this.widget,
    required this.plainText,
    this.isHeading = false,
  });

  final Widget widget;
  final String plainText;
  final bool isHeading;
}

List<List<InlineSpan?>> _dropEmptyTableColumns(List<List<InlineSpan?>> rows) {
  if (rows.length < 2) return rows;
  var columns = 0;
  for (final row in rows) {
    if (row.length > columns) columns = row.length;
  }
  final keep = <int>[];
  for (var column = 0; column < columns; column++) {
    var empty = true;
    for (var row = 1; row < rows.length; row++) {
      final cell = column < rows[row].length ? rows[row][column] : null;
      if ((cell?.toPlainText() ?? '').trim().isNotEmpty) {
        empty = false;
        break;
      }
    }
    if (!empty) keep.add(column);
  }
  if (keep.isEmpty || keep.length == columns) return rows;
  return [
    for (final row in rows)
      [for (final column in keep) column < row.length ? row[column] : null],
  ];
}

String _listPrefix(
  int index, {
  required bool ordered,
  required int orderedStart,
  required bool? checked,
}) {
  if (checked != null) return checked ? '[x] ' : '[ ] ';
  return ordered ? '${orderedStart + index}. ' : '• ';
}

/// Parses GitHub-flavoured markdown for TUI paint, not HTML output.
///
/// `package:markdown` defaults to `encodeHtml: true`, which leaves `&gt;` in
/// table cells and inline code. This renderer copies `node.text` into widgets.
List<md.Node> _parseMarkdown(String source) => md.Document(
  extensionSet: md.ExtensionSet.gitHubFlavored,
  encodeHtml: false,
).parseLines(const LineSplitter().convert(_unwrapGithubDetails(source)));

final _githubDetailsPattern = RegExp(
  r'<details\b[^>]*>\s*(?:<summary\b[^>]*>(.*?)</summary>\s*)?(.*?)</details>',
  caseSensitive: false,
  dotAll: true,
);

final _htmlTagPattern = RegExp('<[^>]+>');

/// Turns GitHub `<details>`/`<summary>` wrappers into markdown the GFM parser
/// can see. `package:markdown`'s GitHub set leaves those tags as raw text.
/// Fenced code is left untouched so samples that mention the tags stay literal.
String _unwrapGithubDetails(String source) {
  final lines = const LineSplitter().convert(source);
  final output = StringBuffer();
  final chunk = StringBuffer();
  var inFence = false;

  void flush({required bool raw}) {
    final text = chunk.toString();
    chunk.clear();
    if (text.isEmpty) return;
    output.write(raw ? text : _unwrapGithubDetailsChunk(text));
  }

  for (final line in lines) {
    if (line.trimLeft().startsWith('```')) {
      if (!inFence) {
        flush(raw: false);
        inFence = true;
        chunk.writeln(line);
      } else {
        chunk.writeln(line);
        flush(raw: true);
        inFence = false;
      }
    } else {
      chunk.writeln(line);
    }
  }
  flush(raw: inFence);
  var result = output.toString();
  if (!source.endsWith('\n') && result.endsWith('\n')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _unwrapGithubDetailsChunk(String source) {
  var current = source;
  for (var i = 0; i < 8; i++) {
    final next = current.replaceAllMapped(_githubDetailsPattern, (match) {
      final summary = match.group(1)?.replaceAll(_htmlTagPattern, '').trim();
      final body = (match.group(2) ?? '').trim();
      if (summary == null || summary.isEmpty) return '\n\n$body\n\n';
      return '\n\n**$summary**\n\n$body\n\n';
    });
    if (next == current) return current;
    current = next;
  }
  return current;
}

bool? _taskState(md.Element item) {
  md.Element? input;
  void find(md.Node node) {
    if (input != null) return;
    if (node is md.Element && node.tag == 'input') {
      input = node;
      return;
    }
    if (node is md.Element) {
      if (node.tag == 'ul' || node.tag == 'ol') return;
      for (final child in node.children ?? const <md.Node>[]) {
        find(child);
      }
    }
  }

  find(item);
  final match = input;
  if (match == null) return null;
  return match.attributes.containsKey('checked');
}
