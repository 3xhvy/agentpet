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

/// A speech bubble showing one row per active agent, with a colored state dot
/// and a unique SF Symbol icon identifying the agent type.
private struct AgentBubble: View {
    let sessions: [AgentSession]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(sessions) { session in
                    AgentRow(session: session)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.06), lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            Triangle()
                .fill(.white)
                .frame(width: 12, height: 7)
        }
        .fixedSize()
    }
}

private struct AgentRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 5) {
            // State dot — color signals urgency
            Circle()
                .fill(stateDotColor)
                .frame(width: 6, height: 6)

            // Real brand logo for the agent
            AgentIconView(kind: session.agentKind, size: 14)

            // Project → activity
            Text(rowText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.black.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var rowText: String {
        let project = session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
        let msg: String
        if let m = session.message, !m.trimmingCharacters(in: .whitespaces).isEmpty {
            msg = m
        } else {
            msg = session.state.rawValue.capitalized
        }
        return "\(project) → \(msg)"
    }

    private var stateDotColor: Color {
        switch session.state {
        case .waiting:              return .orange
        case .working:              return Color(red: 0.22, green: 0.53, blue: 1.0)
        case .done:                 return Color(red: 0.13, green: 0.77, blue: 0.37)
        case .idle, .registered:    return .gray
        }
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
