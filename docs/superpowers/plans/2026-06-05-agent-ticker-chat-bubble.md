# Agent Ticker Chat Bubble Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pet's single generic chat line with a cycling ticker that shows which agent is doing what (`Claude [agentpet] → running bash…`, `Cursor [my-api] → needs you! 👀`), rotating through every active session every 4 seconds, urgency-first.

**Architecture:** Pure formatting logic (`TickerFormatter`) goes into `AgentPetCore` so it can be unit-tested without AppKit. The ticker timer and state (`tickerIndex`, `tickerSessions`, `tickerTimer`) live in `PetController`. `PetController.refreshChat()` is updated to delegate to the ticker when in `.working` or `.waiting` mood; `.celebrate` and `.done` keep using `PetChat` lines as today.

**Tech Stack:** Swift 6, SwiftUI, `@MainActor`, `Timer`, `AgentPetCore` (library target), `Sources/App` (executable target), XCTest.

**Spec:** `docs/superpowers/specs/2026-06-05-agent-ticker-chat-bubble-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/AgentPetCore/TickerFormatter.swift` | Pure: format one session into a display string; sort sessions by urgency |
| Create | `Tests/AgentPetCoreTests/TickerFormatterTests.swift` | Unit tests for `TickerFormatter` |
| Modify | `Sources/App/PetController.swift` | Ticker engine: timer, index, session list, integration with `refreshChat()` |

No other files change.

---

## Task 1: `TickerFormatter` in AgentPetCore

**Files:**
- Create: `Sources/AgentPetCore/TickerFormatter.swift`

- [ ] **Step 1: Create the file with `agentLabel` and `line` helpers**

```swift
// Sources/AgentPetCore/TickerFormatter.swift
import Foundation

/// Pure formatting and sorting logic for the desktop-pet ticker.
/// Lives in AgentPetCore so it can be unit-tested without AppKit.
public enum TickerFormatter {

    /// Short display label for an agent kind.
    public static func agentLabel(for kind: AgentKind) -> String {
        switch kind {
        case .claude:    return "Claude"
        case .cursor:    return "Cursor"
        case .codex:     return "Codex"
        case .gemini:    return "Gemini"
        case .opencode:  return "Opencode"
        case .windsurf:  return "Windsurf"
        case .cli:       return "Agent"
        case .unknown:   return "Agent"
        }
    }

    /// One ticker line for a single session.
    /// Format: `<AgentLabel> [<project>] → <message>`
    public static func line(for session: AgentSession) -> String {
        let label   = agentLabel(for: session.agentKind)
        let project = session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
        let msg: String
        if let m = session.message, !m.trimmingCharacters(in: .whitespaces).isEmpty {
            msg = m
        } else {
            msg = session.state.rawValue.capitalized
        }
        return "\(label) [\(project)] → \(msg)"
    }

    /// Sort order for the ticker: waiting first, then working (most-recently
    /// updated first), then done. Idle and registered sessions are excluded
    /// before calling this — the caller is responsible for filtering.
    public static func sorted(_ sessions: [AgentSession]) -> [AgentSession] {
        sessions.sorted { a, b in
            let pa = priority(a.state)
            let pb = priority(b.state)
            if pa != pb { return pa < pb }
            return a.updatedAt > b.updatedAt   // most recent first within a tier
        }
    }

    // MARK: - Private

    private static func priority(_ state: AgentState) -> Int {
        switch state {
        case .waiting:    return 0
        case .working:    return 1
        case .done:       return 2
        case .idle:       return 3
        case .registered: return 4
        }
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
cd /path/to/agentpet
swift build --target AgentPetCore 2>&1 | tail -5
```

Expected: `Build complete!` with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentPetCore/TickerFormatter.swift
git commit -m "feat(core): add TickerFormatter — label/line/sort for agent ticker"
```

---

## Task 2: Tests for `TickerFormatter`

**Files:**
- Create: `Tests/AgentPetCoreTests/TickerFormatterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/AgentPetCoreTests/TickerFormatterTests.swift
import XCTest
@testable import AgentPetCore

