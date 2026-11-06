import 'dart:async';

import 'package:PiliPlus/pages/video/widgets/player_focus.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/plugin/pl_player/models/shortcut_action.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:media_kit/media_kit.dart';

class _Settings extends Fake implements Box<dynamic> {
  final data = <dynamic, dynamic>{};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => data[key] ?? defaultValue;
}

class _Player extends Fake implements Player {}

class _Controller extends Fake implements PlPlayerController {
  @override
  final bool isLive;

  _Controller({this.isLive = false});

  @override
  final Player videoPlayerController = _Player();

  @override
  Timer? longPressTimer;

  int backwardTicks = 0, backwardEnds = 0;

  @override
  void multiBackwardStart([dynamic timer]) => backwardTicks++;

  @override
  void multiBackwardEnd() => backwardEnds++;

  @override
  void cancelLongPressTimer() {
    longPressTimer?.cancel();
    longPressTimer = null;
  }
}

Future<void> _mount(WidgetTester tester, _Controller controller) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: PlayerFocus(
        plPlayerController: controller,
        onSendDanmaku: () {},
        child: const SizedBox(),
      ),
    ),
  );
  await tester.pump();
  addTearDown(controller.cancelLongPressTimer);
}

void main() {
  final settings = _Settings();
  setUpAll(() => GStorage.setting = settings);
  setUp(settings.data.clear);

  testWidgets('a short backward press seeks once on release', (tester) async {
    final controller = _Controller();
    await _mount(tester, controller);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(controller.backwardTicks, 0);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.backwardEnds, 1);
    expect(controller.longPressTimer, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.backwardTicks, 0);
  });

  testWidgets('a custom backward binding repeats and stops on release', (
    tester,
  ) async {
    settings.data[SettingBoxKey.customKeyBindings] = {
      ShortcutAction.seekBackward.name: const KeyBinding(
        LogicalKeyboardKey.keyB,
      ).toJson(),
    };
    final controller = _Controller();
    await _mount(tester, controller);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.backwardTicks, 0);
    expect(controller.backwardEnds, 0);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
    await tester.pump(const Duration(milliseconds: 650));
    expect(controller.backwardTicks, 3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
    expect(controller.backwardEnds, 1);
    expect(controller.longPressTimer, isNull);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.backwardTicks, 3);
  });

  testWidgets('live playback does not start a backward hold', (tester) async {
    final controller = _Controller(isLive: true);
    await _mount(tester, controller);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
    expect(controller.backwardTicks, 0);
    expect(controller.backwardEnds, 0);
    expect(controller.longPressTimer, isNull);
  });
}
