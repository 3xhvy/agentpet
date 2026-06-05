# Bubble Display Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users configure which tokens appear in the agent bubble, in what order, with which icons, appearance, and session filters — all persisted to UserDefaults and accessible from a new "Bubble" tab in Settings.

**Architecture:** A new `BubbleSettings` ObservableObject (mirrors `ChatSettings`) holds all preferences. `AgentRow` iterates its `effectiveLayout` to render tokens. `AgentBubble` applies its filter/sort settings before building rows. `BubbleSettingsView` provides the settings UI via a new tab in `SetupView`.

**Tech Stack:** SwiftUI, AppKit, UserDefaults, XCTest (logic tests only — `BubbleSettings` lives in the App target, which is not importable in tests)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `Sources/App/BubbleSettings.swift` | **Create** | All model types: `BubbleToken`, `BubbleTokenItem`, `BubbleLayout`, `IconChoice`, `MinStateFilter`, `BubbleSettings` |
| `Sources/App/AgentIcons.swift` | **Modify** | Add `ResolvedIconView`; keep `AgentIconView` as a wrapper |
| `Sources/App/BubbleSettingsView.swift` | **Create** | Full settings tab UI including `IconPickerPopover` |
| `Sources/App/PetView.swift` | **Modify** | `AgentBubble` applies filter/sort/cap; `AgentRow` iterates layout tokens |
| `Sources/App/SetupView.swift` | **Modify** | Add "Bubble" tab to the tab bar |

---

## Task 1: `BubbleSettings` Model

**Files:**
- Create: `Sources/App/BubbleSettings.swift`

- [ ] **Step 1: Create `BubbleSettings.swift` with all model types**

