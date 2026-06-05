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

    // Ticker state
    private var tickerIndex: Int = 0
    private var tickerSessions: [AgentSession] = []
    private var tickerTimer: Timer?
    private static let tickerInterval: TimeInterval = 4.0

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
        // Ticker drives chatLine updates; no separate chat timer needed.
    }

    private var sizeAnimTimer: Timer?
    private var sizeAnimStep = 0
    private var sizeAnimStart = 0.0
    private var sizeAnimTarget = 0.0
    private static let sizeAnimSteps = 14

    /// Eases `petPoint` to a target so a preset tap resizes as smoothly as a
    /// slider drag (each step drives the same smooth window resize).
    func animateSize(to target: Double) {
        sizeAnimTimer?.invalidate()
        sizeAnimTarget = min(max(target, Self.minPoint), Self.maxPoint)
        sizeAnimStart = petPoint
        sizeAnimStep = 0
        sizeAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tickSize() }
        }
    }

    private func tickSize() {
        sizeAnimStep += 1
        let t = min(Double(sizeAnimStep) / Double(Self.sizeAnimSteps), 1)
        let eased = t * t * (3 - 2 * t)   // smoothstep
        petPoint = sizeAnimStart + (sizeAnimTarget - sizeAnimStart) * eased
        if sizeAnimStep >= Self.sizeAnimSteps {
            petPoint = sizeAnimTarget
            sizeAnimTimer?.invalidate()
        }
    }

    /// Called by the daemon whenever the session list changes.
    func update(sessions: [AgentSession]) {
        latestSessions = sessions
        let resolved = MoodResolver.aggregate(sessions)
        defer { lastResolved = resolved }

        if resolved == .done && lastResolved != .done {
            stopTicker()
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

        if resolved == .working || resolved == .waiting {
            applyTickerSessions(sessions)
        } else {
            stopTicker()
        }
    }

    private func settleAfterCelebrate() {
        setMood(MoodResolver.aggregate(latestSessions))
    }

    private func setMood(_ newMood: PetMood) {
        mood = newMood
        refreshChat()
    }

    private func refreshChat() {
        guard showChat, mood != .idle else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        // During working/waiting the ticker owns chatLine; fall back to PetChat
        // for celebrate/done where the ticker is stopped.
        if (mood == .working || mood == .waiting) && !tickerSessions.isEmpty {
            showCurrentTickerLine()
            return
        }
        let pool = ChatSettings.shared.lines(for: mood)
        guard !pool.isEmpty else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        chatLine = pool.randomElement() ?? ""
        StatusBarController.shared.refreshTitle()
    }

    // MARK: - Ticker

    private func applyTickerSessions(_ sessions: [AgentSession]) {
        let active = sessions.filter { $0.state != .idle && $0.state != .registered }
        let sorted = TickerFormatter.sorted(active)
        let changed = sorted.map(\.id) != tickerSessions.map(\.id)
        tickerSessions = sorted
        if sorted.isEmpty {
            stopTicker()
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        if changed { tickerIndex = 0 }
        showCurrentTickerLine()
        startTickerIfNeeded()
    }

    private func startTickerIfNeeded() {
        guard tickerTimer == nil else { return }
        tickerTimer = Timer.scheduledTimer(withTimeInterval: Self.tickerInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.advanceTicker() }
        }
    }

    private func stopTicker() {
        tickerTimer?.invalidate()
        tickerTimer = nil
        tickerIndex = 0
        tickerSessions = []
    }

    private func advanceTicker() {
        guard !tickerSessions.isEmpty else { stopTicker(); return }
        tickerIndex = (tickerIndex + 1) % tickerSessions.count
        showCurrentTickerLine()
    }

    private func showCurrentTickerLine() {
        guard showChat, !tickerSessions.isEmpty else {
            chatLine = ""
            StatusBarController.shared.refreshTitle()
            return
        }
        chatLine = TickerFormatter.line(for: tickerSessions[tickerIndex % tickerSessions.count])
        StatusBarController.shared.refreshTitle()
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
