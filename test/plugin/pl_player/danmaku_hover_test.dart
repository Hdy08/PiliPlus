import 'package:PiliPlus/common/widgets/marquee.dart';
import 'package:PiliPlus/common/widgets/player_bar.dart';
import 'package:PiliPlus/common/widgets/progress_bar/audio_video_progress_bar.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/danmaku_hover_exclusions.dart';
import 'package:PiliPlus/plugin/pl_player/widgets/danmaku_hover_region.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _Danmaku extends Fake implements DanmakuController<int> {
  _Danmaku() {
    add(20);
  }
  final items = <(double, DanmakuItem<int>)>[];
  Offset? query;

  DanmakuItem<int> add(double y, {int? extra = 1}) {
    final item = DanmakuItem<int>(
      content: DanmakuContentItem('test', extra: extra),
      width: 600,
      height: 20,
    );
    items.add((y, item));
    return item;
  }

  @override
  (double, DanmakuItem<int>)? Function(Offset) get findSingleDanmaku =>
      (point) {
        query = point;
        for (final (y, item) in items) {
          if (Rect.fromLTWH(
            item.xPosition,
            y,
            item.width,
            item.height,
          ).contains(point)) {
            return (y, item);
          }
        }
        return null;
      };
}

// The playback clock is a painted leaf, rather than a RenderParagraph.
class _Clock extends LeafRenderObjectWidget {
  const _Clock();
  @override
  RenderObject createRenderObject(BuildContext context) => _ClockBox();
}

class _ClockBox extends RenderBox {
  @override
  bool get isRepaintBoundary => true;
  @override
  void performLayout() => size = constraints.constrain(const Size(80, 28));
  @override
  void paint(PaintingContext context, Offset offset) =>
      context.canvas.drawRect(offset & size, Paint());
}

class _Scene {
  final fake = _Danmaku(), changes = ChangeNotifier();
  final player = GlobalKey(), content = GlobalKey(), video = GlobalKey();
  final header = GlobalKey(), footer = GlobalKey(), track = GlobalKey();
  final lock = GlobalKey(), shot = GlobalKey(), bubble = GlobalKey();
  DanmakuController<int>? source;
  Widget? screen;
  bool enabled = true, visible = true, targetVisible = true;
  bool preview = false;
  double slide = 0, gap = 28;
  Size size = const Size(600, 300);
  Offset padding = Offset.zero;
  DanmakuActionPosition? placement;
  VoidCallback? dismiss;
  int taps = 0, actions = 0, measurements = 0, builds = 0;
  double get y => fake.items.first.$1;
  set y(double value) => fake.items[0] = (value, fake.items.first.$2);
  DanmakuItem<int> get item => fake.items.first.$2;
  RenderBox get box => player.currentContext!.findRenderObject()! as RenderBox;

  DanmakuHoverAreas areas(RenderBox surface, {bool forAction = false}) {
    measurements++;
    return danmakuHoverExclusions(
      surface: surface,
      content: content.currentContext?.findRenderObject(),
      video: video.currentContext?.findRenderObject(),
      header: header.currentContext?.findRenderObject(),
      footer: footer.currentContext?.findRenderObject(),
      controlsVisible: forAction ? targetVisible : null,
      sideControls: {
        lock.currentContext?.findRenderObject(): true,
        shot.currentContext?.findRenderObject(): false,
      },
    );
  }

