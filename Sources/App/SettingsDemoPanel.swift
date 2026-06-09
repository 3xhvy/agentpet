import SwiftUI
import AgentPetCore

/// Live-preview side panels for the Settings window. Drives a LOCAL list of fake
/// agent sessions (never the real pet).
///   • Right column  ("Add webhook"): pick an agent to spawn a webhook.
///   • Middle column ("Live preview"): the pet + the list of active webhooks,
///     where each row's state can be changed or the row deleted.
struct SettingsDemoPanel: View {
    @ObservedObject private var pet = PetController.shared
    @ObservedObject private var imagePets = ImagePetStore.shared
    @ObservedObject private var bubble = BubbleSettings.shared
    @ObservedObject private var bindings = PetBindingsStore.shared
    var onClose: () -> Void

    @State private var sessions: [AgentSession] = []
    @State private var counter = 0
    @State private var celebrating = false
    @State private var lastAgg: PetMood = .idle
    @State private var chatLine = ""
    @State private var celebrateTask: Task<Void, Never>?
    /// Drives the preview mood when multi-agent bubble is OFF (no sessions then).
    @State private var simpleMood: PetMood = .idle

    private let agents: [AgentKind] = [.claude, .codex, .gemini, .cursor, .opencode, .windsurf, .antigravity]
    private let editableStates: [AgentState] = [.working, .waiting, .done, .idle]
    private let previewMoods: [PetMood] = [.idle, .working, .waiting, .done, .celebrate]

    private var activeSessions: [AgentSession] { sessions.filter { $0.state == .working || $0.state == .waiting } }
    private var mood: PetMood {
        if !bubble.multiAgentBubbleEnabled { return simpleMood }
        return celebrating ? .celebrate : MoodResolver.aggregate(sessions)
    }
    private var pack: ImagePetPack? { pet.selectedPetID.flatMap { imagePets.pack(id: $0) } }
    private func count(_ kind: AgentKind) -> Int { sessions.filter { $0.agentKind == kind }.count }

    var body: some View {
        HStack(spacing: 0) {
            previewColumn.frame(minWidth: 440, maxWidth: .infinity)
            Divider()
            addColumn.frame(width: 280)
        }
        .background(Color(white: 0.11))
        .onAppear { refreshChat() }
        .onDisappear { celebrateTask?.cancel() }
    }

    // MARK: middle column , preview + editable webhook list

