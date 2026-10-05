# Menu-bar icon redesign

Oct 1, 2026 · Eidan Erlich · Status: built (shipped in 0.1.0)

## Why

The stage 1 icon is an anchor that is outline when off and filled when on, with 7–9 pt badges for lid mode and battery and a 5 pt attention dot. At menu-bar size, three things go wrong:

- On and off look almost the same.
- The badges are close to unreadable. The battery badge was barely visible.
- The icon says nothing about *how* the Mac is being kept awake.

The goal is a practical icon that reads at a glance, not a decorative one.

**Principle:** at about 16 pt, a symbol drawn inside a symbol stops reading. States are told apart by whole shapes (a solid pill, or none), by short text, and by one sparing use of colour, never by small badges.

## Decisions

| Question | Decision |
| --- | --- |
| What must read without opening the dropdown? | On/off, lid mode, time left, something's wrong. **Not** battery state (macOS's own battery icon covers it). |
| Time left | Shown whenever the session is timed, with a Settings toggle to hide it (on by default). |
| Attention | Orange **and** a shape change, so it still works for colour-blind users. |
| Direction | D, "solid pill when on" (see [directions.png](2026-10-01-menu-bar-icon/directions.png)). |
| Time format | `1:12` from an hour up, `42m` below an hour. |
| Label per kind of awake | Timed shows the time, a task shows ▶, indefinite shows ∞. Lid mode must be clear on its own (see [pill-labels.png](2026-10-01-menu-bar-icon/pill-labels.png)). |

## The states

Shown in precedence order; the first match wins.

| State | Icon | Shown when |
| --- | --- | --- |
| **Attention** | Orange pill with a white **!** | Any guardrail suspension is active (`lidNeedsAC`, `lowBatteryLid`, `lowBatteryAll`, `thermal`), **or** a live lease wants lid but the helper isn't enabled |
| **Awake** | Solid pill: anchor + optional **LID** tag + one *kind label* | `state.systemAssertion` is true |
| **Off** | Dimmed outline anchor, no pill | Otherwise |

Inside the Awake pill, left to right:

1. **The anchor**, 13 pt, always present.
2. **The LID tag**, present exactly when `state.lidSleepDisabled` is true, meaning lid sleep is actually disabled, not just wanted. It's an inverted capsule (menu-bar-coloured block with ink-coloured letters "LID") inside the pill. Present or absent, it can't be misread.
3. **The kind label**, describing the lease that ends last (the same rule `StatusLine` uses: indefinite beats task, task beats timed):
   - **Indefinite** (some live lease has no expiry and no watched process): **∞**, using SF Symbol `infinity`.
   - **Task** (the latest-ending lease watches a process: "While an app runs…", and later `mooring anchor` and agents): **▶**, using SF Symbol `play.fill`.
   - **Timed**: the remaining time, `h:mm` when ≥ 1 h (`1:12`, `8:00`) and `Nm` below that (`42m`, `1m`). Minutes round up, as `DurationText` does, so a live lease never reads `0m`.
   - When **Settings → General → "Show time left in the menu bar"** is off, a timed lease shows no kind label, so the pill holds just the anchor (and LID if applicable). ∞ and ▶ still show, because they're short and carry meaning.

Examples:

| Situation | Pill |
| --- | --- |
| On, until turned off | `[⚓ ∞]` |
| On for 2 h, 1:12 left | `[⚓ 1:12]` |
| On while Xcode runs | `[⚓ ▶]` |
| Lid mode, until turned off | `[⚓ LID ∞]` |
| Lid mode, 42 min left | `[⚓ LID 42m]` |
| Lid wanted, paused by low battery | orange `[!]` |
| Nothing keeping it awake | dimmed `⚓` |

The stage 1 lid and battery badges and the attention dot are removed.

## Drawing

