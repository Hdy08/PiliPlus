import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:PiliPlus/common/widgets/marquee.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/rendering.dart';

class DanmakuHoverAreas {
  const DanmakuHoverAreas({
    this.controls = const [],
    this.progress = const [],
    this.overlays = const [],
  });

  final List<Rect> controls;
  final List<Rect> progress;
  final List<Rect> overlays;
  // Progress and passive overlays may be crossed to reach an existing bubble.
  Iterable<Rect> get transit => progress.followedBy(overlays);
  Iterable<Rect> get all => controls.followedBy(transit);
  Iterable<Rect> get obstacles => controls.followedBy(overlays);
}

/// Measures rendered controls, rather than reserving the whole bar background.
/// Corner groups extend to the player edges, including their internal gaps.
DanmakuHoverAreas danmakuHoverExclusions({
  required RenderBox surface,
  required RenderObject? content,
  required RenderObject? video,
  required RenderObject? header,
  required RenderObject? footer,
  Map<RenderObject?, bool> sideControls = const {},
  bool? controlsVisible,
}) {
  final bounds = Offset.zero & surface.size;
  final areas = <Rect>[];
  final progress = <Rect>[];
  final overlays = <Rect>[];
  final corners = <(bool, bool), Rect>{};

  Rect? rectOf(RenderObject object, [bool? top]) {
    if (object is! RenderBox || !object.hasSize || object.size.isEmpty) {
      return null;
    }
    var local = Offset.zero & object.size;
    if (object is MarqueeRender && object.child != null) {
      // An Expanded short title can have a much wider layout box than its text.
      local = local.intersect(Offset.zero & object.child!.size);
    } else if (object is RenderParagraph) {
      final boxes = object.getBoxesForSelection(
        TextSelection(
          baseOffset: 0,
          extentOffset: object.text.toPlainText().length,
        ),
      );
      if (boxes.isEmpty) return null;
      local = local.intersect(
        boxes.map((box) => box.toRect()).reduce((a, b) => a.expandToInclude(b)),
      );
    }
    var rect = MatrixUtils.transformRect(
      object.getTransformTo(surface),
      local,
    );
    // Reserve the destination immediately, rather than following the slide.
    if (controlsVisible == true && top != null) {
      final bar = top ? header : footer;
      if (bar is RenderFractionalTranslation) {
        rect = rect.shift(
          -Offset(
            bar.translation.dx * bar.size.width,
            bar.translation.dy * bar.size.height,
          ),
        );
      }
    }
    rect = rect.intersect(bounds);
    return rect.isEmpty ? null : rect;
  }

  void add(RenderObject object, {bool? top, bool? left}) {
    final rect = rectOf(object, top);
    if (rect == null) return;
    if (top == null) {
      (object is RenderPointerListener ||
                  object is RenderSemanticsGestureHandler
              ? areas
              : overlays)
          .add(rect);
    } else {
      final key = (top, left ?? rect.center.dx < bounds.center.dx);
      corners.update(
        key,
        (old) => old.expandToInclude(rect),
        ifAbsent: () => rect,
      );
    }
  }

  void visit(RenderObject object, [bool? top, bool? left]) {
    if (identical(object, video) ||
        (object is RenderOffstage && object.offstage) ||
        (object is RenderOpacity && object.opacity == 0) ||
        (object is RenderAnimatedOpacity && object.opacity.value == 0)) {
      return;
    }
    if (identical(object, header)) top = true;
    if (identical(object, footer)) top = false;
    if (top != null && controlsVisible == false) return;
    if (sideControls[object] case final left?) {
      if (rectOf(object) case final rect?) {
        areas.add(
          Rect.fromLTRB(
            left ? 0 : rect.left,
            rect.top,
            left ? rect.right : bounds.right,
            rect.bottom,
          ),
        );
      }
      return;
    }
    if (object is RenderProgressBar) {
      if (object.onDragStart != null || object.onSeek != null) {
        if (rectOf(object, top) case final rect?) progress.add(rect);
      }
      return;
    }
    if (object is RenderPlayerBar && top != null) {
      visit(object.left, top, true);
      if (object.title case final title?) visit(title, top, true);
      visit(object.right, top, false);
      return;
    }
    if (object is RenderPointerListener ||
        object is RenderSemanticsGestureHandler ||
        object is RenderParagraph ||
        object is MarqueeRender ||
        object is RenderImage ||
        (object is RenderCustomPaint &&
            (object.painter != null || object.foregroundPainter != null))) {
      add(object, top: top, left: left);
      return;
    }
    var hasChildren = false;
    object.visitChildren((child) {
      hasChildren = true;
      visit(child, top, left);
    });
    // The playback clock paints paragraphs in its own leaf render box.
    if (!hasChildren &&
        object is RenderBox &&
        object is! RenderProxyBox &&
        object.isRepaintBoundary) {
      add(object, top: top, left: left);
    }
  }

  if (content != null) visit(content);
  for (final MapEntry(key: (top, left), value: rect) in corners.entries) {
    areas.add(
      Rect.fromLTRB(
        left ? 0 : rect.left,
        top ? 0 : rect.top,
        left ? rect.right : bounds.right,
        top ? rect.bottom : bounds.bottom,
      ),
    );
  }
  return DanmakuHoverAreas(
    controls: areas,
    progress: progress,
    overlays: overlays,
  );
}
