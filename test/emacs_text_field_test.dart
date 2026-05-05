import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:emacs_text_field/emacs_text_field.dart';

void main() {
  testWidgets('EmacsTextField renders', (WidgetTester tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmacsTextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Notes'),
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    ctrl.dispose();
  });

  testWidgets('EmacsTextField expands mode', (WidgetTester tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: EmacsTextField(controller: ctrl, expands: true)),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(TextField), findsOneWidget);
    ctrl.dispose();
  });
}
