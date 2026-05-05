/// EmacsTextField — a multiline text field with common Emacs key bindings.
///
// Time-stamp: <Tuesday 2026-05-06 09:00:00 +1000 Graham Williams>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the MIT License.
///
/// ## Supported key bindings
///
/// ### Movement
/// - `C-a` beginning of line
/// - `C-e` end of line
/// - `C-f` forward char
/// - `C-b` backward char
/// - `C-n` next line
/// - `C-p` previous line
/// - `M-f` forward word
/// - `M-b` backward word
///
/// ### Editing
/// - `C-d` delete char forward
/// - `M-d` kill word forward
/// - `M-Backspace` kill word backward
/// - `C-k` kill to end of line
/// - `C-w` kill selection
/// - `C-y` yank (paste from kill ring)
/// - `M-Enter` insert new bullet line (`+ `)
/// - `C-g` cancel / deselect
///
/// ### Chord sequences
/// - `C-c d` insert today as `yyyymmdd`
///
/// ### Undo
/// `C-z` and `C-/` are passed through to Flutter's built-in undo handler.

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A multiline [TextField] with Emacs-style key bindings.
///
/// Usage:
/// ```dart
/// EmacsTextField(
///   controller: _myController,
///   decoration: const InputDecoration(
///     labelText: 'Notes',
///     border: OutlineInputBorder(),
///   ),
/// )
/// ```
///
/// Set [expands] to `true` when the widget is inside an [Expanded] or other
/// bounded-height widget to make it fill the available space.  When
/// [expands] is `false` (default), set [minLines] to control the minimum
/// visible height.

class EmacsTextField extends StatefulWidget {
  const EmacsTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.decoration,
    this.style,
    this.autofocus = false,
    this.expands = false,
    this.minLines,
  });

  /// The text editing controller.
  final TextEditingController controller;

  /// Optional focus node. When omitted, an internal node is used.
  final FocusNode? focusNode;

  /// Decoration passed to the underlying [TextField].
  final InputDecoration? decoration;

  /// Text style passed to the underlying [TextField].
  final TextStyle? style;

  /// Whether to auto-focus when the widget first appears.
  final bool autofocus;

  /// When `true` the field expands to fill its bounded parent (requires an
  /// [Expanded] or similar ancestor).  When `false` (default) the field
  /// grows with content, starting at [minLines] rows.
  final bool expands;

  /// Minimum visible rows when [expands] is `false`. Defaults to `5`.
  final int? minLines;

  @override
  State<EmacsTextField> createState() => _EmacsTextFieldState();
}

class _EmacsTextFieldState extends State<EmacsTextField> {
  // Single-entry kill ring (C-k / C-w → C-y).
  String _killRing = '';

  // Chord prefix for multi-key bindings (e.g. C-c → prefix for C-c d).
  String? _chordPrefix;

  TextEditingController get _ctrl => widget.controller;

  // ── Cursor helpers ─────────────────────────────────────────────────────────

  int get _offset => _ctrl.selection.baseOffset.clamp(0, _ctrl.text.length);

  void _moveTo(int offset, {bool select = false}) {
    final clamped = offset.clamp(0, _ctrl.text.length);
    _ctrl.selection = select
        ? TextSelection(
            baseOffset: _ctrl.selection.baseOffset,
            extentOffset: clamped,
          )
        : TextSelection.collapsed(offset: clamped);
  }

  // ── Line helpers ───────────────────────────────────────────────────────────

  int _lineStart(int at) {
    final text = _ctrl.text;
    if (at == 0) return 0;
    final idx = text.lastIndexOf('\n', at - 1);
    return idx == -1 ? 0 : idx + 1;
  }

  int _lineEnd(int at) {
    final text = _ctrl.text;
    final idx = text.indexOf('\n', at);
    return idx == -1 ? text.length : idx;
  }

  int _nextLine(int at) {
    final text = _ctrl.text;
    final col = at - _lineStart(at);
    final end = _lineEnd(at);
    if (end >= text.length) return text.length;
    final nextStart = end + 1;
    final nextEnd = _lineEnd(nextStart);
    return (nextStart + col).clamp(nextStart, nextEnd);
  }

  int _prevLine(int at) {
    final text = _ctrl.text;
    final start = _lineStart(at);
    if (start == 0) return 0;
    final prevEnd = start - 1;
    final prevStart = _lineStart(prevEnd);
    final col = at - start;
    return (prevStart + col).clamp(prevStart, prevEnd);
  }

  // ── Word helpers ───────────────────────────────────────────────────────────

  static bool _isWord(String ch) => RegExp(r'\w').hasMatch(ch);

  int _wordForward(int at) {
    final text = _ctrl.text;
    var i = at;
    while (i < text.length && !_isWord(text[i])) i++;
    while (i < text.length && _isWord(text[i])) i++;
    return i;
  }

