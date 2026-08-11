import 'package:characters/characters.dart';
import 'package:meta/meta.dart';

import '../core/buffer.dart';
import '../core/color.dart';
import '../core/grapheme_metrics.dart';
import '../core/terminal_style.dart';
import '../core/text_buffer.dart';
import '../render/geometry.dart';
import '../rendering/text_highlight.dart';
import '../widgets/text_layout.dart';

/// The supported terminal paint vocabulary.
///
/// Framework paint passes provide an implementation. Applications and custom
/// decorations can record paint operations but cannot finalize or commit a
/// frame themselves.
abstract interface class TuiCanvas {
  /// Save the current clip state.
  void save();

  /// Restore the last saved clip state.
  void restore();

  /// Intersect subsequent drawing with [rect].
  void clipRect(Rect rect);

  /// Fill [rect] with [color].
  void fillRect(Rect rect, Color color);

  /// Draw [text] at [offset].
  void drawText(
    String text,
    Offset offset,
    Color foreground, {
    Color? background,
    int attributes = 0,
  });

  /// Draw a bordered box.
  void drawBox(
    Rect rect,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  );

  /// Set a single terminal cell.
  void setCell(
    Offset offset,
    String char,
    Color foreground,
    Color background,
    int attributes,
  );

  /// Draw a laid-out text snapshot.
  void drawTextLayout(
    TextLayout layout,
    Offset offset, {
    Rect? sourceRect,
    TextHighlight? selection,
  });
}

/// Creates a canvas recorder for a framework-owned paint pass.
@internal
TuiCanvas createTuiCanvas() => _TuiCanvasRecorder();

/// Encodes and commits a framework-owned canvas recording into [buffer].
@internal
void commitTuiCanvas(Buffer buffer, TuiCanvas canvas) {
  final recorder = canvas;
  if (recorder is! _TuiCanvasRecorder) {
    throw ArgumentError.value(
      canvas,
      'canvas',
      'must be the recorder supplied by the Noir framework',
    );
  }
  _openTuiCompositor.commit(buffer, recorder._finish());
}

final _openTuiCompositor = _OpenTuiCompositor();

final class _TuiCanvasRecorder implements TuiCanvas {
  final List<_TuiDrawCommand> _commands = <_TuiDrawCommand>[];
  final List<Rect?> _clipStack = <Rect?>[];
  Rect? _clip;
  bool _finished = false;

  /// Save the current clip state.
  @override
  void save() {
    _ensureOpen();
    _clipStack.add(_clip);
  }

  /// Restore the last saved clip state.
  @override
  void restore() {
    _ensureOpen();
    if (_clipStack.isEmpty) {
      throw StateError('Cannot restore a TuiCanvas without a matching save().');
    }
    _clip = _clipStack.removeLast();
  }

  /// Intersect subsequent drawing with [rect].
  @override
  void clipRect(Rect rect) {
    _ensureOpen();
    _clip = _intersect(_clip, rect);
  }

  /// Fill [rect] with [color].
  @override
  void fillRect(Rect rect, Color color) {
    _ensureOpen();
    _commands.add(_FillRectCommand(rect, color, clip: _clip));
  }

  /// Draw [text] at [offset].
  @override
  void drawText(
    String text,
    Offset offset,
    Color foreground, {
    Color? background,
    int attributes = 0,
  }) {
    _ensureOpen();
    _commands.add(
      _DrawTextCommand(
        text,
        offset,
        foreground,
        background: background,
        attributes: attributes,
        clip: _clip,
      ),
    );
  }

  /// Draw a bordered box.
  @override
  void drawBox(
    Rect rect,
    BoxOptions options,
    Color borderColor,
    Color backgroundColor,
  ) {
    _ensureOpen();
    _commands.add(
      _DrawBoxCommand(rect, options, borderColor, backgroundColor, clip: _clip),
    );
  }

  /// Set a single terminal cell.
  @override
  void setCell(
    Offset offset,
    String char,
    Color foreground,
    Color background,
    int attributes,
  ) {
    _ensureOpen();
    _commands.add(
      _SetCellCommand(
        offset,
        char,
        foreground,
        background,
        attributes,
        clip: _clip,
      ),
    );
  }

  /// Draw a laid-out text snapshot.
  @override
  void drawTextLayout(
    TextLayout layout,
    Offset offset, {
    Rect? sourceRect,
    TextHighlight? selection,
  }) {
    _ensureOpen();
    _commands.add(
      _DrawTextLayoutCommand(
        layout,
        offset,
        sourceRect: sourceRect,
        selection: selection,
        clip: _clip,
      ),
    );
  }

  /// Finish recording and return an immutable display list.
  _TuiDisplayList _finish() {
    _ensureOpen();
    if (_clipStack.isNotEmpty) {
      throw StateError('Cannot finish a TuiCanvas with unbalanced save().');
    }
    _finished = true;
    return _TuiDisplayList(List<_TuiDrawCommand>.unmodifiable(_commands));
  }

  void _ensureOpen() {
    if (_finished) {
      throw StateError('Cannot record commands after a paint pass finishes.');
    }
  }
}

