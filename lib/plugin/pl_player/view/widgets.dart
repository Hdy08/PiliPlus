part of 'view.dart';

class SeekPreviewLayout extends SingleChildLayoutDelegate {
  const SeekPreviewLayout(this.bar, this.fraction, this.obstructionHeight);

  final Rect bar;
  final double fraction;
  final double obstructionHeight;

  double _bottom(Size size) =>
      (math.min(bar.top, bar.bottom - obstructionHeight) - 8).clamp(
        0.0,
        size.height,
      );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0.0, constraints.maxWidth - 16),
        maxHeight: math.max(0.0, _bottom(constraints.biggest) - 8),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x =
        bar.left +
        1.75 +
        math.max(0.0, bar.width - 3.5) * fraction.clamp(0.0, 1.0);
    final margin = math.min(8.0, math.max(0.0, size.width - childSize.width));
    return Offset(
      (x - childSize.width / 2).clamp(
        margin,
        math.max(margin, size.width - childSize.width - 8),
      ),
      _bottom(size) - childSize.height,
    );
  }

  @override
  bool shouldRelayout(SeekPreviewLayout oldDelegate) =>
      bar != oldDelegate.bar ||
      fraction != oldDelegate.fraction ||
      obstructionHeight != oldDelegate.obstructionHeight;
}

double _dmChartBottomMargin(
  VideoDetailController controller,
  double offset,
) => controller.viewPointList.isNotEmpty && controller.showVP.value
    ? 19.25 + offset
    : 4.25 + offset;