```swift
import Foundation
import AgentPetCore

// MARK: - Token types

enum BubbleToken: String, CaseIterable, Codable, Identifiable {
    case dot, icon, title, project, separator, message, stateLabel, elapsed
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot:        return "State dot"
        case .icon:       return "Agent icon"
        case .title:      return "Chat title"
        case .project:    return "Project folder"
        case .separator:  return "Separator"
        case .message:    return "Activity message"
        case .stateLabel: return "State label"
        case .elapsed:    return "Elapsed time"
        }
    }
}

struct BubbleTokenItem: Codable, Identifiable, Equatable {
    var id: String { token.rawValue }
    let token: BubbleToken
    var isVisible: Bool
}

struct BubbleLayout: Codable, Equatable {
    var tokens: [BubbleTokenItem]

    static let original = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .title,      isVisible: false),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
    ])

    static let standard = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
    ])

    static let detailed = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: true),
        .init(token: .elapsed,    isVisible: true),
    ])

    static func preset(named preset: BubbleSettings.Preset) -> BubbleLayout {
        switch preset {
        case .original: return .original
        case .standard: return .standard
        case .detailed: return .detailed
        case .custom:   return .original
        }
    }
}

// MARK: - Icon choice

enum IconChoice: Equatable {
    case brandLogo(AgentKind)
    case sfSymbol(String)
}

extension IconChoice: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "brandLogo": self = .brandLogo(AgentKind(rawValue: value) ?? .unknown)
        default:          self = .sfSymbol(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brandLogo(let k):
            try c.encode("brandLogo", forKey: .type)
            try c.encode(k.rawValue, forKey: .value)
        case .sfSymbol(let n):
            try c.encode("sfSymbol", forKey: .type)
            try c.encode(n, forKey: .value)
        }
    }
}

// MARK: - Min-state filter

enum MinStateFilter: String, CaseIterable, Codable {
    case all, doneAndAbove, workingAndWaiting, workingOnly

    var displayName: String {
        switch self {
        case .all:               return "All states"
        case .doneAndAbove:      return "Done and above"
        case .workingAndWaiting: return "Working & Waiting"
        case .workingOnly:       return "Working only"
        }
    }

    func includes(_ state: AgentState) -> Bool {
        switch self {
        case .all:               return true
        case .doneAndAbove:      return state.attentionPriority >= 2
        case .workingAndWaiting: return state.attentionPriority >= 3
        case .workingOnly:       return state == .working
        }
    }
}

// MARK: - BubbleSettings

@MainActor
final class BubbleSettings: ObservableObject {
    static let shared = BubbleSettings()

    enum Preset: String, CaseIterable, Codable {
        case original, standard, detailed, custom
        var displayName: String { rawValue.capitalized }
    }

    enum FontSize: String, CaseIterable, Codable {
        case small, medium, large
        var primaryPt: CGFloat   { switch self { case .small: 10; case .medium: 12; case .large: 14 } }
        var secondaryPt: CGFloat { switch self { case .small: 9;  case .medium: 10.5; case .large: 12 } }
        var iconPt: CGFloat      { primaryPt + 2 }
    }

    enum Theme: String, CaseIterable, Codable {
        case light, dark, system
        var displayName: String { rawValue.capitalized }
    }

    // MARK: Published properties

    @Published var preset: Preset {
        didSet { ud.set(preset.rawValue, forKey: Keys.preset) }
    }
    @Published var customLayout: BubbleLayout {
        didSet { saveJSON(Keys.customLayout, customLayout) }
    }
    @Published var separatorChar: String {
        didSet { ud.set(separatorChar, forKey: Keys.separatorChar) }
    }
    @Published var fontSize: FontSize {
        didSet { ud.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    @Published var opacity: Double {
        didSet { ud.set(opacity, forKey: Keys.opacity) }
    }
    @Published var theme: Theme {
        didSet { ud.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var maxSessions: Int {
        didSet { ud.set(maxSessions, forKey: Keys.maxSessions) }
    }
    @Published var minStateFilter: MinStateFilter {
        didSet { ud.set(minStateFilter.rawValue, forKey: Keys.minStateFilter) }
    }
    @Published var groupByKind: Bool {
        didSet { ud.set(groupByKind, forKey: Keys.groupByKind) }
    }
    @Published var hiddenKinds: Set<AgentKind> {
        didSet { saveJSON(Keys.hiddenKinds, Array(hiddenKinds).map(\.rawValue)) }
    }
    /// Keyed by AgentKind.rawValue for JSON compatibility.
    @Published var iconChoices: [String: IconChoice] {
        didSet { saveJSON(Keys.iconChoices, iconChoices) }
    }

    // MARK: Computed

    var effectiveLayout: BubbleLayout {
        preset == .custom ? customLayout : BubbleLayout.preset(named: preset)
    }

    func iconChoice(for kind: AgentKind) -> IconChoice {
        iconChoices[kind.rawValue] ?? .brandLogo(kind)
    }

    func setIconChoice(_ choice: IconChoice, for kind: AgentKind) {
        iconChoices[kind.rawValue] = choice
    }

    func resetIconChoice(for kind: AgentKind) {
        iconChoices.removeValue(forKey: kind.rawValue)
    }

    // MARK: Private

    private let ud = UserDefaults.standard

    private enum Keys {
        static let preset          = "agentpet.bubble.preset"
        static let customLayout    = "agentpet.bubble.customLayout"
        static let separatorChar   = "agentpet.bubble.separatorChar"
        static let fontSize        = "agentpet.bubble.fontSize"
        static let opacity         = "agentpet.bubble.opacity"
        static let theme           = "agentpet.bubble.theme"
        static let maxSessions     = "agentpet.bubble.maxSessions"
        static let minStateFilter  = "agentpet.bubble.minStateFilter"
        static let groupByKind     = "agentpet.bubble.groupByKind"
        static let hiddenKinds     = "agentpet.bubble.hiddenKinds"
        static let iconChoices     = "agentpet.bubble.iconChoices"
    }

    init() {
        preset         = Preset(rawValue: ud.string(forKey: Keys.preset) ?? "") ?? .original
        customLayout   = loadJSON(Keys.customLayout) ?? .original
        separatorChar  = ud.string(forKey: Keys.separatorChar) ?? "·"
        fontSize       = FontSize(rawValue: ud.string(forKey: Keys.fontSize) ?? "") ?? .medium
        opacity        = ud.object(forKey: Keys.opacity) as? Double ?? 1.0
        theme          = Theme(rawValue: ud.string(forKey: Keys.theme) ?? "") ?? .light
        maxSessions    = ud.object(forKey: Keys.maxSessions) as? Int ?? 5
        minStateFilter = MinStateFilter(rawValue: ud.string(forKey: Keys.minStateFilter) ?? "") ?? .all
        groupByKind    = ud.bool(forKey: Keys.groupByKind)
        hiddenKinds    = Set((loadJSON(Keys.hiddenKinds) as [String]? ?? []).compactMap(AgentKind.init(rawValue:)))
        iconChoices    = loadJSON(Keys.iconChoices) ?? [:]
    }

    private func saveJSON<T: Encodable>(_ key: String, _ value: T) {
        ud.set(try? JSONEncoder().encode(value), forKey: key)
    }
}

private func loadJSON<T: Decodable>(_ key: String) -> T? {
    guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(T.self, from: data)
}
```

