# Bubble Display Settings

**Date:** 2026-06-05
**Feature:** User-configurable agent bubble layout, appearance, and filtering

## Overview

The agent status bubble is currently hardcoded: state dot → agent icon → conversation title → project · message. This spec covers making every part of that display configurable — which tokens appear, in what order, how the bubble looks, and which sessions are shown — accessible via a new "Bubble" tab in the existing Settings window.

---

## 1. Data Model

### 1.1 Token Enum

```swift
enum BubbleToken: String, CaseIterable, Codable, Identifiable {
    case dot          // colored state circle (working=blue, waiting=orange, done=green)
    case icon         // agent brand logo (Claude, Cursor, Codex, Gemini, …)
    case title        // conversation chat name (from transcript summary)
    case project      // folder name (last path component of cwd)
    case separator    // configurable separator character between tokens
    case message      // current activity / tool-use description
    case stateLabel   // text state: "Working" | "Waiting" | "Done" | "Idle"
    case elapsed      // time in current state, e.g. "3m" or "1h 2m"
}
```

### 1.2 Layout Types

```swift
struct BubbleTokenItem: Codable, Identifiable, Equatable {
    var id: String { token.rawValue }
    let token: BubbleToken
    var isVisible: Bool
}

struct BubbleLayout: Codable, Equatable {
    var tokens: [BubbleTokenItem]
}
```

A `BubbleLayout` is an ordered list of all 8 tokens. Rendering iterates the list and skips tokens with `isVisible == false`. Reordering means swapping items in the array.

### 1.3 Presets

| Preset | Visible tokens (in order) |
|--------|--------------------------|
| **Minimal** | dot · icon · project · message |
| **Standard** | dot · icon · title · project · separator · message |
| **Detailed** | dot · icon · title · project · separator · message · stateLabel · elapsed |
| **Custom** | User-defined; starts as a copy of Standard on first use |

Presets are static constants on `BubbleLayout`. The Custom layout is persisted independently.

### 1.4 `BubbleSettings` Class

```swift
@MainActor
final class BubbleSettings: ObservableObject {
    static let shared = BubbleSettings()

    enum Preset: String, CaseIterable { case minimal, standard, detailed, custom }
    enum FontSize: String, CaseIterable { case small, medium, large }
    enum Theme: String, CaseIterable { case light, dark, system }

    // Preset selection
    @Published var preset: Preset               // default: .standard
    @Published var customLayout: BubbleLayout   // default: copy of Standard

    // Appearance
    @Published var separatorChar: String        // default: "·"; options: "·" "→" "|" " "
    @Published var fontSize: FontSize           // default: .medium
    @Published var opacity: Double              // default: 1.0; range: 0.6–1.0
    @Published var theme: Theme                 // default: .light

    // Filter & Sort
    @Published var maxSessions: Int             // default: 5; range: 1–10
    @Published var minState: AgentState         // default: .registered (show all)
    @Published var groupByKind: Bool            // default: false
    @Published var hiddenKinds: Set<AgentKind>  // default: []

    /// The layout currently in effect (preset or custom).
    var effectiveLayout: BubbleLayout {
        switch preset {
        case .custom: return customLayout
        default: return BubbleLayout.preset(for: preset)
        }
    }
}
```

All properties are persisted to UserDefaults as JSON, following the `ChatSettings` pattern. Keys are prefixed `agentpet.bubble.*`.

**Font size pixel values:**

| Size | Primary text | Secondary text |
|------|-------------|----------------|
| Small | 10 pt | 9 pt |
| Medium (default) | 12 pt | 10.5 pt |
| Large | 14 pt | 12 pt |

---

## 2. Settings UI — "Bubble" Tab

A `BubbleSettingsView` SwiftUI view added as a new tab in the existing `SettingsWindowController`. The tab label is "Bubble" with icon `bubble.left.and.bubble.right`.

### 2.1 Layout

```
┌──────────────────────────────────────┐
│  Preset   [Minimal] [Standard] [Detailed] [Custom]  │
│                                                      │
│  ── Token Order (enabled when Custom) ──             │
│  ≡  ● dot          State dot           [●]          │
│  ≡  ● icon         Agent icon          [●]          │
│  ≡  ● title        Chat title          [●]          │
│  ≡  ● project      Project folder      [●]          │
│  ≡  ● separator    Separator char      [●]          │
│  ≡  ● message      Activity message    [●]          │
│  ≡  ○ stateLabel   State label         [ ]          │
│  ≡  ○ elapsed      Elapsed time        [ ]          │
│                        [Reset to Standard]           │
│                                                      │
│  ── Appearance ─────────────────────────────────    │
│  Separator   [·] [→] [|] [space]                    │
│  Font size   [S] [M] [L]                            │
│  Opacity     ●───────────────── 100%                 │
│  Theme       [Light] [Dark] [System]                │
│                                                      │
│  ── Filter & Sort ──────────────────────────────    │
│  Max sessions shown      [5 ▲▼]                     │
│  Minimum state           [All states ▾]             │
│  Group by agent kind     [toggle]                   │
│  Hide agents                                        │
│    ☑ Claude  ☑ Cursor  ☑ Codex  ☑ Gemini  …        │
└──────────────────────────────────────────────────────┘
```

