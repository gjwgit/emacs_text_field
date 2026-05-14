/// Linux X11 primary selection helper.
///
// Time-stamp: <2026-05-14>
///
/// Copyright (C) 2026, Togaware Pty Ltd
///
/// Licensed under the MIT License.

library;

import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart' show TextEditingController, VoidCallback;

/// Attaches a listener to [controller] that writes any non-collapsed
/// selection to the X11 primary buffer on Linux, enabling middle-click
/// paste into other applications.
///
/// Uses `xclip` (preferred) or `xsel`. No-op on non-Linux platforms.
/// Returns a cleanup callback — call it in [State.dispose].
VoidCallback attachPrimarySelection(TextEditingController controller) {
  if (!Platform.isLinux) return () {};

  void listener() {
    final sel = controller.selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final selected = sel.textInside(controller.text);
    if (selected.isNotEmpty) writePrimarySelection(selected);
  }

  controller.addListener(listener);
  return () => controller.removeListener(listener);
}

/// Writes [text] to the X11 primary selection buffer on Linux, so it can
/// be pasted into other applications with the middle mouse button.
///
/// Useful for [SelectionArea] `onSelectionChanged` callbacks where there
/// is no [TextEditingController] to attach to.
///
/// Uses `xclip` (preferred) or `xsel`. No-op on non-Linux platforms.
Future<void> writePrimarySelection(String text) async {
  if (!Platform.isLinux || text.isEmpty) return;

  try {
    final xclip = await Process.start('xclip', ['-selection', 'primary']);
    xclip.stdin.write(text);
    await xclip.stdin.close();
    final exit = await xclip.exitCode
        .timeout(const Duration(milliseconds: 300), onTimeout: () => 1);
    if (exit == 0) return;
  } catch (_) {}

  try {
    final xsel = await Process.start('xsel', ['--primary', '--input']);
    xsel.stdin.write(text);
    await xsel.stdin.close();
    await xsel.exitCode
        .timeout(const Duration(milliseconds: 300), onTimeout: () => 1);
  } catch (_) {}
}
