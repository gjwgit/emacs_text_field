import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;

import 'package:flutter_test/flutter_test.dart';

import 'package:emacs_text_field/src/aspell_spell_check_service.dart';

import 'spell_check_helpers.dart';

// These talk to a real aspell process, so they are skipped where it is not
// installed.

void main() async {
  final skip = await hasAspell() ? false : 'aspell is not installed';
  final service = AspellSpellCheckService();
  const locale = Locale('en', 'AU');

  test('flags a misspelled word with its range and suggestions', () async {
    final spans = await service.fetchSpellCheckSuggestions(
      locale,
      'Fix teh bug',
    );
    expect(spans, hasLength(1));
    expect(spans!.single.range, const TextRange(start: 4, end: 7));
    expect(spans.single.suggestions, contains('the'));
    expect(
      spans.single.suggestions.length,
      lessThanOrEqualTo(AspellSpellCheckService.maxSuggestions),
    );
  }, skip: skip);

  test('accepts correct text, contractions and numbers', () async {
    final spans = await service.fetchSpellCheckSuggestions(
      locale,
      "Don't forget the 3 meetings tomorrow.",
    );
    expect(spans, isEmpty);
  }, skip: skip);

  test('reports repeated misspellings at each position', () async {
    final spans = await service.fetchSpellCheckSuggestions(
      locale,
      'teh cat and teh dog',
    );
    expect(spans!.map((s) => s.range.start), [0, 12]);
  }, skip: skip);

  test('concurrent requests each get their own answer', () async {
    final results = await Future.wait([
      service.fetchSpellCheckSuggestions(locale, 'recieve'),
      service.fetchSpellCheckSuggestions(locale, 'hello world'),
    ]);
    expect(results[0], hasLength(1));
    expect(results[1], isEmpty);
  }, skip: skip);
}
