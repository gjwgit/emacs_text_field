# emacs_text_field

A Flutter `TextField` with common Emacs key bindings for movement, killing,
yanking, and chord sequences.  Designed for desktop and tablet applications
where keyboard-centric editing is preferred.

## Features

- All standard Emacs movement commands
- Kill ring (single-entry): `C-k`, `C-w`, `C-y`
- Word operations: `M-f`, `M-b`, `M-d`, `M-Backspace`
- Line bullet helper: `M-Enter` inserts `\n+`
- Chord sequences: `C-c d` inserts today as `yyyymmdd`
- `expands` mode for use inside `Expanded` widgets
- `minLines` for fixed minimum height
- Undo (`C-z`, `C-/`) handled natively by Flutter's `EditableText`

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  emacs_text_field: ^0.1.0
```

Or use a path reference during development:

```yaml
dependencies:
  emacs_text_field:
    path: ../emacs_text_field
```

## Usage

```dart
import 'package:emacs_text_field/emacs_text_field.dart';

// Basic usage (grows with content):
EmacsTextField(
  controller: _noteController,
  decoration: const InputDecoration(
    labelText: 'Notes',
    border: OutlineInputBorder(),
  ),
)

// Expanding (fills bounded parent):
Expanded(
  child: EmacsTextField(
    controller: _noteController,
    expands: true,
    decoration: const InputDecoration(
      border: OutlineInputBorder(),
      hintText: 'Details…',
    ),
  ),
)
```

## Key Bindings

### Movement

| Key | Action |
|-----|--------|
| `C-a` | Beginning of line |
| `C-e` | End of line |
| `C-f` | Forward char |
| `C-b` | Backward char |
| `C-n` | Next line |
| `C-p` | Previous line |
| `M-f` | Forward word |
| `M-b` | Backward word |

### Editing

| Key | Action |
|-----|--------|
| `C-d` | Delete char forward |
| `M-d` | Kill word forward |
| `M-Backspace` | Kill word backward |
| `C-k` | Kill to end of line |
| `C-w` | Kill selection |
| `C-y` | Yank (paste kill ring) |
| `M-Enter` | Insert `\n+` (new bullet) |
| `C-g` | Cancel / deselect |

### Chords

| Sequence | Action |
|----------|--------|
| `C-c d` | Insert today as `yyyymmdd` |

### Undo

`C-z` and `C-/` are passed through to Flutter's native undo handler.

## License

MIT — Copyright (C) 2026 Togaware Pty Ltd
