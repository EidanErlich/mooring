# Maccy

- Repo: https://github.com/p0deje/Maccy
- Commit: c376789c5d377b7c520b6f6e91f3f3a1aa28640b (2026-09-04)
- License: MIT (see LICENSE in this folder)
- Used for: the dropdown's floating panel (stage 1b) and clipboard history, vendored as ClipKit (stage 4)

## Files taken

| Upstream file | Mooring file |
| --- | --- |
| `Maccy/FloatingPanel.swift` | `App/UI/FloatingPanel.swift` (stage 1b) |

## Modifications

- `FloatingPanel`: removed every use of `AppState`, `Popup`, `PopupPosition`, the preview/slideout, and Maccy's `Defaults` keys (saved window size and position); removed resizing and dragging. Content sizes itself through `NSHostingController.sizingOptions = [.preferredContentSize]`; the panel is placed by `PanelPlacement` under the status item and re-anchored on resize. Level `.statusBar` instead of `.screenSaver`. Esc (`cancelOperation`) closes it.
