import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'spell_check_helpers.dart';

void main() async {
  final skip = !await hasAspell();

  testWidgets(
    'right-click on a misspelled word offers and applies a suggestion',
    (tester) async {
      await rightClick(tester, 'Fix teh bug', 5);
      expect(find.text('the'), findsOneWidget);
      expect(find.text('Add to dictionary'), findsOneWidget);
      expect(find.text('Select all'), findsOneWidget);
      await tester.tap(find.text('the'));
      await tester.pumpAndSettle();
      expect(fieldText(tester), 'Fix the bug');
    },
    skip: skip,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
