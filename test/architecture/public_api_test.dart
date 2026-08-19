import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('public barrel exports only curated user-facing symbols', () {
    final source = File('lib/noir.dart').readAsStringSync();
    final exports = _parseExports(source);

    const allowedSymbolsByPath = <String, Set<String>>{
      'src/animation/animation.dart': {
        'Animation',
        'AnimationStatus',
        'AnimationStatusListener',
      },
      'src/animation/animation_controller.dart': {'AnimationController'},
      'src/animation/ticker.dart': {
        'SingleTickerProviderStateMixin',
        'Ticker',
        'TickerCallback',
        'TickerProvider',
        'TickerProviderStateMixin',
      },
      'src/app/app.dart': {'TuiApp', 'runTuiApp'},
      'src/app/hot_reload.dart': {'registerHotReloadExtension'},
      'src/core/capabilities.dart': {
        'ColorSupport',
        'TerminalCapabilities',
        'TerminalSize',
      },
      'src/core/color.dart': {'Color'},
      'src/core/terminal_style.dart': {
        'Attr',
        'BorderSides',
        'BoxOptions',
        'TextAlign',
      },
      'src/core/cursor.dart': {'CursorStyle'},
      'src/core/grapheme_metrics.dart': {
        'cellToGraphemeIndex',
        'graphemeIndexToCell',
        'sliceByCells',
        'terminalCellWidth',
        'terminalStringWidth',
      },
      'src/core/input.dart': {
        'KeyEvent',
        'KeyEventHandler',
        'KeyEventResult',
        'KeyModifiers',
        'KittyFlags',
        'LogicalKeyboardKey',
        'MouseButton',
        'MouseEvent',
        'MouseEventHandler',
        'MouseEventType',
        'MouseScroll',
        'MouseScrollDirection',
        'PasteEvent',
        'PasteEventHandler',
      },
      'src/foundation/change_notifier.dart': {'ChangeNotifier'},
      'src/foundation/disposable.dart': {'Disposable'},
      'src/foundation/listenable.dart': {
        'Listenable',
        'ValueListenable',
        'VoidCallback',
      },
      'src/foundation/text_editing_controller.dart': {'TextEditingController'},
      'src/foundation/text_editing_value.dart': {'TextEditingValue'},
      'src/foundation/text_index_map.dart': {'TextIndexMap'},
      'src/foundation/text_range.dart': {'TextRange'},
      'src/foundation/text_selection.dart': {'TextAffinity', 'TextSelection'},
      'src/foundation/value_notifier.dart': {'ValueNotifier'},
      'src/framework/build_context.dart': {'BuildContext'},
      'src/framework/focus_manager.dart': {
        'FocusNode',
        'FocusOnKeyEvent',
        'FocusScopeNode',
        'FocusTraversalPolicy',
      },
      'src/framework/key.dart': {
        'GlobalKey',
        'Key',
        'LocalKey',
        'ObjectKey',
        'UniqueKey',
        'ValueKey',
      },
      'src/framework/widget.dart': {
        'InheritedWidget',
        'ProxyWidget',
        'State',
        'StatefulWidget',
        'StatelessWidget',
        'Widget',
      },
      'src/painting/box_border.dart': {'Border', 'BorderStyle', 'BoxBorder'},
      'src/painting/box_decoration.dart': {'BoxDecoration'},
      'src/painting/decoration.dart': {'Decoration'},
      'src/painting/tui_canvas.dart': {'TuiCanvas'},
      'src/render/geometry.dart': {
        'Alignment',
        'Axis',
        'BoxConstraints',
        'BoxShape',
        'Constraints',
        'EdgeInsets',
        'Offset',
        'Rect',
        'Size',
      },
      'src/rendering/text_highlight.dart': {'TextHighlight'},
      'src/widgets/actions.dart': {
        'Action',
        'ActionCallback',
        'Actions',
        'CallbackAction',
      },
      'src/widgets/align.dart': {'Align'},
      'src/widgets/badge.dart': {'Badge', 'BadgeVariant'},
      'src/widgets/button.dart': {'Button'},
      'src/widgets/checkbox.dart': {'Checkbox'},
      'src/widgets/constrained_box.dart': {'ConstrainedBox'},
      'src/widgets/container.dart': {'Container'},
      'src/widgets/data_table.dart': {
        'DataColumn',
        'DataTable',
        'DataTableCellBuilder',
        'DataTableSort',
      },
      'src/widgets/decorated_box.dart': {'DecoratedBox', 'DecorationPosition'},
      'src/widgets/divider.dart': {'Divider'},
      'src/widgets/flexible.dart': {'Expanded', 'FlexFit', 'Flexible'},
      'src/widgets/focus.dart': {'Focus', 'FocusScope'},
      'src/widgets/input.dart': {'TextInput', 'ValueChanged'},
      'src/widgets/intents.dart': {
        'ActivateIntent',
        'DeleteBackwardIntent',
        'DeleteForwardIntent',
        'DismissIntent',
        'InsertTabIntent',
        'InsertTextIntent',
        'Intent',
        'MoveCaretDocumentEndIntent',
        'MoveCaretDocumentStartIntent',
        'MoveCaretDownIntent',
        'MoveCaretLeftIntent',
        'MoveCaretLineEndIntent',
        'MoveCaretLineStartIntent',
        'MoveCaretRightIntent',
        'MoveCaretUpIntent',
        'MoveSelectionDownIntent',
        'MoveSelectionFirstIntent',
        'MoveSelectionLastIntent',
        'MoveSelectionPageDownIntent',
        'MoveSelectionPageUpIntent',
        'MoveSelectionUpIntent',
        'NextFocusIntent',
        'PreviousFocusIntent',
        'ScrollDownIntent',
        'ScrollLeftIntent',
        'ScrollPageDownIntent',
        'ScrollPageUpIntent',
        'ScrollRightIntent',
        'ScrollToEndIntent',
        'ScrollToStartIntent',
        'ScrollUpIntent',
        'SubmitTextIntent',
      },
      'src/widgets/list_view.dart': {'ListView', 'ListViewItemBuilder'},
      'src/widgets/padding.dart': {'Padding'},
      'src/widgets/pointer_listener.dart': {'PointerListener'},
      'src/widgets/progress_bar.dart': {'ProgressBar'},
      'src/widgets/rich_text.dart': {'RichText'},
      'src/widgets/row_column.dart': {
        'Column',
        'CrossAxisAlignment',
        'Flex',
        'MainAxisAlignment',
        'MainAxisSize',
        'Row',
      },
      'src/widgets/scroll_box.dart': {'ScrollBox', 'ScrollController'},
      'src/widgets/select.dart': {
        'Select',
        'SelectChanged',
        'SelectConfirmed',
        'SelectOption',
      },
      'src/widgets/shortcuts.dart': {
        'CharacterActivator',
        'ShortcutActivator',
        'Shortcuts',
        'SingleActivator',
      },
      'src/widgets/sized_box.dart': {'SizedBox'},
      'src/widgets/spinner.dart': {'Spinner', 'SpinnerFrames'},
      'src/widgets/switch.dart': {'Switch'},
      'src/widgets/text.dart': {'Text'},
      'src/widgets/text_area.dart': {'TextArea'},
      'src/widgets/text_layout.dart': {
        'TextLayout',
        'TextLayoutLine',
        'TextLayoutRun',
        'TextOverflow',
      },
      'src/widgets/text_input_connection.dart': {'TextInputConnection'},
      'src/widgets/text_span.dart': {'InlineSpan', 'TextSpan'},
      'src/widgets/text_style.dart': {
        'FontStyle',
        'FontWeight',
        'TextDecoration',
        'TextEffect',
        'TextStyle',
        'TextStyles',
      },
      'src/widgets/theme.dart': {'Theme', 'ThemeData'},
      'src/widgets/viewport.dart': {'ViewportController'},
    };

    const forbiddenSymbols = <String>{
      'Buffer',
      'DirectBufferAccess',
      'DirectTextAccess',
      'FFIException',
      'OpenTuiBindings',
      'OpenTuiNativeLibrary',
      'Renderer',
      'RendererHandle',
      'TextBuffer',
      'TextAlignment',
      'TuiBinding',
      'PersistentUtf8Text',
      'PipelineOwner',
    };

    final paths = exports.map((export) => export.path).toSet();
    final allowedPaths = allowedSymbolsByPath.keys.toSet();
    final unexpectedPaths = paths.difference(allowedPaths);
    final missingPaths = allowedPaths.difference(paths);
    final exportsWithoutShow = exports
        .where((export) => !export.hasShow)
        .map((export) => export.path)
        .toList();
    final symbolMismatches = <String>[];

    for (final export in exports) {
      final expectedSymbols = allowedSymbolsByPath[export.path];
      if (expectedSymbols == null) {
        continue;
      }
      if (export.symbols.length != expectedSymbols.length ||
          !export.symbols.containsAll(expectedSymbols)) {
        symbolMismatches.add(
          '${export.path}: expected ${_sorted(expectedSymbols)}, '
          'found ${_sorted(export.symbols)}',
        );
      }
    }

    final exportedForbiddenSymbols = exports
        .expand((export) => export.symbols)
        .where(forbiddenSymbols.contains)
        .toList();

    expect(
      unexpectedPaths,
      isEmpty,
      reason: 'New public exports must be intentionally added to the API lock.',
    );
    expect(
      missingPaths,
      isEmpty,
      reason: 'The public API lock should track the current curated barrel.',
    );
    expect(
      exportsWithoutShow,
      isEmpty,
      reason:
          'Every public export must use show to prevent unintended exposure.',
    );
    expect(
      symbolMismatches,
      isEmpty,
      reason: 'Public exports must match the exact symbol allowlist.',
    );
    expect(
      exportedForbiddenSymbols,
      isEmpty,
      reason:
          'FFI and native plumbing belong in noir_ffi.dart / '
          'noir_low_level.dart.',
    );
    expect(
      source,
      isNot(contains('src/ffi/')),
      reason: 'Generated bindings and FFI wrappers are not public API.',
    );
    expect(
      paths.where(
        (path) =>
            path.contains('noir_low_level.dart') ||
            path.contains('noir_ffi.dart'),
      ),
      isEmpty,
      reason:
          'The public barrel must not re-export the advanced or FFI barrels.',
    );
    expect(
      exports.expand((export) => export.symbols).toSet(),
      hasLength(186),
      reason: 'The high-level surface is locked at exactly 186 symbols.',
    );
  });

  test('capability helpers expose only the current high-level surface', () {
    final source = File('lib/src/core/capabilities.dart').readAsStringSync();

    expect(source, contains('detectCapabilities()'));
    expect(source, isNot(contains('getTerminalCapabilities()')));
    expect(source, isNot(contains('class CapabilityTester')));
  });
}

List<_ExportDirective> _parseExports(String source) {
  final exportPattern = RegExp(
    r"export\s+'([^']+)'\s*(?:show\s*([^;]+))?;",
    multiLine: true,
    dotAll: true,
  );
  return exportPattern
      .allMatches(source)
      .map((match) {
        final symbols = (match.group(2) ?? '')
            .split(',')
            .map((symbol) => symbol.trim())
            .where((symbol) => symbol.isNotEmpty)
            .toSet();
        return _ExportDirective(
          path: match.group(1)!,
          symbols: symbols,
          hasShow: match.group(2) != null,
        );
      })
      .toList(growable: false);
}

List<String> _sorted(Iterable<String> values) =>
    values.toList(growable: false)..sort();

class _ExportDirective {
  const _ExportDirective({
    required this.path,
    required this.symbols,
    required this.hasShow,
  });

  final String path;
  final Set<String> symbols;
  final bool hasShow;
}
