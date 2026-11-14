import AppKit
import SwiftUI

/// Menü çubuğuna tıklandığında veya üzerine gelindiğinde açılan stüdyo sınıfı telemetri paneli.
struct MenuBarPopoverView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: SubscriptionStore
    var onPopoverHoverChange: ((Bool) -> Void)? = nil
    var onOpenMainWindow: (() -> Void)? = nil
    @State private var sortByUsage = false
    @State private var hoveredID: UUID?

    private var displayedSubscriptions: [AISubscription] {
        let items = store.activeSubscriptions
        if sortByUsage {
            return items.sorted { $0.usageRatio > $1.usageRatio }
        }
        return items
    }

    private var highestSeverity: UsageSeverity {
        if store.criticalCount > 0 { return .critical }
        if store.warningCount > 0 { return .warning }
        return .normal
    }

    var body: some View {
        VStack(spacing: 0) {
            studioHeader
            hairlineDivider
            contentArea
            hairlineDivider
            studioFooter
        }
        .frame(width: 392)
        .fixedSize(horizontal: false, vertical: true)
        .background(StudioPalette.windowCanvas(for: colorScheme))
        .preferredColorScheme(store.themeMode.preferredColorScheme)
        .onHover { hovering in
            onPopoverHoverChange?(hovering)
        }
    }

    // MARK: - Header

    private var studioHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                StudioPalette.statusColor(for: highestSeverity).opacity(0.22),
                                StudioPalette.statusColor(for: highestSeverity).opacity(0.06)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                StudioPalette.statusColor(for: highestSeverity).opacity(0.40),
                                lineWidth: 1
                            )
                    )

                Image(systemName: "slider.horizontal.below.square.and.square.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioPalette.statusColor(for: highestSeverity))
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("LIMITWIDGET")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .kerning(0.9)
                        .foregroundStyle(.primary)

                    StudioTagPill(
                        text: store.isSyncing ? "ÖLÇÜLÜYOR" : "CANLI",
                        accent: StudioPalette.statusColor(for: highestSeverity)
                    )
                }

                Text("\(store.activeSubscriptions.count) aktif sağlayıcı • Ortalama %\(store.averageUsagePercentage) • Tavan %\(store.highestUsagePercentage)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                studioIconButton(
                    symbol: store.themeMode.iconName,
                    isActive: store.themeMode != .system,
                    tooltip: "Tema: \(store.themeMode.displayName) (Değiştirmek için tıkla)"
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        store.cycleThemeMode()
                    }
                }

                studioIconButton(
                    symbol: sortByUsage ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down",
                    isActive: sortByUsage,
                    tooltip: sortByUsage ? "Özel sıraya dön" : "Doluluğa göre sırala"
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        sortByUsage.toggle()
                    }
                }

                Button {
                    Task { await store.syncLocalUsageAsync() }
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(StudioPalette.recessedWell(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07),
                                        lineWidth: 0.75
                                    )
                            )

                        if store.isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(store.isSyncing)
                .keyboardShortcut("r", modifiers: .command)
                .help("Canlı kotaları şimdi yenile (⌘R)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(StudioPalette.elevatedHeader(for: colorScheme))
    }

    // MARK: - Content

    @ViewBuilder
    private var contentArea: some View {
        if displayedSubscriptions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "waveform.path.ecg.rectangle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Aktif sağlayıcı bulunmuyor")
                    .font(.system(size: 12.5, weight: .semibold))

                Button {
                    openMainWindow()
                } label: {
                    Text("Sağlayıcı Yapılandır")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 34)
        } else {
            VStack(spacing: 8) {
                ForEach(displayedSubscriptions) { subscription in
                    let isHovered = hoveredID == subscription.id
                    let brand = ProviderBrand.resolve(for: subscription)

                    SubscriptionProgressRow(subscription: subscription, style: .compact)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(StudioPalette.cardFill(for: colorScheme, isHovered: isHovered))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(
                                    StudioPalette.cardBorder(
                                        for: colorScheme,
                                        accent: brand.primary,
                                        isHovered: isHovered
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.14)) {
                                hoveredID = hovering ? subscription.id : nil
                            }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var studioFooter: some View {
        HStack(spacing: 8) {
            StudioStatusDot(
                color: store.isSyncing ? StudioPalette.warningEnd : StudioPalette.normalEnd,
                size: 5
            )

            Text("SENKRON \(store.lastRefreshedAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .kerning(0.4)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                openMainWindow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Stüdyo Paneli")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08),
                            lineWidth: 0.75
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(StudioPalette.recessedWell(for: colorScheme))
                    )
            }
            .buttonStyle(.plain)
            .help("LimitWidget'tan Çık")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(StudioPalette.elevatedHeader(for: colorScheme))
    }

    private var hairlineDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
            .frame(height: 1)
    }

    private func studioIconButton(
        symbol: String,
        isActive: Bool,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            isActive
                                ? Color.accentColor.opacity(0.45)
                                : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)),
                            lineWidth: 0.75
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func openMainWindow() {
        onOpenMainWindow?()
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
