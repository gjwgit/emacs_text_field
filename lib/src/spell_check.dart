/// Spell check configuration and right-click suggestions for EmacsTextField.
///
// Time-stamp: <2026-10-28>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the MIT License.

library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show DefaultSpellCheckService, SpellCheckResults;

import 'package:emacs_text_field/src/aspell_spell_check_service.dart';

/// The spell check configuration for the current platform: aspell on Linux,
/// the native checker where Flutter has one (Android, iOS), otherwise null.
///
/// Null leaves spell check off rather than enabling it without a service,
/// which Flutter reports as an error and ignores.

SpellCheckConfiguration? platformSpellCheckConfiguration() {
  // On the web dart:io's Platform is unsupported, so check kIsWeb first.

  if (kIsWeb) return null;
  if (Platform.isLinux) {
    return SpellCheckConfiguration(
      spellCheckService: AspellSpellCheckService(),
    );
  }
  final native =
      WidgetsBinding.instance.platformDispatcher.nativeSpellCheckServiceDefined;
  return native ? const SpellCheckConfiguration() : null;
}

/// A context menu that lists spelling suggestions for the word under a
/// right-click above the usual cut/copy/paste items, then "Add to
/// dictionary" when [onAddWord] is given.
///
/// Flutter only offers suggestions on a tap on mobile. On desktop a
/// right-click does not move the cursor when the field has focus, so the
/// word is found from the click position, falling back to the cursor when
/// the menu was opened from the keyboard.

Widget spellCheckContextMenuBuilder(
  BuildContext context,
  EditableTextState editableTextState, {
  ValueChanged<String>? onAddWord,
}) {
  final render = editableTextState.renderEditable;
  final click = render.lastSecondaryTapDownPosition;
  final value = editableTextState.currentTextEditingValue;
  final index = click == null
      ? value.selection.extentOffset
      : render.getPositionForPoint(click).offset;
  final span = editableTextState.findSuggestionSpanAtCursorIndex(index);

  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: [
      for (final suggestion in span?.suggestions ?? const <String>[])
        ContextMenuButtonItem(
          label: suggestion,
          onPressed: () {
            final start = span!.range.start;
            editableTextState.userUpdateTextEditingValue(
              value
                  .replaced(span.range, suggestion)
                  .copyWith(
                    selection: TextSelection.collapsed(
                      offset: start + suggestion.length,
                    ),
                  ),
              SelectionChangedCause.toolbar,
            );
            editableTextState.hideToolbar();
          },
        ),
      if (span != null && onAddWord != null)
        ContextMenuButtonItem(
          label: 'Add to dictionary',
          onPressed: () {
            editableTextState.hideToolbar();
            onAddWord(value.text.substring(span.range.start, span.range.end));
          },
        ),
      ...editableTextState.contextMenuButtonItems,
    ],
  );
}

/// Spell checks the text of the [TextField] under [fieldKey] and stores the
/// results on its [EditableText]. Completes true when new results were
/// stored, so the caller rebuilds to show them.
///
/// Flutter only checks text typed at the keyboard, so text already in the
/// controller when a note opens, or changed by an Emacs command, would
/// otherwise never be underlined.

Future<bool> recheckSpelling(
  BuildContext context,
  GlobalKey fieldKey,
  SpellCheckConfiguration config,
) async {
  final editable = _editableOf(fieldKey);
  final text = editable?.currentTextEditingValue.text;
  if (editable == null ||
      text == editable.spellCheckResults?.spellCheckedText) {
    return false;
  }
  final locale =
      Localizations.maybeLocaleOf(context) ?? const Locale('en', 'US');
  final service = config.spellCheckService ?? DefaultSpellCheckService();
  final spans = await service.fetchSpellCheckSuggestions(locale, text!);

  // Drop the answer if the field went away or the text moved on meanwhile.

  if (spans == null ||
      !editable.mounted ||
      editable.currentTextEditingValue.text != text) {
    return false;
  }
  editable.spellCheckResults = SpellCheckResults(text, spans);
  return true;
}

/// Adds [word] to the personal dictionary when [config] uses aspell, then
/// drops its underlines from the [TextField] under [fieldKey]. Completes true
/// when the results changed, so the caller rebuilds to show them.

Future<bool> addToDictionary(
  GlobalKey fieldKey,
  SpellCheckConfiguration config,
  String word,
) async {
  final service = config.spellCheckService;
  if (service is! AspellSpellCheckService) return false;
  await service.addWord(word);
  final editable = _editableOf(fieldKey);
  final results = editable?.spellCheckResults;
  if (editable == null || !editable.mounted || results == null) return false;
  final text = results.spellCheckedText;
  editable.spellCheckResults = SpellCheckResults(text, [
    for (final span in results.suggestionSpans)
      if (text.substring(span.range.start, span.range.end) != word) span,
  ]);
  return true;
}

/// The [EditableTextState] inside the [TextField] under [fieldKey].

EditableTextState? _editableOf(GlobalKey fieldKey) =>
    switch (fieldKey.currentState) {
      final TextSelectionGestureDetectorBuilderDelegate d =>
        d.editableTextKey.currentState,
      _ => null,
    };
