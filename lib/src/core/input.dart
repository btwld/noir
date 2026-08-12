// ignore_for_file: prefer_constructors_over_static_methods, use_setters_to_change_properties
import 'dart:collection';

import 'package:meta/meta.dart';

import '../foundation/listenable.dart';
import '../render/geometry.dart';
import 'renderer.dart';

/// Kinds of mouse interaction reported by the terminal.
enum MouseEventType {
  /// A mouse button was pressed.
  down,

  /// A mouse button was released.
  up,

  /// The pointer moved.
  move,

  /// The scroll wheel was rotated.
  scroll,
}

/// Mouse buttons distinguished by the terminal.
enum MouseButton {
  /// The left mouse button.
  left,

  /// The middle mouse button.
  middle,

  /// The right mouse button.
  right,
}

/// Direction reported by a terminal wheel event.
enum MouseScrollDirection {
  /// Scroll toward the top.
  up,

  /// Scroll toward the bottom.
  down,

  /// Scroll toward the left.
  left,

  /// Scroll toward the right.
  right,
}

/// Immutable wheel direction and positive tick magnitude.
@immutable
final class MouseScroll {
  /// Creates a directed wheel payload.
  MouseScroll({required this.direction, this.magnitude = 1}) {
    if (magnitude <= 0) {
      throw RangeError.range(magnitude, 1, null, 'magnitude');
    }
  }

  /// Raw direction reported by the terminal.
  final MouseScrollDirection direction;

  /// Positive number of wheel ticks represented by this event.
  final int magnitude;
}

/// Keyboard modifier bitmask constants for use with [KeyEvent.modifiers].
class KeyModifiers {
  /// Shift modifier bit.
  static const int shift = 1 << 0;

  /// Alt modifier bit.
  static const int alt = 1 << 1;

  /// Control modifier bit.
  static const int ctrl = 1 << 2;

  /// Super (Windows/Command) modifier bit.
  static const int super_ = 1 << 3;

  /// Hyper modifier bit.
  static const int hyper = 1 << 4;

  /// Meta modifier bit.
  static const int meta = 1 << 5;

  /// Caps Lock active bit.
  static const int capsLock = 1 << 6;

  /// Num Lock active bit.
  static const int numLock = 1 << 7;
}

/// Logical keyboard key identity independent of the raw terminal sequence.
///
/// Named keys use stable constants. Printable input is represented by
/// [KeyEvent.character] with a [LogicalKeyboardKey.forCharacter] identity so
/// widgets can distinguish semantic controls from inserted text.
@immutable
final class LogicalKeyboardKey {
  /// Stores [keyId] and [keyLabel] for a logical key identity.
  const LogicalKeyboardKey._(this.keyId, this.keyLabel);

  /// Stable key identifier.
  final int keyId;

  /// Human-readable key label for diagnostics.
  final String keyLabel;

  /// Unknown/unmapped key.
  static const LogicalKeyboardKey unknown = LogicalKeyboardKey._(0, 'Unknown');

  /// Space key.
  static const LogicalKeyboardKey space = LogicalKeyboardKey._(0x20, 'Space');

  /// Escape key.
  static const LogicalKeyboardKey escape = LogicalKeyboardKey._(0x1b, 'Escape');

  /// Enter/return key.
  static const LogicalKeyboardKey enter = LogicalKeyboardKey._(0x0d, 'Enter');

  /// Tab key.
  static const LogicalKeyboardKey tab = LogicalKeyboardKey._(0x09, 'Tab');

  /// Backspace key.
  static const LogicalKeyboardKey backspace = LogicalKeyboardKey._(
    0x08,
    'Backspace',
  );

  /// Delete key.
  static const LogicalKeyboardKey delete = LogicalKeyboardKey._(0x7f, 'Delete');

  /// Arrow-up key.
  static const LogicalKeyboardKey arrowUp = LogicalKeyboardKey._(
    0x1001,
    'ArrowUp',
  );

  /// Arrow-down key.
  static const LogicalKeyboardKey arrowDown = LogicalKeyboardKey._(
    0x1002,
    'ArrowDown',
  );

  /// Arrow-left key.
  static const LogicalKeyboardKey arrowLeft = LogicalKeyboardKey._(
    0x1003,
    'ArrowLeft',
  );

