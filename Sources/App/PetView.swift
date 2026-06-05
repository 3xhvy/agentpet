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

/// The full floating window content: a chat bubble above the pet.
struct FloatingPetView: View {
    @ObservedObject private var pet = PetController.shared

    var body: some View {
        VStack(spacing: 2) {
            if pet.showChat && pet.selectedPetID != nil {
                if !pet.activeAgentSessions.isEmpty {
                    AgentBubble(sessions: pet.activeAgentSessions)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                } else if !pet.chatLine.isEmpty {
                    ChatBubble(text: pet.chatLine)
                        .transition(AnyTransition.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            PetView(size: pet.petPoint)
        }
        .frame(width: pet.windowSize.width, height: pet.windowSize.height, alignment: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.chatLine)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: pet.activeAgentSessions.count)
        .animation(.easeInOut, value: pet.showChat)
    }
}

// MARK: - Agent Bubble (structured rows for working/waiting)

/// Speech bubble listing one row per active agent session.
/// Applies filter/sort/cap from `BubbleSettings` before rendering.
private struct AgentBubble: View {
    let sessions: [AgentSession]
    @ObservedObject private var settings = BubbleSettings.shared

    private var displaySessions: [AgentSession] {
        var result = sessions
            .filter { !settings.hiddenKinds.contains($0.agentKind) }
            .filter { settings.minStateFilter.includes($0.state) }
        // attentionPriority is internal to AgentPetCore — sort by explicit state rank
        func rank(_ s: AgentState) -> Int {
            switch s { case .working: 4; case .waiting: 3; case .done: 2; case .registered: 1; case .idle: 0 }
        }
        if settings.groupByKind {
            result.sort {
                if $0.agentKind.rawValue != $1.agentKind.rawValue {
                    return $0.agentKind.rawValue < $1.agentKind.rawValue
                }
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
                return $0.updatedAt > $1.updatedAt
            }
        } else {
            result.sort {
                if rank($0.state) != rank($1.state) { return rank($0.state) > rank($1.state) }
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
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(bubbleFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(borderColor, lineWidth: 1))
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

/// One row per session — iterates `BubbleSettings.effectiveLayout` tokens in order.
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
        if token == .title { return session.title != nil }
        return true
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
        case .waiting:           return .orange
        case .working:           return Color(red: 0.22, green: 0.53, blue: 1.0)
        case .done:              return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .idle, .registered: return .gray
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
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Capsule().fill(.white))
                .overlay(Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 7)
        }
        .fixedSize()
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
