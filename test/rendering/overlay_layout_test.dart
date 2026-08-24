import 'package:noir/noir.dart';
import 'package:noir/noir_low_level.dart';
import 'package:noir/src/rendering/object.dart' show PipelineOwner;
import 'package:noir/src/rendering/overlay.dart';
import 'package:test/test.dart';

void main() {
  test('generic base is laid out first with terminal constraints', () {
    final overlay = RenderOverlay();
    final base = _FixedBox(3, 2);
    overlay.setBase(base);
    overlay.layout(const BoxConstraints.tight(width: 10, height: 8));

    expect(overlay.size, const Size(10, 8));
    expect(base.size, const Size(10, 8));
    expect(Offset(base.x, base.y), Offset.zero);
  });

  test('non-box base is adopted and laid out', () {
    final overlay = RenderOverlay();
    final base = _BareRenderObject();
    overlay.setBase(base);
    overlay.layout(const BoxConstraints.tight(width: 6, height: 4));

    expect(identical(base.parent, overlay), isTrue);
    expect(base.width, 6);
    expect(base.height, 4);
  });

  test('entries fill the terminal and paint later than the base', () {
    final overlay = RenderOverlay();
    final base = _FixedBox(2, 2);
    final first = RenderOverlayEntry(child: _FixedBox(3, 1));
    final second = RenderOverlayEntry(child: _FixedBox(1, 1));
    overlay.setBase(base);
    overlay.adoptEntry(first);
    overlay.adoptEntry(second);
    overlay.layout(const BoxConstraints.tight(width: 8, height: 5));

    expect(first.size, const Size(8, 5));
    expect(second.size, const Size(8, 5));
    expect(overlay.entries, [same(first), same(second)]);
  });

  test('show-to-top reorders only that identity', () {
    final overlay = RenderOverlay();
    final first = RenderOverlayEntry(child: _FixedBox(1, 1));
    final second = RenderOverlayEntry(child: _FixedBox(1, 1));
    overlay
      ..setBase(_FixedBox(1, 1))
      ..adoptEntry(first)
      ..adoptEntry(second)
      ..layout(const BoxConstraints.tight(width: 4, height: 4))
      ..moveEntryToTop(first);

    expect(overlay.entries, [same(second), same(first)]);
  });

  test('empty terminal still lays out without negative sizes', () {
    final overlay = RenderOverlay()..setBase(_FixedBox(2, 2));
    overlay.layout(const BoxConstraints.tight(width: 0, height: 0));
    expect(overlay.size, Size.zero);
  });

  test('raw entry child is at origin with natural size', () {
    final child = _FixedBox(3, 2);
    final entry = RenderOverlayEntry(child: child);
    entry.layout(const BoxConstraints.tight(width: 10, height: 6));

    expect(entry.size, const Size(10, 6));
    expect(child.size, const Size(3, 2));
    expect(Offset(child.x, child.y), Offset.zero);
  });

  test('current-frame rootRectOf sums child offsets to the base', () {
    final overlay = RenderOverlay();
    final inner = _FixedBox(2, 1)..x = 3;
    inner.y = 1;
    final base = _ParentBox(inner);
    overlay.setBase(base);
    overlay.layout(const BoxConstraints.tight(width: 10, height: 8));

    expect(overlay.rootRectOf(inner), const Rect.fromLTWH(3, 1, 2, 1));
  });

  test('rootRectOf fails closed for an anchor outside the base', () {
    final overlay = RenderOverlay()..setBase(_FixedBox(2, 2));
    overlay.layout(const BoxConstraints.tight(width: 8, height: 4));
    final outsider = _FixedBox(1, 1);
    expect(() => overlay.rootRectOf(outsider), throwsStateError);
  });

  test('placement prefers below, then above, then the larger side', () {
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(0, 0, 10, 10),
        anchor: const Rect.fromLTWH(1, 1, 2, 1),
        menuSize: const Size(3, 2),
        alignmentOffset: Offset.zero,
      ),
      const Offset(1, 2),
    );
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(0, 0, 10, 6),
        anchor: const Rect.fromLTWH(1, 4, 2, 1),
        menuSize: const Size(3, 3),
        alignmentOffset: Offset.zero,
      ),
      const Offset(1, 1),
    );
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(0, 0, 10, 6),
        anchor: const Rect.fromLTWH(1, 2, 2, 1),
        menuSize: const Size(3, 4),
        alignmentOffset: Offset.zero,
      ),
      const Offset(1, 2),
    );
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(0, 0, 10, 5),
        anchor: const Rect.fromLTWH(1, 2, 2, 1),
        menuSize: const Size(3, 4),
        alignmentOffset: Offset.zero,
      ),
      const Offset(1, 1),
    );
  });

  test('reserved padding deflates without negative extents', () {
    expect(
      deflateSafeRect(const Size(4, 4), const EdgeInsets.all(10)),
      const Rect.fromLTWH(4, 4, 0, 0),
    );
    expect(
      deflateSafeRect(
        const Size(10, 8),
        const EdgeInsets.only(left: 2, right: 3),
      ),
      const Rect.fromLTWH(2, 0, 5, 8),
    );
  });

  test('hit testing visits the top entry before the base', () {
    final overlay = RenderOverlay();
    final base = _HitBox();
    final top = RenderOverlayEntry(modalBarrier: true, child: _FixedBox(1, 1));
    overlay
      ..setBase(base)
      ..adoptEntry(top)
      ..layout(const BoxConstraints.tight(width: 6, height: 4));

    final result = HitTestResult();
    expect(overlay.hitTest(result, const Offset(5, 3)), isTrue);
    expect(result.path.first.target, same(top));
  });

  test('replacing the base does not drain portal entries', () {
    final overlay = RenderOverlay();
    final entry = RenderOverlayEntry(child: _FixedBox(1, 1));
    overlay
      ..setBase(_FixedBox(2, 2))
      ..adoptEntry(entry)
      ..setBase(null);

    expect(overlay.entries, [same(entry)]);
    expect(identical(entry.parent, overlay), isTrue);
  });

  test('an entry cannot replace the base slot', () {
    final overlay = RenderOverlay();
    final base = _FixedBox(2, 2);
    final entry = RenderOverlayEntry(child: _FixedBox(1, 1));
    overlay
      ..setBase(base)
      ..adoptEntry(entry);

    expect(() => overlay.setBase(entry), throwsStateError);
    expect(overlay.base, same(base));
    expect(overlay.entries, [same(entry)]);
    expect(overlay.children, [same(base), same(entry)]);
  });

  test('failed base adoption preserves the current base', () {
    final overlay = RenderOverlay();
    final current = _FixedBox(2, 2);
    final attached = _FixedBox(1, 1);
    final owner = PipelineOwner();
    attached.attach(owner);
    overlay.setBase(current);

    try {
      expect(() => overlay.setBase(attached), throwsStateError);
      expect(overlay.base, same(current));
      expect(current.parent, same(overlay));
      expect(overlay.children, [same(current)]);
    } finally {
      attached.detach();
      owner.dispose();
    }
  });

  test('a failing base attach rolls back to the current base', () {
    final attachError = StateError('base attach failed');
    final current = _FixedBox(2, 2);
    final replacement = _ThrowAfterAttachBox(attachError);
    final overlay = RenderOverlay()..setBase(current);
    final owner = PipelineOwner();
    overlay.attach(owner);

    try {
      expect(() => overlay.setBase(replacement), throwsA(same(attachError)));
      expect(overlay.base, same(current));
      expect(current.parent, same(overlay));
      expect(current.pipelineOwner, same(owner));
      expect(replacement.parent, isNull);
      expect(replacement.pipelineOwner, isNull);
      expect(overlay.children, [same(current)]);
    } finally {
      overlay.detach();
      owner.dispose();
    }
  });

  test('a failing entry attach leaves no unregistered render child', () {
    final attachError = StateError('entry attach failed');
    final entry = RenderOverlayEntry(child: _ThrowAfterAttachBox(attachError));
    final overlay = RenderOverlay();
    final owner = PipelineOwner();
    overlay.attach(owner);

    try {
      expect(() => overlay.adoptEntry(entry), throwsA(same(attachError)));
      expect(entry.parent, isNull);
      expect(entry.pipelineOwner, isNull);
      expect(overlay.entries, isEmpty);
      expect(overlay.children, isEmpty);
    } finally {
      overlay.detach();
      owner.dispose();
    }
  });

  test('a committed drop clears entry metadata before rethrowing', () {
    final detachError = StateError('entry child detach failed');
    final entry = RenderOverlayEntry(child: _ThrowAfterDetachBox(detachError));
    final overlay = RenderOverlay()..adoptEntry(entry);
    final owner = PipelineOwner();
    overlay.attach(owner);

    try {
      expect(() => overlay.dropEntry(entry), throwsA(same(detachError)));
      expect(entry.parent, isNull);
      expect(entry.pipelineOwner, isNull);
      expect(overlay.entries, isEmpty);
      expect(overlay.children, isEmpty);
    } finally {
      overlay.detach();
      owner.dispose();
    }
  });

  test('draining entries continues after a detach failure', () {
    final detachError = StateError('first entry detach failed');
    final first = RenderOverlayEntry(child: _ThrowAfterDetachBox(detachError));
    final second = RenderOverlayEntry(child: _FixedBox(1, 1));
    final overlay = RenderOverlay()
      ..adoptEntry(first)
      ..adoptEntry(second);
    final owner = PipelineOwner();
    overlay.attach(owner);

    try {
      expect(overlay.drainEntries, throwsA(same(detachError)));
      expect(overlay.entries, isEmpty);
      expect(first.parent, isNull);
      expect(second.parent, isNull);
      expect(second.pipelineOwner, isNull);
    } finally {
      overlay.detach();
      owner.dispose();
    }
  });

  test('explicit root position ignores alignment offset', () {
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(0, 0, 12, 12),
        anchor: const Rect.fromLTWH(1, 1, 2, 1),
        menuSize: const Size(3, 2),
        alignmentOffset: const Offset(5, 5),
        explicitRootPosition: const Offset(4, 3),
      ),
      const Offset(4, 3),
    );
  });

  test('placement clamps oversized menus into the safe rect', () {
    expect(
      resolveAnchoredMenuOrigin(
        safeRect: const Rect.fromLTWH(1, 1, 4, 3),
        anchor: const Rect.fromLTWH(-2, -2, 1, 1),
        menuSize: const Size(6, 5),
        alignmentOffset: const Offset(-8, 0),
      ),
      const Offset(1, 1),
    );
  });

  test('anchored entry shrinks the menu to the safe bounds', () {
    final overlay = RenderOverlay();
    final anchor = _FixedBox(2, 1);
    final child = _FixedBox(20, 20);
    overlay
      ..setBase(anchor)
      ..adoptEntry(
        RenderOverlayEntry(
          anchor: anchor,
          reservedPadding: const EdgeInsets.all(1),
          child: child,
        ),
      )
      ..layout(const BoxConstraints.tight(width: 10, height: 8));

    expect(child.size.width, lessThanOrEqualTo(8));
    expect(child.size.height, lessThanOrEqualTo(6));
  });
}

