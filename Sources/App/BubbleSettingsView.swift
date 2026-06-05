import SwiftUI
import AgentPetCore

// MARK: - BubbleSettingsView

struct BubbleSettingsView: View {
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var iconPickerKind: AgentKind?

    var body: some View {
        Form {
            presetSection
            tokenOrderSection
            agentIconsSection
            appearanceSection
            filterSection
        }
        .formStyle(.grouped)
        .popover(item: $iconPickerKind) { kind in
            IconPickerPopover(kind: kind)
        }
    }

    // MARK: Preset

    private var presetSection: some View {
        Section("Layout preset") {
            Picker("Preset", selection: $settings.preset) {
                ForEach(BubbleSettings.Preset.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // MARK: Token Order

    @ViewBuilder
    private var tokenOrderSection: some View {
        let isCustom = settings.preset == .custom
        Section {
            List {
                ForEach($settings.customLayout.tokens) { $item in
                    HStack(spacing: 10) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Toggle(item.token.displayName, isOn: $item.isVisible)
                            .onChange(of: item.isVisible) { _ in
                                if settings.preset != .custom {
                                    settings.preset = .custom
                                }
                            }
                    }
                }
                .onMove { from, to in
                    settings.customLayout.tokens.move(fromOffsets: from, toOffset: to)
                    settings.preset = .custom
                }
            }
            .frame(height: CGFloat(settings.customLayout.tokens.count) * 40)
            .opacity(isCustom ? 1.0 : 0.5)
            .disabled(!isCustom)

            Button("Reset to Original") {
                settings.customLayout = .original
            }
            .disabled(!isCustom)
        } header: {
            Text("Token Order")
        } footer: {
            Text(isCustom
                 ? "Drag to reorder. Toggle to show or hide."
                 : "Select \"Custom\" above to edit the token order.")
        }
    }

    // MARK: Agent Icons

    private var agentIconsSection: some View {
        Section("Agent Icons") {
            ForEach(AgentCatalog.all, id: \.kind) { agent in
                HStack(spacing: 10) {
                    ResolvedIconView(choice: settings.iconChoice(for: agent.kind), size: 20)
                    Text(agent.displayName)
                    Spacer()
                    Button("Change…") { iconPickerKind = agent.kind }
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Text("Separator")
                Spacer()
                Picker("Separator", selection: $settings.separatorChar) {
                    Text("·").tag("·")
                    Text("→").tag("→")
                    Text("|").tag("|")
                    Text("space").tag(" ")
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Font size")
                Spacer()
                Picker("Font size", selection: $settings.fontSize) {
                    Text("S").tag(BubbleSettings.FontSize.small)
                    Text("M").tag(BubbleSettings.FontSize.medium)
                    Text("L").tag(BubbleSettings.FontSize.large)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }

            HStack {
                Text("Opacity")
                Slider(value: $settings.opacity, in: 0.6...1.0)
                Text("\(Int(settings.opacity * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
            }

            HStack {
                Text("Theme")
                Spacer()
                Picker("Theme", selection: $settings.theme) {
                    ForEach(BubbleSettings.Theme.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .labelsHidden()
            }
        }
    }

    // MARK: Filter & Sort

    private var filterSection: some View {
        Section("Filter & Sort") {
            Stepper(
                "Max sessions: \(settings.maxSessions)",
                value: $settings.maxSessions,
                in: 1...10
            )

            Picker("Show sessions", selection: $settings.minStateFilter) {
                ForEach(MinStateFilter.allCases, id: \.self) {
                    Text($0.displayName).tag($0)
                }
            }

            Toggle("Group by agent kind", isOn: $settings.groupByKind)

            Section("Hide agents") {
                ForEach(AgentCatalog.all, id: \.kind) { agent in
                    Toggle(agent.displayName, isOn: Binding(
                        get: { !settings.hiddenKinds.contains(agent.kind) },
                        set: { show in
                            if show { settings.hiddenKinds.remove(agent.kind) }
                            else    { settings.hiddenKinds.insert(agent.kind) }
                        }
                    ))
                }
            }
        }
    }
}

// MARK: - Icon Picker Popover

struct IconPickerPopover: View {
    let kind: AgentKind
    @ObservedObject private var settings = BubbleSettings.shared
    @State private var search = ""

    private var filteredSymbols: [String] {
        search.isEmpty
            ? AgentIcons.curatedSymbols
            : AgentIcons.curatedSymbols.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    private var kindName: String {
        AgentCatalog.all.first { $0.kind == kind }?.displayName ?? kind.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Icon for \(kindName)")
                .font(.headline)
                .padding([.horizontal, .top])
                .padding(.bottom, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    brandSection
                    symbolSection
                }
                .padding(.vertical, 12)
            }

            Divider()

            HStack {
                Button("Reset to default") {
                    settings.resetIconChoice(for: kind)
                }
                .controlSize(.small)
                Spacer()
            }
            .padding()
        }
        .frame(width: 320, height: 380)
        .preferredColorScheme(.dark)
    }

    private var brandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Brand logos")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(AgentIcons.brandKinds, id: \.self) { logoKind in
                    iconCell(choice: .brandLogo(logoKind)) {
                        ResolvedIconView(choice: .brandLogo(logoKind), size: 22)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var symbolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SF Symbols")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 110)
            }
            .padding(.horizontal)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                spacing: 8
            ) {
                ForEach(filteredSymbols, id: \.self) { sym in
                    iconCell(choice: .sfSymbol(sym)) {
                        Image(systemName: sym)
                            .font(.system(size: 18))
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func iconCell<Content: View>(
        choice: IconChoice,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let selected = settings.iconChoice(for: kind) == choice
        Button {
            settings.setIconChoice(choice, for: kind)
        } label: {
            content()
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selected ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
