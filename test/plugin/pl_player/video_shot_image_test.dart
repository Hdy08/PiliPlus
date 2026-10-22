import 'dart:async';
import 'dart:ui' as ui;

import 'package:PiliPlus/common/widgets/cropped_image.dart';
import 'package:PiliPlus/plugin/pl_player/view/view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

class _DeferredImage extends ImageProvider<_DeferredImage> {
  Completer<ui.Image> result = Completer<ui.Image>();
  int loads = 0;

  @override
  Future<_DeferredImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DeferredImage key,
    ImageDecoderCallback decode,
  ) {
    loads++;
    return OneFrameImageStreamCompleter(
      result.future.then(
        (image) => ImageInfo(image: image.clone()),
        onError: (Object error, StackTrace stack) {
          // Network image providers evict failed pending entries before retry.
          scheduleMicrotask(
            () => PaintingBinding.instance.imageCache.evict(key),
          );
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
  }
}

Widget _preview(
  _DeferredImage image, {
  int x = 0,
  int y = 0,
  double height = 90,
  AsyncCallback? onRetry,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: VideoShotImage(
      image: image,
      x: x,
      y: y,
      columns: 3,
      rows: 2,
      height: height,
      onRetry: onRetry,
    ),
  ),
);

void main() {
  late ui.Image sheet;
  setUp(() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 120, 60),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    sheet = picture.toImageSync(120, 60);
    picture.dispose();
  });

  tearDown(() {
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
    sheet.dispose();
  });

  testWidgets('reopening a pending preview shares its load and receives it', (
    tester,
  ) async {
    final image = _DeferredImage();
    await tester.pumpWidget(_preview(image));
    expect(image.loads, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_preview(image, x: 2, y: 1));
    expect(image.loads, 1);
    image.result.complete(sheet);
    await tester.pumpAndSettle();

    var crop = tester.widget<CroppedImage>(find.byType(CroppedImage));
    expect(crop.srcRect, const Rect.fromLTWH(80, 30, 40, 30));
    expect(crop.size, const Size(120, 90));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_preview(image));
    expect(find.byType(CroppedImage), findsOneWidget);
    expect(image.loads, 1);

    await tester.pumpWidget(_preview(image, x: 1, height: 108));
    crop = tester.widget<CroppedImage>(find.byType(CroppedImage));
    expect(crop.srcRect, const Rect.fromLTWH(40, 0, 40, 30));
    expect(crop.size, const Size(144, 108));
    expect(image.loads, 1);
  });

  testWidgets('an older sheet cannot replace the latest requested sheet', (
    tester,
  ) async {
    final first = _DeferredImage(), second = _DeferredImage();
    await tester.pumpWidget(_preview(first));
    await tester.pumpWidget(_preview(second, x: 2));
    second.result.complete(sheet);
    await tester.pumpAndSettle();
    final current = tester
        .widget<CroppedImage>(find.byType(CroppedImage))
        .image;

    first.result.complete(sheet);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CroppedImage>(find.byType(CroppedImage)).image,
      same(current),
    );
    expect(first.loads, 1);
    expect(second.loads, 1);
  });

  testWidgets(
    'movement during loading uses the latest tile without reloading',
    (
      tester,
    ) async {
      final image = _DeferredImage();
      await tester.pumpWidget(_preview(image));
      for (var x = 0; x < 3; x++) {
        await tester.pumpWidget(_preview(image, x: x, y: 1));
      }
      image.result.complete(sheet);
      await tester.pumpAndSettle();
      expect(image.loads, 1);
      expect(
        tester.widget<CroppedImage>(find.byType(CroppedImage)).srcRect,
        const Rect.fromLTWH(80, 30, 40, 30),
      );
    },
  );

  testWidgets('a failed load is retried when reopening the preview', (
    tester,
  ) async {
    final image = _DeferredImage();
    await tester.pumpWidget(_preview(image));
    image.result.completeError(StateError('temporary download failure'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CroppedImage), findsNothing);

    image.result = Completer<ui.Image>();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_preview(image));
    expect(image.loads, 2);
    image.result.complete(sheet);
    await tester.pumpAndSettle();
    expect(find.byType(CroppedImage), findsOneWidget);
  });

  testWidgets('a stationary preview retries once and then stops on failure', (
    tester,
  ) async {
    final image = _DeferredImage();
    await tester.pumpWidget(_preview(image));
    image.result.completeError(StateError('temporary download failure'));
    await tester.pumpAndSettle();
    image.result = Completer<ui.Image>();
    await tester.pump(const Duration(milliseconds: 500));
    expect(image.loads, 2);

    image.result.completeError(StateError('CDN unavailable'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
    expect(image.loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a stationary preview appears when the automatic retry succeeds',
    (
      tester,
    ) async {
      final image = _DeferredImage();
      await tester.pumpWidget(_preview(image));
      image.result.completeError(StateError('temporary download failure'));
      await tester.pumpAndSettle();
      image.result = Completer<ui.Image>();
      await tester.pump(const Duration(milliseconds: 500));
      image.result.complete(sheet);
      await tester.pumpAndSettle();
      expect(image.loads, 2);
      expect(find.byType(CroppedImage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late result after disposal stays reusable without updating UI',
    (
      tester,
    ) async {
      final image = _DeferredImage();
      await tester.pumpWidget(_preview(image));
      await tester.pumpWidget(const SizedBox());
      image.result.complete(sheet);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CroppedImage), findsNothing);

      await tester.pumpWidget(_preview(image));
      expect(find.byType(CroppedImage), findsOneWidget);
      expect(image.loads, 1);
    },
  );

  testWidgets('an old cache repair cannot replace the next preview', (
    tester,
  ) async {
    final first = _DeferredImage(), second = _DeferredImage();
    final repair = Completer<void>();
    var repairs = 0;
    await tester.pumpWidget(
      _preview(
        first,
        onRetry: () {
          repairs++;
          return repair.future;
        },
      ),
    );
    first.result.completeError(StateError('bad cached image'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(repairs, 1);

    await tester.pumpWidget(_preview(second));
    second.result.complete(sheet);
    await tester.pumpAndSettle();
    final current = tester
        .widget<CroppedImage>(find.byType(CroppedImage))
        .image;
    repair.complete();
    await tester.pumpAndSettle();
    expect(
      tester.widget<CroppedImage>(find.byType(CroppedImage)).image,
      same(current),
    );
    expect(first.loads, 1);
    expect(second.loads, 1);
  });
}
