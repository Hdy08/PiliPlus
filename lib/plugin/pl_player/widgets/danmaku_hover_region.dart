import 'dart:async';
import 'dart:math' as math;

import 'package:PiliPlus/plugin/pl_player/widgets/danmaku_hover_exclusions.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

typedef DanmakuActionPosition = ({
  double right,
  double top,
  double triangleOffset,
  bool above,
});

/// Keep the bubble inside the player and its tip aimed at the hover anchor.
DanmakuActionPosition desktopDanmakuActionPosition(
  Offset anchor,
  Size player,
  Size bubble, {
  required double aboveTop,
  Iterable<Rect> obstacles = const [],
}) {
  const gap = 8.0;
  final left = (anchor.dx - bubble.width / 2).clamp(
    gap,
    math.max(gap, player.width - bubble.width - gap),
  );
  final below = (Offset(left.toDouble(), anchor.dy) & bubble).inflate(gap);
  final above =
      anchor.dy + bubble.height + gap > player.height ||
      (aboveTop >= gap && obstacles.any(below.overlaps));
  return (
    right: player.width - left - bubble.width,
    top: (above ? aboveTop : anchor.dy).clamp(
      gap,
      math.max(gap, player.height - bubble.height - gap),
    ),
    triangleOffset: anchor.dx - left - bubble.width / 2,
    above: above,
  );
}

/// Extend the edge adjustment to surrounding content, compensating the tip.
DanmakuActionPosition? avoidDanmakuControls(
  DanmakuActionPosition position,
  Size player,
  Size bubble,
  Iterable<Rect> obstacles,
) {
  const gap = 8.0;
  final preferred = player.width - position.right - bubble.width;
  final maxX = player.width - bubble.width - gap;
  final preferredBounds = (Offset(preferred, position.top) & bubble).inflate(
    gap,
  );
  if (preferred >= gap &&
      preferred <= maxX &&
      !obstacles.any(preferredBounds.overlaps)) {
    return position;
  }
  final candidates = {preferred, gap, maxX};
  for (final rect in obstacles) {
    candidates.addAll([rect.right + gap, rect.left - bubble.width - gap]);
  }
  double? best;
  var distance = double.infinity;
  for (final x in candidates) {
    if (x < gap || x > maxX) continue;
    final bounds = (Offset(x, position.top) & bubble).inflate(gap);
    if (obstacles.any(bounds.overlaps)) continue;
    final delta = (x - preferred).abs();
    if (delta < distance) {
      best = x;
      distance = delta;
    }
  }
  if (best == null) return null;
  return (
    right: player.width - best - bubble.width,
    top: position.top,
    triangleOffset: position.triangleOffset + preferred - best,
    above: position.above,
  );
}

/// Sustained hover suspends one danmaku and reuses the existing action bubble.
/// Exclusion areas keep controls usable while decorative backgrounds pass hover.
class DanmakuHoverRegion<T> extends StatefulWidget {
  const DanmakuHoverRegion({
    super.key,
    required this.enabled,
    required this.controller,
    required this.size,
    required this.actionBuilder,
    required this.child,
    this.danmakuOrigin = Offset.zero,
    this.exclusionAreas,
    this.layoutChanges,
  });

  final bool enabled;
  final ValueGetter<DanmakuController<T>?> controller;
  final Size size;
  final Offset danmakuOrigin;
  final DanmakuHoverAreas Function(RenderBox, {bool forAction})? exclusionAreas;
  final Listenable? layoutChanges;
  final Widget Function(
    DanmakuItem<T>,
    double,
    Offset,
    GlobalKey,
    VoidCallback,
    Iterable<Rect>,
  )
  actionBuilder;
  final Widget child;

  @override
  State<DanmakuHoverRegion<T>> createState() => _DanmakuHoverRegionState<T>();
}

