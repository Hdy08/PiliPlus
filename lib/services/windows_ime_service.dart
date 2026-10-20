import 'dart:async';
import 'dart:io';

import 'package:PiliPlus/common/widgets/flutter/text_field/editable_text.dart'
    as rich_text;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show EditableTextState, FocusManager;

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
    // Search/settings use Flutter's EditableText; comments use our rich editor.
    final richEditableText = context
        ?.findAncestorStateOfType<rich_text.EditableTextState>();
    final shouldEnableIme =
        (editableText != null && !editableText.widget.readOnly) ||
        (richEditableText != null && !richEditableText.widget.readOnly);
    if (_imeEnabled == shouldEnableIme) return;

    _imeEnabled = shouldEnableIme;
    unawaited(_channel.invokeMethod<void>('setImeEnabled', shouldEnableIme));
  }
}
