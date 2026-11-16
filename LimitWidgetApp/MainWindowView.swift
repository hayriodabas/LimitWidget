import SwiftUI

/// Ana pencere: özet kartı ve sağlayıcı listesi. Araç çubuğu düğmeleri sistemin cam araç çubuğunda görünür.
struct MainWindowView: View {
    enum SortMode: String, CaseIterable, Identifiable {
        case custom
        case usage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .custom: return "Kendi sıram"
            case .usage: return "Kullanıma göre"
            }
        }
    }

    @Bindable var store: SubscriptionStore
    var onOpenSettings: () -> Void = {}

    @State private var sortMode: SortMode = .custom
    @State private var showsOnlyAttention = false
    @State private var editingSubscription: AISubscription?
    @State private var isAddingNew = false
    @State private var pendingDeletion: AISubscription?

    private var visibleSubscriptions: [AISubscription] {
        var items = store.orderedSubscriptions
        if showsOnlyAttention {
            items = items.filter { $0.usageRatio >= 0.70 }
        }
        if sortMode == .usage {
            items.sort { $0.usageRatio > $1.usageRatio }
        }
        return items
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 24) {
                OverviewCard(store: store, now: context.date)

                providersSection(now: context.date)

                if let message = store.lastErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .frame(width: 720)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("LimitWidget")
        .navigationSubtitle(windowSubtitle)
        .toolbar { toolbarContent }
        .preferredColorScheme(store.themeMode.preferredColorScheme)
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.string(forKey: "LWDebugOpen") == "add" { isAddingNew = true }
            if UserDefaults.standard.string(forKey: "LWDebugOpen") == "manual" { isAddingNew = true }
        }
        #endif
        .sheet(isPresented: $isAddingNew) {
            SubscriptionEditorSheet(subscription: nil) { newSubscription in
                store.add(newSubscription)
            }
        }
        .sheet(item: $editingSubscription) { subscription in
            SubscriptionEditorSheet(subscription: subscription) { updated in
                store.update(updated)
            }
        }
        .alert(
            "\(pendingDeletion?.providerName ?? "Sağlayıcı") silinsin mi?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("Sil", role: .destructive) {
                withAnimation(.snappy) {
                    store.delete(id: item.id)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { _ in
            Text("Bu sağlayıcı listeden, menü çubuğundan ve widget'tan kaldırılır.")
        }
    }

    private var windowSubtitle: String {
        let active = store.activeSubscriptions.count
        let total = store.subscriptions.count
        if total == 0 { return "Sağlayıcı yok" }
        return active == total ? "\(total) sağlayıcı izleniyor" : "\(active)/\(total) sağlayıcı izleniyor"
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sıralama", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                Divider()

                Toggle("Yalnızca sınıra yakın olanlar", isOn: $showsOnlyAttention)
            } label: {
                Label("Görünüm", systemImage: "line.3.horizontal.decrease")
            }
            .help("Sıralama ve filtre")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await store.syncLocalUsageAsync() }
            } label: {
                Label {
                    Text("Yenile")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                        .symbolEffect(.rotate, options: .repeat(.continuous), isActive: store.isSyncing)
                }
            }
            .disabled(store.isSyncing)
            .keyboardShortcut("r", modifiers: .command)
            .help("Kotaları şimdi yenile (⌘R)")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                isAddingNew = true
            } label: {
                Label("Sağlayıcı Ekle", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
            .help("Sağlayıcı ekle (⌘N)")
        }

        ToolbarSpacer(.fixed, placement: .primaryAction)

        ToolbarItem(placement: .primaryAction) {
            Button(action: onOpenSettings) {
                Label("Ayarlar", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            .help("Ayarlar (⌘,)")
        }
    }

    // MARK: Providers

    private func providersSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Sağlayıcılar")
                    .font(.system(size: 15, weight: .semibold))

                Spacer()

                Text(updatedText(now: now))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 4)

            let items = visibleSubscriptions
            if items.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .surface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ProviderCardRow(
                            subscription: item,
                            now: now,
                            canMoveUp: sortMode == .custom && store.canMove(id: item.id, by: -1),
                            canMoveDown: sortMode == .custom && store.canMove(id: item.id, by: 1),
                            onEdit: { editingSubscription = item },
                            onDelete: { pendingDeletion = item },
                            onToggleEnabled: { store.setEnabled(!item.isEnabled, id: item.id) },
                            onSelectWindow: { store.setWindowType($0, id: item.id) },
                            onMove: { offset in
                                withAnimation(.snappy) {
                                    store.move(id: item.id, by: offset)
                                }
                            }
                        )

                        if index < items.count - 1 {
                            Divider()
                                .padding(.leading, 70)
                                .padding(.trailing, 18)
                        }
                    }
                }
                .surface()
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.subscriptions.isEmpty {
            ContentUnavailableView {
                Label("Henüz sağlayıcı yok", systemImage: "gauge.with.dots.needle.33percent")
            } description: {
                Text("Claude Code, Codex, Antigravity veya OpenCode kotanızı izlemek için bir sağlayıcı ekleyin.")
            } actions: {
                Button("Sağlayıcı Ekle") { isAddingNew = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ContentUnavailableView {
                Label("Sınıra yakın sağlayıcı yok", systemImage: "checkmark.circle")
            } description: {
                Text("Tüm kotalar %70'in altında.")
            } actions: {
                Button("Tümünü Göster") { showsOnlyAttention = false }
                    .buttonStyle(.glass)
            }
        }
    }

    private func updatedText(now: Date) -> String {
        if store.isSyncing { return "Kotalar okunuyor…" }
        let seconds = now.timeIntervalSince(store.lastRefreshedAt)
        if seconds < 60 { return "Az önce güncellendi" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) dk önce güncellendi" }
        return "Son güncelleme \(store.lastRefreshedAt.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Overview

/// En yüksek kullanımı halka ile, durumu tek cümleyle anlatan özet kartı.
private struct OverviewCard: View {
    let store: SubscriptionStore
    let now: Date

    private static let turkish = Locale(identifier: "tr_TR")

    var body: some View {
        let peak = store.peakSubscription
        let ratio = peak?.usageRatio ?? 0

        HStack(alignment: .center, spacing: 24) {
            UsageRing(ratio: ratio, lineWidth: 10) {
                VStack(spacing: 0) {
                    Text(AISubscription.percentText(peak?.usagePercentage ?? 0))
                        .numericStyle(size: 26)
                        .contentTransition(.numericText())
                    Text("en yüksek")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            .animation(.smooth, value: ratio)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(headline)
                        .font(.system(size: 20, weight: .semibold))
                    Text(detail(peak: peak))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 0) {
                    stat(title: "Ortalama", value: AISubscription.percentText(store.averageUsagePercentage))
                    statDivider
                    stat(title: "İzlenen", value: "\(store.activeSubscriptions.count)")
                    statDivider
                    stat(title: "Sıradaki yenilenme", value: nextResetText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .surface()
    }

    private var headline: String {
        let active = store.activeSubscriptions
        guard !active.isEmpty else { return "Takip edilen sağlayıcı yok" }
        let critical = active.filter { $0.severity == .critical }
        let warning = active.filter { $0.severity == .warning }
        if critical.count == 1, let item = critical.first {
            return "\(item.providerName) kotası dolmak üzere"
        }
        if critical.count > 1 {
            return "\(critical.count) sağlayıcının kotası dolmak üzere"
        }
        if warning.count == 1, let item = warning.first {
            return "\(item.providerName) sınırına yaklaşıyor"
        }
        if warning.count > 1 {
            return "\(warning.count) sağlayıcı sınıra yaklaşıyor"
        }
        return "Tüm kotalar rahat"
    }

    private func detail(peak: AISubscription?) -> String {
        guard let peak else {
            return "Araç çubuğundaki + düğmesiyle bir sağlayıcı ekleyin."
        }
        let window = peak.windowType.displayName.lowercased(with: Self.turkish)
        var sentence = "En yüksek kullanım \(peak.providerName) \(window) kotasında."
        if let phrase = peak.resetPhrase(relativeTo: now), phrase != "şimdi" {
            sentence += " \(phrase) sonra yenilenir."
        }
        return sentence
    }

    private var nextResetText: String {
        guard let next = store.nextResettingSubscription(now: now),
              let phrase = next.resetPhrase(relativeTo: now) else {
            return "—"
        }
        return phrase
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(value)
                .numericStyle(size: 15, weight: .medium)
                .contentTransition(.numericText())
        }
        .padding(.trailing, 18)
    }

    private var statDivider: some View {
        Divider()
            .frame(height: 28)
            .padding(.trailing, 18)
    }
}

// MARK: - Provider row

private struct ProviderCardRow: View {
    let subscription: AISubscription
    let now: Date
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleEnabled: () -> Void
    let onSelectWindow: (SubscriptionWindowType) -> Void
    let onMove: (Int) -> Void

    @State private var isHovered = false

    private var windowChoices: [SubscriptionWindowType] {
        guard subscription.dataSource == .localAuto else { return [] }
        switch subscription.effectiveProviderKey {
        case LocalProviderKey.claudeCode.rawValue, LocalProviderKey.codex.rawValue:
            return [.fiveHour, .weekly]
        case LocalProviderKey.opencode.rawValue:
            return [.fiveHour, .weekly, .monthly]
        default:
            return []
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ProviderIcon(subscription: subscription, size: 38)
                .saturation(subscription.isEnabled ? 1 : 0)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(subscription.providerName)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)

                            if subscription.dataSource != .localAuto {
                                Tag(text: "Manuel")
                            }
                            if !subscription.isEnabled {
                                Tag(text: "Menü çubuğunda gizli")
                            }
                        }

                        Text(subscription.secondaryLine)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(subscription.percentText)
                            .numericStyle(size: 22)
                            .foregroundStyle(UsageTone.textStyle(for: subscription.severity))
                            .contentTransition(.numericText())
                        if let sentence = subscription.resetSentence(relativeTo: now) {
                            Text(sentence)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    actionsMenu
                }

                UsageBar(ratio: subscription.usageRatio, height: 7)
                    .animation(.smooth, value: subscription.usageRatio)

                let metrics = subscription.displayMetrics
                if !metrics.isEmpty {
                    MetricStrip(metrics: metrics)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .opacity(subscription.isEnabled ? 1 : 0.62)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { menuItems }
        .onTapGesture(count: 2, perform: onEdit)
    }

    private var actionsMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 26, height: 26)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .menuIndicator(.hidden)
        .fixedSize()
        .opacity(isHovered ? 1 : 0.55)
        .help("Diğer işlemler")
    }

    @ViewBuilder
    private var menuItems: some View {
        Button("Düzenle…", systemImage: "slider.horizontal.3", action: onEdit)

        if !windowChoices.isEmpty {
            Picker(
                "Ana kota",
                selection: Binding(
                    get: { subscription.windowType },
                    set: { onSelectWindow($0) }
                )
            ) {
                ForEach(windowChoices) { window in
                    Text(window.displayName).tag(window)
                }
            }
        }

        Button(
            subscription.isEnabled ? "Menü çubuğunda gizle" : "Menü çubuğunda göster",
            systemImage: subscription.isEnabled ? "eye.slash" : "eye",
            action: onToggleEnabled
        )

        Divider()

        Button("Yukarı taşı", systemImage: "arrow.up") { onMove(-1) }
            .disabled(!canMoveUp)
        Button("Aşağı taşı", systemImage: "arrow.down") { onMove(1) }
            .disabled(!canMoveDown)

        Divider()

        Button("Sil…", systemImage: "trash", role: .destructive, action: onDelete)
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(Capsule(style: .continuous).fill(.quaternary))
    }
}

// MARK: - Surface

extension View {
    /// İçerik kartları için Liquid Glass yüzey.
    func surface(cornerRadius: CGFloat = 20) -> some View {
        glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

// MARK: - Editor

/// Sağlayıcı ekleme ve düzenleme sayfası (Sistem Ayarları düzeninde form).
private struct SubscriptionEditorSheet: View {
    private struct QuickTemplate: Identifiable {
        let id: String
        let key: LocalProviderKey
        let name: String
        let subtitle: String
        let icon: String
        let window: SubscriptionWindowType
        var detail: String = ""
    }

    private static let autoTemplates: [QuickTemplate] = [
        QuickTemplate(id: "claude_code", key: .claudeCode, name: "Claude Code", subtitle: "", icon: "sparkles", window: .weekly, detail: "Anthropic · 5 saatlik ve haftalık kota"),
        QuickTemplate(id: "antigravity", key: .antigravity, name: "Antigravity", subtitle: "", icon: "atom", window: .fiveHour, detail: "Google · Gemini ve Claude/GPT kotası"),
        QuickTemplate(id: "codex", key: .codex, name: "Codex", subtitle: "", icon: "terminal", window: .weekly, detail: "OpenAI · 5 saatlik ve haftalık kota"),
        QuickTemplate(id: "opencode", key: .opencode, name: "OpenCode", subtitle: "", icon: "chevron.left.forwardslash.chevron.right", window: .monthly, detail: "OpenCode Go · 5 saatlik, haftalık ve aylık")
    ]

    private static let manualPresets: [QuickTemplate] = [
        QuickTemplate(id: "cursor", key: .custom, name: "Cursor", subtitle: "Pro Plan", icon: "cursorarrow.rays", window: .monthly),
        QuickTemplate(id: "copilot", key: .custom, name: "GitHub Copilot", subtitle: "Premium istekler", icon: "chevron.left.forwardslash.chevron.right", window: .monthly),
        QuickTemplate(id: "windsurf", key: .custom, name: "Windsurf", subtitle: "Pro Plan", icon: "wind", window: .monthly),
        QuickTemplate(id: "deepseek", key: .custom, name: "DeepSeek", subtitle: "API", icon: "cpu", window: .monthly)
    ]

    private static let simpleWindows: [SubscriptionWindowType] = [.fiveHour, .daily, .weekly, .monthly]

    @Environment(\.dismiss) private var dismiss

    let existingSubscription: AISubscription?
    let onSave: (AISubscription) -> Void

    @State private var dataSource: SubscriptionDataSource
    @State private var providerKey: LocalProviderKey
    @State private var providerName: String
    @State private var subtitle: String
    @State private var iconName: String
    @State private var windowType: SubscriptionWindowType
    @State private var usedPercentage: Double
    @State private var isEnabled: Bool

    init(subscription: AISubscription?, onSave: @escaping (AISubscription) -> Void) {
        self.existingSubscription = subscription
        self.onSave = onSave

        if let sub = subscription {
            _dataSource = State(initialValue: sub.dataSource == .localAuto ? .localAuto : .manual)
            _providerKey = State(initialValue: LocalProviderKey(rawValue: sub.providerKey) ?? .custom)
            _providerName = State(initialValue: sub.providerName)
            _subtitle = State(initialValue: sub.dataSource == .localAuto ? "" : sub.subtitle)
            _iconName = State(initialValue: sub.iconName)
            _windowType = State(initialValue: sub.windowType)
            _usedPercentage = State(initialValue: Double(sub.usagePercentage))
            _isEnabled = State(initialValue: sub.isEnabled)
        } else {
            let first = Self.autoTemplates[0]
            _dataSource = State(initialValue: .localAuto)
            _providerKey = State(initialValue: first.key)
            _providerName = State(initialValue: first.name)
            _subtitle = State(initialValue: "")
            _iconName = State(initialValue: first.icon)
            _windowType = State(initialValue: first.window)
            _usedPercentage = State(initialValue: 25)
            _isEnabled = State(initialValue: true)
        }
    }

    private var trimmedName: String {
        providerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewSubscription: AISubscription {
        let isAuto = dataSource == .localAuto
        let existing = existingSubscription
        let keepsLiveValues = isAuto && existing?.dataSource == .localAuto && existing?.providerKey == providerKey.rawValue
        return AISubscription(
            id: existing?.id ?? UUID(),
            providerKey: isAuto ? providerKey.rawValue : LocalProviderKey.custom.rawValue,
            providerName: trimmedName.isEmpty ? "Sağlayıcı" : trimmedName,
            subtitle: keepsLiveValues ? (existing?.subtitle ?? "") : subtitle,
            iconName: iconName,
            windowType: windowType,
            usedAmount: isAuto ? (keepsLiveValues ? (existing?.usedAmount ?? 0) : 0) : usedPercentage.rounded(),
            totalLimit: 100,
            unitLabel: "%",
            resetsAt: keepsLiveValues ? existing?.resetsAt : nil,
            resetDescription: windowType.displayName,
            dataSource: dataSource,
            isEnabled: isEnabled,
            sortOrder: existing?.sortOrder ?? 0,
            lastUpdated: Date()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Önizleme") {
                    ProviderSummaryRow(subscription: previewSubscription)
                        .padding(.vertical, 4)
                }

                Section {
                    Picker("Takip", selection: $dataSource) {
                        Text("Otomatik").tag(SubscriptionDataSource.localAuto)
                        Text("Manuel").tag(SubscriptionDataSource.manual)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(
                        dataSource == .localAuto
                            ? "Kullanım, bu Mac'teki aracın kendi kayıtlarından kendiliğinden okunur."
                            : "Kullanımı siz girersiniz; istediğiniz zaman güncelleyebilirsiniz."
                    )
                    .foregroundStyle(.secondary)
                }

                if dataSource == .localAuto {
                    Section("Servis") {
                        ForEach(Self.autoTemplates) { template in
                            autoTemplateRow(template)
                        }
                    }
                } else {
                    Section("Servis") {
                        TextField("Ad", text: $providerName, prompt: Text("Örn. Cursor"))
                        TextField("Plan", text: $subtitle, prompt: Text("İsteğe bağlı"))
                        LabeledContent("Hazır şablon") {
                            Menu("Seç") {
                                ForEach(Self.manualPresets) { preset in
                                    Button(preset.name) { applyTemplate(preset) }
                                }
                            }
                            .fixedSize()
                        }
                    }

                    Section("Kullanım") {
                        LabeledContent("Kullanılan") {
                            Text(AISubscription.percentText(Int(usedPercentage.rounded())))
                                .monospacedDigit()
                                .foregroundStyle(UsageTone.textStyle(forRatio: usedPercentage / 100))
                        }
                        Slider(value: $usedPercentage, in: 0...100, step: 1)
                            .labelsHidden()
                    }
                }

                Section {
                    Picker("Kota dönemi", selection: $windowType) {
                        ForEach(Self.simpleWindows) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    Toggle("Menü çubuğunda ve widget'ta göster", isOn: $isEnabled)
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: dataSource) { _, newValue in
                if newValue == .localAuto {
                    let match = Self.autoTemplates.first { $0.key == providerKey } ?? Self.autoTemplates[0]
                    applyTemplate(match)
                } else if Self.autoTemplates.contains(where: { $0.name == providerName }) {
                    applyTemplate(Self.manualPresets[0])
                }
            }

            HStack {
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(existingSubscription == nil ? "Ekle" : "Kaydet") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .padding(.top, 4)
        }
        .frame(width: 480, height: dataSource == .localAuto ? 600 : 640)
    }

    private func autoTemplateRow(_ template: QuickTemplate) -> some View {
        let isSelected = providerKey == template.key
        return Button {
            applyTemplate(template)
        } label: {
            HStack(spacing: 10) {
                ProviderIcon(key: template.key.rawValue, name: template.name, fallbackSymbol: template.icon, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(template.name)
                    Text(template.detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func applyTemplate(_ template: QuickTemplate) {
        providerKey = template.key
        providerName = template.name
        subtitle = template.subtitle
        iconName = template.icon
        windowType = template.window
    }

    private func save() {
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let isAuto = dataSource == .localAuto
        let resolvedKey = isAuto ? providerKey.rawValue : AISubscription.inferProviderKey(from: trimmedName)
        let existing = existingSubscription
        let keepsLiveValues = isAuto && existing?.dataSource == .localAuto && existing?.providerKey == providerKey.rawValue

        let item = AISubscription(
            id: existing?.id ?? UUID(),
            providerKey: resolvedKey,
            providerName: trimmedName,
            subtitle: isAuto ? (keepsLiveValues ? (existing?.subtitle ?? "") : "") : trimmedSubtitle,
            iconName: iconName,
            windowType: windowType,
            usedAmount: isAuto ? (keepsLiveValues ? (existing?.usedAmount ?? 0) : 0) : usedPercentage.rounded(),
            totalLimit: 100,
            unitLabel: "%",
            resetsAt: keepsLiveValues ? existing?.resetsAt : nil,
            resetDescription: windowType.displayName,
            dataSource: dataSource,
            isEnabled: isEnabled,
            sortOrder: existing?.sortOrder ?? 0,
            lastUpdated: Date()
        )
        onSave(item)
        dismiss()
    }
}