### 2.2 Behavior Details

- **Preset segmented control:** Switching immediately applies the preset to the live bubble (no separate Apply button). The token list below updates to show that preset's layout as a non-interactive preview.
- **Custom token list:** Shown as interactive (drag-drop + toggles) only when Custom is selected. For other presets, the same list is shown read-only to communicate what that preset contains.
- **Reset to Standard button:** Copies `BubbleLayout.standard` into `customLayout` and saves.
- **Separator picker:** Segmented control with 4 options. The selected character is used for `separator` tokens in the rendered row; also displayed as a preview label on the segmented button.
- **Min state picker:** Options: "All states" (`.registered`), "Working & Waiting", "Working only".
- **Hide agents checkboxes:** Shows all supported agent kinds (same list as the Integrations tab — installed or not). A hidden kind's sessions are fully suppressed from the bubble.

---

## 3. Rendering

### 3.1 `AgentBubble` — Filtering & Sorting

Before rendering rows, `AgentBubble` applies `BubbleSettings` to the session list:

1. **Kind filter:** Remove sessions where `session.agentKind` is in `hiddenKinds`.
2. **State filter:** Remove sessions where `session.state.attentionPriority < minState.attentionPriority`.
3. **Sort:**
   - If `groupByKind`: sort by `agentKind.rawValue` then by `attentionPriority desc` then `updatedAt desc`.
   - Otherwise: sort by `attentionPriority desc` then `updatedAt desc` (existing behavior).
4. **Cap:** Take the first `maxSessions` items.

### 3.2 `AgentRow` — Token Rendering

`AgentRow` iterates `BubbleSettings.shared.effectiveLayout.tokens`, skips invisible ones, and renders each token as a sub-view inside an `HStack`:

| Token | Renders as |
|-------|-----------|
| `dot` | `Circle().fill(stateDotColor).frame(6×6)` |
| `icon` | `AgentIconView(kind:, size: scaledIconSize)` |
| `title` | Bold `Text`, hidden when `session.title == nil` |
| `project` | Regular `Text` with last path component |
| `separator` | `Text(BubbleSettings.shared.separatorChar)` dimmed |
| `message` | Regular `Text`, falls back to state name |
| `stateLabel` | `Text(session.state.rawValue.capitalized)` |
| `elapsed` | `Text(elapsedString(since: session.stateSince))` |

Tokens that have no value for a given session (e.g. `title` when no title is known) are silently skipped even if `isVisible == true`, so the row never shows blank gaps.

**Appearance application:**
- `fontSize` maps to the pt values in §1.4.
- `opacity` is applied to the bubble background (`Color.white.opacity(settings.opacity)`).
- `theme` drives both the background color and the text foreground:
  - Light: white background, `Color.black.opacity(0.82)` text
  - Dark: `Color(nsColor: .windowBackgroundColor)` background, `Color.white.opacity(0.9)` text
  - System: uses `.background` / `.primary` semantic colors (auto-adapts)

### 3.3 `elapsed` helper

```swift
func elapsedString(since date: Date, now: Date = Date()) -> String {
    let s = Int(now.timeIntervalSince(date))
    if s < 60 { return "\(s)s" }
    let m = s / 60
    if m < 60 { return "\(m)m" }
    return "\(m / 60)h \(m % 60)m"
}
```

---

## 4. File Plan

| File | Action |
|------|--------|
| `Sources/App/BubbleSettings.swift` | **New** — `BubbleToken`, `BubbleTokenItem`, `BubbleLayout`, `BubbleSettings` |
| `Sources/App/BubbleSettingsView.swift` | **New** — Settings tab UI |
| `Sources/App/PetView.swift` | **Modify** — `AgentRow` reads `BubbleSettings`; `AgentBubble` applies filters |
| `Sources/App/SettingsWindowController.swift` | **Modify** — add Bubble tab |
| `Sources/App/PetController.swift` | **No change** — filtering stays in view layer |

---

## 5. Out of Scope

- Per-session custom layout (all sessions use the same layout)
- Animating token reorder changes on the live bubble
- Saving multiple named custom layouts (single Custom slot only)
- Cursor/Codex transcript title support (tracked separately)