final class TickerFormatterTests: XCTestCase {

    // MARK: agentLabel

    func testAgentLabelKnownKinds() {
        XCTAssertEqual(TickerFormatter.agentLabel(for: .claude),   "Claude")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .cursor),   "Cursor")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .codex),    "Codex")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .gemini),   "Gemini")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .opencode), "Opencode")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .windsurf), "Windsurf")
    }

    func testAgentLabelFallbacks() {
        XCTAssertEqual(TickerFormatter.agentLabel(for: .cli),     "Agent")
        XCTAssertEqual(TickerFormatter.agentLabel(for: .unknown), "Agent")
    }

    // MARK: line(for:)

    func testLineWithMessage() {
        let session = AgentSession(
            id: "claude-abc",
            agentKind: .claude,
            project: "/Users/me/agentpet",
            state: .working,
            message: "running bash…",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Claude [agentpet] → running bash…")
    }

    func testLineWithoutMessage() {
        let session = AgentSession(
            id: "cursor-xyz",
            agentKind: .cursor,
            project: "/Users/me/my-api",
            state: .waiting,
            message: nil,
            source: .hook,
            updatedAt: Date()
        )
        // No message → falls back to state name
        XCTAssertEqual(TickerFormatter.line(for: session), "Cursor [my-api] → Waiting")
    }

    func testLineWithWhitespaceOnlyMessage() {
        let session = AgentSession(
            id: "gemini-1",
            agentKind: .gemini,
            project: "/Users/me/frontend",
            state: .working,
            message: "   ",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Gemini [frontend] → Working")
    }

    func testLineFallsBackToIdWhenNoProject() {
        let session = AgentSession(
            id: "my-session-id",
            agentKind: .cli,
            project: nil,
            state: .working,
            message: "running",
            source: .hook,
            updatedAt: Date()
        )
        XCTAssertEqual(TickerFormatter.line(for: session), "Agent [my-session-id] → running")
    }

    // MARK: sorted(_:)

    func testSortedWaitingFirst() {
        let t = Date()
        let working = AgentSession(id: "a", agentKind: .claude, state: .working, source: .hook, updatedAt: t)
        let waiting = AgentSession(id: "b", agentKind: .cursor, state: .waiting, source: .hook, updatedAt: t)
        let done    = AgentSession(id: "c", agentKind: .codex,  state: .done,    source: .hook, updatedAt: t)

        let result = TickerFormatter.sorted([done, working, waiting])
        XCTAssertEqual(result.map(\.id), ["b", "a", "c"])
    }

    func testSortedWorkingByMostRecentFirst() {
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 10)
        let older  = AgentSession(id: "old",   agentKind: .claude, state: .working, source: .hook, updatedAt: t0)
        let newer  = AgentSession(id: "newer", agentKind: .cursor, state: .working, source: .hook, updatedAt: t1)

        let result = TickerFormatter.sorted([older, newer])
        XCTAssertEqual(result.first?.id, "newer", "most recently updated working agent comes first")
    }
}
```

- [ ] **Step 2: Run tests to confirm they fail (TickerFormatter not yet present)**

```bash
swift test --filter TickerFormatterTests 2>&1 | grep -E "error:|FAIL|passed|failed"
```

Expected: compile error because `TickerFormatter` doesn't exist yet. (If Task 1 is already done, they should pass — skip to step 3.)

- [ ] **Step 3: Run tests after Task 1 is done, confirm they all pass**

```bash
swift test --filter TickerFormatterTests 2>&1 | grep -E "Test.*passed|Test.*failed|error:"
```

Expected output (all 7 tests pass):
```
Test Suite 'TickerFormatterTests' passed
```

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentPetCoreTests/TickerFormatterTests.swift
git commit -m "test(core): TickerFormatter — label, line format, sort order"
```

---

## Task 3: Ticker engine in `PetController`

**Files:**
- Modify: `Sources/App/PetController.swift`

Read the current file first. The changes are surgical — three targeted edits.

### 3a — Add ticker state properties