- **Height** 18 pt (it fits the 22 pt menu bar), corner radius 5 pt, 4 pt padding before the anchor and 5 pt after the last element, 3 pt between elements.
- **Text** is SF semibold, 11.5 pt, with monospaced digits so a countdown doesn't change width as digits change. LID is SF heavy, 9.5 pt, in a 12 pt-tall capsule with 3 pt corners.
- **Off** is the outline anchor asset at 55% opacity, as a template image.
- **Awake** is rendered into one **template image**: the pill is opaque, and the anchor, symbols and text are punched out (transparent), so macOS tints it for light and dark menu bars and inverts it while the dropdown is open. The LID tag is an opaque capsule inside a punched-out hole, so it ends up the menu-bar colour with ink letters.
- **Attention** is a **non-template image**: a `NSColor.systemOrange` pill with a white `exclamationmark` (SF Symbol, bold). It is the only coloured state.
- **Width:** the status item uses `NSStatusItem.variableLength`, and the image width is the content width. The image is only rebuilt when its content changes (state, kind, or the visible minute), so the item changes width at most once a minute.
- The anchor artwork is the existing `MenubarAnchorFill.svg`. No new artwork.

## Accessibility

VoiceOver reads one sentence built from the same inputs:

- "Mooring, off"
- "Mooring, on, until turned off"
- "Mooring, on, while an app runs"
- "Mooring, on, 1 hour 12 minutes left"
- "Mooring, lid mode, 42 minutes left"
- "Mooring needs attention: lid mode paused, battery low". The reason is one of: battery low, Mac too warm, needs power, or helper needs approval. For `lowBatteryAll` it says "Mooring paused, battery low".

## Components

- **`MenuBarState`** (new, App/Sources, pure): `enum MenuBarState { case off; case awake(lid: Bool, kind: AwakeKind); case attention(Attention) }` with `enum AwakeKind { case indefinite, task, timed(TimeInterval?) }` (a nil interval means time left is hidden) and `enum Attention { case suspension(Suspension), helperNeedsApproval }`. It's built by `MenuBarState.from(leases:state:wantsLid:helperEnabled:showTimeLeft:now:) -> MenuBarState`. When several suspensions are active the attention reason prefers `lowBatteryAll`, then `lowBatteryLid`, then `thermal`, then `lidNeedsAC`.
- **`MenuBarText`** (pure): `timeLabel(_ seconds: TimeInterval) -> String` (`1:12` / `42m`) and `accessibilityLabel(for: MenuBarState) -> String`.
- **`MenuBarIcon`**: `image(for: MenuBarState) -> NSImage`, which does the drawing above. It replaces `image(for: IconState)`, and `IconState`/`IconBadge` are deleted.
- **`StatusItemController`**: switches to `variableLength`, observes the engine plus the new Defaults key, and refreshes on a once-a-minute timer while the state is timed and time left is visible.
- **Defaults key** `showTimeLeftInMenuBar: Bool`, default `true`, with its toggle on the General settings page.

`AwakeKind` uses the same "ends last" choice as `StatusLine`. To keep the two from drifting apart, that choice moves into AwakeKit as `LeaseText.endingLast(_ leases: [Lease], now: Date) -> Lease?`, which `StatusLine` then uses.

## Testing

- **`MenuBarStateTests`:**
  - every row of the examples table, and the precedence (attention over awake over off);
  - the LID tag follows `lidSleepDisabled`, not `wantsLid`;
  - the toggle hides only timed labels;
  - a task beats a timed lease, and indefinite beats both;
  - the attention reason priority.
- **`MenuBarTextTests`:**
  - `timeLabel`: 30 s → `1m`, 2520 → `42m`, 3600 → `1:00`, 4320 → `1:12`, 28800 → `8:00`, negative → `1m` (never `0m`);
  - the accessibility sentence for each state.
- **`MenuBarIconTests`:**
  - every state yields an 18 pt-tall image;
  - Awake and Off are templates and Attention isn't;
  - `[⚓ LID 1:12]` is wider than `[⚓ 1:12]`, which is wider than `[⚓]`.
- **`LeaseText.endingLast`** in AwakeKit, plus `StatusLine` still passing its existing tests.
- **Manual visual check:** render every state at 1× and 2× on light and dark bars and inspect them.
- **Manual check:** the real menu bar in light mode, dark mode, with the dropdown open (inverted), and in lid mode on battery.

## Spec changes (docs/SPEC.md)

- **UX → Icon states:** replace the badge description with the state table above.
- **Engineering decisions → "Menu-bar icon" and "Icon"** bullets: the pill design; badges and the dot removed.
- **Stage 1b/1c notes** that mention badges: point to this design.

## Out of scope

- Per-module status for Windows or Clipboard. Those are tools, not states; the dropdown covers them.
- Animation, such as a pulse on attention.
- Custom icon themes, and replacing the anchor artwork.
- Showing *which* agent holds a lease. The dropdown's Anchored list does that.
