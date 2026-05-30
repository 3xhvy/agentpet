import AppKit
import SwiftUI

/// Owns the onboarding/Settings window, shown on first launch and reopenable
/// from the menu bar.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        SettingsModel.shared.refresh()

        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(rootView: SetupView(onClose: { [weak self] in
            self?.window?.close()
        }))
        // A non-activating panel: it can become key so its controls respond on
        // the first click, without activating the whole app (which would pull
        // the user out of the window they were working in).
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .nonactivatingPanel]
        panel.title = "AgentPet"
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        self.window = panel

        panel.makeKeyAndOrderFront(nil)
    }

    /// Shows onboarding only the first time the app is ever launched.
    func showOnFirstLaunch() {
        let key = "agentpet.hasOnboarded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }
}