class _DanmakuHoverRegionState<T> extends State<DanmakuHoverRegion<T>> {
  static const _hoverDelay = Duration(milliseconds: 200);
  final _surfaceKey = GlobalKey();
  final _actionKey = GlobalKey();
  DanmakuController<T>? _controller;
  DanmakuItem<T>? _item;
  DanmakuItem<T>? _pendingItem;
  Timer? _hoverTimer;
  Timer? _exitTimer;
  double _y = 0;
  double _pendingY = 0;
  Offset _anchor = Offset.zero;
  Offset _pendingAnchor = Offset.zero;
  PointerEvent? _lastHover;
  bool _recheckScheduled = false;
  Duration? _areasFrame;
  final _areaCache = <bool, DanmakuHoverAreas>{};
  List<Rect> _actionObstacles = const [];

  DanmakuHoverAreas _areas(RenderBox surface, {bool forAction = false}) {
    final frame = WidgetsBinding.instance.currentSystemFrameTimeStamp;
    if (_areasFrame != frame) {
      _areasFrame = frame;
      _areaCache.clear();
    }
    return _areaCache.putIfAbsent(
      forAction,
      () =>
          widget.exclusionAreas?.call(surface, forAction: forAction) ??
          const DanmakuHoverAreas(),
    );
  }

  @override
  void initState() {
    super.initState();
    widget.layoutChanges?.addListener(_layoutChanged);
  }

