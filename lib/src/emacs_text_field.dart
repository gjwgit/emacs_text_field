/// EmacsTextField — a multiline text field with common Emacs key bindings.
///
// Time-stamp: <Tuesday 2026-05-05 19:36:10 +1000 Graham Williams>
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
/// ### Linux primary selection (X11)
/// Highlighting text automatically writes to the X11 primary buffer.
/// Selected text can then be pasted into other Linux apps with middle-click.
/// `C-v` pastes from the primary selection buffer (i.e. whatever is currently
/// highlighted anywhere on screen) rather than the system clipboard.
///
/// ### Undo
/// `C-z` and `C-/` are passed through to Flutter's built-in undo handler.

library;

import 'dart:io' show Platform, Process, ProcessResult;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:emacs_text_field/src/primary_selection.dart';

/// A multiline [TextField] with Emacs-style key bindings.
///
/// On Linux, selected text is automatically written to the X11 primary
/// selection buffer so that it can be pasted into other applications with
/// the middle mouse button. Note that middle-click paste *into* this widget
/// is not supported by the Flutter engine at this time.
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
    this.outerScrollController,
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

  /// Optional [ScrollController] of an outer [SingleChildScrollView].
  /// When provided, [_nudgeScroll] scrolls this controller to keep the
  /// cursor visible after newline insertion or yank operations.
  final ScrollController? outerScrollController;

  @override
  State<EmacsTextField> createState() => _EmacsTextFieldState();
}

class _EmacsTextFieldState extends State<EmacsTextField> {
  // Single-entry kill ring (C-k / C-w → C-y).
  String _killRing = '';

  // Chord prefix for multi-key bindings (e.g. C-c → prefix for C-c d).
  String? _chordPrefix;

  // Internal scroll controller so _nudgeScroll can jump to cursor.
  final _scrollCtrl = ScrollController();

  // GlobalKey on the TextField so _nudgeScroll can find the nearest
  // Scrollable ancestor and ensure the cursor is visible.
  final _fieldKey = GlobalKey();

  // Cleanup callback returned by attachPrimarySelection.
  late VoidCallback _removePrimary;

  TextEditingController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _removePrimary = attachPrimarySelection(_ctrl);
  }

  @override
  void didUpdateWidget(EmacsTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _removePrimary();
      _removePrimary = attachPrimarySelection(widget.controller);
    }
  }

  @override
  void dispose() {
    _removePrimary();
    _scrollCtrl.dispose();
    super.dispose();
  }

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
    while (i < text.length && !_isWord(text[i])) {
      i++;
    }
    ;
    while (i < text.length && _isWord(text[i])) {
      i++;
    }
    ;
    return i;
  }

  int _wordBackward(int at) {
    final text = _ctrl.text;
    var i = at;
    while (i > 0 && !_isWord(text[i - 1])) {
      i--;
    }
    ;
    while (i > 0 && _isWord(text[i - 1])) {
      i--;
    }
    ;
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

  /// Scrolls the outer [SingleChildScrollView] to keep the cursor visible
  /// after an operation that moves it downward (newline insertion, yank, etc.).
  void _nudgeScroll() {
    final outer = widget.outerScrollController;
    if (outer == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !outer.hasClients) return;
      final renderBox =
          _fieldKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final style =
          widget.style ?? DefaultTextStyle.of(_fieldKey.currentContext!).style;
      final painter = TextPainter(
        text: TextSpan(text: _ctrl.text, style: style),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: renderBox.size.width);
      final cursorOffset = _ctrl.selection.baseOffset.clamp(
        0,
        _ctrl.text.length,
      );
      final caretDy = painter
          .getOffsetForCaret(TextPosition(offset: cursorOffset), Rect.zero)
          .dy;
      final lineH = painter.preferredLineHeight;
      painter.dispose();
      // fieldTop is the field's Y offset within the scroll view.
      final fieldTop =
          renderBox.localToGlobal(Offset.zero).dy - outer.position.pixels;
      final cursorY = fieldTop + caretDy;
      final pos = outer.position;
      final visibleBottom = pos.pixels + pos.viewportDimension;
      if (cursorY + lineH > visibleBottom) {
        outer.jumpTo(
          (pos.pixels + (cursorY + lineH - visibleBottom)).clamp(
            0.0,
            pos.maxScrollExtent,
          ),
        );
      }
    });
  }

  /// Reads from the X11 primary selection buffer (via xclip or xsel) and
  /// inserts the text at the current cursor position.
  Future<void> _pasteFromPrimary() async {
    String text = '';
    try {
      final result = await Process.run('xclip', ['-selection', 'primary', '-o'])
          .timeout(
            const Duration(milliseconds: 300),
            onTimeout: () => ProcessResult(-1, 1, '', ''),
          );
      if (result.exitCode == 0) text = result.stdout as String;
    } catch (_) {}

    if (text.isEmpty) {
      try {
        final result = await Process.run('xsel', ['--primary', '--output'])
            .timeout(
              const Duration(milliseconds: 300),
              onTimeout: () => ProcessResult(-1, 1, '', ''),
            );
        if (result.exitCode == 0) text = result.stdout as String;
      } catch (_) {}
    }

    if (text.isEmpty) return;
    final o = _offset;
    final sel = _ctrl.selection;
    // Replace selection if one exists, otherwise insert at cursor.
    final start = sel.isCollapsed ? o : sel.start;
    final end = sel.isCollapsed ? o : sel.end;
    _ctrl.value = _ctrl.value.copyWith(
      text: _ctrl.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _nudgeScroll();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;

    // ── Chord completion ───────────────────────────────────────────────────
    if (_chordPrefix != null) {
      final prefix = _chordPrefix!;
      _chordPrefix = null;
      if (prefix == 'C-c' && !ctrl && !alt && key == LogicalKeyboardKey.keyD) {
        // C-c d — insert today as yyyymmdd.
        final now = DateTime.now();
        final stamp =
            '${now.year}'
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
          _nudgeScroll();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyW:
          _killSelection();
          return KeyEventResult.handled;

        case LogicalKeyboardKey.keyV:
          // On Linux, Ctrl-V pastes from the X11 primary selection buffer
          // (i.e. whatever is currently highlighted anywhere on screen),
          // rather than the system clipboard. On other platforms fall through
          // to Flutter's default Ctrl-V behaviour.
          if (Platform.isLinux) {
            _pasteFromPrimary();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;

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
            selection: TextSelection.collapsed(offset: o + insertion.length),
          );
          _nudgeScroll();
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
        key: _fieldKey,
        controller: _ctrl,
        focusNode: widget.focusNode,
        scrollController: _scrollCtrl,
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
