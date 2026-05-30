import AppKit
import SwiftUI

/// Owns the onboarding/Settings window, shown on first launch and reopenable
/// from the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        SettingsModel.shared.refresh()

        // Always rebuild so the window opens fresh (default tab, scrolled to top)
        // instead of restoring the previous session's state.
        window?.close()
        window = nil

        // Show a Dock icon while Settings is open (requires .regular policy).
        NSApp.setActivationPolicy(.regular)

        let host = ClickThroughHostingView(rootView: SetupView(onClose: { [weak self] in
            self?.window?.close()
        }))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        panel.title = "AgentPet"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.center()
        self.window = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        // Back to a menu bar accessory (no Dock icon) when Settings closes.
        NSApp.setActivationPolicy(.accessory)
    }

    /// Shows onboarding only the first time the app is ever launched.
    func showOnFirstLaunch() {
        let key = "agentpet.hasOnboarded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        show()
    }
}