  /// Arrow-right key.
  static const LogicalKeyboardKey arrowRight = LogicalKeyboardKey._(
    0x1004,
    'ArrowRight',
  );

  /// Home key.
  static const LogicalKeyboardKey home = LogicalKeyboardKey._(0x1005, 'Home');

  /// End key.
  static const LogicalKeyboardKey end = LogicalKeyboardKey._(0x1006, 'End');

  /// Page-up key.
  static const LogicalKeyboardKey pageUp = LogicalKeyboardKey._(
    0x1007,
    'PageUp',
  );

  /// Page-down key.
  static const LogicalKeyboardKey pageDown = LogicalKeyboardKey._(
    0x1008,
    'PageDown',
  );

  /// Letter A key.
  static const LogicalKeyboardKey keyA = LogicalKeyboardKey._(0x61, 'KeyA');

  /// Letter B key.
  static const LogicalKeyboardKey keyB = LogicalKeyboardKey._(0x62, 'KeyB');

  /// Letter C key.
  static const LogicalKeyboardKey keyC = LogicalKeyboardKey._(0x63, 'KeyC');

  /// Letter D key.
  static const LogicalKeyboardKey keyD = LogicalKeyboardKey._(0x64, 'KeyD');

  /// Letter E key.
  static const LogicalKeyboardKey keyE = LogicalKeyboardKey._(0x65, 'KeyE');

  /// Letter F key.
  static const LogicalKeyboardKey keyF = LogicalKeyboardKey._(0x66, 'KeyF');

  /// Letter G key.
  static const LogicalKeyboardKey keyG = LogicalKeyboardKey._(0x67, 'KeyG');

  /// Letter H key.
  static const LogicalKeyboardKey keyH = LogicalKeyboardKey._(0x68, 'KeyH');

  /// Letter I key.
  static const LogicalKeyboardKey keyI = LogicalKeyboardKey._(0x69, 'KeyI');

  /// Letter J key.
  static const LogicalKeyboardKey keyJ = LogicalKeyboardKey._(0x6a, 'KeyJ');

  /// Letter K key.
  static const LogicalKeyboardKey keyK = LogicalKeyboardKey._(0x6b, 'KeyK');

  /// Letter L key.
  static const LogicalKeyboardKey keyL = LogicalKeyboardKey._(0x6c, 'KeyL');

  /// Letter M key.
  static const LogicalKeyboardKey keyM = LogicalKeyboardKey._(0x6d, 'KeyM');

  /// Letter N key.
  static const LogicalKeyboardKey keyN = LogicalKeyboardKey._(0x6e, 'KeyN');

  /// Letter O key.
  static const LogicalKeyboardKey keyO = LogicalKeyboardKey._(0x6f, 'KeyO');

  /// Letter P key.
  static const LogicalKeyboardKey keyP = LogicalKeyboardKey._(0x70, 'KeyP');

  /// Letter Q key.
  static const LogicalKeyboardKey keyQ = LogicalKeyboardKey._(0x71, 'KeyQ');

  /// Letter R key.
  static const LogicalKeyboardKey keyR = LogicalKeyboardKey._(0x72, 'KeyR');

  /// Letter S key.
  static const LogicalKeyboardKey keyS = LogicalKeyboardKey._(0x73, 'KeyS');

  /// Letter T key.
  static const LogicalKeyboardKey keyT = LogicalKeyboardKey._(0x74, 'KeyT');

  /// Letter U key.
  static const LogicalKeyboardKey keyU = LogicalKeyboardKey._(0x75, 'KeyU');

  /// Letter V key.
  static const LogicalKeyboardKey keyV = LogicalKeyboardKey._(0x76, 'KeyV');

  /// Letter W key.
  static const LogicalKeyboardKey keyW = LogicalKeyboardKey._(0x77, 'KeyW');

  /// Letter X key.
  static const LogicalKeyboardKey keyX = LogicalKeyboardKey._(0x78, 'KeyX');

  /// Letter Y key.
  static const LogicalKeyboardKey keyY = LogicalKeyboardKey._(0x79, 'KeyY');

  /// Letter Z key.
  static const LogicalKeyboardKey keyZ = LogicalKeyboardKey._(0x7a, 'KeyZ');

