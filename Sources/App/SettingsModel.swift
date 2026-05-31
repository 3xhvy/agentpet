import AppKit
import Foundation
import UserNotifications
import AgentPetCore

/// Backs the onboarding/Settings window: notification permission status and
/// per-agent hook install state, with the actions to change them.
@MainActor
final class SettingsModel: ObservableObject {
    static let shared = SettingsModel()

    enum NotificationState: Equatable {
        case unavailable   // running as bare binary, no bundle
        case notDetermined
        case enabled
        case denied
    }

    @Published private(set) var notificationState: NotificationState = .notDetermined
    @Published private(set) var installedKinds: Set<AgentKind> = []

    let agents = AgentCatalog.all

    func refresh() {
        var set: Set<AgentKind> = []
        for agent in agents where agent.isSupported {
            if let spec = AgentHooks.spec(for: agent.kind),
               ClaudeHookInstaller.isInstalledOnDisk(path: spec.settingsPath, events: spec.events) {
                set.insert(agent.kind)
            }
        }
        installedKinds = set
        refreshNotificationState()
    }

    func isInstalled(_ kind: AgentKind) -> Bool {
        installedKinds.contains(kind)
    }

    private func hookCommand(for kind: AgentKind) -> String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "agentpet"
        return "\"\(path)\" hook --agent \(kind.rawValue)"
    }

    func toggleInstall(_ kind: AgentKind) {
        guard let spec = AgentHooks.spec(for: kind) else { return }
        if installedKinds.contains(kind) {
            try? ClaudeHookInstaller.uninstallFromDisk(path: spec.settingsPath, events: spec.events)
        } else {
            try? ClaudeHookInstaller.installToDisk(command: hookCommand(for: kind), path: spec.settingsPath, events: spec.events)
        }
        refresh()
    }

    /// Prompts for a pet folder or .zip, imports it, and selects it.
    func importPet() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a pet folder (with pet.json) or a .zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let id = ImagePetStore.shared.importPack(from: url) {
            PetController.shared.selectedPetID = id
        }
    }

    func enableNotifications() {
        guard NotificationManager.shared.isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshNotificationState() }
        }
    }

    /// Opens System Settings to AgentPet's notification pane (used when denied).
    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshNotificationState() {
        guard NotificationManager.shared.isAvailable else {
            notificationState = .unavailable
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.notificationState = .enabled
                case .denied:
                    self.notificationState = .denied
                default:
                    self.notificationState = .notDetermined
                }
            }
        }
    }
}
