import SwiftUI
import AgentPetCore

/// The pet sprite alone (imported pack, reacting to mood). Shows a paw
/// placeholder if no pet is selected yet.
struct PetView: View {
    var size: CGFloat = 120
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var bindings = PetBindingsStore.shared

    var body: some View {
        content
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var content: some View {
        if let id = pet.selectedPetID, let pack = imagePets.pack(id: id) {
            let clip = bindings.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: pet.mood)
            ImageSpriteView(frames: pack.clip(clip), mood: pet.mood, size: size)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.secondary)
        }
    }
}

/// Reports the natural size of the pet + bubble so the window can hug its content.
private struct PetContentSizeKey: PreferenceKey {
    static var defaultValue: CGSize { .zero }
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 { value = next }
    }
}

/// The full floating window content: a chat bubble above the pet.
struct FloatingPetView: View {
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var bubbleSettings = BubbleSettings.shared

    var body: some View {
        VStack(spacing: 2) {
            if pet.showChat && pet.selectedPetID != nil {
                if bubbleSettings.multiAgentBubbleEnabled && !pet.activeAgentSessions.isEmpty {
                    AgentBubble(sessions: pet.activeAgentSessions)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                } else if !pet.chatLine.isEmpty {
                    ChatBubble(text: pet.chatLine)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            PetView(size: pet.petPoint)
        }
        .fixedSize(horizontal: true, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: PetContentSizeKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(PetContentSizeKey.self) { size in
            PetWindowController.shared.resizeToContent(size)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.chatLine)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.activeAgentSessions.count)
        .animation(.easeInOut, value: pet.showChat)
    }
}

// MARK: - Agent Bubble (structured rows for working/waiting)

/// Sessions with the same agent kind + project are collapsed into one row.
private struct GroupedSession: Identifiable {
    let session: AgentSession   // highest-priority session in the group
    let count: Int              // total sessions sharing this kind+project
    var id: String { session.id }
}

/// Speech bubble listing one row per (agentKind, project) group.
/// Applies filter/sort/cap from `BubbleSettings` before rendering.
/// `tailEdge` controls whether the pointer arrow points down (pet) or up (menu bar).
struct AgentBubble: View {
    let sessions: [AgentSession]
    var tailEdge: Edge = .bottom
    @ObservedObject private var settings = BubbleSettings.shared

    // attentionPriority is internal to AgentPetCore — use local rank
    private func rank(_ s: AgentState) -> Int {
        switch s { case .working: 4; case .waiting: 3; case .done: 2; case .registered: 1; case .idle: 0 }
    }

    private var groupedSessions: [GroupedSession] {
        // 1. Filter
        let filtered = sessions
            .filter { !settings.hiddenKinds.contains($0.agentKind) }
            .filter { settings.minStateFilter.includes($0.state) }

        // 2. Sort
        var sorted = filtered
        if settings.groupByKind {
            sorted.sort {
                if $0.agentKind.rawValue != $1.agentKind.rawValue {
                    return $0.agentKind.rawValue < $1.agentKind.rawValue
                }
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
                return $0.updatedAt > $1.updatedAt
            }
        } else {
            sorted.sort {
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
                return $0.updatedAt > $1.updatedAt
            }
        }

        // 3. One row per session id. Collapse only exact duplicate ids (defensive).
        var result: [GroupedSession]
        if settings.collapseDuplicates {
            var seen: [String: Int] = [:]
            result = []
            for s in sorted {
                if let idx = seen[s.id] {
                    result[idx] = GroupedSession(session: result[idx].session, count: result[idx].count + 1)
                } else {
                    seen[s.id] = result.count
                    result.append(GroupedSession(session: s, count: 1))
                }
            }
        } else {
            result = sorted.map { GroupedSession(session: $0, count: 1) }
        }

        // 4. Cap to maxSessions
        return Array(result.prefix(settings.maxSessions))
    }

    private var isPetChat: Bool { tailEdge == .bottom }
    // Use capsule only for a single-agent pet-chat bubble; switch to rounded rect for 2+ agents.
    private var useCapsule: Bool { isPetChat && groupedSessions.count <= 1 }

    var body: some View {
        let fill = isPetChat ? Color.white : bubbleFill
        let stroke = isPetChat ? Color.black.opacity(0.06) : borderColor

        VStack(spacing: 0) {
            if tailEdge == .top {
                Triangle()
                    .fill(fill)
                    .frame(width: 12, height: 7)
                    .scaleEffect(x: 1, y: -1)
            }
            VStack(alignment: .leading, spacing: isPetChat ? 4 : 5) {
                ForEach(groupedSessions) { group in
                    AgentRow(session: group.session, count: group.count, chatStyle: isPetChat)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, isPetChat ? 7 : 9)
            .background {
                if useCapsule {
                    Capsule().fill(fill)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(fill)
                }
            }
            .overlay {
                if useCapsule {
                    Capsule().strokeBorder(stroke, lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke, lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            if tailEdge == .bottom {
                Triangle()
                    .fill(fill)
                    .frame(width: 12, height: 7)
            }
        }
        .fixedSize(horizontal: isPetChat, vertical: true)
        .frame(maxWidth: 420, alignment: .leading)
    }

    /// Inner content width cap (bubble max minus horizontal padding).
    static let contentMaxWidth: CGFloat = 396
    /// Pet chat bubble hugs content; still capped for very long lines.
    static let petContentMaxWidth: CGFloat = 320

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

/// One row per agent session. Iterates `BubbleSettings.effectiveLayout` tokens
/// in order on a single line; project/title shrink before the message does.
private struct AgentRow: View {
    let session: AgentSession
    var count: Int = 1
    var chatStyle: Bool = false
    @ObservedObject private var settings = BubbleSettings.shared

    private var primaryPt: CGFloat { chatStyle ? 12 : settings.fontSize.primaryPt }
    private var secondaryPt: CGFloat { chatStyle ? 10.5 : settings.fontSize.secondaryPt }
    private var iconPt: CGFloat { chatStyle ? 14 : settings.fontSize.iconPt }
    private var rowMaxWidth: CGFloat {
        chatStyle ? AgentBubble.petContentMaxWidth : AgentBubble.contentMaxWidth
    }

    private var isWaiting: Bool { session.state == .waiting }

    var body: some View {
        let visible = settings.effectiveLayout.tokens.filter { $0.isVisible && tokenHasValue($0.token) }

        HStack(alignment: .center, spacing: 4) {
            if visible.contains(where: { $0.token == .dot }) {
                tokenView(for: .dot)
            }
            HStack(alignment: .center, spacing: 4) {
                ForEach(visible.filter { $0.token != .dot }) { item in
                    tokenView(for: item.token)
                }
                if count > 1 {
                    Text("×\(count)")
                        .font(.system(size: settings.fontSize.secondaryPt, weight: .semibold))
                        .foregroundStyle(textColor(0.5))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(textColor(0.08))
                        )
                }
            }
            .modifier(WaitingTextFlash(active: isWaiting))
        }
        .frame(maxWidth: rowMaxWidth, alignment: .leading)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: session.message)
    }

    @ViewBuilder
    private func tokenView(for token: BubbleToken) -> some View {
        switch token {
        case .dot:
            StateDot(color: stateDotColor, style: dotStyle)
        case .icon:
            ResolvedIconView(
                choice: settings.iconChoice(for: session.agentKind),
                size: iconPt
            )
        case .title:
            if let title = session.title {
                Text(title)
                    .font(.system(size: primaryPt, weight: .semibold))
                    .foregroundStyle(textColor(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
            }
        case .project:
            Text(projectName)
                .font(.system(size: primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
        case .separator:
            Text(settings.separatorChar)
                .font(.system(size: primaryPt, weight: .regular))
                .foregroundStyle(textColor(0.35))
        case .message:
            Text(messageText)
                .font(.system(size: primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .id(messageText)
        case .stateLabel:
            Text(session.state.rawValue.capitalized)
                .font(.system(size: secondaryPt, weight: .regular))
                .foregroundStyle(textColor(0.55))
        case .elapsed:
            Text(elapsedString(since: session.stateSince))
                .font(.system(size: secondaryPt, weight: .regular))
                .foregroundStyle(textColor(0.45))
                .monospacedDigit()
        }
    }

    private func tokenHasValue(_ token: BubbleToken) -> Bool {
        if token == .title { return session.title != nil }
        return true
    }

    private func textColor(_ opacity: Double) -> Color {
        if chatStyle { return .black.opacity(opacity) }
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
        if !m.isEmpty { return m }
        return ClaudeActivityFormatter.stateMessage(for: session.state)
            ?? session.state.rawValue.capitalized
    }

    private var stateDotColor: Color {
        switch session.state {
        case .waiting:           return .orange
        case .working:           return Color(red: 0.22, green: 0.53, blue: 1.0)
        case .done:              return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .idle, .registered: return .gray
        }
    }

    private var dotStyle: StateDot.Style {
        switch session.state {
        case .working, .waiting, .done: return .pulse
        default:                        return .plain
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

// MARK: - Simple Chat Bubble (celebrate / done / waiting fallback)

/// A plain speech bubble with a downward tail, used for celebrate/done lines.
private struct ChatBubble: View {
    let text: String

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.85))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 7)
        }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: 420)
    }
}

// MARK: - State dot

/// State dot with optional sonar pulse (working, waiting, done) or plain.
private struct StateDot: View {
    enum Style { case plain, pulse }

    let color: Color
    let style: Style

    var body: some View {
        Group {
            switch style {
            case .plain:
                Circle().fill(color).frame(width: 6, height: 6)
            case .pulse:
                PulsingRingDot(color: color)
            }
        }
        .frame(width: 14, height: 14)
    }
}

private struct PulsingRingDot: View {
    let color: Color
    @State private var expanded = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: expanded ? 14 : 6, height: expanded ? 14 : 6)
                .opacity(expanded ? 0 : 0.8)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).repeatForever(autoreverses: false)) {
                expanded = true
            }
        }
    }
}

// MARK: - Waiting text flash

/// Gently pulses row text opacity when waiting for input (no strikethrough).
private struct WaitingTextFlash: ViewModifier {
    let active: Bool
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(active ? (dimmed ? 0.4 : 1.0) : 1.0)
            .onAppear { sync() }
            .onChange(of: active) { _ in sync() }
    }

    private func sync() {
        if active {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                dimmed = true
            }
        } else {
            dimmed = false
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
