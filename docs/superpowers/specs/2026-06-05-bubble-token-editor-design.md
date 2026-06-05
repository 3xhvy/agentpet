# Bubble Token Editor — Design Spec
**Date:** 2026-06-05  
**Status:** Approved

---

## Overview

Replace the current "Token Order" section (a vertical list with toggles + drag handles gated behind a "Custom" preset) with a three-section element editor that is always live, always editable, and displays tokens in the same horizontal orientation they appear in the real bubble.

The preset picker (Original / Standard / Detailed / Custom) is removed. The settings panel always shows the editor directly.

---

## Section 1 — Token Palette

A horizontal wrapping row of chip buttons for every token **not currently active** in the canvas row.

- Chips: `State dot`, `Agent icon`, `Chat title`, `Project`, `Separator`, `Message`, `State label`, `Elapsed`
- A chip is shown only when its token is absent from the active canvas row
- Tapping/clicking a chip appends that token to the end of the canvas row
- If all tokens are active, the palette area shows a muted hint: *"All tokens are in use"*
- Chips are styled as small rounded rectangles with the token display name

---

## Section 2 — Active Row Canvas

A horizontal row of draggable chips representing the tokens currently in the bubble, **in the exact order they render**.

- Left-to-right order matches the bubble render order
- Each chip has a small `×` button to remove it (returns it to the palette)
- Chips are draggable for reordering (macOS drag within the row)
- Row wraps if tokens overflow the panel width
- When the canvas is empty, a centered placeholder text appears: *"Add tokens above to build your bubble row"*
- Changes write immediately to `BubbleSettings.shared.customLayout`

---

## Section 3 — Live Preview

A rendered `AgentRow` using static mock data that updates instantly as the canvas changes.

**Mock session:**
- Agent kind: Claude  
- Project: `agentpet`  
- Title: `Fix login crash`  
- State: `working`  
- Message: `Reading source files`  
- `stateSince`: 3 minutes ago (static offset, not a real timer)

The preview renders inside a small bubble frame (rounded rectangle, same style as the real `AgentBubble`) so it visually matches what appears on screen.

---

## Data Model Changes

- Remove `BubbleSettings.Preset` enum and `preset` property
- Remove `BubbleLayout.preset(named:)` static method
- Remove preset presets `original`, `standard`, `detailed` from `BubbleLayout` (keep as internal helpers or migration defaults)
- `effectiveLayout` becomes `customLayout` directly (no indirection needed)
- On first launch after migration, default `customLayout` is set to what was `BubbleLayout.original`
- `BubbleSettings.init()` falls back to `.original` tokens if no saved layout

---

## UI Changes

**`BubbleSettingsView`:**
- Replace `presetSection` and `tokenOrderSection` with the new three-section editor (palette, canvas, preview)
- Section header for palette: *"Available tokens"*
- Section header for canvas: *"Bubble row"* (with hint: *"Drag to reorder · tap × to remove"*)
- Section header for preview: *"Preview"*
- The rest of the tab (Agent Icons, Appearance, Filter & Sort) is unchanged

**`BubbleSettings.swift`:**
- Remove `Preset` enum
- Remove `preset` published property and its `UserDefaults` key
- `effectiveLayout` → remove; callers use `customLayout` directly

**`PetView.swift`:**
- Replace `settings.effectiveLayout` with `settings.customLayout` everywhere

**`BubbleLayout`:**
- Retain struct; remove `preset(named:)` and static preset constants (or keep them private for migration)

---

## Implementation Notes

- Use `LazyVStack` / `HStack` wrapping with `.flexibleWidth` for the palette chip grid
- The chip drag-reorder in the canvas can be implemented with SwiftUI's `onDrag` / `onDrop` since `List` drag is column-only. Alternatively, use a custom horizontal drag implementation or a fixed-width `HStack` with explicit drag gesture.
- Preview section should not react to the appearance/filter settings (it uses hard-coded mock); it only reacts to the token layout and the icon/font/theme appearance settings.

---

## Out of Scope

- Per-token configuration (e.g., truncation length for `title`)
- Saved named presets / preset library
- Undo/redo for canvas edits
