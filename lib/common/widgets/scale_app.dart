import 'dart:async' show scheduleMicrotask;
import 'dart:collection' show Queue;
import 'dart:ui' show PointerDataPacket;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/gestures.dart' show PointerEventConverter;
import 'package:flutter/rendering.dart' show RenderView, ViewConfiguration;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// ref https://github.com/LastMonopoly/scaled_app

/// Adapted from [WidgetsFlutterBinding]
///
class ScaledWidgetsFlutterBinding extends WidgetsFlutterBinding {
  ScaledWidgetsFlutterBinding._({this._scaleFactor = 1.0});

  /// Calculate scale factor from device size.
  double _scaleFactor;

  /// Update scaleFactor callback, then rebuild layout
  set scaleFactor(double scaleFactor) {
    if (_scaleFactor == scaleFactor) return;
    _scaleFactor = scaleFactor;
    handleMetricsChanged();
    if (_windowsTextInput != null) {
      addPostFrameCallback((_) => _windowsTextInput!.updateGeometry());
    }
  }

  _WindowsScaledTextInput? _windowsTextInput;

  double devicePixelRatioScaled = 0;

  static ScaledWidgetsFlutterBinding? _binding;

  static ScaledWidgetsFlutterBinding get instance => _binding!;

  /// Scaling will be applied based on [scaleFactor] callback.
  ///
  static WidgetsBinding ensureInitialized({double scaleFactor = 1.0}) =>
      _binding ??= ScaledWidgetsFlutterBinding._(scaleFactor: scaleFactor);

  @override
  BinaryMessenger createBinaryMessenger() {
    final messenger = super.createBinaryMessenger();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return _windowsTextInput = _WindowsScaledTextInput(
        messenger,
        scaleFactor: () => _scaleFactor,
      );
    }
    return messenger;
  }

  /// Override the method from [RendererBinding.createViewConfiguration] to
  /// change what size or device pixel ratio the [RenderView] will use.
  ///
  /// See more:
  /// * [RendererBinding.createViewConfiguration]
  /// * [TestWidgetsFlutterBinding.createViewConfiguration]
  @override
  ViewConfiguration createViewConfigurationFor(RenderView renderView) {
    final view = renderView.flutterView;
    final devicePixelRatio = view.devicePixelRatio;
    devicePixelRatioScaled = devicePixelRatio * _scaleFactor;
    final BoxConstraints physicalConstraints =
        BoxConstraints.fromViewConstraints(view.physicalConstraints);
    return ViewConfiguration(
      physicalConstraints: physicalConstraints,
      logicalConstraints: physicalConstraints / devicePixelRatioScaled,
      devicePixelRatio: devicePixelRatioScaled,
    );
  }

  /// Adapted from [GestureBinding.initInstances]
  @override
  void initInstances() {
    super.initInstances();
    platformDispatcher.onPointerDataPacket = _handlePointerDataPacket;
  }

  @override
  void unlocked() {
    super.unlocked();
    _flushPointerEventQueue();
  }

  final Queue<PointerEvent> _pendingPointerEvents = Queue<PointerEvent>();

  /// When we scale UI using [ViewConfiguration], [ui.window] stays the same.
  ///
  /// [GestureBinding] uses [platformDispatcher.implicitView.devicePixelRatio] for calculations,
  /// so we override corresponding methods.
  ///
  void _handlePointerDataPacket(PointerDataPacket packet) {
    // We convert pointer data to logical pixels so that e.g. the touch slop can be
    // defined in a device-independent manner.
    try {
      _pendingPointerEvents.addAll(
        PointerEventConverter.expand(packet.data, _devicePixelRatioForView),
      );
      if (!locked) {
        _flushPointerEventQueue();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'gestures library',
          context: ErrorDescription('while handling a pointer data packet'),
        ),
      );
    }
  }

  double _devicePixelRatioForView(int viewId) => devicePixelRatioScaled;

  /// Dispatch a [PointerCancelEvent] for the given pointer soon.
  ///
  /// The pointer event will be dispatched before the next pointer event and
  /// before the end of the microtask but not within this function call.
  @override
  void cancelPointer(int pointer) {
    if (_pendingPointerEvents.isEmpty && !locked) {
      scheduleMicrotask(_flushPointerEventQueue);
    }
    _pendingPointerEvents.addFirst(PointerCancelEvent(pointer: pointer));
  }

  void _flushPointerEventQueue() {
    assert(!locked);

    while (_pendingPointerEvents.isNotEmpty) {
      handlePointerEvent(_pendingPointerEvents.removeFirst());
    }
  }
}

/// Windows applies monitor DPI itself; only compensate for app UI scaling.
class _WindowsScaledTextInput extends BinaryMessenger {
  _WindowsScaledTextInput(this._delegate, {required this.scaleFactor});

  final BinaryMessenger _delegate;
  final double Function() scaleFactor;
  static const _codec = JSONMethodCodec();
  final _geometry = <String, MethodCall>{};

  ByteData _encodeGeometry(MethodCall call) {
    final scale = scaleFactor();
    final args = Map<String, dynamic>.from(call.arguments as Map);
    if (call.method == 'TextInput.setEditableSizeAndTransform') {
      final transform = List<double>.from(args['transform'] as List);
      // Local rects are scaled separately, so preserve the linear part.
      transform[12] *= scale;
      transform[13] *= scale;
      args['transform'] = transform;
      args['width'] = (args['width'] as num) * scale;
      args['height'] = (args['height'] as num) * scale;
    } else if ((args['width'] as num) >= 0 && (args['height'] as num) >= 0) {
      // Preserve Flutter's sentinel for an invalid rect.
      for (final key in const ['x', 'y', 'width', 'height']) {
        args[key] = (args[key] as num) * scale;
      }
    }
    return _codec.encodeMethodCall(MethodCall(call.method, args));
  }

  // TextInputConnection can cache unchanged rects when app scaling changes.
  void updateGeometry() {
    for (final call in _geometry.values) {
      _delegate.send(SystemChannels.textInput.name, _encodeGeometry(call));
    }
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    if (channel == SystemChannels.textInput.name && message != null) {
      final call = _codec.decodeMethodCall(message);
      switch (call.method) {
        case 'TextInput.setClient' || 'TextInput.clearClient':
          _geometry.clear();
        case 'TextInput.setEditableSizeAndTransform' ||
            'TextInput.setMarkedTextRect' ||
            'TextInput.setCaretRect':
          _geometry[call.method] = call;
          if (scaleFactor() != 1.0) message = _encodeGeometry(call);
      }
    }
    return _delegate.send(channel, message);
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      _delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) =>
      // ignore: deprecated_member_use
      _delegate.handlePlatformMessage(channel, data, callback);
}
