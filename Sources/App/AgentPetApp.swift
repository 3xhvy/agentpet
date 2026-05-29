import SwiftUI
import AppKit

struct AgentPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("AgentPet", systemImage: "pawprint.fill") {
            MenuBarContentView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Runs the app as a menu bar accessory (no Dock icon) and boots the daemon.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PetController.shared.start()
        PetWindowController.shared.start()
        AppDaemon.shared.start()
    }
}