- [ ] **Step 1: Add three private properties after `private var chatTimer: Timer?`**

Find this block (around line 39):
```swift
private var lastResolved: PetMood = .idle
private var latestSessions: [AgentSession] = []
private var celebrateTimer: Timer?
private var chatTimer: Timer?
```

Replace with:
```swift
private var lastResolved: PetMood = .idle
private var latestSessions: [AgentSession] = []
private var celebrateTimer: Timer?
private var chatTimer: Timer?

// Ticker state
private var tickerIndex: Int = 0
private var tickerSessions: [AgentSession] = []
private var tickerTimer: Timer?
private static let tickerInterval: TimeInterval = 4.0
```

### 3b — Update `update(sessions:)` to drive the ticker

- [ ] **Step 2: Integrate ticker into `update(sessions:)`**

Find the existing `update(sessions:)` method:
```swift
func update(sessions: [AgentSession]) {
    latestSessions = sessions
    let resolved = MoodResolver.aggregate(sessions)
    defer { lastResolved = resolved }

    if resolved == .done && lastResolved != .done {
        setMood(.celebrate)
        celebrateTimer?.invalidate()
        celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
        }
        return
    }
    if mood == .celebrate && resolved == .done {
        return  // let the celebration finish
    }
    celebrateTimer?.invalidate()
    setMood(resolved)
}
```

Replace with:
```swift
func update(sessions: [AgentSession]) {
    latestSessions = sessions
    let resolved = MoodResolver.aggregate(sessions)
    defer { lastResolved = resolved }

    if resolved == .done && lastResolved != .done {
        stopTicker()
        setMood(.celebrate)
        celebrateTimer?.invalidate()
        celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
        }
        return
    }
    if mood == .celebrate && resolved == .done {
        return  // let the celebration finish
    }
    celebrateTimer?.invalidate()
    setMood(resolved)

    if resolved == .working || resolved == .waiting {
        applyTickerSessions(sessions)
    } else {
        stopTicker()
    }
}
```

### 3c — Replace `refreshChat()` and add ticker helpers

- [ ] **Step 3: Update `refreshChat()` and add ticker methods**

Find the existing `refreshChat()` method:
```swift
private func refreshChat() {
    let pool = ChatSettings.shared.lines(for: mood)
    guard showChat, mood != .idle, !pool.isEmpty else {
        chatLine = ""
        StatusBarController.shared.refreshTitle()
        return
    }
    chatLine = pool.randomElement() ?? ""
    StatusBarController.shared.refreshTitle()
}
```

Replace with:
```swift
private func refreshChat() {
    guard showChat, mood != .idle else {
        chatLine = ""
        StatusBarController.shared.refreshTitle()
        return
    }
    // During working/waiting the ticker owns chatLine; fall back to PetChat for
    // celebrate/done where the ticker is stopped.
    if (mood == .working || mood == .waiting) && !tickerSessions.isEmpty {
        showCurrentTickerLine()
        return
    }
    let pool = ChatSettings.shared.lines(for: mood)
    guard !pool.isEmpty else {
        chatLine = ""
        StatusBarController.shared.refreshTitle()
        return
    }
    chatLine = pool.randomElement() ?? ""
    StatusBarController.shared.refreshTitle()
}

// MARK: - Ticker

private func applyTickerSessions(_ sessions: [AgentSession]) {
    let active = sessions.filter { $0.state != .idle && $0.state != .registered }
    let sorted = TickerFormatter.sorted(active)
    let changed = sorted.map(\.id) != tickerSessions.map(\.id)
    tickerSessions = sorted
    if sorted.isEmpty {
        stopTicker()
        chatLine = ""
        StatusBarController.shared.refreshTitle()
        return
    }
    if changed { tickerIndex = 0 }
    showCurrentTickerLine()
    startTickerIfNeeded()
}

private func startTickerIfNeeded() {
    guard tickerTimer == nil else { return }
    tickerTimer = Timer.scheduledTimer(withTimeInterval: Self.tickerInterval, repeats: true) { _ in
        Task { @MainActor [weak self] in self?.advanceTicker() }
    }
}

private func stopTicker() {
    tickerTimer?.invalidate()
    tickerTimer = nil
    tickerIndex = 0
    tickerSessions = []
}

private func advanceTicker() {
    guard !tickerSessions.isEmpty else { stopTicker(); return }
    tickerIndex = (tickerIndex + 1) % tickerSessions.count
    showCurrentTickerLine()
}

private func showCurrentTickerLine() {
    guard showChat, !tickerSessions.isEmpty else {
        chatLine = ""
        StatusBarController.shared.refreshTitle()
        return
    }
    chatLine = TickerFormatter.line(for: tickerSessions[tickerIndex % tickerSessions.count])
    StatusBarController.shared.refreshTitle()
}
```

