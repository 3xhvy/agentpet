import SwiftUI
import AgentPetCore

/// Onboarding / Settings content: grant notifications and choose which agents
/// to wire up.
struct SetupView: View {
    @ObservedObject private var model = SettingsModel.shared
    @ObservedObject private var pet = PetController.shared
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AgentPet")
                    .font(.title2.bold())
                Text("Get notified and watch your pet react as your AI agents run.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications").font(.headline)
                        Text(notificationDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    notificationButton
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Agent integrations").font(.headline)
                    ForEach(model.agents) { agent in
                        AgentRow(agent: agent,
                                 installed: model.isInstalled(agent.kind),
                                 toggle: { model.toggleInstall(agent.kind) })
                        if agent.id != model.agents.last?.id { Divider() }
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pet").font(.headline)
                    HStack(spacing: 12) {
                        ForEach(model.availablePets) { option in
                            PetCard(option: option,
                                    selected: pet.currentPackName == option.name,
                                    select: { pet.selectPack(named: option.name) })
                        }
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { model.refresh() }
    }

    private var notificationDescription: String {
        switch model.notificationState {
        case .unavailable: return "Available once installed as AgentPet.app"
        case .notDetermined: return "Allow AgentPet to notify you when an agent finishes or needs input"
        case .enabled: return "Enabled"
        case .denied: return "Denied. Enable in System Settings to get alerts"
        }
    }

    @ViewBuilder private var notificationButton: some View {
        switch model.notificationState {
        case .enabled:
            Label("Enabled", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .denied:
            Button("Open Settings") { model.openSystemNotificationSettings() }
        case .notDetermined:
            Button("Enable") { model.enableNotifications() }
        case .unavailable:
            Text("Unavailable").foregroundStyle(.secondary)
        }
    }
}

private struct PetCard: View {
    let option: SettingsModel.PetOption
    let selected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                Text(option.preview).font(.system(size: 34))
                Text(option.name).font(.caption)
            }
            .frame(width: 76, height: 76)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AgentRow: View {
    let agent: AgentIntegration
    let installed: Bool
    let toggle: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                if let note = agent.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                } else if installed {
                    Text("Hook installed").font(.caption).foregroundStyle(.green)
                }
            }
            Spacer()
            if agent.isSupported {
                Button(installed ? "Remove" : "Install") { toggle() }
            } else {
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
