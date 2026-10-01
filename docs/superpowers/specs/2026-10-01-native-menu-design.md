# The dropdown as a real menu

Oct 1, 2026 · Eidan Erlich · Status: option chosen and spike approved in conversation; spec awaiting owner review

## Why

The dropdown is a custom floating panel (adapted from Maccy's `FloatingPanel`). With "Automatically hide and show the menu bar" on, the bar slides away while the panel is open, because macOS keeps the bar shown only for a real menu. A non-activating accessory app has no API to hold it (spike, 2026-10-01). The stopgap in PR #5 moves or closes the panel with the bar, but the bar still hides.

Chai's dropdown is a real `NSMenu` (SwiftUI `MenuBarExtra`, menu style), and the bar stays put. The owner tried a throwaway spike: a real `NSMenu` whose rows are SwiftUI views (switches, ✓ rows, live countdown, ✕ buttons, a multi-select app submenu). It felt "way better".

## Decision

The dropdown becomes an `NSMenu` opened from the status item. Native items are used where AppKit has the control. Hosted SwiftUI views (`NSMenuItem.view` holding an `NSHostingView`) are used where it doesn't. Sections become submenus instead of pages that open in place.

This reverses SPEC.md's "The dropdown is a custom panel, not a native menu". Its reasons were a live search field, countdowns and ✕ buttons. Hosted views cover the countdowns and ✕ buttons. Search moves to the Clipboard popup (see Stage 4 below).

## Layout

```
 ● On · lid mode · 1h 12m left          hosted, live
 ──────────────────────────────────
 Awake                            ›     native submenu
 ──────────────────────────────────
 Settings…                       ⌘,     native
 Quit Mooring                    ⌘Q     native
```

**Awake ›** (contents as today, in a submenu):

| Row | Kind | Click |
| --- | --- | --- |
| On | hosted switch | toggles the menu session; menu stays open |
| For 30 min … Until turned off | hosted rows with ✓ (`DurationPick` rule) | picks the duration; menu stays open so the ✓ and icon update in view |
| While an app runs / While Xcode runs … | native submenu item, title from `AppSessionText.rowTitle`, `state = .on` while apps are picked | opens the app list |
| ↳ running apps | hosted rows with icon and ✓, rebuilt each time the submenu opens | picks or un-picks; menu stays open (multi-select) |
| Keep screen on, Allow lid close | hosted switches | as today; menu stays open |
| Until I open the lid | hosted row | starts the lid session |
| Approve lid mode… | native item (while the helper isn't enabled) | registers, opens Login Items; menu closes |
| Anchored | caption, then **one hosted item per lease** (owner, reason, time left, ✕) | ✕ ends that lease; menu stays open |

Windows and Clipboard become submenus with stages 3 and 4. A module that's off shows a single "Turn On…" item, as today.

## Behaviour

- **Opening.** Click routing is unchanged: by default left click toggles and right click opens, and the swap setting still applies. The open click shows the menu as the status item's own menu, so macOS highlights the icon and keeps the bar shown. The status item's `menu` is set only for that click, so left click keeps toggling.
- **Closing.** Native: an outside click, Esc, or choosing a native item.
- **Highlight.** Hosted rows draw the menu highlight (accent background, white text) for the item that `NSMenuDelegate.menu(_:willHighlight:)` reports. Mouse and arrow keys therefore highlight custom and native rows alike. Return on a highlighted hosted row runs its action when AppKit forwards it. This is nice to have, not required.
- **Live content.** Hosted views observe `AwakeEngine` (Observation), so the header, ✓ marks and switches update while the menu is open. The countdowns use a 1 s `TimelineView`, paused while the menu is closed.
- **Lists that change while open.** Lease rows are separate menu items, synced to `engine.leases` on open and on every lease change while open. So ✕, expiry and a new agent lease add or remove rows instead of resizing one view. The app list is rebuilt when its submenu opens.
- **Size.** 300 pt wide. Each hosted item's height is its SwiftUI fitting height.
- **Auto-hidden menu bar and full screen.** Handled by macOS. The stopgap in PR #5 (occlusion signal, pointer prediction, lifting the panel) is deleted.

## Components

- **`DropdownMenu`** (new, App/UI): builds and owns the root `NSMenu` and the Awake submenu. It is the `NSMenuDelegate`: `menuWillOpen` / `menuDidClose` set `isOpen`; `willHighlight` sets the highlighted tag; `menuNeedsUpdate` rebuilds the app list. It also syncs the lease items.
- **`DropdownController`**: opens `DropdownMenu` from the status item instead of the panel.
- **`MenuRow`**: drawn from the shared highlight state instead of `onHover`. Its ✓ column stays.
- **`DropdownModel`**: keeps `lastPick`. `page`, `maxHeight` and `isPresented` are replaced by `isOpen` and `highlightedTag`.
- **Deleted:**
  - `FloatingPanel.swift`, `PanelPlacement.swift`, `DropdownView`'s page switch, and their tests;
  - the SPEC.md auto-hide note.
- **Stays:** `AwakeSectionView`'s pieces (lid rows, the battery confirmation, picked-app names, `AppSessionText`), split into hosted row views.

## Stage 4 (Clipboard) consequence

A menu can't reliably hold a focused search field. The Clipboard popup (⇧⌘C) therefore becomes Maccy's own floating panel, opened directly, with search focused. The dropdown's **Clipboard ›** submenu shows recent items, Pause Recording, Ignore Next Copy, Clear, and "Search… ⇧⌘C", which opens that panel. Maccy's `FloatingPanel` is vendored at stage 4 instead of stage 1. SPEC.md's stage 4 table and Vendoring note get this change now, so the spec doesn't contradict itself.

## Testing

- **`DropdownMenuTests`** (app tests, real `NSMenu`):
  - root item order and titles;
  - Awake submenu rows with the helper enabled and not enabled;
  - the app item title and `state` follow `sessionApps`;
  - lease items match `engine.leases` after acquire, release and expiry, including while open;
  - `willHighlight` sets the highlighted tag;
  - `menuDidClose` clears it and sets `isOpen = false`.
- **Existing:** `DropdownModelTests` (`DurationPick`), `AppSessionTextTests`, `MenuRowLayoutTests` (updated), `ClickRouterTests` (the open action still opens).
- **Owner check:** the bar stays shown with auto-hide on and in a full-screen app; switches, ✓ rows, multi-select apps, countdown and ✕ behave as in the spike; arrow keys highlight; light and dark mode.

## Out of scope

- Windows and Clipboard content (stages 3 and 4).
- Keyboard type-select inside hosted rows.