Widget buildDmChart(
  Color color,
  List<double> dmTrend,
  VideoDetailController videoDetailController, [
  double offset = 0,
]) {
  return IgnorePointer(
    child: Container(
      height: 12,
      margin: EdgeInsets.only(
        bottom: _dmChartBottomMargin(videoDetailController, offset),
      ),
      child: LineChart(
        LineChartData(
          titlesData: const FlTitlesData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          minX: 0,
          maxX: (dmTrend.length - 1).toDouble(),
          minY: 0,
          maxY: dmTrend.max,
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                dmTrend.length,
                (index) => FlSpot(
                  index.toDouble(),
                  dmTrend[index],
                ),
              ),
              isCurved: true,
              barWidth: 1,
              color: color,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildSeekTime(int seconds, int duration) {
  const textStyle = TextStyle(color: Colors.white, fontSize: 12);
  return Container(
    decoration: const BoxDecoration(
      color: Color(0x88000000),
      borderRadius: BorderRadius.all(Radius.circular(64)),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Row(
      spacing: 2,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(DurationUtils.formatDuration(seconds), style: textStyle),
        const Text('/', style: textStyle),
        Text(DurationUtils.formatDuration(duration), style: textStyle),
      ],
    ),
  );
}

Widget buildSeekPreviewWidget(
  PlPlayerController plPlayerController,
  double maxWidth,
  double maxHeight, {
  bool centered = true,
}) {
  return Obx(
    () {
      if (!plPlayerController.showPreview.value) {
        return const SizedBox.shrink();
      }

      try {
        final data = plPlayerController.videoShot!.data;

        final double scale =
            plPlayerController.isFullScreen.value &&
                (PlatformUtils.isDesktop || !plPlayerController.isVertical)
            ? 4
            : 3;
        double height = 27 * scale;
        final compatHeight = maxHeight - 140;
        if (compatHeight > 50) {
          height = math.min(height, compatHeight);
        }

        final int imgXLen = data.imgXLen;
        final int imgYLen = data.imgYLen;
        final int totalPerImage = data.totalPerImage;

        return Align(
          alignment: Alignment.center,
          widthFactor: centered ? null : 1,
          heightFactor: centered ? null : 1,
          child: Obx(
            () {
              final index = plPlayerController.previewIndex.value!;
              int pageIndex = (index ~/ totalPerImage).clamp(
                0,
                data.image.length - 1,
              );
              int align = index % totalPerImage;
              int x = align % imgXLen;
              int y = align ~/ imgXLen;
              final url = data.image[pageIndex];

              return ClipRRect(
                borderRadius: Style.mdRadius,
                child: VideoShotImage(
                  image: CachedNetworkImageProvider(
                    url,
                    cacheManager: CacheManager.manager,
                    headers: Constants.baseHeaders,
                  ),
                  x: x,
                  y: y,
                  columns: imgXLen,
                  rows: imgYLen,
                  height: height,
                  onRetry: () => CacheManager.manager.removeFile(url),
                ),
              );
            },
          ),
        );
      } catch (e) {
        if (kDebugMode) rethrow;
        return const SizedBox.shrink();
      }
    },
  );
}

class VideoShotImage extends StatefulWidget {
  const VideoShotImage({
    super.key,
    required this.image,
    required this.x,
    required this.y,
    required this.columns,
    required this.rows,
    required this.height,
    this.onRetry,
  }) : assert(columns > 0 && rows > 0);

  final ImageProvider image;
  final int x;
  final int y;
  final int columns;
  final int rows;
  final double height;
  final AsyncCallback? onRetry;

  @override
  State<VideoShotImage> createState() => _VideoShotImageState();
}

class _VideoShotImageState extends State<VideoShotImage> {
  ImageStream? _stream;
  ImageProvider? _provider;
  ImageInfo? _imageInfo;
  Timer? _retryTimer;
  bool _retried = false;
  int _generation = 0;
  late final _listener = ImageStreamListener(
    (image, synchronousCall) {
      _retryTimer?.cancel();
      setState(() {
        _imageInfo?.dispose();
        _imageInfo = image;
      });
    },
    onError: (Object error, StackTrace? stack) {
      // One retry while visible; do not poll or keep retrying a broken CDN URL.
      if (_imageInfo == null && !_retried) {
        _retried = true;
        _retryTimer = Timer(
          const Duration(milliseconds: 500),
          _retry,
        );
      }
    },
    reportErrors: false,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  void _resolveImage() {
    // ImageCache shares pending loads and bounds decoded memory across previews.
    // Decode for the largest preview at this pixel density, rather than a 4K sheet.
    final provider = ResizeImage(
      widget.image,
      height: (108 * View.of(context).devicePixelRatio).ceil() * widget.rows,
      policy: ResizeImagePolicy.fit,
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (_stream?.key == stream.key) return;
    _generation++;
    _provider = provider;
    _stream?.removeListener(_listener);
    _imageInfo?.dispose();
    _imageInfo = null;
    _stream = stream..addListener(_listener);
  }

  Future<void> _retry() async {
    final generation = _generation;
    // A corrupt disk entry would otherwise fail on every retry and reopening.
    try {
      await widget.onRetry?.call();
    } catch (_) {}
    if (!mounted || generation != _generation || _imageInfo != null) return;
    await _provider?.evict();
    if (mounted && generation == _generation) setState(_resolveImage);
  }

  @override
  void didUpdateWidget(VideoShotImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image || oldWidget.rows != widget.rows) {
      _generation++;
      _retryTimer?.cancel();
      _retried = false;
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _generation++;
    _retryTimer?.cancel();
    _stream?.removeListener(_listener);
    _imageInfo?.dispose();
    super.dispose();
  }

  late final _imgPaint = Paint()..filterQuality = FilterQuality.medium;
  late final _borderPaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    if (_imageInfo case final imageInfo?) {
      final image = imageInfo.image;
      final tileWidth = image.width / widget.columns;
      final tileHeight = image.height / widget.rows;
      final size = Size(widget.height * tileWidth / tileHeight, widget.height);
      final dstRect = Offset.zero & size;
      return CroppedImage(
        size: size,
        image: image,
        srcRect: Rect.fromLTWH(
          widget.x * tileWidth,
          widget.y * tileHeight,
          tileWidth,
          tileHeight,
        ),
        dstRect: dstRect,
        rrect: RRect.fromRectAndRadius(dstRect, const Radius.circular(10)),
        imgPaint: _imgPaint,
        borderPaint: _borderPaint,
      );
    }
    return const SizedBox.shrink();
  }
}

const double _triangleHeight = 5.6;

class _DanmakuTip extends SingleChildRenderObjectWidget {
  const _DanmakuTip({
    super.key,
    this.offset = 0,
    this.above = false,
    super.child,
  });

  final double offset;
  final bool above;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderDanmakuTip(offset: offset, above: above);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderDanmakuTip renderObject,
  ) {
    renderObject
      ..offset = offset
      ..above = above;
  }
}

class _RenderDanmakuTip extends RenderProxyBox {
  _RenderDanmakuTip({
    required this._offset,
    required this._above,
  });

  bool _above;
  set above(bool value) {
    if (_above == value) return;
    _above = value;
    markNeedsPaint();
  }

  double _offset;
  double get offset => _offset;
  set offset(double value) {
    if (_offset == value) return;
    _offset = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final paint = Paint()
      ..color = const Color(0xB3000000)
      ..style = .fill;

    final radius = size.height / 2;
    const triangleBase = _triangleHeight * 2 / 3;

    final triangleCenterX = (size.width / 2 + _offset).clamp(
      radius + triangleBase,
      size.width - radius - triangleBase,
    );
    final path = Path()
      // triangle (exceed)
      ..moveTo(triangleCenterX - triangleBase, 0)
      ..lineTo(triangleCenterX, -_triangleHeight)
      ..lineTo(triangleCenterX + triangleBase, 0)
      // top
      ..lineTo(size.width - radius, 0)
      // right
      ..arcToPoint(
        Offset(size.width - radius, size.height),
        radius: Radius.circular(radius),
      )
      // bottom
      ..lineTo(radius, size.height)
      // left
      ..arcToPoint(
        Offset(radius, 0),
        radius: Radius.circular(radius),
      )
      ..close();

    context.canvas
      ..save()
      ..translate(offset.dx, offset.dy);
    if (_above) {
      context.canvas
        ..translate(0, size.height)
        ..scale(1, -1);
    }
    context.canvas
      ..drawPath(path, paint)
      ..drawPath(
        path,
        paint
          ..color = const Color(0x7EFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.25,
      )
      ..restore();

    super.paint(context, offset);
  }
}

class _VideoTime extends LeafRenderObjectWidget {
  const _VideoTime({
    required this.position,
    required this.duration,
  });

  final String position;
  final String duration;

  @override
  _RenderVideoTime createRenderObject(BuildContext context) => _RenderVideoTime(
    position: position,
    duration: duration,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderVideoTime renderObject,
  ) {
    renderObject
      ..position = position
      ..duration = duration;
  }
}

class _RenderVideoTime extends RenderBox {
  _RenderVideoTime({
    required this._position,
    required this._duration,
  });

  String _duration;
  set duration(String value) {
    if (_duration == value) return;
    _duration = value;
    final paragraph = _buildParagraph(const Color(0xFFD0D0D0), _duration);
    if (paragraph.maxIntrinsicWidth != _cache?.maxIntrinsicWidth) {
      markNeedsLayout();
    } else {
      markNeedsSemanticsUpdate();
    }
    _cache?.dispose();
    _cache = paragraph;
  }

  String _position;
  set position(String value) {
    _position = value;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  ui.Paragraph? _cache;

  static ui.Paragraph _buildParagraph(Color color, String time) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: 10,
              height: 1.4,
              fontFamily: 'Monospace',
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: 10,
              height: 1.4,
              fontFamily: 'Monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
          ..addText(time);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: .infinity));
  }

  @override
  ui.Size computeDryLayout(covariant BoxConstraints constraints) {
    final paragraph = _cache ??= _buildParagraph(
      const Color(0xFFD0D0D0),
      _duration,
    );
    return Size(paragraph.maxIntrinsicWidth, paragraph.height * 2);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..textDirection = .ltr
      ..label = 'position:$_position\nduration:$_duration';
  }

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    final para = _buildParagraph(Colors.white, _position);
    context.canvas
      ..drawParagraph(
        para,
        Offset(
          offset.dx + _cache!.maxIntrinsicWidth - para.maxIntrinsicWidth,
          offset.dy,
        ),
      )
      ..drawParagraph(_cache!, Offset(offset.dx, offset.dy + para.height));
    para.dispose();
  }

  @override
  void dispose() {
    _cache?.dispose();
    _cache = null;
    super.dispose();
  }

  @override
  bool get isRepaintBoundary => true;
}
