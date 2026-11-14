import SwiftUI

/// Tüm aboneliklerin yönetildiği ve detaylı stüdyo telemetri kartlarının gösterildiği ana pencere.
struct MainWindowView: View {
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "Tümü"
        case attention = "Yüksek (%70+)"

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
                    valueColor: StudioPalette.progressiveColor(for: Double(store.averageUsagePercentage) / 100.0)
                )
                verticalReadoutHairline
                telemetryReadoutCell(
                    label: "TAVAN YÜK",
                    value: "%\(store.highestUsagePercentage)",
                    valueColor: StudioPalette.progressiveColor(for: Double(store.highestUsagePercentage) / 100.0)
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
                let statusColor = StudioPalette.progressiveColor(for: sub.usageRatio)
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
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .lineLimit(1)
                .foregroundStyle(valueColor)
        }
        .fixedSize(horizontal: true, vertical: false)
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
        HStack(spacing: 8) {
            // Filtre Kapsülü
            HStack(spacing: 2) {
                ForEach(FilterOption.allCases) { option in
                    let isSelected = filterOption == option
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            filterOption = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                            : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .fixedSize(horizontal: true, vertical: false)
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
            HStack(spacing: 2) {
                ForEach(SortOption.allCases) { option in
                    let isSelected = sortOption == option
                    Button {
                        withAnimation(.snappy(duration: 0.18)) {
                            sortOption = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(
                                        isSelected
                                            ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                            : Color.clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .fixedSize(horizontal: true, vertical: false)
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
            HStack(spacing: 2) {
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
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.14) : Color.white)
                                        : Color.clear
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .fixedSize(horizontal: true, vertical: false)
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

            Spacer(minLength: 8)

            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Sıfırla")
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
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
            .help("Varsayılan sağlayıcı şablonunu geri yükle")

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
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
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
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
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

/// Sadeleştirilmiş, tek tıkla hazır şablonlu ve canlı önizlemeli sağlayıcı ekleme/düzenleme paneli.
private struct SubscriptionEditorSheet: View {
    private struct QuickTemplate: Identifiable {
        let id: String
        let key: LocalProviderKey
        let name: String
        let subtitle: String
        let icon: String
        let window: SubscriptionWindowType
        let isAuto: Bool
    }

    private static let autoTemplates: [QuickTemplate] = [
        QuickTemplate(
            id: "claude_code",
            key: .claudeCode,
            name: "Claude Code",
            subtitle: "Max / Pro • Otomatik Canlı Kota",
            icon: "sparkles",
            window: .weekly,
            isAuto: true
        ),
        QuickTemplate(
            id: "antigravity",
            key: .antigravity,
            name: "Antigravity",
            subtitle: "Gemini & Claude/GPT • Canlı Kota",
            icon: "atom",
            window: .fiveHour,
            isAuto: true
        ),
        QuickTemplate(
            id: "codex",
            key: .codex,
            name: "Codex",
            subtitle: "ChatGPT Plus/Pro • Canlı Kota",
            icon: "terminal",
            window: .weekly,
            isAuto: true
        ),
        QuickTemplate(
            id: "opencode",
            key: .opencode,
            name: "OpenCode",
            subtitle: "OpenCode Go • Canlı Kota",
            icon: "chevron.left.forwardslash.chevron.right",
            window: .monthly,
            isAuto: true
        )
    ]

    private static let manualPresets: [QuickTemplate] = [
        QuickTemplate(id: "cursor", key: .custom, name: "Cursor", subtitle: "Pro Plan • 500 Hızlı İstek", icon: "cursorarrow.rays", window: .monthly, isAuto: false),
        QuickTemplate(id: "copilot", key: .custom, name: "GitHub Copilot", subtitle: "Premium İstek Kotası", icon: "network", window: .monthly, isAuto: false),
        QuickTemplate(id: "windsurf", key: .custom, name: "Windsurf", subtitle: "Pro Flow Kredisi", icon: "bolt.fill", window: .monthly, isAuto: false),
        QuickTemplate(id: "deepseek", key: .custom, name: "DeepSeek", subtitle: "API / Aylık Kullanım", icon: "cpu", window: .monthly, isAuto: false)
    ]

    private static let simpleWindows: [SubscriptionWindowType] = [.fiveHour, .daily, .weekly, .monthly]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
            _dataSource = State(initialValue: sub.dataSource)
            _providerKey = State(initialValue: LocalProviderKey(rawValue: sub.providerKey) ?? .custom)
            _providerName = State(initialValue: sub.providerName)
            _subtitle = State(initialValue: sub.subtitle)
            _iconName = State(initialValue: sub.iconName)
            _windowType = State(initialValue: sub.windowType)
            _usedPercentage = State(initialValue: Double(sub.usagePercentage))
            _isEnabled = State(initialValue: sub.isEnabled)
        } else {
            // Varsayılan olarak en pratik mod: Otomatik Claude Code seçili başlar
            let first = Self.autoTemplates[0]
            _dataSource = State(initialValue: .localAuto)
            _providerKey = State(initialValue: first.key)
            _providerName = State(initialValue: first.name)
            _subtitle = State(initialValue: first.subtitle)
            _iconName = State(initialValue: first.icon)
            _windowType = State(initialValue: first.window)
            _usedPercentage = State(initialValue: 25)
            _isEnabled = State(initialValue: true)
        }
    }

    private var previewSubscription: AISubscription {
        AISubscription(
            id: existingSubscription?.id ?? UUID(),
            providerKey: dataSource == .localAuto ? providerKey.rawValue : LocalProviderKey.custom.rawValue,
            providerName: providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Sağlayıcı Adı" : providerName,
            subtitle: subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? (dataSource == .localAuto ? "Otomatik Canlı Kota" : "%\(Int(usedPercentage.rounded())) Kullanıldı")
                : subtitle,
            iconName: iconName,
            windowType: windowType,
            usedAmount: dataSource == .localAuto ? (existingSubscription?.usedAmount ?? 35) : usedPercentage,
            totalLimit: 100,
            unitLabel: "%",
            resetsAt: existingSubscription?.resetsAt,
            resetDescription: windowType.displayName,
            dataSource: dataSource,
            isEnabled: isEnabled,
            sortOrder: existingSubscription?.sortOrder ?? 0,
            lastUpdated: Date()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Başlık
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(existingSubscription == nil ? "Sağlayıcı Ekle" : "Sağlayıcıyı Düzenle")
                        .font(.system(size: 16, weight: .bold))
                    Text("Hazır bir servis seçin veya özel bir abonelik yüzdesi tanımlayın.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Canlı Önizleme Kartı
            VStack(alignment: .leading, spacing: 6) {
                Text("ÖNİZLEME")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(.secondary)

                SubscriptionProgressRow(subscription: previewSubscription, style: .compact)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(StudioPalette.cardFill(for: colorScheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(StudioPalette.cardBorder(for: colorScheme), lineWidth: 1)
                    )
            }

            // 1. Mod Seçimi: Otomatik Bağlantı vs Manuel Takip
            Picker("Takip Türü", selection: $dataSource) {
                Text("Otomatik (Canlı Okuma)").tag(SubscriptionDataSource.localAuto)
                Text("Manuel (Özel Sağlayıcı)").tag(SubscriptionDataSource.manual)
            }
            .pickerStyle(.segmented)
            .onChange(of: dataSource) { _, newValue in
                if newValue == .localAuto {
                    let match = Self.autoTemplates.first(where: { $0.key == providerKey }) ?? Self.autoTemplates[0]
                    applyTemplate(match)
                } else if Self.autoTemplates.contains(where: { $0.name == providerName }) {
                    applyTemplate(Self.manualPresets[0])
                }
            }

            if dataSource == .localAuto {
                // Otomatik Sağlayıcı Kartları (Tek Tıkla Seçim)
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. DESTEKLENEN SERVİSİ SEÇİN")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .kerning(0.7)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Self.autoTemplates) { tpl in
                            let isSelected = providerKey == tpl.key
                            let dummySub = AISubscription(
                                providerKey: tpl.key.rawValue,
                                providerName: tpl.name,
                                iconName: tpl.icon,
                                windowType: tpl.window,
                                usedAmount: 0,
                                totalLimit: 100
                            )
                            let brand = ProviderBrand.resolve(for: dummySub)

                            Button {
                                applyTemplate(tpl)
                            } label: {
                                HStack(spacing: 10) {
                                    ProviderBrandBadge(subscription: dummySub, size: 30)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tpl.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(tpl.window.displayName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(brand.primary)
                                            .font(.system(size: 14))
                                    }
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            isSelected
                                                ? brand.primary.opacity(colorScheme == .dark ? 0.16 : 0.10)
                                                : StudioPalette.recessedWell(for: colorScheme)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            isSelected
                                                ? brand.primary.opacity(0.65)
                                                : (colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)),
                                            lineWidth: isSelected ? 1.4 : 0.8
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                // Manuel Sağlayıcı Girişi (Hızlı Şablonlar + İsim + Yüzde Kaydırıcısı)
                VStack(alignment: .leading, spacing: 10) {
                    Text("HIZLI ŞABLONLAR")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .kerning(0.7)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        ForEach(Self.manualPresets) { preset in
                            let isSelected = providerName.lowercased() == preset.name.lowercased()
                            Button {
                                applyTemplate(preset)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: 10, weight: .semibold))
                                    Text(preset.name)
                                        .font(.system(size: 11, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(
                                            isSelected
                                                ? Color.accentColor.opacity(0.18)
                                                : StudioPalette.recessedWell(for: colorScheme)
                                        )
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            isSelected ? Color.accentColor : Color.secondary.opacity(0.2),
                                            lineWidth: 0.8
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sağlayıcı Adı")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Örn. Cursor, Copilot, DeepSeek", text: $providerName)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Plan / Açıklama (İsteğe Bağlı)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Örn. Pro Plan", text: $subtitle)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Mevcut Kullanım Yüzdesi")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("%\(Int(usedPercentage.rounded()))")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(StudioPalette.progressiveColor(for: usedPercentage / 100.0))
                        }
                        Slider(value: $usedPercentage, in: 0...100, step: 1)
                    }
                }
            }

            // 2. Kota Yenilenme Periyodu (Sadece 4 net seçenek)
            VStack(alignment: .leading, spacing: 6) {
                Text("YENİLENME PERİYODU")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(.secondary)

                Picker("Periyot", selection: $windowType) {
                    ForEach(Self.simpleWindows) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Divider()

            // Alt Çubuk: Aktif Anahtarı + İptal / Kaydet
            HStack {
                Toggle("Menü Çubuğu ve Widget'ta Göster", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5, weight: .medium))

                Spacer()

                Button("İptal") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(existingSubscription == nil ? "Sağlayıcıyı Ekle" : "Kaydet") {
                    save()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(StudioPalette.windowCanvas(for: colorScheme))
    }

    private func applyTemplate(_ template: QuickTemplate) {
        providerKey = template.key
        providerName = template.name
        subtitle = template.subtitle
        iconName = template.icon
        windowType = template.window
    }

    private func save() {
        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedKey = dataSource == .localAuto
            ? providerKey.rawValue
            : AISubscription.inferProviderKey(from: trimmedName)

        let item = AISubscription(
            id: existingSubscription?.id ?? UUID(),
            providerKey: resolvedKey,
            providerName: trimmedName,
            subtitle: trimmedSubtitle.isEmpty ? windowType.displayName : trimmedSubtitle,
            iconName: iconName,
            windowType: windowType,
            usedAmount: dataSource == .localAuto ? (existingSubscription?.usedAmount ?? 0) : usedPercentage.rounded(),
            totalLimit: 100,
            unitLabel: "%",
            resetsAt: existingSubscription?.resetsAt,
            resetDescription: windowType.displayName,
            dataSource: dataSource,
            isEnabled: isEnabled,
            sortOrder: existingSubscription?.sortOrder ?? 0,
            lastUpdated: Date()
        )
        onSave(item)
        dismiss()
    }
}