- [ ] **Step 2: Build to verify it compiles**

```bash
cd /Users/hohoanghvy/Projects/agentpet && swift build 2>&1 | grep -E "error:|build complete"
```

Expected: `ok (build complete)`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/BubbleSettings.swift
git commit -m "feat: add BubbleSettings model with layout, icon, and filter types"
```

---

## Task 2: `ResolvedIconView` in `AgentIcons.swift`

**Files:**
- Modify: `Sources/App/AgentIcons.swift`

The curated SF Symbol list lives here so it's one canonical source for both the picker and the view.

- [ ] **Step 1: Add `ResolvedIconView` and `AgentKind: Identifiable` to `AgentIcons.swift`**

At the bottom of `Sources/App/AgentIcons.swift`, append:

```swift
// MARK: - AgentKind identifiable (needed for popover(item:))

extension AgentKind: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Curated SF Symbols for the icon picker

extension AgentIcons {
    /// All AgentKind cases that have embedded SVG brand logos.
    static let brandKinds: [AgentKind] = [.claude, .cursor, .codex, .gemini, .windsurf, .opencode]

    /// 28 curated SF Symbol names shown in the icon picker.
    static let curatedSymbols: [String] = [
        // Code & Terminal
        "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "cpu", "command",
        // AI & Magic
        "brain", "wand.and.stars", "sparkles", "bolt",
        // Workflow
        "arrow.triangle.2.circlepath", "checklist", "tray.and.arrow.down", "doc.text",
        // Network
        "antenna.radiowaves.left.and.right", "network", "wifi", "cloud",
        // Interface
        "gear", "slider.horizontal.3", "paintbrush", "theatermasks", "person.crop.circle",
        // Objects
        "desktopcomputer", "laptopcomputer", "keyboard", "hammer", "wrench.and.screwdriver",
        // Extra
        "eye", "hourglass",
    ]
}

// MARK: - ResolvedIconView

/// Renders an `IconChoice` — either a brand SVG logo or an SF Symbol.
struct ResolvedIconView: View {
    let choice: IconChoice
    var size: CGFloat = 14

    var body: some View {
        switch choice {
        case .brandLogo(let kind):
            if let img = AgentIcons.image(for: kind) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: fallback(for: kind))
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
    }

    private func fallback(for kind: AgentKind) -> String {
        switch kind {
        case .cli:     return "terminal"
        case .unknown: return "questionmark.circle"
        default:       return "sparkle"
        }
    }
}
```

- [ ] **Step 2: Update `AgentIconView` to delegate to `ResolvedIconView`**

Replace the existing `AgentIconView.body` with:

```swift
struct AgentIconView: View {
    let kind: AgentKind
    var size: CGFloat = 14

