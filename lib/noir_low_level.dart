/// Noir — advanced/internal framework API.
///
/// Use this barrel when you need renderer/buffer primitives, supported custom
/// render-widget and render-object protocols, or advanced lifecycle owners.
/// Concrete Element types remain framework-owned. This API is advanced — most
/// apps should not need it; prefer
/// `package:noir/noir.dart`.
///
/// For raw FFI (ABI-unstable until the native library stabilizes), see
/// `package:noir/noir_ffi.dart`.
library;

// Scheduler and advanced application hosting.
export 'src/animation/ticker.dart' show TickerScheduler;
export 'src/app/tui_binding.dart' show TuiBinding;
// Renderer and buffer primitives.
export 'src/core/buffer.dart' show Buffer, DirectBufferAccess;
export 'src/core/capabilities.dart' show CapabilitiesDetection;
// Cursor management (controller + extension on Renderer)
export 'src/core/cursor.dart' show CursorController, CursorManagement;
// Input extensions on Renderer
export 'src/core/input.dart'
    show
        InputManager,
        InputPriority,
        InputSubscription,
        KeyboardSupport,
        MouseSupport;
export 'src/core/renderer.dart' show Renderer;
// Advanced widget adapters, lifecycle owners, focus, and diagnostics.
export 'src/framework/diagnostics.dart'
    show WidgetInspectorService, describeIdentity;
export 'src/framework/element.dart' show MultiChildRenderObjectWidget;
export 'src/framework/focus_manager.dart' show FocusManager;
export 'src/framework/owner.dart' show BuildOwner, FrameCallback;
export 'src/framework/widget.dart'
    show RenderObjectWidget, SingleChildRenderObjectWidget;
// Geometry shared with the high-level widget surface.
export 'src/render/geometry.dart' show Axis;
// Render-object base classes and concrete render objects
export 'src/rendering/box.dart' show RenderBox;
export 'src/rendering/constrained_box.dart' show RenderConstrainedBox;
export 'src/rendering/decorated_box.dart' show RenderDecoratedBox;
export 'src/rendering/flex.dart' show RenderFlex;
export 'src/rendering/object.dart'
    show
        HitTestEntry,
        HitTestResult,
        HitTestTarget,
        PaintingContext,
        RenderObject,
        RenderObjectWithSingleChild;
export 'src/rendering/padding.dart' show RenderPadding;
export 'src/rendering/paragraph.dart' show RenderParagraph;
export 'src/rendering/positioned_box.dart' show RenderPositionedBox;
export 'src/rendering/proxy_box.dart' show RenderProxyBox;
// Render objects owned by widget files (re-exported as a convenience).
export 'src/widgets/scroll_box.dart' show RenderScrollBox;
export 'src/widgets/text_area.dart' show RenderTextArea;
export 'src/widgets/text_layout.dart' show TextLayoutEngine;
