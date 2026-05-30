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

        // Always rebuild so the window opens fresh (default tab, scrolled to top)
        // instead of restoring the previous session's state.
        window?.close()
        window = nil

        // Non-activating panel + click-through hosting view: controls respond on
        // the first click without the window ever becoming key, so the user's
        // current app keeps keyboard focus.
        let host = ClickThroughHostingView(rootView: SetupView(onClose: { [weak self] in
            self?.window?.close()
        }))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "AgentPet"
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.center()
        self.window = panel

        panel.orderFrontRegardless()
    }

    /// Shows onboarding only the first time the app is ever launched.
    func showOnFirstLaunch() {
        let key = "agentpet.hasOnboarded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }
}
