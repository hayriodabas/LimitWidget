import SwiftUI

/// Tüm aboneliklerin yönetildiği ve detaylı stüdyo telemetri kartlarının gösterildiği ana pencere.
struct MainWindowView: View {
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "Tüm Sağlayıcılar"
        case attention = "Yüksek Yük (%70+)"

        var id: String { rawValue }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case custom = "Özel Sıra"
        case usageDescending = "Yüke Göre"

        var id: String { rawValue }
    }

    @Environment(\.colorScheme) private var colorScheme
    @Bindable var store: SubscriptionStore
    @State private var filterOption: FilterOption = .all
    @State private var sortOption: SortOption = .custom
    @State private var editingSubscription: AISubscription?
    @State private var isAddingNew = false
    @State private var showResetConfirmation = false
    @State private var hoveredCardID: UUID?
    @State private var isHoveringReadoutDeck = false

    private var filteredSubscriptions: [AISubscription] {
        let base: [AISubscription]
        switch filterOption {
        case .all:
            base = store.subscriptions
        case .attention:
            base = store.subscriptions.filter { $0.usageRatio >= 0.70 }
        }

        switch sortOption {
        case .custom:
            return base.sorted { $0.sortOrder < $1.sortOrder }
        case .usageDescending:
            return base.sorted { $0.usageRatio > $1.usageRatio }
        }
    }

    private var highestSeverity: UsageSeverity {
        if store.criticalCount > 0 { return .critical }
        if store.warningCount > 0 { return .warning }
        return .normal
    }

    var body: some View {
        VStack(spacing: 0) {
            studioTelemetryHeader
            hairlineDivider
            studioControlBar
            hairlineDivider
            subscriptionList
            hairlineDivider
            studioStatusFooter
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(StudioPalette.windowCanvas(for: colorScheme))
        .preferredColorScheme(store.themeMode.preferredColorScheme)
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
        .confirmationDialog(
            "Varsayılan sağlayıcı şablonuna dönülsün mü?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Şablonu Yükle ve Canlı Ölç", role: .destructive) {
                store.resetToDefaults()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Mevcut özel abonelikleriniz varsayılan 4 sağlayıcıyla değiştirilip canlı kotalar yeniden okunacaktır.")
        }
    }

    // MARK: - Studio Telemetry Header

    private var studioTelemetryHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            // Sol: Uygulama Kimliği ve Canlı Telemetri Durumu
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    StudioPalette.statusColor(for: highestSeverity).opacity(0.24),
                                    StudioPalette.statusColor(for: highestSeverity).opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(
                                    StudioPalette.statusColor(for: highestSeverity).opacity(0.42),
                                    lineWidth: 1
                                )
                        )

                    Image(systemName: "slider.horizontal.below.square.and.square.filled")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StudioPalette.statusColor(for: highestSeverity))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("LIMITWIDGET")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .kerning(1.1)

                        StudioTagPill(
                            text: store.isSyncing ? "SENKRONİZE EDİLİYOR" : "CANLI TELEMETRİ",
                            accent: StudioPalette.statusColor(for: highestSeverity)
                        )
                    }

                    Text("Yerel CLI, OAuth ve App Group üzerinden gerçek zamanlı kota izleme konsolu")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            // Sağ: Gömülü Enstrüman Okuma Modülü (Instrument Readout Deck)
            HStack(spacing: 0) {
                telemetryReadoutCell(
                    label: "AKTİF HAT",
                    value: "\(store.activeSubscriptions.count)/\(store.subscriptions.count)",
                    valueColor: .primary
                )
                verticalReadoutHairline
                telemetryReadoutCell(
                    label: "ORTALAMA YÜK",
                    value: "%\(store.averageUsagePercentage)",
                    valueColor: StudioPalette.normalEnd
                )
                verticalReadoutHairline
                telemetryReadoutCell(
                    label: "TAVAN YÜK",
                    value: "%\(store.highestUsagePercentage)",
                    valueColor: StudioPalette.statusColor(for: highestSeverity)
                )
                verticalReadoutHairline
                telemetryReadoutCell(
                    label: "KRİTİK",
                    value: "\(store.criticalCount)",
                    valueColor: store.criticalCount > 0 ? StudioPalette.criticalStart : .secondary
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(StudioPalette.recessedWell(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isHoveringReadoutDeck
                            ? StudioPalette.statusColor(for: highestSeverity).opacity(0.45)
                            : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)),
                        lineWidth: 1
                    )
            )
            .onHover { hovering in
                isHoveringReadoutDeck = hovering
            }
            .popover(isPresented: $isHoveringReadoutDeck, arrowEdge: .bottom) {
                topRatioHoverBreakdownView
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(StudioPalette.elevatedHeader(for: colorScheme))
    }

    private var topRatioHoverBreakdownView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SAĞLAYICI KOTA DAĞILIMI")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("TAVAN %\(store.highestUsagePercentage)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(StudioPalette.statusColor(for: highestSeverity))
            }

            ForEach(store.activeSubscriptions) { sub in
                let statusColor = StudioPalette.statusColor(for: sub.severity)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        ProviderBrandBadge(subscription: sub, size: 18)
                        Text(sub.providerName)
                            .font(.system(size: 11.5, weight: .semibold))
                        Spacer(minLength: 8)
                        Text(sub.formattedResetCountdown())
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("%\(sub.usagePercentage)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor)
                    }

                    StudioMeterBar(
                        ratio: sub.usageRatio,
                        severity: sub.severity,
                        height: 5,
                        showTicks: false
                    )

                    Text(sub.compactSummaryText)
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
            }
        }
        .padding(12)
        .frame(width: 310)
        .background(StudioPalette.windowCanvas(for: colorScheme))
    }

    private func telemetryReadoutCell(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .kerning(0.7)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var verticalReadoutHairline: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
            .frame(width: 1, height: 28)
    }

    // MARK: - Studio Control Bar

    private var studioControlBar: some View {
        HStack(spacing: 10) {
            // Filtre Kapsülü
            HStack(spacing: 3) {
                ForEach(FilterOption.allCases) { option in
                    let isSelected = filterOption == option
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            filterOption = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                            : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(StudioPalette.recessedWell(for: colorScheme))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07),
                        lineWidth: 0.75
                    )
            )

            // Sıralama Seçici
            HStack(spacing: 3) {
                ForEach(SortOption.allCases) { option in
                    let isSelected = sortOption == option
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            sortOption = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                            : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(StudioPalette.recessedWell(for: colorScheme))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07),
                        lineWidth: 0.75
                    )
            )

            // Tema Seçici (Sistem / Koyu / Açık)
            HStack(spacing: 3) {
                ForEach(AppThemeMode.allCases) { mode in
                    let isSelected = store.themeMode == mode
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            store.setThemeMode(mode)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 10, weight: .semibold))
                            Text(mode.displayName)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.12) : Color.white)
                                        : Color.clear
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(StudioPalette.recessedWell(for: colorScheme))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07),
                        lineWidth: 0.75
                    )
            )

            Spacer()

            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Şablonu Sıfırla")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                            lineWidth: 0.75
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                Task { await store.syncLocalUsageAsync() }
            } label: {
                HStack(spacing: 6) {
                    if store.isSyncing {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Canlı Ölç")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.10),
                            lineWidth: 0.75
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(store.isSyncing)

            Button {
                isAddingNew = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Sağlayıcı Ekle")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.23, green: 0.51, blue: 0.96),
                                    Color(red: 0.15, green: 0.39, blue: 0.92)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(StudioPalette.elevatedHeader(for: colorScheme).opacity(0.75))
    }

    // MARK: - Subscription Card List

    @ViewBuilder
    private var subscriptionList: some View {
        if filteredSubscriptions.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 32, weight: .thin))
                    .foregroundStyle(.secondary)
                Text("Bu filtreye uygun sağlayıcı bulunmuyor")
                    .font(.system(size: 14, weight: .semibold))
                Text("Tüm sağlayıcıları görüntüleyin veya yeni bir abonelik kartı ekleyin.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            VStack(spacing: 10) {
                ForEach(filteredSubscriptions) { subscription in
                    studioProviderCard(for: subscription)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func studioProviderCard(for subscription: AISubscription) -> some View {
        let isHovered = hoveredCardID == subscription.id
        let brand = ProviderBrand.resolve(for: subscription)

        return HStack(spacing: 14) {
            // Sol marka aksan şeridi
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(brand.gradient)
                .frame(width: 3.5)
                .padding(.vertical, 4)

            SubscriptionProgressRow(subscription: subscription, style: .detailed)

            // Sağ: Stüdyo Hızlı İşlem Sütunu
            VStack(spacing: 6) {
                Button {
                    togglePrimaryWindow(for: subscription)
                } label: {
                    Text(subscription.windowType.shortLabel.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(StudioPalette.recessedWell(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                                    lineWidth: 0.75
                                )
                        )
                }
                .buttonStyle(.plain)
                .help("Ana çubuk penceresini değiştir (5sa / Haftalık / Aylık)")

                HStack(spacing: 5) {
                    Button {
                        editingSubscription = subscription
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(StudioPalette.recessedWell(for: colorScheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Yapılandır")

                    Button {
                        store.delete(id: subscription.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StudioPalette.criticalStart.opacity(0.85))
                            .frame(width: 26, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(StudioPalette.recessedWell(for: colorScheme))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Kaldır")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(StudioPalette.cardFill(for: colorScheme, isHovered: isHovered))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    StudioPalette.cardBorder(
                        for: colorScheme,
                        accent: brand.primary,
                        isHovered: isHovered
                    ),
                    lineWidth: 1
                )
        )
        .opacity(subscription.isEnabled ? 1.0 : 0.55)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredCardID = hovering ? subscription.id : nil
            }
        }
    }

    private func togglePrimaryWindow(for subscription: AISubscription) {
        var updated = subscription
        switch subscription.windowType {
        case .fiveHour:
            updated.windowType = .weekly
        case .weekly:
            updated.windowType = subscription.providerKey == LocalProviderKey.opencode.rawValue ? .monthly : .fiveHour
        case .monthly, .daily, .creditBalance:
            updated.windowType = .fiveHour
        }
        store.update(updated)
    }

    // MARK: - Footer

    private var studioStatusFooter: some View {
        HStack(spacing: 10) {
            StudioStatusDot(
                color: store.isSyncing ? StudioPalette.warningEnd : StudioPalette.normalEnd,
                size: 5.5
            )

            Text(
                store.isSyncing
                    ? "CANLI KOTA KAYNAKLARI SORGULANIYOR…"
                    : "SON GÜNCELLEME: \(store.lastRefreshedAt.formatted(date: .omitted, time: .standard))"
            )
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .kerning(0.5)
            .foregroundStyle(.secondary)

            Spacer()

            if let errorMessage = store.lastErrorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(StudioPalette.criticalStart)
            } else {
                Text("APP GROUP & WIDGETKIT SENKRONİZE")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .kerning(0.5)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
        .background(StudioPalette.elevatedHeader(for: colorScheme))
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
            .frame(height: 1)
    }
}

/// Abonelik ekleme ve düzenleme formu.
private struct SubscriptionEditorSheet: View {
    private static let availableIcons = [
        "sparkles",
        "terminal",
        "chevron.left.forwardslash.chevron.right",
        "atom",
        "network",
        "cursorarrow.rays",
        "cpu",
        "bolt.fill"
    ]

    @Environment(\.dismiss) private var dismiss

    let existingSubscription: AISubscription?
    let onSave: (AISubscription) -> Void

    @State private var providerKey: LocalProviderKey
    @State private var providerName: String
    @State private var subtitle: String
    @State private var iconName: String
    @State private var windowType: SubscriptionWindowType
    @State private var usedAmount: Double
    @State private var totalLimit: Double
    @State private var unitLabel: String
    @State private var dataSource: SubscriptionDataSource
    @State private var hasResetDate: Bool
    @State private var resetsAt: Date
    @State private var resetDescription: String
    @State private var isEnabled: Bool

    init(subscription: AISubscription?, onSave: @escaping (AISubscription) -> Void) {
        self.existingSubscription = subscription
        self.onSave = onSave
        _providerKey = State(initialValue: LocalProviderKey(rawValue: subscription?.providerKey ?? "") ?? .custom)
        _providerName = State(initialValue: subscription?.providerName ?? "")
        _subtitle = State(initialValue: subscription?.subtitle ?? "")
        _iconName = State(initialValue: subscription?.iconName ?? "sparkles")
        _windowType = State(initialValue: subscription?.windowType ?? .monthly)
        _usedAmount = State(initialValue: subscription?.usedAmount ?? 0)
        _totalLimit = State(initialValue: subscription?.totalLimit ?? 100)
        _unitLabel = State(initialValue: subscription?.unitLabel ?? "%")
        _dataSource = State(initialValue: subscription?.dataSource ?? .manual)
        _hasResetDate = State(initialValue: subscription?.resetsAt != nil)
        _resetsAt = State(initialValue: subscription?.resetsAt ?? Date().addingTimeInterval(3600 * 5))
        _resetDescription = State(initialValue: subscription?.resetDescription ?? "")
        _isEnabled = State(initialValue: subscription?.isEnabled ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(existingSubscription == nil ? "Yeni Sağlayıcı Ekle" : "Sağlayıcı Yapılandırması")
                .font(.system(size: 14, weight: .bold))
                .padding(.top, 18)
                .padding(.bottom, 10)

            Form {
                TextField("Sağlayıcı Adı", text: $providerName, prompt: Text("Örn. Claude Code, Codex, OpenCode"))
                TextField("Alt Başlık / Plan", text: $subtitle, prompt: Text("Örn. Max Plan, Plus, Go"))

                Picker("Sembol", selection: $iconName) {
                    ForEach(Self.availableIcons, id: \.self) { symbol in
                        Label(symbol, systemImage: symbol).tag(symbol)
                    }
                }

                Picker("Birincil Pencere", selection: $windowType) {
                    ForEach(SubscriptionWindowType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                Picker("Veri Kaynağı", selection: $dataSource) {
                    ForEach(SubscriptionDataSource.allCases) { source in
                        Text(source.displayName).tag(source)
                    }
                }

                if dataSource == .localAuto {
                    Picker("Otomatik Okuyucu", selection: $providerKey) {
                        ForEach(LocalProviderKey.allCases) { key in
                            Text(key.displayName).tag(key)
                        }
                    }
                }

                HStack {
                    TextField("Kullanılan", value: $usedAmount, format: .number)
                    TextField("Toplam Limit", value: $totalLimit, format: .number)
                    TextField("Birim", text: $unitLabel)
                        .frame(width: 80)
                }

                Toggle("Sıfırlanma Tarihi Belirt", isOn: $hasResetDate)
                if hasResetDate {
                    DatePicker("Sıfırlanma Zamanı", selection: $resetsAt)
                } else {
                    TextField("Sıfırlanma Açıklaması", text: $resetDescription, prompt: Text("Örn. Haftalık pencere"))
                }

                Toggle("Menü Çubuğu ve Widget'ta Göster", isOn: $isEnabled)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("İptal") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Kaydet") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || totalLimit <= 0)
            }
            .padding(16)
        }
        .frame(width: 460, height: 520)
    }

    private func save() {
        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUnit = unitLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = resetDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let item = AISubscription(
            id: existingSubscription?.id ?? UUID(),
            providerKey: providerKey.rawValue,
            providerName: trimmedName,
            subtitle: trimmedSubtitle,
            iconName: iconName,
            windowType: windowType,
            usedAmount: max(usedAmount, 0),
            totalLimit: max(totalLimit, 0.01),
            unitLabel: trimmedUnit.isEmpty ? "%" : trimmedUnit,
            resetsAt: hasResetDate ? resetsAt : nil,
            resetDescription: trimmedDesc.isEmpty ? nil : trimmedDesc,
            dataSource: dataSource,
            isEnabled: isEnabled,
            sortOrder: existingSubscription?.sortOrder ?? 0,
            lastUpdated: Date()
        )
        onSave(item)
        dismiss()
    }
}
