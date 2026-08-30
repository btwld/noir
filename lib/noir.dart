/// Noir — high-level widget and application API.
///
/// This barrel exposes the public surface needed to build TUI apps with the
/// Flutter-like widget framework. For renderer/buffer primitives, custom
/// render-object adapters, or advanced hosting and coordination through
/// `TuiBinding`, `RenderObject`, and `BuildOwner`, see
/// `package:noir/noir_low_level.dart`. Concrete Element types remain
/// framework-owned and are not part of either barrel.
///
/// For raw FFI (ABI-unstable), see `package:noir/noir_ffi.dart`.
///
/// ```dart
/// import 'package:noir/noir.dart';
/// ```
library;

// Animation
export 'src/animation/animation.dart'
    show Animation, AnimationStatus, AnimationStatusListener;
export 'src/animation/animation_controller.dart' show AnimationController;
export 'src/animation/ticker.dart'
    show
        SingleTickerProviderStateMixin,
        Ticker,
        TickerCallback,
        TickerProvider,
        TickerProviderStateMixin;
// App entrypoint
export 'src/app/app.dart' show TuiApp, runTuiApp;
// Opt-in hot-reload service extension for development builds.
export 'src/app/hot_reload.dart' show registerHotReloadExtension;
// Color
export 'src/core/color.dart' show Color;
// Cursor style enum (the controller itself is in noir_low_level)
export 'src/core/cursor.dart' show CursorStyle;
// Grapheme/cell metrics
export 'src/core/grapheme_metrics.dart'
    show
        cellToGraphemeIndex,
        graphemeIndexToCell,
        sliceByCells,
        terminalCellWidth,
        terminalStringWidth;
// Input event types (Renderer extensions live in noir_low_level)
export 'src/core/input.dart'
    show
        KeyEvent,
        KeyEventHandler,
        KeyEventResult,
        KeyModifiers,
        KittyFlags,
        LogicalKeyboardKey,
        MouseButton,
        MouseEvent,
        MouseEventHandler,
        MouseEventType,
        MouseScroll,
        MouseScrollDirection,
        PasteEvent,
        PasteEventHandler;
export 'src/core/terminal_image.dart'
    show
        ImageColorStatus,
        ImageFit,
        ImageFormat,
        ImageProtocol,
        TerminalImage,
        TerminalImageErrorCode,
        TerminalImageException,
        TerminalImageInfo;
// Terminal semantic values shared with the FFI tier.
export 'src/core/terminal_style.dart'
    show Attr, BorderSides, BoxOptions, TextAlign;
// Foundation
export 'src/foundation/change_notifier.dart' show ChangeNotifier;
export 'src/foundation/disposable.dart' show Disposable;
export 'src/foundation/listenable.dart'
    show Listenable, ValueListenable, VoidCallback;
export 'src/foundation/selected_text.dart' show SelectedText;
export 'src/foundation/text_editing_controller.dart' show TextEditingController;
export 'src/foundation/text_editing_value.dart' show TextEditingValue;
export 'src/foundation/text_index_map.dart' show TextIndexMap;
export 'src/foundation/text_range.dart' show TextRange;
export 'src/foundation/text_selection.dart' show TextAffinity, TextSelection;
export 'src/foundation/value_notifier.dart' show ValueNotifier;
// Widget framework: user-facing surface only.
export 'src/framework/build_context.dart' show BuildContext;
// Focus types users see
export 'src/framework/focus_manager.dart'
    show FocusNode, FocusOnKeyEvent, FocusScopeNode, FocusTraversalPolicy;
// Keys
export 'src/framework/key.dart'
    show GlobalKey, Key, LocalKey, ObjectKey, UniqueKey, ValueKey;
// Widget framework
export 'src/framework/widget.dart'
    show
        InheritedWidget,
        ProxyWidget,
        State,
        StatefulWidget,
        StatelessWidget,
        Widget;
// Painting
export 'src/painting/box_border.dart' show Border, BorderStyle, BoxBorder;
export 'src/painting/box_decoration.dart' show BoxDecoration;
export 'src/painting/decoration.dart' show Decoration;
export 'src/painting/tui_canvas.dart' show TuiCanvas;
// Geometry (single source of truth for geometric types)
export 'src/render/geometry.dart'
    show
        Alignment,
        Axis,
        BoxConstraints,
        BoxShape,
        Constraints,
        EdgeInsets,
        Offset,
        Rect,
        Size;
// Text-rendering helpers users see
export 'src/rendering/stack.dart' show StackFit;
export 'src/rendering/text_highlight.dart' show TextHighlight;
export 'src/rendering/wrap.dart' show WrapAlignment, WrapCrossAlignment;
// Widgets
export 'src/widgets/actions.dart'
    show Action, ActionCallback, Actions, CallbackAction;
export 'src/widgets/align.dart' show Align;
export 'src/widgets/ascii_font.dart' show AsciiFont, AsciiFontFamily;
export 'src/widgets/autocomplete.dart'
    show Autocomplete, AutocompleteOptionBuilder, AutocompleteStatus;
export 'src/widgets/badge.dart' show Badge, BadgeVariant;
export 'src/widgets/button.dart' show Button;
export 'src/widgets/checkbox.dart' show Checkbox;
export 'src/widgets/code_view.dart'
    show
        CodeHighlighter,
        CodeView,
        HighlightErrorCallback,
        PlainTextCodeHighlighter,
        StyledTextRange;