/// Immutable list of terminal draw commands.
final class _TuiDisplayList {
  /// Creates a display list.
  const _TuiDisplayList(this.commands);

  /// Recorded commands in paint order.
  final List<_TuiDrawCommand> commands;
}

/// A single recorded terminal draw operation.
sealed class _TuiDrawCommand {
  const _TuiDrawCommand({this.clip});

  /// Optional clip rectangle active when this command was recorded.
  final Rect? clip;
}

/// Fill-rectangle command.
final class _FillRectCommand extends _TuiDrawCommand {
  /// Creates a fill-rectangle command.
  const _FillRectCommand(this.rect, this.color, {super.clip});

  /// Destination rectangle.
  final Rect rect;

  /// Fill color.
  final Color color;
}

/// Draw-text command.
final class _DrawTextCommand extends _TuiDrawCommand {
  /// Creates a draw-text command.
  const _DrawTextCommand(
    this.text,
    this.offset,
    this.foreground, {
    this.background,
    this.attributes = 0,
    super.clip,
  });

  /// Text to draw.
  final String text;

  /// Destination offset.
  final Offset offset;

  /// Foreground color.
  final Color foreground;

  /// Optional background color.
  final Color? background;

  /// Text attributes.
  final int attributes;
}

/// Draw-box command.
final class _DrawBoxCommand extends _TuiDrawCommand {
  /// Creates a draw-box command.
  const _DrawBoxCommand(
    this.rect,
    this.options,
    this.borderColor,
    this.backgroundColor, {
    super.clip,
  });

  /// Destination rectangle.
  final Rect rect;

  /// Border options.
  final BoxOptions options;

  /// Border color.
  final Color borderColor;

  /// Background color.
  final Color backgroundColor;
}

/// Set-cell command.
final class _SetCellCommand extends _TuiDrawCommand {
  /// Creates a set-cell command.
  const _SetCellCommand(
    this.offset,
    this.char,
    this.foreground,
    this.background,
    this.attributes, {
    super.clip,
  });

  /// Destination offset.
  final Offset offset;

  /// Cell glyph.
  final String char;

  /// Foreground color.
  final Color foreground;

  /// Background color.
  final Color background;

  /// Text attributes.
  final int attributes;
}

/// Draw-laid-out-text command.
final class _DrawTextLayoutCommand extends _TuiDrawCommand {
  /// Creates a laid-out-text command.
  const _DrawTextLayoutCommand(
    this.layout,
    this.offset, {
    this.sourceRect,
    this.selection,
    super.clip,
  });

  /// Text layout to draw.
  final TextLayout layout;

  /// Destination offset.
  final Offset offset;

  /// Optional source rectangle within the laid-out text buffer.
  final Rect? sourceRect;

  /// Optional source-text highlight.
  final TextHighlight? selection;
}

/// Encodes a display list into the current OpenTUI [Buffer].
final class _DisplayListEncoder {
  /// Encode [displayList] into [buffer].
  void encode(Buffer buffer, _TuiDisplayList displayList) {
    for (final command in displayList.commands) {
      final target = _targetFor(buffer, command.clip);
      switch (command) {
        case _FillRectCommand():
          target.fillRect(
            command.rect.left,
            command.rect.top,
            command.rect.width,
            command.rect.height,
            command.color,
          );
        case _DrawTextCommand():
          target.drawText(
            command.text,
            command.offset.dx,
            command.offset.dy,
            command.foreground,
            bg: command.background,
            attributes: command.attributes,
          );
        case _DrawBoxCommand():
          target.drawBox(
            command.rect.left,
            command.rect.top,
            command.rect.width,
            command.rect.height,
            command.options,
            command.borderColor,
            command.backgroundColor,
          );
        case _SetCellCommand():
          target.setCell(
            command.offset.dx,
            command.offset.dy,
            command.char,
            command.foreground,
            command.background,
            command.attributes,
          );
        case _DrawTextLayoutCommand():
          final source = command.sourceRect;
          if (source != null) {
            final drawTarget = _sourceClipTarget(
              buffer,
              command.clip,
              command.offset,
              source,
            );
            _drawTextLayoutSourceClip(drawTarget, command, source);
          } else {
            final textBuffer = _textBufferForLayout(command);
            try {
              target.drawTextBuffer(
                textBuffer,
                command.offset.dx,
                command.offset.dy,
              );
            } finally {
              textBuffer.dispose();
            }
          }
      }
    }
  }

  void _drawTextLayoutSourceClip(
    Buffer target,
    _DrawTextLayoutCommand command,
    Rect source,
  ) {
    if (source.width <= 0 || source.height <= 0) {
      return;
    }

    final layout = command.layout;
    for (
      var lineIndex = source.top;
      lineIndex < source.bottom && lineIndex < layout.lines.length;
      lineIndex++
    ) {
      if (lineIndex < 0) {
        continue;
      }
      final line = layout.lines[lineIndex];
      var cell = 0;
      for (final run in line.runs) {
        var sourceOffset = run.sourceStart;
        for (final cluster in run.text.characters) {
          final width = terminalCellWidth(cluster);
          final nextCell = cell + width;
          final sourceEnd = sourceOffset + cluster.length;
          if (cell >= source.left && nextCell <= source.right) {
            target.setCell(
              command.offset.dx + cell - source.left,
              command.offset.dy + lineIndex - source.top,
              cluster,
              _foregroundForCluster(command, run, sourceOffset, sourceEnd),
              _backgroundForCluster(command, run, sourceOffset, sourceEnd),
              run.style.computedAttributes,
            );
          }
          cell = nextCell;
          sourceOffset = sourceEnd;
          if (cell >= source.right) {
            break;
          }
        }
      }
    }
  }