  int _wordBackward(int at) {
    final text = _ctrl.text;
    var i = at;
    while (i > 0 && !_isWord(text[i - 1])) i--;
    while (i > 0 && _isWord(text[i - 1])) i--;
    return i;
  }

  // ── Kill helpers ───────────────────────────────────────────────────────────

  void _kill(int from, int to) {
    if (from == to) return;
    final text = _ctrl.text;
    _killRing = text.substring(
      from.clamp(0, text.length),
      to.clamp(0, text.length),
    );
    _ctrl.value = _ctrl.value.copyWith(
      text: text.replaceRange(
        from.clamp(0, text.length),
        to.clamp(0, text.length),
        '',
      ),
      selection: TextSelection.collapsed(offset: from.clamp(0, text.length)),
    );
  }

  void _killSelection() {
    final sel = _ctrl.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    _kill(sel.start, sel.end);
  }

  // ── Character manipulation ─────────────────────────────────────────────────

  void _deleteForward() {
    final o = _offset;
    if (o >= _ctrl.text.length) return;
    _ctrl.value = _ctrl.value.copyWith(
      text: _ctrl.text.replaceRange(o, o + 1, ''),
      selection: TextSelection.collapsed(offset: o),
    );
  }

  // ── Key event handler ──────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // ── Chord completion ───────────────────────────────────────────────────
    if (_chordPrefix != null) {
      final prefix = _chordPrefix!;
      _chordPrefix = null;
      if (prefix == 'C-c' && !ctrl && !alt &&
          key == LogicalKeyboardKey.keyD) {
        // C-c d — insert today as yyyymmdd.
        final now = DateTime.now();
        final stamp = '${now.year}'
            '${now.month.toString().padLeft(2, '0')}'
            '${now.day.toString().padLeft(2, '0')}';
        final o = _offset;
        _ctrl.value = _ctrl.value.copyWith(
          text: _ctrl.text.replaceRange(o, o, stamp),
          selection: TextSelection.collapsed(offset: o + stamp.length),
        );
        return KeyEventResult.handled;
      }
      // Unknown chord — fall through.
    }

    // ── Ctrl bindings ──────────────────────────────────────────────────────
    if (ctrl && !alt) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          _chordPrefix = 'C-c';
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyA:
          _moveTo(_lineStart(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyE:
          _moveTo(_lineEnd(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyF:
          _moveTo((_offset + 1).clamp(0, _ctrl.text.length));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyB:
          _moveTo((_offset - 1).clamp(0, _ctrl.text.length));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyN:
          _moveTo(_nextLine(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyP:
          _moveTo(_prevLine(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyD:
          _deleteForward();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyK:
          final start = _offset;
          final end = _lineEnd(start);
          if (start == end && end < _ctrl.text.length) {
            _kill(start, start + 1);
          } else {
            _kill(start, end);
          }
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyY:
          if (_killRing.isEmpty) return KeyEventResult.handled;
          final o = _offset;
          _ctrl.value = _ctrl.value.copyWith(
            text: _ctrl.text.replaceRange(o, o, _killRing),
            selection: TextSelection.collapsed(offset: o + _killRing.length),
          );
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyW:
          _killSelection();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyG:
          _moveTo(_offset);
          return KeyEventResult.handled;

        // C-z and C-/ — pass through to Flutter's undo handler.

        default:
          return KeyEventResult.ignored;
      }
    }

    // ── Alt / Meta bindings ────────────────────────────────────────────────
    if (alt && !ctrl) {
      switch (key) {
        case LogicalKeyboardKey.keyF:
          _moveTo(_wordForward(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyB:
          _moveTo(_wordBackward(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyD:
          _kill(_offset, _wordForward(_offset));
          return KeyEventResult.handled;

        case LogicalKeyboardKey.backspace:
          _kill(_wordBackward(_offset), _offset);
          return KeyEventResult.handled;

        case LogicalKeyboardKey.enter:
          // M-Enter — insert new bullet line.
          const insertion = '\n+ ';
          final o = _offset;
          _ctrl.value = _ctrl.value.copyWith(
            text: _ctrl.text.replaceRange(o, o, insertion),
            selection: TextSelection.collapsed(
              offset: o + insertion.length,
            ),
          );
          return KeyEventResult.handled;

        default:
          return KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _onKey,
      child: TextField(
        controller: _ctrl,
        focusNode: widget.focusNode,
        decoration: widget.decoration,
        style: widget.style,
        autofocus: widget.autofocus,
        expands: widget.expands,
        maxLines: widget.expands ? null : null,
        minLines: widget.expands ? null : (widget.minLines ?? 5),
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        textAlignVertical: TextAlignVertical.top,
      ),
    );
  }
}
