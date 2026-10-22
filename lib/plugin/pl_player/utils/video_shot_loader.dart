import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/video/video_shot/data.dart';

/// Shares metadata requests and retries temporary empty results while previewing.
class VideoShotLoader {
  VideoShotLoader({
    required this.fetch,
    required this.isActive,
    required this.onLoaded,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<LoadingState<VideoShotData>> Function() fetch;
  final bool Function() isActive;
  final void Function() onLoaded;
  final DateTime Function() _now;

  LoadingState<VideoShotData>? state;
  Timer? _retryTimer;
  DateTime? _retryAt;
  int _failures = 0;
  int _generation = 0;

  void load() {
    if (state is Loading || state is Success<VideoShotData>) return;
    final remaining = _retryAt?.difference(_now());
    if (remaining != null && remaining > Duration.zero) {
      _scheduleRetry(remaining);
      return;
    }
    if (_failures >= 3) _failures = 0;
    stopRetry();
    state = LoadingState.loading();
    _load(_generation);
  }

  Future<void> _load(int generation) async {
    LoadingState<VideoShotData> result;
    try {
      result = await fetch();
      if (result case Success(:final response)
          when response.index.isEmpty ||
              response.image.isEmpty ||
              response.imgXLen <= 0 ||
              response.imgYLen <= 0) {
        result = const Error(null);
      }
    } catch (error) {
      result = Error(error.toString());
    }
    if (generation != _generation) return;
    state = result;
    if (result is Success<VideoShotData>) {
      _failures = 0;
      _retryAt = null;
      onLoaded();
    } else {
      _failures++;
      final delay = Duration(
        seconds: switch (_failures) {
          1 => 1,
          2 => 3,
          _ => 30,
        },
      );
      _retryAt = _now().add(delay);
      _scheduleRetry(delay);
    }
  }

  void _scheduleRetry(Duration delay) {
    // At most three requests per attempt, only while a preview is active.
    // Later interaction can try again after the cooldown, without reopening.
    if (_failures >= 3 || _retryTimer != null || !isActive()) return;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      if (isActive()) {
        _retryAt = null;
        load();
      }
    });
  }

  void stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void clear() {
    _generation++;
    stopRetry();
    state = null;
    _retryAt = null;
    _failures = 0;
  }
}