  Color _foregroundForCluster(
    _DrawTextLayoutCommand command,
    TextLayoutRun run,
    int sourceStart,
    int sourceEnd,
  ) {
    final selection = command.selection;
    if (selection != null &&
        _selectionIntersects(selection, sourceStart, sourceEnd)) {
      return selection.foregroundColor ?? run.style.color;
    }
    return run.style.color;
  }

  Color _backgroundForCluster(
    _DrawTextLayoutCommand command,
    TextLayoutRun run,
    int sourceStart,
    int sourceEnd,
  ) {
    final selection = command.selection;
    if (selection != null &&
        _selectionIntersects(selection, sourceStart, sourceEnd)) {
      return selection.backgroundColor ??
          run.style.backgroundColor ??
          Color.transparent;
    }
    return run.style.backgroundColor ?? Color.transparent;
  }

  bool _selectionIntersects(
    TextHighlight selection,
    int sourceStart,
    int sourceEnd,
  ) => sourceStart < selection.end && sourceEnd > selection.start;

  TextBuffer _textBufferForLayout(_DrawTextLayoutCommand command) {
    final layout = command.layout;
    final textBuffer = TextBuffer.create();
    for (var lineIndex = 0; lineIndex < layout.lines.length; lineIndex++) {
      final line = layout.lines[lineIndex];
      for (final run in line.runs) {
        textBuffer.writeChunk(
          run.text,
          run.style.color,
          run.style.backgroundColor ?? Color.transparent,
          run.style.computedAttributes,
        );
      }
      if (lineIndex < layout.lines.length - 1) {
        textBuffer.writeChunk(
          '\n',
          layout.style.color,
          layout.style.backgroundColor ?? Color.transparent,
          layout.style.computedAttributes,
        );
      }
    }
    textBuffer.finalizeLineInfo();

    final selection = command.selection;
    if (selection != null && layout.text.isNotEmpty) {
      final rawStart = selection.start.clamp(0, layout.text.length);
      final rawEnd = selection.end.clamp(rawStart, layout.text.length);
      if (rawStart < rawEnd) {
        final start = layout.bufferOffsetForSourceUtf16(rawStart);
        final end = layout.bufferOffsetForSourceUtf16(rawEnd);
        if (start < end) {
          textBuffer.setSelection(
            start,
            end,
            selection.backgroundColor ?? const Color(0.3, 0.5, 0.9, 0.5),
            selection.foregroundColor ?? layout.style.color,
          );
        }
      }
    }
    return textBuffer;
  }

  Buffer _targetFor(Buffer buffer, Rect? clip) {
    if (clip == null) {
      return buffer;
    }

    final bufferClip = Rect.fromLTWH(0, 0, buffer.width, buffer.height);
    final effectiveClip = _intersect(bufferClip, clip);
    return buffer.clipped(
      clipX: effectiveClip.left,
      clipY: effectiveClip.top,
      clipWidth: effectiveClip.width,
      clipHeight: effectiveClip.height,
    );
  }

  Buffer _sourceClipTarget(
    Buffer buffer,
    Rect? commandClip,
    Offset offset,
    Rect source,
  ) {
    final bufferClip = Rect.fromLTWH(0, 0, buffer.width, buffer.height);
    final destinationClip = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      source.width,
      source.height,
    );
    var effectiveClip = _intersect(bufferClip, destinationClip);
    if (commandClip != null) {
      effectiveClip = _intersect(effectiveClip, commandClip);
    }
    return buffer.clipped(
      clipX: effectiveClip.left,
      clipY: effectiveClip.top,
      clipWidth: effectiveClip.width,
      clipHeight: effectiveClip.height,
    );
  }
}

/// Compositor that applies a recorded display list to OpenTUI.
final class _OpenTuiCompositor {
  final _DisplayListEncoder _encoder = _DisplayListEncoder();

  /// Commit [displayList] to the current frame [buffer].
  void commit(Buffer buffer, _TuiDisplayList displayList) {
    _encoder.encode(buffer, displayList);
  }
}

Rect _intersect(Rect? a, Rect b) {
  if (a == null) {
    return b;
  }
  final left = a.left > b.left ? a.left : b.left;
  final top = a.top > b.top ? a.top : b.top;
  final right = a.right < b.right ? a.right : b.right;
  final bottom = a.bottom < b.bottom ? a.bottom : b.bottom;
  if (right <= left || bottom <= top) {
    return Rect.fromLTWH(left, top, 0, 0);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
