import Foundation
import AgentPetCore

/// Owns the live session state inside the running app: starts the socket
/// server, drains any queued events on launch, applies incoming events and
/// prunes stale ones, and publishes a display-ordered list to the UI.
///
/// All `SessionStore` access is confined to the main actor.
@MainActor
final class AppDaemon: ObservableObject {
    static let shared = AppDaemon()

    @Published private(set) var sessions: [AgentSession] = []

    private let store = SessionStore()
    private let server = EventSocketServer(path: AgentPetPaths.socketPath)
    private var pruneTimer: Timer?

    func start() {
        try? FileManager.default.createDirectory(
            atPath: AgentPetPaths.baseDir, withIntermediateDirectories: true
        )

        EventSocketServer.drainQueue(directory: AgentPetPaths.queueDir) { [store] event in
            store.apply(event, now: Date())
        }
        refresh()

        try? server.start { event in
            Task { @MainActor [weak self] in self?.ingest(event) }
        }

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.prune() }
        }
    }

    private func ingest(_ event: AgentEvent) {
        store.apply(event, now: Date())
        refresh()
    }

    private func prune() {
        store.prune(now: Date())
        refresh()
    }

    private func refresh() {
        sessions = store.sorted
        PetController.shared.update(sessions: sessions)
    }
}
