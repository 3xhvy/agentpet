import Foundation
import AgentPetCore

/// Resolves the aggregate session mood, plays a short `celebrate` burst when
/// work finishes, owns the selected (imported) pet, and drives the chat bubble.
@MainActor
final class PetController: ObservableObject {
    static let shared = PetController()

    @Published private(set) var mood: PetMood = .idle
    @Published private(set) var chatLine: String = ""

    @Published var selectedPetID: String? {
        didSet { UserDefaults.standard.set(selectedPetID, forKey: Self.petKey) }
    }
    @Published var showChat: Bool {
        didSet {
            UserDefaults.standard.set(showChat, forKey: Self.chatKey)
            refreshChat()
        }
    }
    /// Sprite point size, freely adjustable via a slider.
    @Published var petPoint: Double {
        didSet { UserDefaults.standard.set(petPoint, forKey: Self.sizeKey) }
    }

    static let minPoint: Double = 60
    static let maxPoint: Double = 240
    static let presets: [(String, Double)] = [("S", 84), ("M", 120), ("L", 168)]

    /// Floating window size for a sprite point size (room for the bubble above).
    static func windowSize(forPoint point: Double) -> CGSize {
        CGSize(width: point + 110, height: point + 64)
    }
    var windowSize: CGSize { Self.windowSize(forPoint: petPoint) }

    private var lastResolved: PetMood = .idle
    private var latestSessions: [AgentSession] = []
    private var celebrateTimer: Timer?
    private var chatTimer: Timer?

    private static let petKey = "agentpet.selectedPetID"
    private static let chatKey = "agentpet.showChat"
    private static let sizeKey = "agentpet.petSize"
    private static let celebrateDuration: TimeInterval = 3

    init() {
        selectedPetID = UserDefaults.standard.string(forKey: Self.petKey)
        showChat = (UserDefaults.standard.object(forKey: Self.chatKey) as? Bool) ?? true
        let saved = UserDefaults.standard.object(forKey: Self.sizeKey) as? Double ?? 120
        petPoint = min(max(saved, Self.minPoint), Self.maxPoint)
    }

    func start() {
        // Vary the chat line periodically while the pet is active.
        chatTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.refreshChat() }
        }
    }

    private var sizeAnimTimer: Timer?

    /// Eases `petPoint` to a target so a preset tap resizes as smoothly as a
    /// slider drag (each step drives the same smooth window resize).
    func animateSize(to target: Double) {
        sizeAnimTimer?.invalidate()
        let clamped = min(max(target, Self.minPoint), Self.maxPoint)
        let start = petPoint
        let steps = 14
        var i = 0
        sizeAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                i += 1
                let t = min(Double(i) / Double(steps), 1)
                let eased = t * t * (3 - 2 * t)   // smoothstep
                self.petPoint = start + (clamped - start) * eased
                if i >= steps {
                    self.petPoint = clamped
                    self.sizeAnimTimer?.invalidate()
                }
            }
        }
    }

    /// Called by the daemon whenever the session list changes.
    func update(sessions: [AgentSession]) {
        latestSessions = sessions
        let resolved = MoodResolver.aggregate(sessions)
        defer { lastResolved = resolved }

        if resolved == .done && lastResolved != .done {
            setMood(.celebrate)
            celebrateTimer?.invalidate()
            celebrateTimer = Timer.scheduledTimer(withTimeInterval: Self.celebrateDuration, repeats: false) { _ in
                Task { @MainActor [weak self] in self?.settleAfterCelebrate() }
            }
            return
        }
        if mood == .celebrate && resolved == .done {
            return  // let the celebration finish
        }
        celebrateTimer?.invalidate()
        setMood(resolved)
    }

    private func settleAfterCelebrate() {
        setMood(MoodResolver.aggregate(latestSessions))
    }

    private func setMood(_ newMood: PetMood) {
        mood = newMood
        refreshChat()
    }

    private func refreshChat() {
        let pool = ChatSettings.shared.lines(for: mood)
        guard showChat, mood != .idle, !pool.isEmpty else {
            chatLine = ""
            return
        }
        chatLine = pool.randomElement() ?? ""
    }
}

/// Built-in (system) chat lines per mood.
enum PetChat {
    static let lines: [PetMood: [String]] = [
        .working: [
            "Thinking…", "Working on it…", "On it!", "Crunching code…",
            "Hmm, let me see…", "Cooking something up…", "Deep in thought…",
            "Brain go brrr…", "Almost there…", "Wiring it up…",
        ],
        .waiting: [
            "I need you!", "Your turn 👀", "Waiting on you…", "Can you check this?",
            "Psst, need input!", "Awaiting orders…", "Help me out?", "Stuck, need you!",
        ],
        .done: [
            "All done! ✅", "Finished!", "Ta-da!", "Done and dusted!",
            "Nailed it!", "That's a wrap!", "Mission complete!",
        ],
        .celebrate: [
            "🎉 Woohoo!", "We did it!", "Victory!", "Yesss!", "High five! 🙌", "Champion!",
        ],
    ]
}
