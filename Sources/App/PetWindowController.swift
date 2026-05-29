import AppKit
import SwiftUI

/// A borderless, always-on-top, draggable floating window that hosts the pet.
/// Visibility is user-toggleable from the menu bar.
@MainActor
final class PetWindowController: ObservableObject {
    static let shared = PetWindowController()

    @Published var isVisible: Bool = true {
        didSet { applyVisibility(isVisible) }
    }

    private var panel: NSPanel?

    func start() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FloatingPetView())

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 236, y: frame.minY + 30))
        }

        self.panel = panel
        applyVisibility(isVisible)
    }

    private func applyVisibility(_ visible: Bool) {
        if visible {
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
}