final class _FixedBox extends RenderBox {
  _FixedBox(this.naturalWidth, this.naturalHeight);

  final int naturalWidth;
  final int naturalHeight;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.constrainWidth(naturalWidth),
      constraints.constrainHeight(naturalHeight),
    );
  }
}

final class _ThrowAfterDetachBox extends RenderBox {
  _ThrowAfterDetachBox(this.error);

  final StateError error;

  @override
  void detach() {
    super.detach();
    throw error;
  }
}

final class _ThrowAfterAttachBox extends RenderBox {
  _ThrowAfterAttachBox(this.error);

  final StateError error;

  @override
  void didAttach(PipelineOwner owner) {
    super.didAttach(owner);
    throw error;
  }
}

final class _ParentBox extends RenderBox {
  _ParentBox(this.inner) {
    adoptChild(inner);
  }

  final RenderBox inner;

  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
    inner.layout(const BoxConstraints());
  }
}

final class _BareRenderObject extends RenderObject {
  @override
  void performLayout(Constraints constraints) {
    width = constraints.maxWidth ?? 0;
    height = constraints.maxHeight ?? 0;
  }

  @override
  void paint(PaintingContext context, Offset offset) {}
}

final class _HitBox extends RenderBox implements HitTestTarget {
  @override
  void performBoxLayout(BoxConstraints constraints) {
    size = Size(
      constraints.maxWidth ?? constraints.minWidth,
      constraints.maxHeight ?? constraints.minHeight,
    );
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void handleEvent(MouseEvent event, HitTestEntry entry) {}
}
