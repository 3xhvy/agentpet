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
/// Corner radii scale down as rows stack so tall bubbles stay boxy, not pill-shaped.
private enum BubbleChrome {
    static let petRoundRadius: CGFloat = 999
    static let petStackedRadius: CGFloat = 14
    static let menuCornerRadius: CGFloat = 10

    static func petRadius(rowCount: Int) -> CGFloat {
        rowCount > 1 ? petStackedRadius : petRoundRadius
    }
}

/// Rounded rect whose radius never exceeds half the width/height — avoids stadium ends.
private struct ClampedRoundedRect: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height / 2)
        return RoundedRectangle(cornerRadius: r, style: .circular).path(in: rect)
    }
}

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
    private var rowCount: Int { groupedSessions.count }
    private var cornerRadius: CGFloat {
        isPetChat ? BubbleChrome.petRadius(rowCount: rowCount) : BubbleChrome.menuCornerRadius
    }
    /// Hug width for up to 3 rows; use a stable box width when 4+ rows stack.
    private var hugHorizontal: Bool { isPetChat && rowCount <= 3 }

    var body: some View {
        let fill = isPetChat ? Color.white : bubbleFill
        let stroke = isPetChat ? Color.black.opacity(0.06) : borderColor
        let bubbleShape = SpeechBubbleShape(
            radius: cornerRadius,
            tailWidth: 12,
            tailHeight: 7,
            tailEdge: tailEdge
        )
        let verticalPad = isPetChat ? 7.0 : 9.0
        let tailPad: CGFloat = 7

        VStack(alignment: .leading, spacing: isPetChat ? 4 : 5) {
            ForEach(groupedSessions) { group in
                AgentRow(
                    session: group.session,
                    count: group.count,
                    chatStyle: isPetChat,
                    fillWidth: !hugHorizontal
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, verticalPad + (tailEdge == .top ? tailPad : 0))
        .padding(.bottom, verticalPad + (tailEdge == .bottom ? tailPad : 0))
        .frame(
            minWidth: hugHorizontal ? nil : AgentBubble.petContentMaxWidth + 24,
            alignment: .leading
        )
        .background {
            bubbleShape
                .fill(fill)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
        }
        .overlay {
            bubbleShape.stroke(stroke, lineWidth: 1)
        }
        .fixedSize(horizontal: hugHorizontal, vertical: true)
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

/// One row per agent session. Icon and project stay fully visible; only the
/// activity message truncates when space is tight.
private struct AgentRow: View {
    let session: AgentSession
    var count: Int = 1
    var chatStyle: Bool = false
    var fillWidth: Bool = false
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
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .modifier(WaitingTextFlash(active: isWaiting))
        }
        .frame(maxWidth: fillWidth ? .infinity : rowMaxWidth, alignment: .leading)
        .help(hoverText)
    }

    @ViewBuilder
    private func tokenView(for token: BubbleToken) -> some View {
        switch token {
        case .dot:
            StateDot(color: stateDotColor, style: dotStyle)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        case .icon:
            ResolvedIconView(
                choice: settings.iconChoice(for: session.agentKind),
                size: iconPt
            )
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        case .title:
            if let title = session.title {
                Text(title)
                    .font(.system(size: primaryPt, weight: .semibold))
                    .foregroundStyle(textColor(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)
            }
        case .project:
            Text(projectName)
                .font(.system(size: primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        case .separator:
            Text(settings.separatorChar)
                .font(.system(size: primaryPt, weight: .regular))
                .foregroundStyle(textColor(0.35))
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
        case .message:
            Text(messageText)
                .font(.system(size: primaryPt, weight: .medium))
                .foregroundStyle(textColor(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(-1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        case .contextPercentage:
            if let text = TickerFormatter.contextPercentageText(for: session) {
                Text(text)
                    .font(.system(size: secondaryPt, weight: .semibold))
                    .foregroundStyle(textColor(0.58))
                    .monospacedDigit()
                    .fixedSize(horizontal: true, vertical: false)
            }
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
        if token == .contextPercentage {
            return TickerFormatter.contextPercentageText(for: session) != nil
        }
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
        return m.isEmpty ? session.state.rawValue.capitalized : m
    }

    private var hoverText: String {
        let suffix = count > 1 ? " x\(count)" : ""
        return TickerFormatter.line(for: session) + suffix
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
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.black.opacity(0.85))
            .lineLimit(2)
            .truncationMode(.tail)
            .padding(.horizontal, 12)
            .padding(.top, 7)
            .padding(.bottom, 14)
            .background {
                SpeechBubbleShape(
                    radius: BubbleChrome.petRoundRadius,
                    tailWidth: 12,
                    tailHeight: 7,
                    tailEdge: .bottom
                )
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            }
            .overlay {
                SpeechBubbleShape(
                    radius: BubbleChrome.petRoundRadius,
                    tailWidth: 12,
                    tailHeight: 7,
                    tailEdge: .bottom
                )
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: 420)
    }
}

private struct SpeechBubbleShape: Shape {
    var radius: CGFloat
    var tailWidth: CGFloat
    var tailHeight: CGFloat
    var tailEdge: Edge = .bottom

    func path(in rect: CGRect) -> Path {
        switch tailEdge {
        case .top:    return topTailPath(in: rect)
        case .bottom: return bottomTailPath(in: rect)
        default:      return ClampedRoundedRect(radius: radius).path(in: rect)
        }
    }

    private func bottomTailPath(in rect: CGRect) -> Path {
        let body = rect.divided(atDistance: rect.height - tailHeight, from: .minYEdge).slice
        return roundedBodyWithTail(
            body: body,
            tip: CGPoint(x: body.midX, y: rect.maxY),
            tailLeft: body.midX - tailWidth / 2,
            tailRight: body.midX + tailWidth / 2,
            tailY: body.maxY
        )
    }

    private func topTailPath(in rect: CGRect) -> Path {
        let body = rect.divided(atDistance: tailHeight, from: .minYEdge).remainder
        return roundedBodyWithTail(
            body: body,
            tip: CGPoint(x: body.midX, y: rect.minY),
            tailLeft: body.midX - tailWidth / 2,
            tailRight: body.midX + tailWidth / 2,
            tailY: body.minY
        )
    }

    private func roundedBodyWithTail(
        body: CGRect,
        tip: CGPoint,
        tailLeft: CGFloat,
        tailRight: CGFloat,
        tailY: CGFloat
    ) -> Path {
        let r = min(radius, body.width / 2, body.height / 2)
        var p = Path()

        if tailEdge == .bottom {
            p.move(to: CGPoint(x: body.minX + r, y: body.minY))
            p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
            p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r),
                     radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
            p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: tailRight, y: tailY))
            p.addLine(to: tip)
            p.addLine(to: CGPoint(x: tailLeft, y: tailY))
            p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
            p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
            p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r),
                     radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            p.move(to: tip)
            p.addLine(to: CGPoint(x: tailRight, y: tailY))
            p.addLine(to: CGPoint(x: body.maxX - r, y: body.minY))
            p.addArc(center: CGPoint(x: body.maxX - r, y: body.minY + r),
                     radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            p.addLine(to: CGPoint(x: body.maxX, y: body.maxY - r))
            p.addArc(center: CGPoint(x: body.maxX - r, y: body.maxY - r),
                     radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: body.minX + r, y: body.maxY))
            p.addArc(center: CGPoint(x: body.minX + r, y: body.maxY - r),
                     radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: body.minX, y: body.minY + r))
            p.addArc(center: CGPoint(x: body.minX + r, y: body.minY + r),
                     radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            p.addLine(to: CGPoint(x: tailLeft, y: tailY))
            p.addLine(to: tip)
        }

        p.closeSubpath()
        return p
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
