# SimpleNotr

A simple, secure, local-first note-taking app for macOS — inspired by Obsidian but with a tighter security model.

## Philosophy

Notes are plain files on your disk. No database, no sync account, no cloud dependency.

| Format | Editing | Rendering |
|--------|---------|-----------|
| `.txt` | Plain text editor | None — raw text only, zero processing |
| `.md`  | Raw markdown (left pane) | Safe preview (right pane) — no external requests |

### Security guarantees

- **TXT files**: Link detection, data detection, and all automatic text processing are explicitly disabled at the `NSTextView` level. URLs in plain text notes are never activated.
- **MD files**: Before rendering, the markdown is sanitized:
  - External image links `![alt](https://…)` → replaced with `[external image]`
  - External links `[text](https://…)` → replaced with just `text` (no href)
  - `ftp://` and `mailto:` links → display text only
  - All remaining link activations are intercepted by SwiftUI's `openURL` environment — only `note://` internal links are allowed through; everything else is discarded
- **No WebView**: The markdown preview is rendered entirely with SwiftUI — no `WKWebView`, no HTML, no JavaScript

## Features

- Vault-based organisation (any folder = a vault)
- Folder tree sidebar mirrors your actual directory structure
- Split-pane editor for `.md` files (edit left, preview right)
- WikiLinks: `[[Note Name]]` — click to navigate in preview
- Relative links: `[text](./other-note.md)` — also navigable
- Autosave with 0.6 s debounce
- Create / rename / delete notes and folders
- Full undo/redo and Find via native `NSTextView`
- Light & dark mode

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (for building)

## Build & Run

### With Xcode (recommended)

1. Clone the repo
2. Open the folder in Xcode — it will detect `Package.swift` automatically
3. Select the **SimpleNotr** scheme and click Run (⌘R)

### From the command line

```bash
git clone https://github.com/your-handle/simplenotr
cd simplenotr
swift run
```

> **Note**: `swift run` launches the SwiftUI app directly. For a distributable `.app` bundle, build with Xcode and use **Product › Archive**.

### Build release binary

```bash
swift build -c release
# Binary at: .build/release/SimpleNotr
```

## Project Structure

```
Sources/SimpleNotr/
├── SimpleNotrApp.swift          # @main entry point, menu commands
├── Models/
│   └── NoteItem.swift           # File/folder data model
├── Services/
│   ├── VaultManager.swift       # Vault open/save, file tree, CRUD
│   └── MarkdownProcessor.swift  # Sanitiser + block-level parser
└── Views/
    ├── ContentView.swift         # Root layout + vault picker
    ├── WelcomeView.swift         # First-launch vault picker screen
    ├── SidebarView.swift         # Folder tree, context menus, toolbar
    ├── EditorView.swift          # Autosaving editor, split pane for MD
    ├── PlainTextEditorView.swift # Secure NSTextView wrapper
    └── MarkdownPreviewView.swift # Block renderer, link interceptor
```

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Markdown note | ⌘N |
| New Text note | ⇧⌘N |
| New Folder | ⌥⌘N |
| Open Vault | ⇧⌘O |

## License

MIT