- [ ] **Step 4: Remove the now-unused `chatTimer` (the ticker timer replaces it)**

Find and remove the `chatTimer` setup in `start()`:
```swift
func start() {
    // Vary the chat line periodically while the pet is active.
    chatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
        Task { @MainActor [weak self] in self?.refreshChat() }
    }
}
```

Replace with:
```swift
func start() {
    // Ticker drives chatLine updates; no separate chat timer needed.
}
```

Also remove the `private var chatTimer: Timer?` property line added in Step 1 — it's no longer used. The property was in the block you already edited in Step 1, so remove it there.

> **Final state of the properties block after both edits:**
> ```swift
> private var lastResolved: PetMood = .idle
> private var latestSessions: [AgentSession] = []
> private var celebrateTimer: Timer?
> 
> // Ticker state
> private var tickerIndex: Int = 0
> private var tickerSessions: [AgentSession] = []
> private var tickerTimer: Timer?
> private static let tickerInterval: TimeInterval = 4.0
> ```

- [ ] **Step 5: Build the full app target**

```bash
swift build 2>&1 | grep -E "error:|warning:|Build complete"
```

Expected: `Build complete!` with no errors. Fix any compiler errors before proceeding.

- [ ] **Step 6: Run all tests to confirm nothing is broken**

```bash
swift test 2>&1 | grep -E "passed|failed|error:"
```

Expected: all tests pass, including the new `TickerFormatterTests`.

- [ ] **Step 7: Manual smoke test**

1. Build and open `AgentPet.app`.
2. In a terminal, run: `agentpet run --agent claude --project /tmp/demo -- sleep 30`
3. Open a second: `agentpet run --agent cursor --project /tmp/other -- sleep 30`
4. Watch the desktop pet's chat bubble — it should cycle:
   - `Claude [demo] → Working` (4 s)
   - `Cursor [other] → Working` (4 s)
   - repeat
5. Kill the `sleep` processes → bubble should disappear.
6. Verify `.celebrate` still plays (finish a real agent session normally).

- [ ] **Step 8: Commit**

```bash
git add Sources/App/PetController.swift
git commit -m "feat(pet): ticker chat bubble — cycles through active agents every 4s"
```

---

## Self-Review Checklist

- [x] **Spec: ticker cycles all active agents** — `applyTickerSessions` + timer in `advanceTicker` ✓
- [x] **Spec: waiting agents first** — `TickerFormatter.sorted` priority 0 ✓
- [x] **Spec: format `<Agent> [<project>] → <msg>`** — `TickerFormatter.line(for:)` ✓
- [x] **Spec: 0 sessions → bubble hides** — `stopTicker()` + `chatLine = ""` in `applyTickerSessions` ✓
- [x] **Spec: celebrate/done keep PetChat lines** — `stopTicker()` called before `setMood(.celebrate)` ✓
- [x] **Spec: `showChat = false` respected** — `showCurrentTickerLine()` guards on `showChat` ✓
- [x] **Spec: session change resets to index 0** — `if changed { tickerIndex = 0 }` ✓
- [x] **No placeholders** — all code shown inline ✓
- [x] **Type consistency** — `TickerFormatter.sorted`, `TickerFormatter.line(for:)` used consistently across tasks ✓
