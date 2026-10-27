import 'dart:io' show Process;

import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:emacs_text_field/emacs_text_field.dart';

// Shared by the spell check tests, which talk to a real aspell process and
// are skipped where it is not installed. aspell is started once per isolate
// and tied to the test that started it, so each test needing a fresh field
// lives in its own file (each file runs in its own isolate).

/// Whether aspell is installed.

Future<bool> hasAspell() async {
  try {
    return (await Process.run('aspell', ['--version'])).exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Builds the field around [text] and right-clicks inside its word at
/// [offset]. Building runs in real time so the aspell process can answer:
/// process I/O never completes inside the test's fake async zone.

Future<void> rightClick(WidgetTester tester, String text, int offset) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmacsTextField(controller: TextEditingController(text: text)),
        ),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 500));
  });
  await tester.pump();
  await tester.tap(find.byType(TextField));
  await tester.pump(const Duration(milliseconds: 500));
  final editable = tester.state<EditableTextState>(find.byType(EditableText));
  final caret = editable.renderEditable.getLocalRectForCaret(
    TextPosition(offset: offset),
  );
  await tester.tapAt(
    tester.getTopLeft(find.byType(EditableText)) + caret.center,
    buttons: kSecondaryButton,
  );
  await tester.pumpAndSettle();
}

/// The field's current text.

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;
