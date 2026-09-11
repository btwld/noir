import '../foundation/change_notifier.dart';
import '../render/geometry.dart';

/// Shared integer viewport math — offset clamping, paging, and
/// ensure-visible logic — with a single owner so subtle off-by-ones don't
/// drift between widgets. Its consumers are `Select`, `TextArea`, and the
/// patch-manager view; `ScrollBox` owns a separate double-precision scroll
/// model (`ScrollController`).
///
/// A `ViewportController` is dumb: it has no opinion about how content is
/// painted, what a "page" looks like visually, or whether scroll is by row
/// or by cell. Callers provide `contentExtent` and `viewportExtent` in
/// whatever unit suits them (rows for Select, lines for TextArea).
///
/// Listeners are notified when content extent, viewport extent, or scroll
/// offset changes.
class ViewportController extends ChangeNotifier {
  /// Validates non-negative extents and clamps [scrollOffset] to their range.
  ViewportController({
    int contentExtent = 0,
    int viewportExtent = 0,
    int scrollOffset = 0,
  }) : _contentExtent = contentExtent,
       _viewportExtent = viewportExtent,
       _scrollOffset = scrollOffset {
    requireNonNegativeExtent(_contentExtent, 'contentExtent');
    requireNonNegativeExtent(_viewportExtent, 'viewportExtent');
    _scrollOffset = _clamp(_scrollOffset);
  }

  int _contentExtent;
  int _viewportExtent;
  int _scrollOffset;

  /// Total scrollable content size, in caller-chosen units.
  int get contentExtent => _contentExtent;
  set contentExtent(int value) {
    requireNonNegativeExtent(value, 'contentExtent');
    if (_contentExtent == value) return;
    _contentExtent = value;
    _scrollOffset = _clamp(_scrollOffset);
    notifyListeners();
  }

  /// Visible window size, in caller-chosen units.
  int get viewportExtent => _viewportExtent;
  set viewportExtent(int value) {
    requireNonNegativeExtent(value, 'viewportExtent');
    if (_viewportExtent == value) return;
    _viewportExtent = value;
    _scrollOffset = _clamp(_scrollOffset);
    notifyListeners();
  }

  /// Current scroll offset, always clamped to `[0, maxScrollOffset]`.
  int get scrollOffset => _scrollOffset;

  /// Maximum scroll offset (zero when content fits in viewport).
  int get maxScrollOffset {
    final max = _contentExtent - _viewportExtent;
    return max < 0 ? 0 : max;
  }

  /// Jump immediately to [offset], clamped to `[0, maxScrollOffset]`.
  /// Returns true if the offset actually changed.
  bool jumpTo(int offset) {
    final clamped = _clamp(offset);
    if (clamped == _scrollOffset) return false;
    _scrollOffset = clamped;
    notifyListeners();
    return true;
  }

  /// Page up by [viewportExtent], clamped. Returns true if offset changed.
  /// A degenerate viewport (extent <= 0) is a no-op.
  bool pageUp() {
    if (_viewportExtent <= 0) return false;
    return jumpTo(_scrollOffset - _viewportExtent);
  }

  /// Page down by [viewportExtent], clamped. Returns true if offset changed.
  bool pageDown() {
    if (_viewportExtent <= 0) return false;
    return jumpTo(_scrollOffset + _viewportExtent);
  }

  /// Adjust [scrollOffset] so the half-open range `[itemStart, itemEnd)` is
  /// visible. The scroll change is the minimum needed: an item above the
  /// viewport snaps the viewport top to `itemStart`; an item below snaps
  /// the bottom to `itemEnd`. Returns true if the offset changed.
  bool ensureVisible(int itemStart, int itemEnd) {
    if (_viewportExtent <= 0) return false;
    if (itemStart < _scrollOffset) {
      return jumpTo(itemStart);
    }
    if (itemEnd > _scrollOffset + _viewportExtent) {
      return jumpTo(itemEnd - _viewportExtent);
    }
    return false;
  }

  int _clamp(int value) {
    if (value < 0) return 0;
    final max = maxScrollOffset;
    if (value > max) return max;
    return value;
  }
}