    var body: some View {
        ResolvedIconView(choice: .brandLogo(kind), size: size)
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|build complete"
```

Expected: `ok (build complete)`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/AgentIcons.swift
git commit -m "feat: add ResolvedIconView and icon picker helpers to AgentIcons"
```

---

## Task 3: Refactor `AgentBubble` and `AgentRow` in `PetView.swift`

**Files:**
- Modify: `Sources/App/PetView.swift`

This task replaces the hardcoded rendering with layout-driven rendering and applies `BubbleSettings` filters to the session list.

- [ ] **Step 1: Replace `AgentBubble`**

Replace the entire `AgentBubble` struct with:

```swift
private struct AgentBubble: View {
    let sessions: [AgentSession]
    @ObservedObject private var settings = BubbleSettings.shared

    private var displaySessions: [AgentSession] {
        var result = sessions
            .filter { !settings.hiddenKinds.contains($0.agentKind) }
            .filter { settings.minStateFilter.includes($0.state) }
        if settings.groupByKind {
            result.sort {
                if $0.agentKind.rawValue != $1.agentKind.rawValue {
                    return $0.agentKind.rawValue < $1.agentKind.rawValue
                }
                if $0.state.attentionPriority != $1.state.attentionPriority {
                    return $0.state.attentionPriority > $1.state.attentionPriority
                }
                return $0.updatedAt > $1.updatedAt
            }
        } else {
            result.sort {
                if $0.state.attentionPriority != $1.state.attentionPriority {
                    return $0.state.attentionPriority > $1.state.attentionPriority
                }
                return $0.updatedAt > $1.updatedAt
            }
        }
        return Array(result.prefix(settings.maxSessions))
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(displaySessions) { session in
                    AgentRow(session: session)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(bubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(bubbleFill)
                .frame(width: 12, height: 7)
        }
        .fixedSize()
    }

    private var bubbleFill: Color {
        switch settings.theme {
        case .light:  return Color.white.opacity(settings.opacity)
        case .dark:   return Color(nsColor: .windowBackgroundColor).opacity(settings.opacity)
        case .system: return Color(nsColor: .textBackgroundColor).opacity(settings.opacity)
        }
    }

    private var borderColor: Color {
        switch settings.theme {
        case .light:  return .black.opacity(0.06)
        case .dark:   return .white.opacity(0.12)
        case .system: return Color.primary.opacity(0.08)
        }
    }
}
```

- [ ] **Step 2: Replace `AgentRow`**

Replace the entire `AgentRow` struct with:

```swift
private struct AgentRow: View {
    let session: AgentSession
    @ObservedObject private var settings = BubbleSettings.shared

    var body: some View {
        let visible = settings.effectiveLayout.tokens.filter { $0.isVisible && tokenHasValue($0.token) }
        HStack(alignment: .center, spacing: 4) {
            ForEach(visible) { item in
                tokenView(for: item.token)
            }
        }
    }

    @ViewBuilder
    private func tokenView(for token: BubbleToken) -> some View {
        switch token {
        case .dot:
            Circle()
                .fill(stateDotColor)
                .frame(width: 6, height: 6)
        case .icon:
            ResolvedIconView(
                choice: settings.iconChoice(for: session.agentKind),
                size: settings.fontSize.iconPt
            )
        case .title:
            if let title = session.title {
                Text(title)
                    .font(.system(size: settings.fontSize.primaryPt, weight: .semibold))
                    .foregroundStyle(textColor(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        case .project:
            Text(projectName)
                .font(.system(size: settings.fontSize.primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        case .separator:
            Text(settings.separatorChar)
                .font(.system(size: settings.fontSize.primaryPt, weight: .regular))
                .foregroundStyle(textColor(0.35))
        case .message:
            Text(messageText)
                .font(.system(size: settings.fontSize.primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        case .stateLabel:
            Text(session.state.rawValue.capitalized)
                .font(.system(size: settings.fontSize.secondaryPt, weight: .regular))
                .foregroundStyle(textColor(0.55))
        case .elapsed:
            Text(elapsedString(since: session.stateSince))
                .font(.system(size: settings.fontSize.secondaryPt, weight: .regular))
                .foregroundStyle(textColor(0.45))
                .monospacedDigit()
        }
    }

    private func tokenHasValue(_ token: BubbleToken) -> Bool {
        switch token {
        case .title: return session.title != nil
        default:     return true
        }
    }

    private func textColor(_ opacity: Double) -> Color {
        switch settings.theme {
        case .light:  return .black.opacity(opacity)
        case .dark:   return .white.opacity(opacity)
        case .system: return Color.primary.opacity(opacity)
        }
    }

    private var projectName: String {
        session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
    }

    private var messageText: String {
        let m = session.message?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? session.state.rawValue.capitalized : m
    }

    private var stateDotColor: Color {
        switch session.state {
        case .waiting:             return .orange
        case .working:             return Color(red: 0.22, green: 0.53, blue: 1.0)
        case .done:                return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .idle, .registered:   return .gray
        }
    }

    private func elapsedString(since date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60  { return "\(s)s" }
        let m = s / 60
        if m < 60  { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|build complete"
```

Expected: `ok (build complete)`

- [ ] **Step 4: Commit**

```bash
git add Sources/App/PetView.swift
git commit -m "feat: AgentRow reads BubbleSettings layout; AgentBubble applies filters"
```

---

## Task 4: `BubbleSettingsView` + `IconPickerPopover`

**Files:**
- Create: `Sources/App/BubbleSettingsView.swift`

- [ ] **Step 1: Create the file**

```swift
import SwiftUI
import AgentPetCore

struct BubbleSettingsView: View {
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var iconPickerKind: AgentKind?

    var body: some View {
        Form {
            presetSection
            tokenOrderSection
            agentIconsSection
            appearanceSection
            filterSection
        }
        .formStyle(.grouped)
        .popover(item: $iconPickerKind) { kind in
            IconPickerPopover(kind: kind)
        }
    }

    // MARK: Preset

    private var presetSection: some View {
        Section("Layout preset") {
            Picker("Preset", selection: $settings.preset) {
                ForEach(BubbleSettings.Preset.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: Token Order

    private var tokenOrderSection: some View {
        let isCustom = settings.preset == .custom
        return Section {
            List {
                ForEach($settings.customLayout.tokens) { $item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Toggle(item.token.displayName, isOn: $item.isVisible)
                            .onChange(of: item.isVisible) { _ in
                                settings.preset = .custom
                            }
                    }
                }
                .onMove { from, to in
                    settings.customLayout.tokens.move(fromOffsets: from, toOffset: to)
                    settings.preset = .custom
                }
            }
            .environment(\.editMode, .constant(isCustom ? .active : .inactive))
            .frame(height: CGFloat(settings.customLayout.tokens.count) * 40)
            .opacity(isCustom ? 1.0 : 0.5)
            .disabled(!isCustom)

            Button("Reset to Original") {
                settings.customLayout = .original
            }
            .disabled(!isCustom)
        } header: {
            Text("Token Order")
        } footer: {
            Text(isCustom
                ? "Drag to reorder. Toggle to show or hide."
                : "Select "Custom" above to edit the token order.")
        }
    }

    // MARK: Agent Icons

    private var agentIconsSection: some View {
        Section("Agent Icons") {
            ForEach(AgentCatalog.all, id: \.kind) { agent in
                HStack(spacing: 10) {
                    ResolvedIconView(choice: settings.iconChoice(for: agent.kind), size: 20)
                    Text(agent.displayName)
                    Spacer()
                    Button("Change…") { iconPickerKind = agent.kind }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Text("Separator")
                Spacer()
                Picker("Separator", selection: $settings.separatorChar) {
                    Text("·").tag("·")
                    Text("→").tag("→")
                    Text("|").tag("|")
                    Text("·none·").tag(" ")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Font size")
                Spacer()
                Picker("Font size", selection: $settings.fontSize) {
                    Text("S").tag(BubbleSettings.FontSize.small)
                    Text("M").tag(BubbleSettings.FontSize.medium)
                    Text("L").tag(BubbleSettings.FontSize.large)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Opacity")
                Slider(value: $settings.opacity, in: 0.6...1.0)
                Text("\(Int(settings.opacity * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
            }

            HStack {
                Text("Theme")
                Spacer()
                Picker("Theme", selection: $settings.theme) {
                    ForEach(BubbleSettings.Theme.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
        }
    }

    // MARK: Filter & Sort

    private var filterSection: some View {
        Section("Filter & Sort") {
            Stepper(
                "Max sessions: \(settings.maxSessions)",
                value: $settings.maxSessions,
                in: 1...10
            )

            Picker("Show sessions", selection: $settings.minStateFilter) {
                ForEach(MinStateFilter.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }

            Toggle("Group by agent kind", isOn: $settings.groupByKind)

            Section("Hide agents") {
                ForEach(AgentCatalog.all, id: \.kind) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get:  { !settings.hiddenKinds.contains(agent.kind) },
                        set:  { show in
                            if show { settings.hiddenKinds.remove(agent.kind) }
                            else    { settings.hiddenKinds.insert(agent.kind) }
                        }
                    ))
                }
            }
        }
    }
}

// MARK: - Icon Picker Popover

struct IconPickerPopover: View {
    let kind: AgentKind
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var search = ""

    private var filteredSymbols: [String] {
        search.isEmpty ? AgentIcons.curatedSymbols
            : AgentIcons.curatedSymbols.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var kindName: String {
        AgentCatalog.all.first { $0.kind == kind }?.displayName ?? kind.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Icon for \(kindName)")
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Brand logos grid
                    Text("Brand logos")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                        spacing: 8
                    ) {
                        ForEach(AgentIcons.brandKinds, id: \.self) { logoKind in
                            iconCell(choice: .brandLogo(logoKind)) {
                                ResolvedIconView(choice: .brandLogo(logoKind), size: 22)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // SF Symbols grid
                    HStack {
                        Text("SF Symbols")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TextField("Search", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)
                            .frame(width: 110)
                    }
                    .padding(.horizontal)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                        spacing: 8
                    ) {
                        ForEach(filteredSymbols, id: \.self) { sym in
                            iconCell(choice: .sfSymbol(sym)) {
                                Image(systemName: sym)
                                    .font(.system(size: 18))
                                    .frame(width: 22, height: 22)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Reset to default") {
                    settings.resetIconChoice(for: kind)
                }
                .controlSize(.small)
                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 380)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func iconCell<Content: View>(
        choice: IconChoice,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = settings.iconChoice(for: kind) == choice
        Button {
            settings.setIconChoice(choice, for: kind)
        } label: {
            content()
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|build complete"
```

Expected: `ok (build complete)`

- [ ] **Step 3: Commit**

```bash
git add Sources/App/BubbleSettingsView.swift
git commit -m "feat: add BubbleSettingsView and IconPickerPopover"
```

---

## Task 5: Wire "Bubble" Tab into `SetupView`

**Files:**
- Modify: `Sources/App/SetupView.swift`

- [ ] **Step 1: Add `.bubble` to the `Tab` enum**

In `SetupView`, find:
```swift
enum Tab { case general, pet, about }
```
Replace with:
```swift
enum Tab { case general, pet, bubble, about }
```

- [ ] **Step 2: Add the tab button to `tabBar`**

In the `tabBar` computed property, add after the Pet button:
```swift
TabButton(icon: "bubble.left.and.bubble.right.fill", label: "Bubble", selected: tab == .bubble) { tab = .bubble }
```

- [ ] **Step 3: Add the case to the `Group` switch**

In the `Group { switch tab { ... } }` block, add before `.about`:
```swift
case .bubble:
    BubbleSettingsView()
```

- [ ] **Step 4: Build and run**

```bash
swift build 2>&1 | grep -E "error:|build complete"
```

Expected: `ok (build complete)`

```bash
pkill -x AgentPet 2>/dev/null; sleep 1 && bash scripts/build-app.sh 2>&1 | tail -3
open "/Users/hohoanghvy/Projects/agentpet/build/AgentPet.app"
```

**Manual checks:**
- [ ] Settings window shows "Bubble" tab
- [ ] Switching presets immediately changes the live bubble
- [ ] Custom mode enables drag-drop token reordering
- [ ] "Change…" opens the icon picker popover
- [ ] Picking a brand logo or SF symbol updates the bubble icon live
- [ ] Opacity slider changes bubble transparency live
- [ ] Max sessions stepper correctly caps the session list
- [ ] Hiding an agent kind removes its rows from the bubble

- [ ] **Step 5: Commit**

```bash
git add Sources/App/SetupView.swift
git commit -m "feat: add Bubble tab to Settings for configurable agent bubble display"
```