    private var previewColumn: some View {
        VStack(spacing: 0) {
            header
            Divider()
            stage
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if bubble.multiAgentBubbleEnabled {
                        quickActions
                        sessionList
                    } else {
                        simpleMoodPicker
                    }
                }
                .padding(16)
            }
        }
    }

    /// Simple-bubble mode has no sessions , pick a mood to preview its message.
    private var simpleMoodPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview mood").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(previewMoods, id: \.self) { m in
                    Button(stateLabel(m)) { setSimpleMood(m) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(simpleMood == m ? Color.systemAccent : nil)
                }
            }
            Text("Shows your Simple-bubble message for each state.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func setSimpleMood(_ m: PetMood) {
        simpleMood = m
        if m == .waiting { SoundSettings.shared.play(.waiting) }
        if m == .done || m == .celebrate { SoundSettings.shared.play(.done) }
        refreshChat()
    }

    private var header: some View {
        HStack {
            Label("Live preview", systemImage: "sparkles.tv").font(.headline)
            Spacer()
            Text(stateLabel(mood))
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(stateColor(mood).opacity(0.22)))
                .foregroundStyle(stateColor(mood))
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// Pet sits at the BOTTOM of the stage like a real desktop pet; the bubble
    /// grows upward above it. Clipped so a tall bubble never spills into the header.
    private var stage: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Color(white: 0.2), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 6) {
                if pet.showChat {
                    if bubble.multiAgentBubbleEnabled && !activeSessions.isEmpty {
                        AgentBubble(sessions: activeSessions)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    } else if !chatLine.isEmpty && (mood != .idle || pet.showIdleMessage) {
                        ChatBubble(text: chatLine)
                            .transition(.scale(scale: 0.7).combined(with: .opacity))
                    }
                }
                petSprite
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .frame(height: 300, alignment: .bottom)
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: activeSessions.count)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: chatLine)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: mood)
    }

    @ViewBuilder private var petSprite: some View {
        if let pack {
            let clip = bindings.clipIndex(packId: pack.id, clipCount: pack.clipCount, mood: mood)
            ImageSpriteView(frames: pack.clip(clip), mood: mood, size: min(max(pet.petPoint, 80), 120))
        } else {
            VStack(spacing: 6) {
                Image(systemName: "pawprint.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Pick a pet in the Pet tab").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick scenarios").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 6)], alignment: .leading, spacing: 6) {
                Button("Spawn 3 working") { spawnMany() }.buttonStyle(.bordered).controlSize(.small)
                Button("Finish all") { finishAll() }.buttonStyle(.bordered).controlSize(.small)
                Button("Clear all") { clearAll() }.buttonStyle(.bordered).controlSize(.small).tint(.red)
            }
        }
    }

    /// The active webhooks: each row's state is editable and it can be deleted.
    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active webhooks").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !sessions.isEmpty {
                    Text("\(sessions.count)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if sessions.isEmpty {
                Text("No webhooks yet. Add one from the right →")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(sessions) { s in
                    HStack(spacing: 8) {
                        agentIcon(s.agentKind).frame(width: 16, height: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label(s.agentKind)).font(.system(size: 12, weight: .semibold))
                            Text(s.project ?? s.id).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        statePicker(for: s)
                        Button { removeSession(s.id) } label: {
                            Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).help("Delete this webhook")
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
                }
            }
        }
    }

    /// Per-row dropdown to change that webhook's state.
    private func statePicker(for s: AgentSession) -> some View {
        Menu {
            ForEach(editableStates, id: \.self) { st in
                Button(st.rawValue.capitalized) { setSessionState(s.id, st) }
            }
        } label: {
            HStack(spacing: 3) {
                Text(s.state.rawValue).font(.caption2.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(stateColor(s.state).opacity(0.22)))
            .foregroundStyle(stateColor(s.state))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: right column , add webhook

    private var addColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Add webhook", systemImage: "plus.app.fill").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            if !bubble.multiAgentBubbleEnabled {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.system(size: 26)).foregroundStyle(.secondary)
                    Text("Webhooks are for the multi-agent bubble.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("Turn on Multi-agent bubble to add agents here. In Simple mode, use the Preview mood buttons on the left.")
                        .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(agents, id: \.self) { kind in
                        HStack(spacing: 8) {
                            agentIcon(kind).frame(width: 18, height: 18)
                            Text(label(kind)).font(.system(size: 13, weight: .semibold))
                            if count(kind) > 0 {
                                Text("×\(count(kind))").font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Capsule().fill(Color.white.opacity(0.1)))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { addSession(kind, .working) } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent).tint(Color.systemAccent).controlSize(.small)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.15)))
                    }
                    Text("Add agents here, then change each webhook's state or delete it in the list on the left.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(16)
            }
            }
        }
    }

    // MARK: behaviour

    /// Append a new webhook session of `kind` (several of one kind can run).
    private func addSession(_ kind: AgentKind, _ state: AgentState) {
        counter += 1
        let n = count(kind) + 1
        let now = Date()
        sessions.append(AgentSession(
            id: "demo-\(kind.rawValue)-\(counter)",
            agentKind: kind,
            project: sampleProject(kind) + (n > 1 ? " #\(n)" : ""),
            title: sampleTitle(kind),
            state: state,
            message: sampleMessage(state),
            source: .hook,
            updatedAt: now,
            stateSince: now
        ))
        after()
    }

    /// Change one webhook row's state.
    private func setSessionState(_ id: String, _ state: AgentState) {
        guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[i].state = state
        sessions[i].stateSince = Date()
        sessions[i].message = sampleMessage(state)
        if state == .waiting { SoundSettings.shared.play(.waiting) }
        after()
    }

    private func removeSession(_ id: String) { sessions.removeAll { $0.id == id }; after() }

    private func spawnMany() {
        addSession(.claude, .working); addSession(.cursor, .working); addSession(.codex, .working)
    }

    private func finishAll() {
        guard !sessions.isEmpty else { return }
        for i in sessions.indices { sessions[i].state = .done }
        after()
    }

    private func clearAll() {
        sessions = []
        celebrating = false
        celebrateTask?.cancel()
        after()
    }

    /// Recompute mood, fire the done sound + celebrate burst on the working→done
    /// edge, and refresh the fallback chat line.
    private func after() {
        let agg = MoodResolver.aggregate(sessions)
        if agg == .done && lastAgg != .done {
            SoundSettings.shared.play(.done)
            celebrating = true
            celebrateTask?.cancel()
            celebrateTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { celebrating = false; refreshChat() }
            }
        }
        if agg != .done { celebrating = false; celebrateTask?.cancel() }
        lastAgg = agg
        refreshChat()
    }

    private func refreshChat() {
        if mood == .idle && !pet.showIdleMessage {
            chatLine = ""
            return
        }
        let pool = bubble.multiAgentBubbleEnabled
            ? BubbleMessages.shared.lines(for: nil, mood: mood)
            : ChatSettings.shared.lines(for: mood)
        chatLine = pet.showChat ? (pool.randomElement() ?? "") : ""
    }

    // MARK: sample data

    private func sampleProject(_ kind: AgentKind) -> String {
        switch kind {
        case .claude: return "agentpet"
        case .codex: return "api-server"
        case .gemini: return "ml-pipeline"
        case .cursor: return "web-app"
        case .opencode: return "cli-tools"
        case .windsurf: return "dashboard"
        case .antigravity: return "mobile-app"
        default: return "project"
        }
    }

    private func sampleTitle(_ kind: AgentKind) -> String? {
        switch kind {
        case .claude: return "Fix the login redirect"
        case .codex: return "Add pagination to /pets"
        case .gemini: return "Tune the ranking model"
        case .cursor: return "Refactor the gallery grid"
        default: return nil
        }
    }

    /// Realistic "live" message a hook would carry; a custom bubble message overrides it.
    private func sampleMessage(_ state: AgentState) -> String? {
        switch state {
        case .working:    return "Editing PetView.swift…"
        case .waiting:    return "Waiting for your input"
        case .done:       return "Done"
        case .registered: return "Starting up…"
        case .idle:       return nil
        }
    }

    @ViewBuilder private func agentIcon(_ kind: AgentKind) -> some View {
        if let img = AgentIcons.image(for: kind) {
            Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: "terminal").foregroundStyle(.secondary)
        }
    }

    private func label(_ kind: AgentKind) -> String { TickerFormatter.agentLabel(for: kind) }

    private func stateLabel(_ m: PetMood) -> String {
        switch m {
        case .idle: return "Idle"
        case .working: return "Working"
        case .waiting: return "Waiting"
        case .done: return "Done"
        case .celebrate: return "Celebrate"
        }
    }

    private func stateColor(_ m: PetMood) -> Color {
        switch m {
        case .idle: return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .done, .celebrate: return .green
        }
    }

    private func stateColor(_ s: AgentState) -> Color {
        switch s {
        case .working, .registered: return .blue
        case .waiting: return .orange
        case .done: return .green
        case .idle: return .secondary
        }
    }
}