  /// Digit 0 key.
  static const LogicalKeyboardKey digit0 = LogicalKeyboardKey._(0x30, 'Digit0');

  /// Digit 1 key.
  static const LogicalKeyboardKey digit1 = LogicalKeyboardKey._(0x31, 'Digit1');

  /// Digit 2 key.
  static const LogicalKeyboardKey digit2 = LogicalKeyboardKey._(0x32, 'Digit2');

  /// Digit 3 key.
  static const LogicalKeyboardKey digit3 = LogicalKeyboardKey._(0x33, 'Digit3');

  /// Digit 4 key.
  static const LogicalKeyboardKey digit4 = LogicalKeyboardKey._(0x34, 'Digit4');

  /// Digit 5 key.
  static const LogicalKeyboardKey digit5 = LogicalKeyboardKey._(0x35, 'Digit5');

  /// Digit 6 key.
  static const LogicalKeyboardKey digit6 = LogicalKeyboardKey._(0x36, 'Digit6');

  /// Digit 7 key.
  static const LogicalKeyboardKey digit7 = LogicalKeyboardKey._(0x37, 'Digit7');

  /// Digit 8 key.
  static const LogicalKeyboardKey digit8 = LogicalKeyboardKey._(0x38, 'Digit8');

  /// Digit 9 key.
  static const LogicalKeyboardKey digit9 = LogicalKeyboardKey._(0x39, 'Digit9');

  /// F1 key.
  static const LogicalKeyboardKey f1 = LogicalKeyboardKey._(0x1101, 'F1');

  /// F2 key.
  static const LogicalKeyboardKey f2 = LogicalKeyboardKey._(0x1102, 'F2');

  /// F3 key.
  static const LogicalKeyboardKey f3 = LogicalKeyboardKey._(0x1103, 'F3');

  /// F4 key.
  static const LogicalKeyboardKey f4 = LogicalKeyboardKey._(0x1104, 'F4');

  /// F5 key.
  static const LogicalKeyboardKey f5 = LogicalKeyboardKey._(0x1105, 'F5');

  /// F6 key.
  static const LogicalKeyboardKey f6 = LogicalKeyboardKey._(0x1106, 'F6');

  /// F7 key.
  static const LogicalKeyboardKey f7 = LogicalKeyboardKey._(0x1107, 'F7');

  /// F8 key.
  static const LogicalKeyboardKey f8 = LogicalKeyboardKey._(0x1108, 'F8');

  /// F9 key.
  static const LogicalKeyboardKey f9 = LogicalKeyboardKey._(0x1109, 'F9');

  /// F10 key.
  static const LogicalKeyboardKey f10 = LogicalKeyboardKey._(0x110a, 'F10');

  /// F11 key.
  static const LogicalKeyboardKey f11 = LogicalKeyboardKey._(0x110b, 'F11');

  /// F12 key.
  static const LogicalKeyboardKey f12 = LogicalKeyboardKey._(0x110c, 'F12');

  /// Shift modifier pseudo-key.
  static const LogicalKeyboardKey shift = LogicalKeyboardKey._(0x1201, 'Shift');

  /// Control modifier pseudo-key.
  static const LogicalKeyboardKey control = LogicalKeyboardKey._(
    0x1202,
    'Control',
  );

  /// Alt modifier pseudo-key.
  static const LogicalKeyboardKey alt = LogicalKeyboardKey._(0x1203, 'Alt');

  /// Meta modifier pseudo-key.
  static const LogicalKeyboardKey meta = LogicalKeyboardKey._(0x1204, 'Meta');

  /// Returns the logical key for an ASCII letter.
  static LogicalKeyboardKey forLetter(String lowerAsciiLetter) {
    if (lowerAsciiLetter.length != 1) return forCharacter(lowerAsciiLetter);
    return switch (lowerAsciiLetter.toLowerCase()) {
      'a' => keyA,
      'b' => keyB,
      'c' => keyC,
      'd' => keyD,
      'e' => keyE,
      'f' => keyF,
      'g' => keyG,
      'h' => keyH,
      'i' => keyI,
      'j' => keyJ,
      'k' => keyK,
      'l' => keyL,
      'm' => keyM,
      'n' => keyN,
      'o' => keyO,
      'p' => keyP,
      'q' => keyQ,
      'r' => keyR,
      's' => keyS,
      't' => keyT,
      'u' => keyU,
      'v' => keyV,
      'w' => keyW,
      'x' => keyX,
      'y' => keyY,
      'z' => keyZ,
      _ => forCharacter(lowerAsciiLetter),
    };
  }

