import Foundation
import AgentPetCore

// MARK: - Token types

enum BubbleToken: String, CaseIterable, Codable, Identifiable {
    case dot, icon, title, project, separator, message, stateLabel, elapsed
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot:        return "State dot"
        case .icon:       return "Agent icon"
        case .title:      return "Chat title"
        case .project:    return "Project folder"
        case .separator:  return "Separator"
        case .message:    return "Activity message"
        case .stateLabel: return "State label"
        case .elapsed:    return "Elapsed time"
        }
    }
}

struct BubbleTokenItem: Codable, Identifiable, Equatable {
    var id: String { token.rawValue }
    let token: BubbleToken
    var isVisible: Bool
}

struct BubbleLayout: Codable, Equatable {
    var tokens: [BubbleTokenItem]

    static let original = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .title,      isVisible: false),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
    ])

    static let standard = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
    ])

    static let detailed = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: true),
        .init(token: .elapsed,    isVisible: true),
    ])

    static func preset(named preset: BubbleSettings.Preset) -> BubbleLayout {
        switch preset {
        case .original: return .original
        case .standard: return .standard
        case .detailed: return .detailed
        case .custom:
            assertionFailure("preset(named:) should not be called with .custom — use effectiveLayout instead")
            return .original
        }
    }
}

// MARK: - Icon choice

enum IconChoice: Equatable {
    case brandLogo(AgentKind)
    case sfSymbol(String)
}

extension IconChoice: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "brandLogo": self = .brandLogo(AgentKind(rawValue: value) ?? .unknown)
        default:          self = .sfSymbol(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brandLogo(let k):
            try c.encode("brandLogo", forKey: .type)
            try c.encode(k.rawValue, forKey: .value)
        case .sfSymbol(let n):
            try c.encode("sfSymbol", forKey: .type)
            try c.encode(n, forKey: .value)
        }
    }
}

// MARK: - Min-state filter

enum MinStateFilter: String, CaseIterable, Codable {
    case all, doneAndAbove, workingAndWaiting, workingOnly

    var displayName: String {
        switch self {
        case .all:               return "All states"
        case .doneAndAbove:      return "Done and above"
        case .workingAndWaiting: return "Working & Waiting"
        case .workingOnly:       return "Working only"
        }
    }

    func includes(_ state: AgentState) -> Bool {
        // attentionPriority is internal to AgentPetCore — compare states explicitly
        switch self {
        case .all:               return true
        case .doneAndAbove:      return state == .working || state == .waiting || state == .done
        case .workingAndWaiting: return state == .working || state == .waiting
        case .workingOnly:       return state == .working
        }
    }
}

// MARK: - BubbleSettings

@MainActor
final class BubbleSettings: ObservableObject {
    static let shared = BubbleSettings()

    enum Preset: String, CaseIterable, Codable {
        case original, standard, detailed, custom
        var displayName: String { rawValue.capitalized }
    }

    enum FontSize: String, CaseIterable, Codable {
        case small, medium, large
        var primaryPt: CGFloat   { switch self { case .small: 10; case .medium: 12; case .large: 14 } }
        var secondaryPt: CGFloat { switch self { case .small: 9;  case .medium: 10.5; case .large: 12 } }
        var iconPt: CGFloat      { primaryPt + 2 }
    }

    enum Theme: String, CaseIterable, Codable {
        case light, dark, system
        var displayName: String { rawValue.capitalized }
    }

    // MARK: Published properties

    @Published var preset: Preset {
        didSet { ud.set(preset.rawValue, forKey: Keys.preset) }
    }
    @Published var customLayout: BubbleLayout {
        didSet { saveJSON(Keys.customLayout, customLayout) }
    }
    @Published var separatorChar: String {
        didSet { ud.set(separatorChar, forKey: Keys.separatorChar) }
    }
    @Published var fontSize: FontSize {
        didSet { ud.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    @Published var opacity: Double {
        didSet { ud.set(opacity, forKey: Keys.opacity) }
    }
    @Published var theme: Theme {
        didSet { ud.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var maxSessions: Int {
        didSet { ud.set(maxSessions, forKey: Keys.maxSessions) }
    }
    @Published var minStateFilter: MinStateFilter {
        didSet { ud.set(minStateFilter.rawValue, forKey: Keys.minStateFilter) }
    }
    @Published var groupByKind: Bool {
        didSet { ud.set(groupByKind, forKey: Keys.groupByKind) }
    }
    @Published var hiddenKinds: Set<AgentKind> {
        didSet { saveJSON(Keys.hiddenKinds, Array(hiddenKinds).map(\.rawValue)) }
    }
    /// Keyed by AgentKind.rawValue for JSON compatibility.
    @Published var iconChoices: [String: IconChoice] {
        didSet { saveJSON(Keys.iconChoices, iconChoices) }
    }

    // MARK: Computed

    var effectiveLayout: BubbleLayout {
        preset == .custom ? customLayout : BubbleLayout.preset(named: preset)
    }

    func iconChoice(for kind: AgentKind) -> IconChoice {
        iconChoices[kind.rawValue] ?? .brandLogo(kind)
    }

    func setIconChoice(_ choice: IconChoice, for kind: AgentKind) {
        iconChoices[kind.rawValue] = choice
    }

    func resetIconChoice(for kind: AgentKind) {
        iconChoices.removeValue(forKey: kind.rawValue)
    }

    // MARK: Private

    private let ud = UserDefaults.standard

    private enum Keys {
        static let preset          = "agentpet.bubble.preset"
        static let customLayout    = "agentpet.bubble.customLayout"
        static let separatorChar   = "agentpet.bubble.separatorChar"
        static let fontSize        = "agentpet.bubble.fontSize"
        static let opacity         = "agentpet.bubble.opacity"
        static let theme           = "agentpet.bubble.theme"
        static let maxSessions     = "agentpet.bubble.maxSessions"
        static let minStateFilter  = "agentpet.bubble.minStateFilter"
        static let groupByKind     = "agentpet.bubble.groupByKind"
        static let hiddenKinds     = "agentpet.bubble.hiddenKinds"
        static let iconChoices     = "agentpet.bubble.iconChoices"
    }

    init() {
        preset         = Preset(rawValue: ud.string(forKey: Keys.preset) ?? "") ?? .original
        customLayout   = Self.loadJSON(Keys.customLayout) ?? .original
        separatorChar  = ud.string(forKey: Keys.separatorChar) ?? "·"
        fontSize       = FontSize(rawValue: ud.string(forKey: Keys.fontSize) ?? "") ?? .medium
        opacity        = ud.object(forKey: Keys.opacity) as? Double ?? 1.0
        theme          = Theme(rawValue: ud.string(forKey: Keys.theme) ?? "") ?? .system
        maxSessions    = ud.object(forKey: Keys.maxSessions) as? Int ?? 5
        minStateFilter = MinStateFilter(rawValue: ud.string(forKey: Keys.minStateFilter) ?? "") ?? .all
        groupByKind    = ud.bool(forKey: Keys.groupByKind)
        hiddenKinds    = Set((Self.loadJSON(Keys.hiddenKinds) as [String]? ?? []).compactMap(AgentKind.init(rawValue:)))
        iconChoices    = Self.loadJSON(Keys.iconChoices) ?? [:]
    }

    private func saveJSON<T: Encodable>(_ key: String, _ value: T) {
        ud.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func loadJSON<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
