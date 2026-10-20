import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/common/widgets/flutter/text_field/editable_text.dart';
import 'package:flutter/widgets.dart' show FocusManager;
import 'package:flutter/services.dart';

class WindowsImeService {
  WindowsImeService._();

  static final WindowsImeService instance = WindowsImeService._();

  static const MethodChannel _channel = MethodChannel('piliplus/windows_ime');

  bool? _imeEnabled;

  void initialize() {
    if (!Platform.isWindows) return;

    FocusManager.instance.addListener(_handleFocusChanged);
    _handleFocusChanged();
  }

  void _handleFocusChanged() {
    final context = FocusManager.instance.primaryFocus?.context;
    final editableText = context?.findAncestorStateOfType<EditableTextState>();
    final shouldEnableIme =
        editableText != null && !editableText.widget.readOnly;
    if (_imeEnabled == shouldEnableIme) return;

    _imeEnabled = shouldEnableIme;
    unawaited(_channel.invokeMethod<void>('setImeEnabled', shouldEnableIme));
  }
}
