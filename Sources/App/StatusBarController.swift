import AppKit
import SwiftUI
import AgentPetCore

/// Owns the menu bar status item and a native `NSPopover` (the pattern used by
/// polished menu bar apps): smooth open/close animation, a real arrow pointing
/// at the icon, and transient auto-dismiss on outside clicks.
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var lastSessions: [AgentSession] = []

    /// Whether to show the agent count next to the menu bar icon.
    @Published var showCount: Bool {
        didSet {
            UserDefaults.standard.set(showCount, forKey: "agentpet.showCount")
            updateStatus(lastSessions)
        }
    }

    override init() {
        showCount = (UserDefaults.standard.object(forKey: "agentpet.showCount") as? Bool) ?? true
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "AgentPet")
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: MenuContentView(dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Reflects live agent state in the menu bar: a count of running agents, or
    /// an orange count when some need input, so it reads at a glance.
    func updateStatus(_ sessions: [AgentSession]) {
        lastSessions = sessions
        guard let button = statusItem?.button else { return }
        let active = sessions.filter { $0.state != .idle }
        let waiting = active.filter { $0.state == .waiting }.count
        let running = active.filter { $0.state == .working || $0.state == .registered }.count

        guard showCount, waiting > 0 || running > 0 else {
            button.title = ""
            return
        }
        let count = waiting > 0 ? waiting : running
        let color: NSColor = waiting > 0 ? .systemOrange : .labelColor
        button.attributedTitle = NSAttributedString(string: "\(count)", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .baselineOffset: 0.5,
        ])
        button.imageHugsTitle = true
    }

    /// Shows the same popover anchored to an arbitrary view (e.g. the floating
    /// pet on right-click).
    func showPopover(relativeTo rect: NSRect, of view: NSView, edge: NSRectEdge) {
        if popover.isShown { popover.performClose(nil) }
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
    }
}
