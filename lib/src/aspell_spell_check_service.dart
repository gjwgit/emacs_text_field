/// Spell checking on Linux through an `aspell -a` (ispell pipe) process.
///
// Time-stamp: <2026-10-28>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the MIT License.

library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Process;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;

/// A [SpellCheckService] backed by a long-running `aspell -a` process.
///
/// Flutter has no native spell checker on Linux, so this service talks the
/// ispell pipe protocol to aspell. One process is shared by every field and
/// started on first use. Each word is sent on its own line so the offsets
/// come from our own tokenising rather than aspell's, and results are cached
/// per word so re-checking on every keystroke only asks about new words.
///
/// The dictionary follows `LANG` (e.g. `en_AU.UTF-8`), falling back to the
/// widget's locale. When aspell is not installed every check returns no
/// suggestions, so the field simply shows no underlines.

class AspellSpellCheckService implements SpellCheckService {
  /// Maximum number of suggestions kept for each misspelled word.
  static const maxSuggestions = 5;

  static final _word = RegExp(r"\p{L}+(?:'\p{L}+)*", unicode: true);
  static final _cache = <String, List<String>?>{};
  static Process? _process;
  static StreamIterator<String>? _lines;
  static Future<void> _queue = Future.value();
  static bool _unavailable = false;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) => _serial(() => _check(locale, text));

  /// Adds [word] to the user's personal aspell dictionary (e.g.
  /// `~/.aspell.en.pws`) and saves it, so it is accepted from now on in
  /// every field, and by any other program that uses aspell.

  Future<void> addWord(String word) => _serial(() async {
    _cache[word] = null;
    try {
      _process?.stdin.write('*$word\n#\n');
      await _process?.stdin.flush();
    } catch (_) {
      // 20261028 gjw The pipe broke: the word stays accepted for this
      // session through the cache, and the next check restarts aspell.

      _process = null;
    }
  });

  /// Runs [task] after any earlier one: the pipe answers in order, so only
  /// one conversation with aspell may be in progress at a time.

  static Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<SuggestionSpan>?> _check(Locale locale, String text) async {
    final matches = _word.allMatches(text).toList();
    final unknown = {
      for (final m in matches)
        if (!_cache.containsKey(m[0])) m[0]!,
    }.toList();

    if (_unavailable) return [];
    if (unknown.isNotEmpty && !await _lookup(locale, unknown)) return [];

    return [
      for (final m in matches)
        if (_cache[m[0]] != null)
          SuggestionSpan(TextRange(start: m.start, end: m.end), _cache[m[0]]!),
    ];
  }

  /// Asks aspell about [words], caching null for correct words and the
  /// suggestion list for misspelled ones. Returns false if aspell is
  /// unavailable or the pipe broke, in which case nothing is cached.

  Future<bool> _lookup(Locale locale, List<String> words) async {
    try {
      final lines = await _start(locale);
      _process!.stdin.write(words.map((w) => '^$w\n').join());
      await _process!.stdin.flush();
      for (final w in words) {
        List<String>? suggestions;

        // Read this word's result lines up to the blank line ending them.

        while (await lines.moveNext() && lines.current.isNotEmpty) {
          final line = lines.current;
          if (line.startsWith('#')) suggestions = [];
          if (line.startsWith('&')) {
            suggestions = line
                .substring(line.indexOf(':') + 1)
                .split(',')
                .map((s) => s.trim())
                .take(maxSuggestions)
                .toList();
          }
        }
        _cache[w] = suggestions;
      }
      return true;
    } catch (_) {
      _process?.kill();
      _process = null;
      return false;
    }
  }

  /// Starts aspell if it is not already running and consumes its banner.

  Future<StreamIterator<String>> _start(Locale locale) async {
    if (_process != null) return _lines!;
    final lang = Platform.environment['LANG']?.split('.').first;

    // 20261028 gjw Inside a snap aspell and its dictionaries are staged
    // under $SNAP, not the host /usr/lib/aspell compiled into aspell.

    final snap = Platform.environment['SNAP'];
    final Process process;
    try {
      process = await Process.start('aspell', [
        '-a',
        '--encoding=utf-8',
        '--lang=${lang == null || lang == 'C' ? locale.toString() : lang}',
        if (snap != null) ...[
          '--data-dir=$snap/usr/lib/aspell',
          '--dict-dir=$snap/usr/lib/aspell',
        ],
      ]);
    } catch (_) {
      // 20261028 gjw Not installed: stop trying rather than spawn aspell on
      // every keystroke.

      _unavailable = true;
      rethrow;
    }
    final lines = StreamIterator(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await lines.moveNext()) {
      // 20261028 gjw No dictionary for the language: aspell exits at once.

      _unavailable = true;
      throw StateError('aspell exited');
    }
    _process = process;
    _lines = lines;
    return lines;
  }
}
