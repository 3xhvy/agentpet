import SwiftUI
import AppKit
import AgentPetCore

/// Rich menu bar popover: a blurred dark card with an arrow pointing at the
/// status item, a live agent list, and a footer bar.
struct MenuContentView: View {
    @ObservedObject private var daemon = AppDaemon.shared
    @ObservedObject private var petWindow = PetWindowController.shared
    var dismiss: () -> Void
    var arrowOffset: CGFloat = 0

    /// Idle sessions are historical/quiet; show only active or just-finished ones.
    private var agents: [AgentSession] {
        daemon.sessions.filter { $0.state != .idle }
    }

    var body: some View {
        VStack(spacing: 0) {
            ArrowUp()
                .fill(.regularMaterial)
                .frame(width: 22, height: 9)
                .offset(x: arrowOffset)
            card
        }
        .frame(width: 300)
        .environment(\.colorScheme, .dark)
        .noFocusRing()
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            divider
            agentSection
            divider
            controls
            divider
            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private var divider: some View { Divider().overlay(Color.white.opacity(0.08)) }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "pawprint.fill").font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 1) {
                Text("AgentPet").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
        }
        .padding(14)
    }

    private var subtitle: String {
        let total = agents.count
        if total == 0 { return "No agents running" }
        let running = agents.filter { $0.state == .working || $0.state == .registered }.count
        return "\(total) agent\(total == 1 ? "" : "s") · \(running) running"
    }

    // MARK: Agents

    private var agentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("Agents")
            if agents.isEmpty {
                Text("Nothing running right now.")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 14).padding(.bottom, 12)
            } else {
                ForEach(agents) { AgentRow(session: $0) }
                    .padding(.bottom, 6)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1.4)
            .foregroundStyle(.white.opacity(0.35))
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            Image(systemName: "pawprint").foregroundStyle(.white.opacity(0.8))
            Text("Show pet").font(.system(size: 13)).foregroundStyle(.white)
            Spacer()
            Toggle("", isOn: $petWindow.isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            FooterButton(icon: "gearshape", label: "Settings") {
                dismiss()
                SettingsWindowController.shared.show()
            }
            Spacer()
            FooterButton(icon: "power", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

struct ArrowUp: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

private struct FooterButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}

private struct AgentRow: View {
    let session: AgentSession

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(project).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text(session.state.rawValue.capitalized).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timeString(now: context.date))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
    }

    private var project: String {
        session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
    }

    private var dotColor: Color {
        switch session.state {
        case .working, .registered: return .blue
        case .waiting: return .orange
        case .done: return .green
        case .idle: return .gray
        }
    }

    private func timeString(now: Date) -> String {
        switch session.state {
        case .done, .idle:
            return session.updatedAt.formatted(date: .omitted, time: .shortened)
        default:
            let s = max(0, Int(now.timeIntervalSince(session.stateSince)))
            return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
        }
    }
}