  /// Returns the logical key for an ASCII digit.
  static LogicalKeyboardKey forDigit(String digit) {
    if (digit.length != 1) return forCharacter(digit);
    return switch (digit) {
      '0' => digit0,
      '1' => digit1,
      '2' => digit2,
      '3' => digit3,
      '4' => digit4,
      '5' => digit5,
      '6' => digit6,
      '7' => digit7,
      '8' => digit8,
      '9' => digit9,
      _ => forCharacter(digit),
    };
  }

  /// Returns the logical key for printable text.
  static LogicalKeyboardKey forCharacter(String character) {
    if (character == ' ') return space;
    if (character.length == 1) {
      final code = character.codeUnitAt(0);
      if (code >= 0x30 && code <= 0x39) return forDigit(character);
      if (code >= 0x41 && code <= 0x5a) {
        return forLetter(character.toLowerCase());
      }
      if (code >= 0x61 && code <= 0x7a) return forLetter(character);
    }
    return LogicalKeyboardKey._(
      0x200000000 + _stableStringHash(character),
      character,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LogicalKeyboardKey && other.keyId == keyId;

  @override
  int get hashCode => keyId;

  @override
  String toString() => 'LogicalKeyboardKey($keyLabel)';
}

/// Result returned by key-event handlers in the focus/shortcut pipeline.
enum KeyEventResult {
  /// The event was handled and should not continue.
  handled,

  /// The event was ignored and may continue to another handler.
  ignored,

  /// Stop the current handler chain but do not mark the event handled.
  skipRemainingHandlers,
}

int _stableStringHash(String value) {
  var hash = 0;
  for (final codeUnit in value.codeUnits) {
    hash = 0x1fffffff & (hash * 31 + codeUnit);
  }
  return hash;
}

/// Kitty keyboard protocol enhancement flags for use with [KeyboardSupport.enableKittyKeyboard].
class KittyFlags {
  /// Disambiguate escape codes from named keys.
  static const int disambiguateEscapeCodes = 1 << 0;

  /// Report key press, repeat, and release event types.
  static const int reportEventTypes = 1 << 1;

  /// Report the shifted/base codepoints alongside the key.
  static const int reportAlternateKeys = 1 << 2;

  /// Report all keys as escape codes rather than plain text.
  static const int reportAllKeysAsEscapeCodes = 1 << 3;

  /// Report the text associated with each key event.
  static const int reportAssociatedText = 1 << 4;
}

/// Mouse input methods added to [Renderer].
extension MouseSupport on Renderer {
  /// Enables mouse reporting; pass [enableMovement] to also track pointer moves.
  void enableMouse({bool enableMovement = false}) {
    bindings.enableMouse(handle, enableMovement);
  }

  /// Disables mouse reporting.
  void disableMouse() {
    bindings.disableMouse(handle);
  }
}

/// Kitty keyboard protocol methods added to [Renderer].
extension KeyboardSupport on Renderer {
  /// Enables the Kitty keyboard protocol with the given [flags].
  void enableKittyKeyboard({int flags = KittyFlags.disambiguateEscapeCodes}) {
    bindings.enableKittyKeyboard(handle, flags);
  }

  /// Disables the Kitty keyboard protocol and reverts to standard terminal key reporting.
  void disableKittyKeyboard() {
    bindings.disableKittyKeyboard(handle);
  }
}

/// Mixin shared by all input events to allow a handler to stop further
/// dispatch by calling [consume]. Once an event is consumed, listeners at
/// lower priorities (and any remaining listeners at the current priority)
/// will not be invoked.
mixin _Consumable {
  bool _consumed = false;

  /// Whether [consume] has been called on this event.
  bool get isConsumed => _consumed;

  /// Stop further dispatch of this event.
  void consume() {
    _consumed = true;
  }
}

/// Mouse input event delivered to registered [MouseEventHandler] listeners.
class MouseEvent with _Consumable {
  /// Creates a mouse event.
  ///
  /// Scroll events require [scroll]. Every other event type rejects scroll
  /// metadata so stale wheel state cannot enter dispatch.
  MouseEvent({
    required this.type,
    required this.button,
    required this.x,
    required this.y,
    this.modifiers = 0,
    this.scroll,
    Offset? localPosition,
  }) : localPosition = localPosition ?? Offset(x, y) {
    if (type == MouseEventType.scroll && scroll == null) {
      throw ArgumentError.value(
        scroll,
        'scroll',
        'must be provided for a scroll event',
      );
    }
    if (type != MouseEventType.scroll && scroll != null) {
      throw ArgumentError.value(
        scroll,
        'scroll',
        'must be null for a non-scroll event',
      );
    }
  }

  /// Kind of mouse interaction (press, release, move, or scroll).
  final MouseEventType type;

  /// Mouse button involved in the event.
  final MouseButton button;

  /// Absolute terminal column of the event.
  final int x;

  /// Absolute terminal row of the event.
  final int y;

  /// Active keyboard modifier bits (see [KeyModifiers]).
  final int modifiers;

  /// Directed wheel payload for [MouseEventType.scroll], otherwise null.
  final MouseScroll? scroll;

  /// Position in the local coordinate space of the current hit-test target.
  ///
  /// Parser output and manually constructed events default this to the
  /// absolute terminal position. The framework pointer router creates
  /// localized copies for each hit-test target while preserving [x] and [y].
  final Offset localPosition;
}

/// Keyboard input event delivered to registered [KeyEventHandler] listeners.
class KeyEvent with _Consumable {
  /// Records key data, defaulting to a non-repeat press with no modifiers.
  KeyEvent({
    required this.logicalKey,
    required this.keyCode,
    this.character,
    this.modifiers = 0,
    this.isPress = true,
    this.isRepeat = false,
  });

  /// Logical key identity.
  final LogicalKeyboardKey logicalKey;

  /// Raw key code reported by the terminal, or 0 when unavailable.
  final int keyCode;

  /// Printable character for text input. Null for non-printable keys.
  final String? character;

  /// Active keyboard modifier bits (see [KeyModifiers]).
  final int modifiers;

  /// Whether this is a key press (true) or release (false).
  final bool isPress;

  /// Whether this event is an auto-repeat of a held key.
  final bool isRepeat;

  /// Whether Shift is pressed.
  bool get isShiftPressed => modifiers & KeyModifiers.shift != 0;

  /// Whether Control is pressed.
  bool get isControlPressed => modifiers & KeyModifiers.ctrl != 0;

  /// Whether Alt is pressed.
  bool get isAltPressed => modifiers & KeyModifiers.alt != 0;

  /// Whether Meta is pressed.
  bool get isMetaPressed => modifiers & KeyModifiers.meta != 0;
}

/// A bracketed-paste block delivered as a single event instead of one
/// synthetic key event per character. Subscribe via
/// [InputManager.onPaste].
class PasteEvent with _Consumable {
  /// Delivers [text] as one consumable bracketed-paste event.
  PasteEvent(this.text);

  /// The pasted text content delivered as a single block.
  final String text;
}

/// Terminal capability response categories parsed from ANSI reports.
enum TerminalCapabilityKind {
  /// Primary device attributes (`CSI ? ... c`).
  primaryDeviceAttributes,

  /// Secondary device attributes (`CSI > ... c`).
  secondaryDeviceAttributes,

  /// Tertiary device attributes (`CSI = ... c`).
  tertiaryDeviceAttributes,

  /// DEC private-mode report (`CSI ? ... $ y`).
  privateModeReport,

  /// Cursor position report (`CSI row ; column R`).
  cursorPositionReport,

  /// Kitty keyboard protocol status (`CSI ? ... u`).
  kittyKeyboardStatus,

  /// Device control string (`ESC P ... ST`).
  deviceControlString,

  /// Operating system command (`ESC ] ... BEL/ST`).
  operatingSystemCommand,

  /// Application program command (`ESC _ ... ST`).
  applicationProgramCommand,

  /// Privacy message (`ESC ^ ... ST`).
  privacyMessage,
}

/// Terminal capability/query response captured from the input stream.
class TerminalCapabilityEvent with _Consumable {
  /// Preserves a response's kind, unframed payload, and raw ANSI sequence.
  TerminalCapabilityEvent({
    required this.kind,
    required this.payload,
    required this.raw,
  });

  /// Response category.
  final TerminalCapabilityKind kind;

  /// Response body without the ANSI opener/terminator.
  final String payload;

  /// Original ANSI sequence.
  final String raw;
}

/// Callback signature for mouse event listeners registered with [InputManager.onMouse].
typedef MouseEventHandler = void Function(MouseEvent event);

/// Callback signature for key event listeners registered with [InputManager.onKey].
typedef KeyEventHandler = void Function(KeyEvent event);

/// Callback signature for paste event listeners registered with [InputManager.onPaste].
typedef PasteEventHandler = void Function(PasteEvent event);

/// Event handler typedef for terminal capability responses.
typedef CapabilityResponseHandler =
    void Function(TerminalCapabilityEvent event);

/// Standard priority constants used by [InputManager].
///
/// Higher numbers run first. Callers may pass arbitrary integers — these
/// constants are the conventional anchor points so app shortcuts, focus
/// routing, and generic widget listeners stay in a predictable order.
class InputPriority {
  /// App-wide shortcuts (Ctrl-Q, F-keys, etc.) — runs first.
  static const int app = 100;

  /// Focused widget receives input next.
  static const int focus = 50;

  /// Fallback widget listeners.
  static const int widget = 0;
}

/// Handle returned from [InputManager.onKey], [InputManager.onMouse], and
/// [InputManager.onPaste]. Call [cancel] to remove the underlying
/// subscription; safe to call multiple times.
class InputSubscription {
  InputSubscription._(this._cancel);

  final void Function() _cancel;
  bool _cancelled = false;

  /// Remove this subscription. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}

/// Internal dispatch kernel for terminal input events.
///
/// Supports multiple subscribers per event type, dispatched in priority
/// order (highest first). Within a single priority bucket, handlers are
/// called in registration order. A handler that calls [event.consume]
/// stops further dispatch of that event.
final class InputDispatcher {
  // priority -> insertion-ordered list. SplayTreeMap keeps keys sorted so
  // we can walk priorities in either direction without re-sorting on each
  // dispatch. The lists preserve registration order within a bucket.
  final SplayTreeMap<int, List<KeyEventHandler>> _keyByPriority =
      SplayTreeMap<int, List<KeyEventHandler>>();
  final SplayTreeMap<int, List<MouseEventHandler>> _mouseByPriority =
      SplayTreeMap<int, List<MouseEventHandler>>();
  final SplayTreeMap<int, List<PasteEventHandler>> _pasteByPriority =
      SplayTreeMap<int, List<PasteEventHandler>>();
  final SplayTreeMap<int, List<CapabilityResponseHandler>>
  _capabilityByPriority = SplayTreeMap<int, List<CapabilityResponseHandler>>();
  VoidCallback? _afterEvent;

  /// Registers [handler] in [byPriority] and returns a handle that, when
  /// cancelled, removes the subscription (dropping empty priority buckets).
  InputSubscription _subscribe<H>(
    SplayTreeMap<int, List<H>> byPriority,
    H handler,
    int priority,
  ) {
    final list = byPriority.putIfAbsent(priority, () => <H>[]);
    list.add(handler);
    return InputSubscription._(() {
      list.remove(handler);
      if (list.isEmpty) {
        byPriority.remove(priority);
      }
    });
  }

  /// Subscribe to key events at the given [priority]. Returns a handle
  /// that, when cancelled, removes the subscription.
  InputSubscription onKey(
    KeyEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _subscribe(_keyByPriority, handler, priority);

  /// Subscribe to mouse events at the given [priority]. Returns a handle
  /// that, when cancelled, removes the subscription.
  InputSubscription onMouse(
    MouseEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _subscribe(_mouseByPriority, handler, priority);

  /// Subscribe to paste events at the given [priority]. Returns a handle
  /// that, when cancelled, removes the subscription.
  InputSubscription onPaste(
    PasteEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _subscribe(_pasteByPriority, handler, priority);

  /// Subscribe to terminal capability responses at the given [priority].
  /// Returns a handle that, when cancelled, removes the subscription.
  InputSubscription onCapabilityResponse(
    CapabilityResponseHandler handler, {
    int priority = InputPriority.widget,
  }) => _subscribe(_capabilityByPriority, handler, priority);

  /// Set callback invoked after any input is processed. Used by the app
  /// binding to schedule a frame after every dispatched event.
  void setEventDispatch(VoidCallback? callback) {
    _afterEvent = callback;
  }

  /// Dispatch [event] through [byPriority] high → low, stopping as soon as a
  /// handler consumes it. Schedules a frame via [_afterEvent] exactly once,
  /// unless [scheduleOnlyIfHandled] is set and no handler ran.
  void _dispatchEventBucket<E extends _Consumable>(
    SplayTreeMap<int, List<void Function(E)>> byPriority,
    E event, {
    bool scheduleOnlyIfHandled = false,
  }) {
    // Walk priorities high → low. Snapshot each bucket because subscribers
    // may add or cancel during dispatch.
    final priorities = byPriority.keys
        .toList(growable: false)
        .reversed
        .toList();
    var handled = false;
    for (final priority in priorities) {
      final bucket = byPriority[priority];
      if (bucket == null) continue;
      final snapshot = List<void Function(E)>.from(bucket);
      for (final handler in snapshot) {
        handled = true;
        handler(event);
        if (event.isConsumed) {
          _afterEvent?.call();
          return;
        }
      }
    }
    if (!scheduleOnlyIfHandled || handled) {
      _afterEvent?.call();
    }
  }

  /// Dispatch a key event to all subscribers in priority order
  /// (highest first). Stops as soon as a handler calls [event.consume].
  void dispatchKeyEvent(KeyEvent event) =>
      _dispatchEventBucket<KeyEvent>(_keyByPriority, event);

  /// Dispatch a mouse event to all subscribers in priority order
  /// (highest first). Stops as soon as a handler calls [event.consume].
  void dispatchMouseEvent(MouseEvent event) =>
      _dispatchEventBucket<MouseEvent>(_mouseByPriority, event);

  /// Dispatch a paste event to all subscribers in priority order
  /// (highest first). Stops as soon as a handler calls [event.consume].
  void dispatchPasteEvent(PasteEvent event) =>
      _dispatchEventBucket<PasteEvent>(_pasteByPriority, event);

  /// Dispatch a terminal capability response. Frame scheduling runs only
  /// when at least one capability listener handled the response.
  void dispatchCapabilityResponse(TerminalCapabilityEvent event) =>
      _dispatchEventBucket<TerminalCapabilityEvent>(
        _capabilityByPriority,
        event,
        scheduleOnlyIfHandled: true,
      );
}

/// Input manager for handling terminal input events.
///
/// Widgets and applications use this facade to register key, mouse, and
/// paste listeners, or to inject events in tests. Events are dispatched in
/// priority order and stop when a listener consumes them.
class InputManager {
  /// Initializes a facade backed by one priority-aware input dispatcher.
  InputManager() : _dispatcher = InputDispatcher();

  final InputDispatcher _dispatcher;

  /// Subscribe to key events at the given [priority].
  InputSubscription onKey(
    KeyEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _dispatcher.onKey(handler, priority: priority);

  /// Subscribe to mouse events at the given [priority].
  InputSubscription onMouse(
    MouseEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _dispatcher.onMouse(handler, priority: priority);

  /// Subscribe to paste events at the given [priority].
  InputSubscription onPaste(
    PasteEventHandler handler, {
    int priority = InputPriority.widget,
  }) => _dispatcher.onPaste(handler, priority: priority);

  /// Dispatch a key event to all subscribers in priority order.
  void dispatchKey(KeyEvent event) => _dispatcher.dispatchKeyEvent(event);

  /// Dispatch a mouse event to all subscribers in priority order.
  void dispatchMouse(MouseEvent event) => _dispatcher.dispatchMouseEvent(event);

  /// Dispatch a paste event to all subscribers in priority order.
  void dispatchPaste(PasteEvent event) => _dispatcher.dispatchPasteEvent(event);
}

/// Kernel-only access to the dispatch owner behind [InputManager].
extension InputManagerKernelAccess on InputManager {
  /// The dispatch kernel backing this manager.
  InputDispatcher get dispatcher => _dispatcher;
}
