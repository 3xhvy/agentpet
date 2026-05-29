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

    struct PetOption: Identifiable, Equatable {
        let name: String
        let preview: String
        var id: String { name }
    }

    @Published private(set) var notificationState: NotificationState = .notDetermined
    @Published private(set) var claudeInstalled = false

    let agents = AgentCatalog.all

    var availablePets: [PetOption] {
        PetPackLoader.loadBuiltins().map {
            PetOption(name: $0.name, preview: $0.animation(for: .idle).frames.first ?? "🐾")
        }
    }

    func refresh() {
        claudeInstalled = ClaudeHookInstaller.isInstalledOnDisk()
        refreshNotificationState()
    }

    func isInstalled(_ kind: AgentKind) -> Bool {
        kind == .claude ? claudeInstalled : false
    }

    func toggleInstall(_ kind: AgentKind) {
        guard kind == .claude else { return }
        if claudeInstalled {
            try? ClaudeHookInstaller.uninstallFromDisk()
        } else {
            let path = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "agentpet"
            try? ClaudeHookInstaller.installToDisk(command: "\"\(path)\" hook")
        }
        claudeInstalled = ClaudeHookInstaller.isInstalledOnDisk()
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