  void _layoutChanged() {
    _areasFrame = null;
    if ((_item == null && _pendingItem == null) || _recheckScheduled) return;
    _recheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _recheckScheduled = false;
      if (!mounted || (_item == null && _pendingItem == null)) return;
      // The pointer may be stationary while the controls slide underneath it.
      if (_lastHover case final event?) _hover(event);
      if (_item != null) {
        final surface =
            _surfaceKey.currentContext!.findRenderObject()! as RenderBox;
        if (!listEquals(
          _actionObstacles,
          _areas(surface, forAction: true).obstacles.toList(),
        )) {
          setState(() {});
        }
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _cancelPending() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _pendingItem = null;
  }

  void _resume({bool rebuild = true}) {
    _exitTimer?.cancel();
    _exitTimer = null;
    if (_item == null) return;
    _item!.suspend = false;
    _item = null;
    if (rebuild) setState(() {});
  }

  void _clear({bool rebuild = true}) {
    _cancelPending();
    _resume(rebuild: rebuild);
  }

  void _leave() {
    if (_item != null) _exitTimer ??= Timer(_hoverDelay, _resume);
  }

  void _hover(PointerEvent event) {
    if (!widget.enabled || event.kind != PointerDeviceKind.mouse) return;
    _lastHover = event;
    final surface =
        _surfaceKey.currentContext!.findRenderObject()! as RenderBox;
    final position = surface.globalToLocal(event.position);
    final local = position - widget.danmakuOrigin;
    final controller = widget.controller();
    if (_item case final item?
        when !item.expired && identical(controller, _controller)) {
      final rect = Rect.fromLTWH(item.xPosition, _y, item.width, item.height);
      var retained = rect.contains(local);
      var overAction = false;
      if (_actionKey.currentContext?.findRenderObject()
          case final RenderBox box) {
        final action =
            box.localToGlobal(Offset.zero, ancestor: surface) & box.size;
        overAction = action.contains(position);
        // Include the triangle/gap so the mouse can move into the bubble.
        final bridge = Rect.fromLTRB(
          action.left,
          math.min(action.top, rect.bottom + widget.danmakuOrigin.dy),
          action.right,
          math.max(action.bottom, rect.top + widget.danmakuOrigin.dy),
        );
        retained |= bridge.contains(position);
      }
      final areas = _areas(surface);
      if (areas.controls.any((rect) => rect.contains(position)) ||
          (!retained &&
              areas.overlays.any((rect) => rect.contains(position)))) {
        _clear();
        return;
      }
      // Allow crossing the progress bar, while bubble buttons take precedence.
      final overProgress =
          !overAction && areas.progress.any((rect) => rect.contains(position));
      if (retained && !overProgress) {
        _exitTimer?.cancel();
        _exitTimer = null;
        _cancelPending();
        return;
      }
      _leave();
      if (overProgress) {
        _cancelPending();
        return;
      }
    } else if (_item != null) {
      _clear();
    }
    final hit = local.dx >= 0 && local.dy >= 0
        ? controller?.findSingleDanmaku(local)
        : null;
    if (hit case (final y, final item)
        when !item.expired &&
            item.content.extra != null &&
            Rect.fromLTWH(
              item.xPosition,
              y,
              item.width,
              item.height,
            ).contains(local)) {
      // Empty video needs no control-tree measurement. Reuse geometry within
      // the frame when several mouse events arrive before the next paint.
      if (_areas(surface).all.any((rect) => rect.contains(position))) {
        _clear();
        return;
      }
      _pendingY = y;
      _pendingAnchor = position;
      if (identical(_pendingItem, item) && identical(_controller, controller)) {
        return;
      }
      _cancelPending();
      _controller = controller;
      _pendingItem = item;
      _hoverTimer = Timer(_hoverDelay, () {
        _hoverTimer = null;
        // Danmaku keep moving during the delay; verify the same item is still
        // under the pointer before suspending it and showing its actions.
        if (_lastHover case final event?) _hover(event);
        if (!identical(_pendingItem, item) ||
            !identical(_controller, controller)) {
          return;
        }
        _clear(rebuild: false);
        _y = _pendingY;
        _anchor = _pendingAnchor;
        setState(() => _item = item..suspend = true);
      });
    } else {
      _cancelPending();
    }
  }

  @override
  void didUpdateWidget(covariant DanmakuHoverRegion<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    _areasFrame = null;
    if (widget.layoutChanges != oldWidget.layoutChanges) {
      oldWidget.layoutChanges?.removeListener(_layoutChanged);
      widget.layoutChanges?.addListener(_layoutChanged);
    }
    if (!widget.enabled ||
        oldWidget.size != widget.size ||
        oldWidget.danmakuOrigin != widget.danmakuOrigin ||
        ((_item != null || _pendingItem != null) &&
            !identical(_controller, widget.controller()))) {
      _clear(rebuild: false);
    }
  }

  @override
  void dispose() {
    widget.layoutChanges?.removeListener(_layoutChanged);
    _clear(rebuild: false);
    super.dispose();
  }

  Widget _buildAction(DanmakuItem<T> item) {
    Widget build(Iterable<Rect> obstacles) => widget.actionBuilder(
      item,
      _y + widget.danmakuOrigin.dy,
      _anchor,
      _actionKey,
      () {
        if (identical(_item, item)) _clear();
      },
      obstacles,
    );
    if (widget.exclusionAreas == null) return build(const []);
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final surface =
              _surfaceKey.currentContext!.findRenderObject()! as RenderBox;
          _actionObstacles = _areas(
            surface,
            forAction: true,
          ).obstacles.toList();
          return Stack(
            children: [
              build(_actionObstacles),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (_item == null && _pendingItem == null) return;
      if (_actionKey.currentContext?.findRenderObject()
          case final RenderBox action) {
        if ((Offset.zero & action.size).contains(
          action.globalToLocal(event.position),
        )) {
          return;
        }
      }
      final surface =
          _surfaceKey.currentContext!.findRenderObject()! as RenderBox;
      final position = surface.globalToLocal(event.position);
      if (_areas(surface).all.any((rect) => rect.contains(position))) {
        _clear();
      }
    },
    child: MouseRegion(
      cursor: _item != null ? SystemMouseCursors.basic : MouseCursor.defer,
      onEnter: _hover,
      onHover: _hover,
      onExit: (_) {
        _lastHover = null;
        _cancelPending();
        _leave();
      },
      child: Stack(
        key: _surfaceKey,
        fit: StackFit.passthrough,
        children: [
          widget.child,
          if (_item case final item?) _buildAction(item),
        ],
      ),
    ),
  );
}
