import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'spell_check_helpers.dart';

// This writes to aspell's personal dictionary, so it only runs when
// ASPELL_CONF points aspell at a scratch home:
//
//   ASPELL_CONF="home-dir $(mktemp -d)" flutter test

void main() async {
  final skip =
      !await hasAspell() || Platform.environment['ASPELL_CONF'] == null;

  testWidgets(
    'Add to dictionary accepts the word everywhere in the field',
    (tester) async {
      await rightClick(tester, 'Ask Zorbleplix about Zorbleplix', 6);
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      expect(editable.spellCheckResults!.suggestionSpans, hasLength(2));
      await tester.tap(find.text('Add to dictionary'));
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(editable.spellCheckResults!.suggestionSpans, isEmpty);
      expect(fieldText(tester), 'Ask Zorbleplix about Zorbleplix');
    },
    skip: skip,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
