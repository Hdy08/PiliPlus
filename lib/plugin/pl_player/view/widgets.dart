part of 'view.dart';

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
        bottom:
            videoDetailController.viewPointList.isNotEmpty &&
                videoDetailController.showVP.value
            ? 19.25 + offset
            : 4.25 + offset,
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

const _kBarMargin = 20.0;

Widget buildSeekPreviewWidget(
  PlPlayerController plPlayerController,
  double maxWidth,
  double maxHeight,
) {
  return Obx(
    () {
      if (!plPlayerController.showPreview.value) {
        return const SizedBox.shrink();
      }

      try {
        final data = plPlayerController.videoShot!.data;

        final double scale = PlatformUtils.isDesktop
            ? maxHeight > maxWidth
                  ? 3
                  : 4
            : plPlayerController.isFullScreen.value &&
                  !plPlayerController.isVertical
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

        return Obx(
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

            final dx = plPlayerController.hoverDx;
            final hovering = dx != null;
            final position = hovering
                ? DurationUtils.formatDuration(
                    plPlayerController.seekPosition.value,
                  )
                : null;

            return VideoShotImage(
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
              position: position,
              builder: (image, size) {
                final child = ClipRRect(
                  borderRadius: Style.mdRadius,
                  child: image,
                );
                if (hovering) {
                  final width = size.width;
                  final left = clampDouble(
                    dx - width / 2 + _kBarMargin,
                    _kBarMargin,
                    maxWidth - width - _kBarMargin,
                  );

                  return Positioned(
                    left: left,
                    bottom: 80,
                    child: child,
                  );
                }
                return Center(child: child);
              },
            );
          },
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
    this.position,
    this.builder,
  }) : assert(columns > 0 && rows > 0);

  final ImageProvider image;
  final int x;
  final int y;
  final int columns;
  final int rows;
  final double height;
  final AsyncCallback? onRetry;
  final String? position;
  final Widget Function(Widget image, Size size)? builder;

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
    ..strokeWidth = kPreviewStroke;

  @override
  Widget build(BuildContext context) {
    if (_imageInfo case final imageInfo?) {
      final image = imageInfo.image;
      final tileWidth = image.width / widget.columns;
      final tileHeight = image.height / widget.rows;
      final size = Size(widget.height * tileWidth / tileHeight, widget.height);
      final dstRect = Offset.zero & size;
      final child = CroppedImage(
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
        position: widget.position,
      );
      return widget.builder?.call(child, size) ?? child;
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

  static final double _fontSize = PlatformUtils.isDesktop ? 12 : 10;

  @override
  _RenderVideoTime createRenderObject(BuildContext context) => _RenderVideoTime(
    fontSize: MediaQuery.textScalerOf(context).scale(_fontSize),
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
    required this._fontSize,
    required this._position,
    required this._duration,
  });

  final double _fontSize;

  String _duration;
  set duration(String value) {
    if (_duration == value) return;
    _duration = value;
    final paragraph = _buildParagraph(_durationColor, _duration, _fontSize);
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

  static const _positionColor = Colors.white;
  static const _durationColor = Color(0xFFD0D0D0);

  ui.Paragraph? _cache;

  static ui.Paragraph _buildParagraph(
    Color color,
    String time,
    double fontSize,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: fontSize,
              height: 1.4,
              fontFamily: 'Monospace',
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
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
      _durationColor,
      _duration,
      _fontSize,
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
    final para = _buildParagraph(_positionColor, _position, _fontSize);
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
