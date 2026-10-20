import 'dart:io';

import 'package:PiliPlus/common/widgets/flutter/text_field/controller.dart';
import 'package:PiliPlus/common/widgets/flutter/text_field/editable_text.dart'
    as rich_text;
import 'package:PiliPlus/services/windows_ime_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('enable Chinese IME for standard and rich text fields', (
    tester,
  ) async {
    const channel = MethodChannel('piliplus/windows_ime');
    final imeStates = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      expectSync(call.method, 'setImeEnabled');
      imeStates.add(call.arguments as bool);
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    final standardFocus = FocusNode();
    final cupertinoFocus = FocusNode();
    final richFocus = FocusNode();
    final readOnlyFocus = FocusNode();
    final readOnlyRichFocus = FocusNode();
    final playerFocus = FocusNode();
    final standardController = TextEditingController();
    final cupertinoController = TextEditingController();
    final richController = RichTextEditingController();
    final readOnlyRichController = RichTextEditingController();
    addTearDown(() {
      standardFocus.dispose();
      cupertinoFocus.dispose();
      richFocus.dispose();
      readOnlyFocus.dispose();
      readOnlyRichFocus.dispose();
      playerFocus.dispose();
      standardController.dispose();
      cupertinoController.dispose();
      richController.dispose();
      readOnlyRichController.dispose();
    });

    WindowsImeService.instance.initialize();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextField(
                controller: standardController,
                focusNode: standardFocus,
              ),
              CupertinoTextField(
                controller: cupertinoController,
                focusNode: cupertinoFocus,
              ),
              rich_text.EditableText(
                controller: richController,
                focusNode: richFocus,
                style: const TextStyle(),
                cursorColor: Colors.blue,
                backgroundCursorColor: Colors.grey,
              ),
              TextField(focusNode: readOnlyFocus, readOnly: true),
              rich_text.EditableText(
                controller: readOnlyRichController,
                focusNode: readOnlyRichFocus,
                readOnly: true,
                style: const TextStyle(),
                cursorColor: Colors.blue,
                backgroundCursorColor: Colors.grey,
              ),
              Focus(focusNode: playerFocus, child: const SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(imeStates, [false]);
    for (final (focus, controller) in [
      (standardFocus, standardController),
      (cupertinoFocus, cupertinoController),
      (richFocus, richController),
    ]) {
      playerFocus.requestFocus();
      await tester.pump();
      expect(imeStates.last, isFalse);

      focus.requestFocus();
      await tester.pump();
      expect(imeStates.last, isTrue);

      // The candidate composition must remain enabled until it is committed.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'zhongwen',
          selection: TextSelection.collapsed(offset: 8),
          composing: TextRange(start: 0, end: 8),
        ),
      );
      await tester.pump();
      expect(imeStates.last, isTrue);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '中文',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      await tester.pump();
      expect(controller.text, '中文');
    }

    for (final focus in [readOnlyFocus, richFocus, readOnlyRichFocus]) {
      focus.requestFocus();
      await tester.pump();
      expect(imeStates.last, focus == richFocus);
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(imeStates.last, isFalse);
    await tester.pumpWidget(const SizedBox());
  }, skip: !Platform.isWindows);
}
