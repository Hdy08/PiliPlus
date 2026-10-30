import 'package:PiliPlus/pages/common/fab_mixin.dart';
import 'package:PiliPlus/utils/feed_back.dart';
import 'package:extended_nested_scroll_view/extended_nested_scroll_view.dart'
    show ExtendedNestedScrollViewState;
import 'package:material_ui/material_ui.dart';

typedef BackToTopLayoutBuilder = Widget Function(Widget body, Widget? fab);

class BackToTop extends StatefulWidget {
  const BackToTop({
    super.key,
    required this.child,
    this.fab,
    this.layoutBuilder,
  });

  final Widget child;
  final Widget? fab;
  final BackToTopLayoutBuilder? layoutBuilder;

  @override
  State<BackToTop> createState() => _BackToTopState();
}

class _BackToTopState extends State<BackToTop>
    with SingleTickerProviderStateMixin, BaseFabMixin, LazyFabMixin {
  final _scrollables = <ScrollableState>{};
  final _canScroll = ValueNotifier(false);
  ScrollableState? _activeScrollable;
  bool _updateScheduled = false;

  @override
  void didUpdateWidget(BackToTop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scrollables.isNotEmpty) _scheduleUpdate();
  }

  bool _isVisible(ScrollableState scrollable) {
    if (!scrollable.mounted ||
        !TickerMode.getValuesNotifier(scrollable.context).value.enabled) {
      return false;
    }
    final viewport = scrollable.context.findRenderObject();
    final container = context.findRenderObject();
    if (viewport is! RenderBox ||
        container is! RenderBox ||
        !viewport.attached ||
        !viewport.hasSize ||
        !container.hasSize ||
        viewport.size.isEmpty ||
        container.size.isEmpty) {
      return false;
    }
    return (viewport.localToGlobal(Offset.zero) & viewport.size).overlaps(
      container.localToGlobal(Offset.zero) & container.size,
    );
  }

  bool _isScrollable(ScrollableState scrollable) {
    final position = scrollable.position;
    final outer = _outerController(scrollable)?.position;
    return position.hasContentDimensions &&
        position.axis == Axis.vertical &&
        position.minScrollExtent.isFinite &&
        position.maxScrollExtent.isFinite &&
        (position.maxScrollExtent > position.minScrollExtent ||
            (outer != null && outer.maxScrollExtent > outer.minScrollExtent));
  }

  ScrollController? _outerController(ScrollableState scrollable) {
    final context = scrollable.context;
    final position = scrollable.position;
    final extended = context
        .findAncestorStateOfType<ExtendedNestedScrollViewState>();
    if (extended != null &&
        (extended.innerController.positions.contains(position) ||
            extended.outerController.positions.contains(position))) {
      return extended.outerController;
    }
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    if (nested != null &&
        (nested.innerController.positions.contains(position) ||
            nested.outerController.positions.contains(position))) {
      return nested.outerController;
    }
    return null;
  }

  void _scheduleUpdate() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      _scrollables.removeWhere((scrollable) => !scrollable.mounted);
      final active = _activeScrollable;
      if (active == null || !_isVisible(active) || !_isScrollable(active)) {
        _activeScrollable = null;
        for (final scrollable in _scrollables) {
          if (_isVisible(scrollable) && _isScrollable(scrollable)) {
            _activeScrollable = scrollable;
          }
        }
      }
      _canScroll.value = _activeScrollable != null;
    });
  }

  ScrollableState? _register(BuildContext? context) {
    if (context == null) return null;
    final scrollable = Scrollable.maybeOf(context);
    if (_scrollables.contains(scrollable)) return scrollable;
    if (scrollable == null ||
        scrollable.position is PageMetrics ||
        scrollable.context.findAncestorStateOfType<EditableTextState>() !=
            null) {
      return null;
    }
    _scrollables.add(scrollable);
    return scrollable;
  }

  bool _onMetrics(ScrollMetricsNotification notification) {
    if (notification.metrics.axis == Axis.vertical) {
      _register(notification.context);
      _scheduleUpdate();
    }
    return false;
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics is PageMetrics) {
      if (notification is ScrollEndNotification) {
        _activeScrollable = null;
        showFab();
        _scheduleUpdate();
      }
      return false;
    }
    if (notification.metrics.axis != Axis.vertical) return false;
    final scrollable = _register(notification.context);
    if (scrollable == null) return false;
    _activeScrollable = scrollable;
    if (notification is UserScrollNotification) {
      if (notification.metrics.axisDirection == AxisDirection.up) {
        switch (notification.direction) {
          case .forward:
            hideFab();
          case .reverse:
            showFab();
          default:
        }
      } else {
        onNotification(notification);
      }
    }
    if (notification is ScrollStartNotification ||
        notification is ScrollEndNotification) {
      _scheduleUpdate();
    }
    return false;
  }

  void _toTop() {
    final scrollable = _activeScrollable;
    if (scrollable == null || !_isVisible(scrollable)) return;
    feedBack();
    final controller = _outerController(scrollable);
    final position = controller?.position ?? scrollable.position;
    final target = position.axisDirection == AxisDirection.up
        ? position.maxScrollExtent
        : position.minScrollExtent;
    if (!target.isFinite) return;
    // Avoid animating through thousands of items on long lists.
    final innerPosition = scrollable.position;
    final distance =
        (position.pixels - target).abs() +
        (controller == null
            ? 0
            : (innerPosition.pixels - innerPosition.minScrollExtent).abs());
    if (distance >= position.viewportDimension * 7) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
    showFab();
  }

  Widget _layout(Widget body, Widget? fab) {
    if (widget.layoutBuilder case final builder?) return builder(body, fab);
    if (fab == null) return body;
    return Stack(
      children: [
        body,
        Positioned(right: 0, bottom: 0, child: fab),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (context.dependOnInheritedWidgetOfExactType<_BackToTopScope>() != null) {
      return _layout(widget.child, widget.fab);
    }
    final padding = MediaQuery.viewPaddingOf(context);
    final bottomInset =
        context.dependOnInheritedWidgetOfExactType<BackToTopInset>()?.bottom ??
        0.0;
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final body = _BackToTopScope(
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: _onMetrics,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
      ),
    );
    return _layout(
      body,
      ValueListenableBuilder(
        valueListenable: _canScroll,
        child: widget.fab,
        builder: (context, canScroll, fab) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (canScroll && !keyboardVisible)
              ClipRect(
                child: SlideTransition(
                  position: fabAnimation,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: kFloatingActionButtonMargin,
                      top: kFloatingActionButtonMargin,
                      right: kFloatingActionButtonMargin + padding.right,
                      bottom:
                          kFloatingActionButtonMargin +
                          (fab == null ? padding.bottom + bottomInset : 0),
                    ),
                    child: FloatingActionButton(
                      heroTag: null,
                      tooltip: '回到顶部',
                      onPressed: _toTop,
                      child: const Icon(Icons.vertical_align_top),
                    ),
                  ),
                ),
              ),
            ?fab,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _canScroll.dispose();
    _activeScrollable = null;
    _scrollables.clear();
    super.dispose();
  }
}

class _BackToTopScope extends InheritedWidget {
  const _BackToTopScope({required super.child});

  @override
  bool updateShouldNotify(_BackToTopScope oldWidget) => false;
}

class BackToTopInset extends InheritedWidget {
  const BackToTopInset({super.key, required this.bottom, required super.child});

  final double bottom;

  @override
  bool updateShouldNotify(BackToTopInset oldWidget) =>
      bottom != oldWidget.bottom;
}
