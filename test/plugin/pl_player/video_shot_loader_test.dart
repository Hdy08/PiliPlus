import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_shot/data.dart';
import 'package:PiliPlus/plugin/pl_player/utils/video_shot_loader.dart';
import 'package:flutter_test/flutter_test.dart';

VideoShotData _data({bool emptyIndex = false, bool emptyImages = false}) =>
    VideoShotData(
      imgXLen: 10,
      imgYLen: 10,
      imgXSize: 480,
      imgYSize: 270,
      image: emptyImages ? [] : ['https://example.com/sheet.jpg'],
      index: emptyIndex ? [] : [0, 0, 5, 11],
    );

class _Requests {
  _Requests(WidgetTester tester) {
    loader = VideoShotLoader(
      fetch: () {
        final request = Completer<LoadingState<VideoShotData>>();
        requests.add(request);
        return request.future;
      },
      isActive: () => active,
      onLoaded: () => loaded++,
      now: tester.binding.clock.now,
    );
  }

  bool active = true;
  int loaded = 0;
  final requests = <Completer<LoadingState<VideoShotData>>>[];
  late final VideoShotLoader loader;
}

void main() {
  testWidgets('temporary empty metadata recovers without moving or reopening', (
    tester,
  ) async {
    for (final failure in <LoadingState<VideoShotData>>[
      const Error('视频无截图', code: 10008),
      const Error(null),
      Success(_data(emptyIndex: true)),
      Success(_data(emptyImages: true)),
    ]) {
      final r = _Requests(tester);
      r.loader.load();
      r.requests.single.complete(failure);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(r.requests, hasLength(2));
      r.requests.last.complete(Success(_data()));
      await tester.pump();
      expect(r.loader.state, isA<Success<VideoShotData>>());
      expect(r.loaded, 1);
      r.loader.load();
      expect(r.requests, hasLength(2));
      r.loader.clear();
    }
  });

  testWidgets(
    'mouse movement shares requests and cannot bypass retry backoff',
    (
      tester,
    ) async {
      final r = _Requests(tester);
      for (var i = 0; i < 100; i++) {
        r.loader.load();
      }
      expect(r.requests, hasLength(1));
      r.requests.single.completeError(StateError('temporary parse failure'));
      await tester.pump();
      for (var i = 0; i < 100; i++) {
        r.loader.load();
      }
      expect(r.requests, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(r.requests, hasLength(2));
      r.loader.clear();
    },
  );

  testWidgets('retry budget is finite and later interaction can recover', (
    tester,
  ) async {
    final r = _Requests(tester);
    r.loader.load();
    r.requests.last.complete(const Error(null));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    r.requests.last.complete(const Error(null));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    r.requests.last.complete(const Error(null));
    await tester.pump();
    expect(r.requests, hasLength(3));
    r.loader.load();
    expect(r.requests, hasLength(3));
    await tester.pump(const Duration(minutes: 1));
    expect(r.requests, hasLength(3));
    r.loader.load();
    expect(r.requests, hasLength(4));
    r.requests.last.complete(Success(_data()));
    await tester.pump();
    expect(r.loaded, 1);
    r.loader.clear();
  });

  testWidgets('leaving cancels retries and returning reuses the same loader', (
    tester,
  ) async {
    final r = _Requests(tester);
    r.loader.load();
    r.requests.single.complete(const Error(null));
    await tester.pump();
    r.active = false;
    r.loader.stopRetry();
    await tester.pump(const Duration(seconds: 5));
    expect(r.requests, hasLength(1));
    r.active = true;
    r.loader.load();
    expect(r.requests, hasLength(2));
    r.requests.last.complete(Success(_data()));
    await tester.pump();
    expect(r.loaded, 1);
    r.loader.clear();
  });

  testWidgets('late metadata and retries cannot affect a new video', (
    tester,
  ) async {
    final r = _Requests(tester);
    r.loader.load();
    r.loader.clear();
    r.loader.load();
    final current = _data();
    r.requests.last.complete(Success(current));
    await tester.pump();
    r.requests.first.complete(const Error(null));
    await tester.pump(const Duration(seconds: 10));
    expect(r.loader.state?.data, same(current));
    expect(r.requests, hasLength(2));
    expect(r.loaded, 1);
    r.loader.clear();
  });
}
