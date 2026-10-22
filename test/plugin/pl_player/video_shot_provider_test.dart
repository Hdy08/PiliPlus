import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/cropped_image.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _url =
    'https://bimp.hdslb.com/videoshotpvhdboss/29396437498_s792xb-0001.jpg';

class _Cache extends Fake implements BaseCacheManager {
  _Cache(this.good, [this.bad]);

  final File good;
  File? bad;
  int loads = 0;
  int removals = 0;

  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) async* {
    expect(url, _url);
    loads++;
    yield FileInfo(
      bad ?? good,
      FileSource.Cache,
      DateTime.now().add(const Duration(days: 1)),
      url,
    );
  }

  @override
  Future<void> removeFile(String key) async {
    expect(key, _url);
    removals++;
    bad = null;
  }
}

Widget _preview(_Cache cache, {int x = 0, void Function(Object)? onError}) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: VideoShotImage(
          image: CachedNetworkImageProvider(
            _url,
            cacheManager: cache,
            errorListener: onError,
          ),
          x: x,
          y: 1,
          columns: 10,
          rows: 10,
          height: 81,
          onRetry: () => cache.removeFile(_url),
        ),
      ),
    );

Future<void> _waitFor(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (ready()) return;
  }
  fail('Image stream did not finish');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File good, bad;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('piliplus-video-shot-');
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(const Color(0xFFFFFFFF), BlendMode.src);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4800, 2700);
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    good = await File('${directory.path}/good.png').writeAsBytes(
      bytes!.buffer.asUint8List(),
    );
    bad = await File('${directory.path}/bad.jpg')
        .writeAsString('truncated image');
  });

  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  });
  tearDownAll(() => directory.delete(recursive: true));

  testWidgets(
    'real provider bounds large-sheet decode and reuses it across tiles',
    (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = _Cache(good);
      await tester.pumpWidget(_preview(cache));
      await _waitFor(
        tester,
        () => find.byType(CroppedImage).evaluate().isNotEmpty,
      );
      final crop = tester.widget<CroppedImage>(find.byType(CroppedImage));
      expect(crop.image.width, 1920);
      expect(crop.image.height, 1080);
      expect(crop.srcRect, const Rect.fromLTWH(0, 108, 192, 108));
      expect(crop.size, const Size(144, 81));
      for (var x = 0; x < 10; x++) {
        await tester.pumpWidget(_preview(cache, x: x));
      }
      expect(cache.loads, 1);
      expect(cache.removals, 0);
    },
  );

  testWidgets(
    'a bad disk cache entry is removed before retrying the real decoder',
    (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final cache = _Cache(good, bad);
      var errors = 0;
      await tester.pumpWidget(_preview(cache, onError: (_) => errors++));
      await _waitFor(tester, () => errors == 1);
      expect(find.byType(CroppedImage), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
      await _waitFor(
        tester,
        () => find.byType(CroppedImage).evaluate().isNotEmpty,
      );
      expect(cache.loads, 2);
      expect(cache.removals, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
