# Agent Ticker Chat Bubble

**Date:** 2026-06-05  
**Status:** Approved

## Problem

When running many AI agent tabs (Claude Code, Cursor, Codex, Gemini) in parallel, the desktop pet only shows an aggregate mood and a generic chat line like "Thinking…". To find out which tab is doing what, users must click the menu bar icon and read the popover. With 5+ active sessions this context-switch overhead adds up and causes missed "waiting for input" prompts.

## Goal

Make the floating pet's chat bubble cycle through every active agent session, one line at a time, so the user can glance at the desktop and know exactly which agent is doing what — without opening the menu bar popover.

## Out of Scope

- New UI widgets or additional windows
- Stacked / multi-bubble layout
- Per-project pet assignment
- Changes to the menu bar popover, notifications, or any other view

---

## Design

### Ticker Engine (inside `PetController`)

Replace the current random-line `refreshChat()` logic with a stateful ticker when at least one non-idle, non-registered session is active.

**State owned by `PetController`:**
```
tickerIndex: Int = 0
tickerSessions: [AgentSession] = []   // sorted, refreshed on every update(sessions:)
tickerTimer: Timer?                    // fires every tickerInterval seconds
```

**Interval:** 4 seconds per agent. Hardcoded constant `tickerInterval = 4.0`.

**Session filter:** same as `MenuContentView.agents` — exclude `.idle` and `.registered` states.

**Sort order (applied on every `update(sessions:)` call):**
1. `.waiting` — always first (needs user input)
2. `.working` — sorted by `updatedAt` descending (most recently active first)
3. `.done` — last

**Timer lifecycle:**
- Started when the first active session arrives.
- Reset to index 0 whenever `tickerSessions` changes (new session, session removed, or state change).
- Invalidated when `tickerSessions` becomes empty (bubble hides).

---

### Line Format

Each ticker line is built as:

```
<AgentLabel> [<project>] → <message>
```

- **`AgentLabel`** — derived from `session.agentKind` (typed `AgentKind` enum, already on `AgentSession`):
  - `.claude` → `Claude`
  - `.cursor` → `Cursor`
  - `.codex` → `Codex`
  - `.gemini` → `Gemini`
  - `.opencode` → `Opencode`
  - `.windsurf` → `Windsurf`
  - `.cli` → `Agent` (launched via `agentpet run` wrapper)
  - `.unknown` → `Agent`
- **`project`** — `session.project`'s last path component (already used in `AgentRow`). Falls back to the session id if nil.
- **`message`** — `session.message` if non-empty; otherwise `session.state.rawValue.capitalized`.

Examples:
```
Claude [agentpet] → running bash…
Cursor [my-api] → needs you! 👀
Codex [infra] → Working
Gemini [frontend] → Thinking…
```

---

### Mood States

The ticker only replaces the chat line during `.working` and `.waiting` moods (aggregate). During `.celebrate` and post-celebrate `.done`, `PetChat` lines continue to be used (celebration is a short burst and should stay expressive). Once the app returns to `.idle`, `chatLine` clears as today.

| Aggregate mood | Chat line source        |
|----------------|------------------------|
| `.working`     | Ticker (agent lines)   |
| `.waiting`     | Ticker (agent lines, waiting agents first) |
| `.done`        | `PetChat.done` lines   |
| `.celebrate`   | `PetChat.celebrate` lines |
| `.idle`        | `""` (bubble hidden)   |

---

### Single-Agent Case

When `tickerSessions.count == 1`, no cycling needed. The timer still fires every 4 seconds but always rebuilds the same line from the live session data (so the message updates as the agent's tool call changes).

---

### Custom Chat Lines (ChatSettings)

User-configured custom lines in `ChatSettings` apply to `.done` and `.celebrate` states only (same as the moods where `PetChat` lines are used). The ticker takes full control during `.working` and `.waiting`. This is a deliberate simplification: agent-specific lines are more useful than custom affirmations while work is in flight.

---

### Edge Cases

| Scenario | Behaviour |
|----------|-----------|
| 0 active sessions | `chatLine = ""`, bubble hides, ticker stopped |
| Session finishes mid-cycle | `update(sessions:)` fires → list rebuilds → ticker resets to index 0 |
| `showChat = false` | Ticker still runs internally but `chatLine` is never published to the view (same gate as today) |
| Very long project name or message | `ChatBubble` already uses `.lineLimit(1)` + `.truncationMode(.tail)` — no change needed |
| `agentKind` is `.cli` or `.unknown` | Label shows as `Agent` |

---

## Files Changed

| File | Change |
|------|--------|
| `Sources/App/PetController.swift` | Replace `refreshChat()` random-line logic with ticker engine; add `tickerIndex`, `tickerSessions`, `tickerTimer`; add `tickerLine(for:)` → `String` helper that formats one session into the display string |

No other files need to change. `FloatingPetView`, `ChatBubble`, `PetView`, `MenuBarContentView`, and all hook/daemon code are untouched.

---

## Success Criteria

1. With 3+ active agent sessions, the chat bubble visibly cycles through each agent every 4 seconds.
2. A `.waiting` agent always appears in the first position of the cycle.
3. When all agents go idle, the bubble disappears.
4. `.celebrate` / `.done` lines still play correctly after a session finishes.
5. No changes needed to any other view or settings file.