  Widget button(double width, [Key? key]) => SizedBox(
    width: width,
    height: 30,
    child: GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => taps++,
      child: const Text('button'),
    ),
  );

  Widget bar(bool top, Widget child) => Positioned(
    top: top ? 0 : null,
    bottom: top ? null : 0,
    left: 0,
    right: 0,
    child: Offstage(
      offstage: !visible,
      child: FractionalTranslation(
        key: top ? header : footer,
        translation: Offset(0, top ? slide : -slide * 1.2),
        child: Container(
          color: const Color(0x88000000),
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    ),
  );

  Widget build() => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox.fromSize(
        key: player,
        size: size,
        child: DanmakuHoverRegion<int>(
          enabled: enabled,
          controller: () => source ?? fake,
          size: size,
          danmakuOrigin: padding,
          exclusionAreas: areas,
          layoutChanges: changes,
          actionBuilder: (_, y, anchor, key, close, obstacles) {
            builds++;
            dismiss = close;
            final p = placement = avoidDanmakuControls(
              desktopDanmakuActionPosition(
                Offset(anchor.dx, y + gap),
                size,
                const Size(120, 30),
                aboveTop: y - 38,
                obstacles: obstacles,
              ),
              size,
              const Size(120, 30),
              obstacles,
            );
            if (p == null) return const SizedBox.shrink();
            return Positioned(
              right: p.right,
              top: p.top,
              child: SizedBox(
                key: key,
                width: 120,
                height: 30,
                child: GestureDetector(
                  key: bubble,
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    actions++;
                    close();
                  },
                  child: const Text('actions'),
                ),
              ),
            );
          },
          child: Stack(
            key: content,
            children: [
              Positioned.fill(
                child: ColoredBox(
                  key: video,
                  color: const Color(0xff000000),
                  child: screen ?? const Text('subtitle'),
                ),
              ),
              bar(
                true,
                Row(
                  children: [
                    button(70),
                    const Expanded(child: MarqueeText('title')),
                    button(80),
                  ],
                ),
              ),
              bar(
                false,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProgressBar(
                      key: track,
                      progress: 0,
                      total: 100,
                      baseBarColor: const Color(0xff444444),
                      progressBarColor: const Color(0xffffffff),
                      bufferedBarColor: const Color(0xff888888),
                      thumbColor: const Color(0xffffffff),
                      thumbGlowColor: const Color(0xffaaaaaa),
                      onDragStart: (_) {},
                      onSeek: (_) => taps++,
                    ),
                    const SizedBox(height: 10),
                    PlayerBar(
                      left: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [button(90), const _Clock()],
                      ),
                      right: button(100),
                    ),
                  ],
                ),
              ),
              if (visible)
                for (final (left, key) in [(true, lock), (false, shot)])
                  Positioned(
                    left: left ? 16 : null,
                    right: left ? null : 16,
                    top: 130,
                    child: button(30, key),
                  ),
              if (preview)
                const Positioned(
                  left: 240,
                  bottom: 65,
                  child: IgnorePointer(child: Text('hover preview')),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Offset origin(WidgetTester t) => t.getTopLeft(find.byKey(player));
  Rect rect(WidgetTester t, Key key) =>
      t.getRect(find.byKey(key)).shift(-origin(t));
  Future<void> pump(WidgetTester t) => t.pumpWidget(build());
  Future<void> move(
    WidgetTester t,
    TestGesture mouse,
    Offset point, {
    int dwellMs = 200,
  }) async {
    await mouse.moveTo(origin(t) + point);
    await t.pump(Duration(milliseconds: dwellMs));
  }

  Future<void> click(WidgetTester t, TestGesture mouse, Offset point) async {
    await move(t, mouse, point);
    await mouse.down(origin(t) + point);
    await mouse.up();
    await t.pump();
  }
}

Future<(_Scene, TestGesture)> _mount(
  WidgetTester t, {
  bool real = false,
}) async {
  final s = _Scene();
  if (real) {
    s.visible = false;
    s.screen = DanmakuScreen<int>(
      size: s.size,
      option: const DanmakuOption(duration: 10, fontSize: 18),
      createdController: (controller) => s.source = controller,
    );
  }
  await s.pump(t);
  final mouse = await t.createGesture(kind: PointerDeviceKind.mouse);
  await mouse.addPointer(location: Offset.zero);
  return (s, mouse);
}

void main() {
  testWidgets('requires 200ms on the same item before pausing', (t) async {
    final (s, mouse) = await _mount(t);
    final second = s.fake.add(90);
    await s.move(t, mouse, const Offset(300, 30), dwellMs: 199);
    expect(s.item.suspend, isFalse);
    expect(find.byKey(s.bubble), findsNothing);
    await s.move(t, mouse, const Offset(350, 30), dwellMs: 1);
    expect(s.item.suspend, isTrue);
    expect(find.byKey(s.bubble), findsOneWidget);

    await s.move(t, mouse, const Offset(300, 200));
    await s.move(t, mouse, const Offset(300, 30), dwellMs: 150);
    await s.move(t, mouse, const Offset(300, 100), dwellMs: 199);
    expect((s.item.suspend, second.suspend), (false, false));
    expect(find.byKey(s.bubble), findsNothing);
    await t.pump(const Duration(milliseconds: 1));
    expect(second.suspend, isTrue);

    await s.move(t, mouse, const Offset(300, 200));
    await s.move(t, mouse, const Offset(300, 30), dwellMs: 150);
    s.item.xPosition = 400;
    await t.pump(const Duration(milliseconds: 50));
    expect(s.item.suspend, isFalse);
    expect(find.byKey(s.bubble), findsNothing);

    s.item.xPosition = 0;
    await s.move(t, mouse, const Offset(300, 31), dwellMs: 0);
    await mouse.removePointer();
    await t.pump(const Duration(milliseconds: 200));
    expect(s.item.suspend, isFalse);
    expect(find.byKey(s.bubble), findsNothing);
  });

  testWidgets('delays leaving, cancels on return and releases exclusions', (
    t,
  ) async {
    final (s, mouse) = await _mount(t);
    const start = Offset(300, 30), outside = Offset(300, 180);
    await s.move(t, mouse, start);
    await s.move(t, mouse, outside, dwellMs: 100);
    s.changes.notifyListeners();
    await t.pump();
    await s.move(t, mouse, outside + const Offset(10, 0), dwellMs: 99);
    expect(s.item.suspend, isTrue);
    expect(find.byKey(s.bubble), findsOneWidget);
    await t.pump(const Duration(milliseconds: 1));
    expect(s.item.suspend, isFalse);
    expect(find.byKey(s.bubble), findsNothing);

    await s.move(t, mouse, start);
    for (final back in [start, s.rect(t, s.bubble).center]) {
      await s.move(t, mouse, outside, dwellMs: 199);
      await s.move(t, mouse, back, dwellMs: 1);
      await t.pump(const Duration(milliseconds: 200));
      expect(s.item.suspend, isTrue);
    }
    final second = s.fake.add(90), bubble = s.rect(t, s.bubble);
    await s.move(t, mouse, const Offset(300, 100), dwellMs: 199);
    expect((s.item.suspend, second.suspend), (true, false));
    expect(s.rect(t, s.bubble), bubble);
    await t.pump(const Duration(milliseconds: 1));
    expect((s.item.suspend, second.suspend), (false, true));

    await s.move(t, mouse, start);
    await s.move(t, mouse, const Offset(-10, -10), dwellMs: 199);
    expect(s.item.suspend, isTrue);
    await t.pump(const Duration(milliseconds: 1));
    expect(s.item.suspend, isFalse);
    for (final excluded in [
      const Offset(20, 30),
      const Offset(20, 140),
    ]) {
      await s.move(t, mouse, start);
      await s.move(t, mouse, outside, dwellMs: 100);
      await s.move(t, mouse, excluded, dwellMs: 0);
      expect(s.item.suspend, isFalse);
      expect(find.byKey(s.bubble), findsNothing);
    }
    s
      ..y = 195
      ..gap = 65;
    await s.pump(t);
    final track = s.rect(t, s.track);
    for (final progress in [
      track.center,
      track.centerRight - const Offset(20, 0),
    ]) {
      await s.move(t, mouse, const Offset(300, 205));
      await s.move(t, mouse, progress, dwellMs: 199);
      expect(s.item.suspend, isTrue);
      await s.move(t, mouse, s.rect(t, s.bubble).center, dwellMs: 1);
      await t.pump(const Duration(milliseconds: 200));
      expect(s.item.suspend, isTrue);
      await s.move(t, mouse, progress, dwellMs: 199);
      expect(s.item.suspend, isTrue);
      await t.pump(const Duration(milliseconds: 1));
      expect(s.item.suspend, isFalse);
      expect(find.byKey(s.bubble), findsNothing);
    }
    await mouse.removePointer();
  });

  testWidgets('skips empty video and reuses unchanged geometry', (t) async {
    final (s, mouse) = await _mount(t);
    for (var x = 250.0; x < 350; x++) {
      await mouse.moveTo(s.origin(t) + Offset(x, 200));
    }
    expect((s.measurements, s.builds), (0, 0));
    for (var x = 250.0; x < 350; x++) {
      await mouse.moveTo(s.origin(t) + Offset(x, 30));
    }
    expect((s.measurements, s.builds), (1, 0));
    await t.pump(const Duration(milliseconds: 200));
    final builds = s.builds;
    expect(builds, greaterThan(0));
    for (var i = 0; i < 3; i++) {
      s.changes.notifyListeners();
      await t.pump(const Duration(milliseconds: 16));
      await t.pump();
    }
    expect(s.builds, builds);
    await mouse.removePointer();
    await t.pump(const Duration(milliseconds: 200));
  });

  test('positions and tips respect edges and obstacles', () {
    const bubble = Size(120, 30);
    for (final width in [360.0, 600.0]) {
      final player = Size(width, 300);
      for (final x in [30.0, width / 2, width - 30]) {
        final edge = desktopDanmakuActionPosition(
          Offset(x, 80),
          player,
          bubble,
          aboveTop: 42,
        );
        final left = width - edge.right - bubble.width;
        expect(left, greaterThanOrEqualTo(8));
        expect(edge.right, greaterThanOrEqualTo(8));
        expect(left + 60 + edge.triangleOffset, x);
        expect(avoidDanmakuControls(edge, player, bubble, const []), edge);
        final obstacle = Rect.fromLTWH(left, 70, 30, 60);
        final p = avoidDanmakuControls(edge, player, bubble, [obstacle])!;
        final bounds = Offset(width - p.right - 120, p.top) & bubble;
        expect(bounds.overlaps(obstacle), isFalse);
        expect(bounds.center.dx + p.triangleOffset, x);
        expect(p.top, edge.top);
        expect(
          avoidDanmakuControls(edge, player, bubble, [Offset.zero & player]),
          isNull,
        );
      }
    }
    final up = desktopDanmakuActionPosition(
      const Offset(300, 298),
      const Size(600, 300),
      bubble,
      aboveTop: 232,
    );
    expect((up.above, up.top), (true, 232));
    final blocked = desktopDanmakuActionPosition(
      const Offset(300, 218),
      const Size(600, 300),
      bubble,
      aboveTop: 160,
      obstacles: [const Rect.fromLTWH(200, 210, 200, 60)],
    );
    expect((blocked.above, blocked.top), (true, 160));
  });

  testWidgets('measures content, excluding bar backgrounds', (t) async {
    final (s, mouse) = await _mount(t);
    for (final width in [600.0, 360.0]) {
      s.size = Size(width, 300);
      await s.pump(t);
      final areas = s.areas(s.box);
      for (final point in [
        const Offset(1, 1),
        Offset(width - 1, 1),
        const Offset(150, 280),
        Offset(width - 1, 299),
        const Offset(1, 140),
        Offset(width - 1, 140),
      ]) {
        expect(areas.controls.any((r) => r.contains(point)), isTrue);
      }
      for (final point in [
        Offset(width / 2, 20),
        Offset(width * .6, 280),
        Offset(width / 2, 140),
      ]) {
        expect(areas.all.any((r) => r.contains(point)), isFalse);
      }
      final track = s.rect(t, s.track);
      expect(areas.progress, [track]);
      expect(areas.obstacles, isNot(contains(track)));
      expect(
        areas.all.every((r) => r.intersect(Offset.zero & s.size) == r),
        isTrue,
      );
    }
    s.visible = false;
    await s.pump(t);
    expect(s.areas(s.box).all, isEmpty);
    await mouse.removePointer();
  });

  testWidgets('keeps corner and side controls usable', (t) async {
    final (s, mouse) = await _mount(t);
    for (final (y, edgeY, tapY) in [
      (0.0, 1.0, 25.0),
      (100.0, 140.0, 140.0),
      (270.0, 299.0, 280.0),
    ]) {
      for (final left in [true, false]) {
        await s.move(t, mouse, const Offset(-10, -10));
        s.y = y;
        final controls = s.areas(s.box).controls;
        final control = controls.firstWhere(
          (r) => r.contains(Offset(left ? 1 : 599, edgeY)),
        );
        final x = left ? control.right + 10 : control.left - 10;
        await s.move(t, mouse, Offset(x, s.y + 10));
        final bubble = s.rect(t, s.bubble);
        expect(controls.any(bubble.overlaps), isFalse);
        expect(bubble.center.dx + s.placement!.triangleOffset, x);
        await s.move(t, mouse, bubble.center);
        expect(s.item.suspend, isTrue);
        await s.click(t, mouse, Offset(left ? 25 : 575, tapY));
        expect(s.item.suspend, isFalse);
      }
    }
    expect(s.taps, 6);
    await mouse.removePointer();
  });

  testWidgets(
    'uses animation destinations and rechecks hover',
    (t) async {
      final (s, mouse) = await _mount(t);
      s
        ..y = 0
        ..slide = -1;
      await s.pump(t);
      final corner = s
          .areas(s.box, forAction: true)
          .controls
          .firstWhere((r) => r.contains(Offset.zero));
      final x = corner.right + 10;
      await s.move(t, mouse, Offset(x, 10));
      final shown = s.rect(t, s.bubble);
      for (final slide in [-1.0, -.4, 0.0]) {
        s.slide = slide;
        await s.pump(t);
        s.changes.notifyListeners();
        await t.pump();
        await t.pump();
        expect(s.rect(t, s.bubble), shown);
      }
      s.targetVisible = false;
      await s.pump(t);
      final hidden = s.rect(t, s.bubble);
      expect(hidden.top, shown.top);
      expect(hidden.left, x - 60);
      s.slide = -1;
      await s.pump(t);
      expect(s.rect(t, s.bubble), hidden);
      await s.move(t, mouse, const Offset(20, 10));
      s
        ..targetVisible = true
        ..slide = 0;
      await s.pump(t);
      s.changes.notifyListeners();
      await t.pump();
      await t.pump();
      expect(s.item.suspend, isFalse);
      await mouse.removePointer();
    },
  );

  testWidgets('crosses progress to reach bubbles above or below', (
    t,
  ) async {
    final (s, mouse) = await _mount(t);
    for (final (y, gap, x) in [
      (195.0, 65.0, 300.0),
      (210.0, 28.0, 300.0),
      (210.0, 28.0, 100.0),
      (270.0, 28.0, 300.0),
    ]) {
      s
        ..y = y
        ..gap = gap
        ..preview = y == 195;
      await s.pump(t);
      final track = s.rect(t, s.track);
      await s.move(t, mouse, track.center);
      expect(s.item.suspend, isFalse);
      final start = Offset(x, y + 10);
      await s.move(t, mouse, start);
      final bubble = s.rect(t, s.bubble);
      expect(s.placement!.above, y == 270 || x == 100);
      if (y == 210 && x == 300) expect(bubble.overlaps(track), isTrue);
      final target = y == 210 && x == 300
          ? bubble.intersect(track).center
          : bubble.center;
      for (final f in [.25, .5, .75, 1.0]) {
        await s.move(
          t,
          mouse,
          Offset.lerp(start, target, f)!,
          dwellMs: 40,
        );
        expect(s.item.suspend, isTrue);
      }
      await s.click(t, mouse, target);
      expect(s.item.suspend, isFalse);
    }
    expect((s.actions, s.taps), (4, 0));
    await s.click(
      t,
      mouse,
      s.rect(t, s.track).centerRight - const Offset(20, 0),
    );
    expect(s.taps, 1);
    await mouse.removePointer();
  });

  testWidgets(
    'isolates touch, selection and async actions',
    (t) async {
      final (s, mouse) = await _mount(t);
      final second = s.fake.add(90), noActions = s.fake.add(150, extra: null);
      s
        ..padding = const Offset(0, 4)
        ..y = 0;
      await s.pump(t);
      await t.tapAt(s.origin(t) + const Offset(300, 14));
      await s.move(t, mouse, const Offset(300, 1));
      expect((s.item.suspend, s.fake.query), (false, null));
      s.y = 20;
      await s.move(t, mouse, const Offset(300, 34));
      final bubble = s.rect(t, s.bubble), oldDismiss = s.dismiss!;
      expect(s.fake.query, const Offset(300, 30));
      expect((s.item.suspend, second.suspend), (true, false));
      await s.move(t, mouse, const Offset(350, 34));
      expect(s.rect(t, s.bubble), bubble);
      await s.move(t, mouse, const Offset(300, 104));
      oldDismiss();
      await t.pump();
      expect((s.item.suspend, second.suspend), (false, true));
      await s.move(t, mouse, const Offset(300, 154));
      expect((second.suspend, noActions.suspend), (false, false));
      expect(find.byKey(s.bubble), findsNothing);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'releases selection on every lifecycle change',
    (t) async {
      for (final dwellMs in [0, 200]) {
        for (final reset in [
          'exit',
          'disable',
          'resize',
          'source',
          'dispose',
        ]) {
          final (s, mouse) = await _mount(t);
          await s.move(t, mouse, const Offset(300, 30), dwellMs: dwellMs);
          expect(s.item.suspend, dwellMs != 0);
          if (dwellMs != 0) {
            await s.move(t, mouse, const Offset(300, 180), dwellMs: 0);
          }
          switch (reset) {
            case 'exit':
              await s.move(t, mouse, const Offset(-10, -10));
            case 'disable':
              s.enabled = false;
            case 'resize':
              s.size = const Size(500, 300);
            case 'source':
              s.source = _Danmaku();
          }
          await t.pumpWidget(reset == 'dispose' ? const SizedBox() : s.build());
          await t.pump(const Duration(milliseconds: 200));
          expect(s.item.suspend, isFalse, reason: reset);
          expect(find.byKey(s.bubble), findsNothing);
          await mouse.removePointer();
        }
      }
    },
  );

  testWidgets(
    'pauses and resumes only the hovered item',
    (t) async {
      final (s, mouse) = await _mount(t, real: true);
      final controller = s.source!;
      controller.addDanmaku(DanmakuContentItem('first', extra: 1));
      controller.addDanmaku(DanmakuContentItem('second', extra: 2));
      await t.pump();
      await t.pump(const Duration(milliseconds: 16));
      await t.pump(const Duration(seconds: 3));
      final items = controller.scrollDanmaku.expand((track) => track).toList();
      expect(items, hasLength(2));
      final first = items[0], second = items[1];
      await s.move(t, mouse, Offset(first.xPosition + 10, 10));
      final x = first.xPosition, otherX = second.xPosition;
      await t.pump(const Duration(milliseconds: 500));
      expect(
        (first.suspend, first.xPosition, controller.running),
        (true, x, true),
      );
      expect(second.xPosition, lessThan(otherX));
      await s.move(t, mouse, const Offset(300, 200));
      await t.pump(const Duration(milliseconds: 500));
      expect(first.suspend, isFalse);
      expect(first.xPosition, lessThan(x));
      await mouse.removePointer();
      await t.pumpWidget(const SizedBox());
    },
  );
}