export 'src/widgets/constrained_box.dart' show ConstrainedBox;
export 'src/widgets/container.dart' show Container;
export 'src/widgets/data_table.dart'
    show DataColumn, DataTable, DataTableCellBuilder, DataTableSort;
export 'src/widgets/decorated_box.dart' show DecoratedBox, DecorationPosition;
export 'src/widgets/diff_view.dart'
    show
        DiffDocument,
        DiffFile,
        DiffHunk,
        DiffHunkCallback,
        DiffLine,
        DiffLineCallback,
        DiffLineKind,
        DiffRowBuilder,
        DiffView,
        DiffViewController,
        DiffViewMode,
        UnifiedDiffParser;
export 'src/widgets/divider.dart' show Divider;
export 'src/widgets/document_view.dart' show SelectionCopyCallback;
export 'src/widgets/flexible.dart' show Expanded, FlexFit, Flexible;
export 'src/widgets/focus.dart' show Focus, FocusScope;
export 'src/widgets/icons.dart' show Icons;
export 'src/widgets/image.dart'
    show
        Image,
        ImageErrorBuilder,
        ImageLoadErrorCode,
        ImageLoadException,
        ImageLoadingBuilder;
export 'src/widgets/input.dart' show TextInput, ValueChanged;
export 'src/widgets/intents.dart'
    show
        ActivateIntent,
        DeleteBackwardIntent,
        DeleteForwardIntent,
        DismissIntent,
        InsertTabIntent,
        InsertTextIntent,
        Intent,
        MoveCaretDocumentEndIntent,
        MoveCaretDocumentStartIntent,
        MoveCaretDownIntent,
        MoveCaretLeftIntent,
        MoveCaretLineEndIntent,
        MoveCaretLineStartIntent,
        MoveCaretRightIntent,
        MoveCaretUpIntent,
        MoveSelectionDownIntent,
        MoveSelectionFirstIntent,
        MoveSelectionLastIntent,
        MoveSelectionPageDownIntent,
        MoveSelectionPageUpIntent,
        MoveSelectionUpIntent,
        NextFocusIntent,
        PreviousFocusIntent,
        ScrollDownIntent,
        ScrollLeftIntent,
        ScrollPageDownIntent,
        ScrollPageUpIntent,
        ScrollRightIntent,
        ScrollToEndIntent,
        ScrollToStartIntent,
        ScrollUpIntent,
        SubmitTextIntent;
export 'src/widgets/list_view.dart' show ListView, ListViewItemBuilder;
export 'src/widgets/markdown_view.dart'
    show MarkdownBlockRenderer, MarkdownThemeData, MarkdownView;
export 'src/widgets/menu_anchor.dart'
    show MenuAnchor, MenuAnchorChildBuilder, MenuController;
export 'src/widgets/modal.dart' show Modal, ModalController;
export 'src/widgets/overlay.dart'
    show OverlayPortal, OverlayPortalController, WidgetBuilder;
export 'src/widgets/padding.dart' show Padding;
export 'src/widgets/panel.dart' show Panel;
export 'src/widgets/pointer_listener.dart' show PointerListener;
export 'src/widgets/progress_bar.dart' show ProgressBar;
export 'src/widgets/rich_text.dart' show RichText;
export 'src/widgets/row_column.dart'
    show Column, CrossAxisAlignment, Flex, MainAxisAlignment, MainAxisSize, Row;
export 'src/widgets/scroll_box.dart' show ScrollBox, ScrollController;
export 'src/widgets/select.dart'
    show Select, SelectChanged, SelectConfirmed, SelectOption;
export 'src/widgets/shortcuts.dart'
    show CharacterActivator, ShortcutActivator, Shortcuts, SingleActivator;
export 'src/widgets/sized_box.dart' show SizedBox;
export 'src/widgets/slider.dart' show Slider;
export 'src/widgets/spinner.dart' show Spinner, SpinnerFrames;
export 'src/widgets/stack.dart' show Positioned, Stack;
export 'src/widgets/switch.dart' show Switch;
export 'src/widgets/tab_select.dart' show TabSelect;
export 'src/widgets/text.dart' show Text;
export 'src/widgets/text_area.dart' show TextArea;
export 'src/widgets/text_input_connection.dart' show TextInputConnection;
export 'src/widgets/text_layout.dart'
    show TextLayout, TextLayoutLine, TextLayoutRun, TextOverflow;
export 'src/widgets/text_span.dart' show InlineSpan, TextSpan;
export 'src/widgets/text_style.dart'
    show
        FontStyle,
        FontWeight,
        TextDecoration,
        TextEffect,
        TextStyle,
        TextStyles;
export 'src/widgets/text_table.dart'
    show
        TextTable,
        TextTableColumnFitter,
        TextTableColumnWidthMode,
        TextTableWrapMode;
export 'src/widgets/theme.dart' show Theme, ThemeData;
export 'src/widgets/tree_view.dart'
    show TreeNode, TreeView, TreeViewController, TreeViewItemBuilder;
export 'src/widgets/viewport.dart' show ViewportController;
export 'src/widgets/wrap.dart' show Wrap;
