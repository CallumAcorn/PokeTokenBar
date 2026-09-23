---
summary: "PokeTokenBar's visual language — card chrome, icon badges, typography scale, color/material rules, sprite treatment — so new screens read as the same app instead of drifting."
read_when:
  - Building a new screen, card, button, or modal
  - Unsure what corner radius / opacity / font size to use for something
  - Reviewing UI code for visual consistency with the rest of the app
---

# Visual style

Concrete values pulled from what's actually in `BattleView.swift`/`CompanionView.swift`/
`TradeView.swift` today, not aspirational guidelines — copy these, don't invent new ones.
Compiled 2026-09-22 while building battle spectator mode, whose screen deliberately matched this
vocabulary end to end.

## Layout — no `NavigationStack`

Every multi-step flow (roster picker → waiting → battling, trade offer → confirm, settings tabs)
is a manual `@State` swap inside a **fixed-size container**, not push/pop navigation:

- Popover: `PopoverMetrics.width = 360`, `padding = 14`.
- Standalone battle window: `BattleWindowMetrics.width = 520`, `height = 460`, `padding = 14`.

A screen transition is `if`/`switch` over local `@State` (a `PickerStep` enum, a `Phase`, a
`Bool`) swapping which child view renders — see `PopoverView.body`'s `if nav.showTrade { ... }
else if nav.showSettings { ... }` and `BattleView.rosterPicker`'s `switch pickerStep`. Reopening a
popover always resets to Home (`PopoverNavigation.reset()`, called on every open) — a screen isn't
sticky state, in-progress *work* (a live poll, a pending offer) is, and that lives in the relevant
store, not the view.

## Card chrome — the default container

The one shape used for a lobby row, a mode-choice button, an invite card, a result modal:

```swift
.padding(14)                                   // 10–16 depending on content density
.background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
.overlay(
    RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1))
```

Corner radius scales with the card's size: 10 for a small tappable row, 12 for a standard card,
14–16 for a bigger showcase card (an invite card, a result modal). Add `.shadow(color: .black
.opacity(0.08–0.25), radius: 6–10, y: 2–4)` on a card that needs to visually lift off whatever's
behind it (floating over a scene, not just sitting in a plain list).

**Exception — a card painted over a busy/animated background** (the battle scene's info boxes):
use `.regularMaterial` instead of the flat `Color.secondary.opacity` fill. A translucent card reads
fine over the popover's flat background; over shifting sprite art/terrain it needs the material's
own blur to stay legible. Same rule for anything that must guarantee contrast regardless of what's
behind it (a result card over a colorful field) — use a **solid** surface instead of either:
`Color(nsColor: .windowBackgroundColor)`, theme-adaptive, never colored text sitting directly on a
tinted background.

## Icon badges

A colored square with a white SF Symbol, used for every "this is category X" affordance (a mode
choice, an invite prompt, a lobby entry's icon):

```swift
Image(systemName: "...")
    .font(.system(size: 18–22, weight: .semibold))
    .foregroundStyle(.white)
    .frame(width: 38–52, height: 38–52)          // bigger = more prominent (a hero prompt vs a row icon)
    .background(tint.gradient, in: RoundedRectangle(cornerRadius: 10–14, style: .continuous))
```

`tint` is semantic, not decorative — reused consistently: `.accentColor` for the primary/create
action, `.orange` for browse/discovery, `.blue` for a link/share action. Pick from this set before
introducing a new color for a new action; a new tint should mean a new *kind* of action, not just
visual variety.

## The "mode choice" button pattern

Icon badge + bold title + one-line secondary subtitle + trailing chevron, on the card chrome above,
`.buttonStyle(.plain)`:

```swift
HStack(spacing: 12) {
    <icon badge>
    VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(.primary)
        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
    }
    Spacer(minLength: 4)
    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
}
```

This is the entry point for any "pick one of a few big options" screen (`BattleView.modeChoiceButton`).
A smaller row variant (a lobby entry, `openBattleRow`/`liveBattleRow`) drops the subtitle and title
size to 13/11, keeps the same card chrome and trailing chevron/icon.

## Typography scale

No type-ramp enum exists — sizes are picked inline, but consistently:

| Role | Size / weight |
|---|---|
| Screen prompt ("How do you want to start?") | 13, semibold, `.secondary` |
| Card title | 12–14, bold |
| Card subtitle / secondary line | 10–11, regular, `.secondary` |
| Tiny badge/count label | 8–9, heavy or semibold |
| Result/modal title | 18–22, bold |
| Body text in a chat/log row | 10–11 |

## Buttons

- **Primary action**: `.buttonStyle(.borderedProminent)`, `.controlSize(.large)` — one per screen,
  the thing this screen exists to let you do (Join, Done, the paste-card's submit).
- **Secondary action**: `.buttonStyle(.bordered)`, same or `.large` control size.
- **Tertiary / icon-only**: `.buttonStyle(.borderless)`, `.controlSize(.small)` (a refresh spinner,
  a close/forfeit icon).
- A demoted-but-still-real option (not a plain card) uses `.bordered` + a semantic `.tint(...)` +
  `.controlSize(.small)` with an icon `Label`, never bare colored text — plain secondary-colored
  text reads as an inert caption, not a control, and gets missed (learned the hard way turning
  "Join via link" into a text button before reverting to a full card).

## Sprites

- Ground shadow: `Ellipse().fill(Color.black.opacity(0.16))`, `width: size * 0.85, height: size *
  0.24`, negative `VStack` spacing (`-size * 0.16`) to overlap it under the sprite.
- Fainted: `.opacity(0.35)`, `.rotationEffect(.degrees(90))`, `.animation(.easeInOut(duration:
  0.35), value: fainted)`.
- `.id(speciesID)` on the sprite so a species change is a real insert/remove SwiftUI can
  `.transition(.opacity)` across, not a prop update on the same view.

## HP / status color

```swift
if fraction > 0.5 { .green } else if fraction > 0.2 { .orange } else { .red }
```
Same three-stop thresholds everywhere an HP bar appears. Bar itself: dark track
(`Color.black.opacity(0.35)`, never a theme-dependent `.secondary.opacity` — must stay legible
against variable backgrounds), filled portion in the status color, `cornerRadius: 3`, hairline
`Color.black.opacity(0.4)` border.

## Modals

A centered card over a dimming scrim (`Color.black.opacity(0.45)`) when the underlying content
should stay visible-but-secondary (a spectator's result over its still-live log). A **full-screen
takeover** (no scrim, background replaced) when the prior screen has nothing worth keeping on
screen once this state is reached (a participant's own win/loss screen, log accessible only via an
explicit toggle). Pick based on whether anything behind the modal is still worth seeing at a
glance — don't default to takeover just because it's simpler.

## Empty / loading states

A list that can be empty must not flash "empty" during its first load — a spinner state and a
genuine-empty state are different renders:

```swift
if isLoading && items.isEmpty {
    ProgressView()                       // first load, nothing to show yet
} else if items.isEmpty {
    Image(systemName: "tray")            // a real, confirmed-empty result
    Text(emptyMessage)
} else {
    <the list>
}
```
(`browseStatus` in `BattleView.swift` is the canonical implementation — reuse the shape even where
the exact view isn't reusable across files.)

## Localization

Every user-facing string goes through `L`/`Localization.swift`'s `t(ko, en, ja, es)` — Korean
first (this fork's own primary language), the other three always present, never a bare English
literal in a SwiftUI view. See `CLAUDE.md`'s "기여 언어 규약" for the *separate* rule about PR/commit
English (that's about contribution language, not in-app strings — both apply, to different things).
