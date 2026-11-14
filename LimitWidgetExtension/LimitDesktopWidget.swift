import SwiftUI
import WidgetKit

/// Masaüstü WidgetKit zaman çizelgesi girdisi.
struct LimitWidgetEntry: TimelineEntry {
    let date: Date
    let subscriptions: [AISubscription]
    let themeMode: AppThemeMode
}

/// Abonelik deposundan widget zaman çizelgesi üreten sağlayıcı.
struct LimitTimelineProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> LimitWidgetEntry {
        LimitWidgetEntry(
            date: Date(),
            subscriptions: AISubscription.makeDefaultSubscriptions(),
            themeMode: .system
        )
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (LimitWidgetEntry) -> Void) {
        let repo = SubscriptionRepository()
        let items = loadActiveSubscriptions(from: repo)
        completion(LimitWidgetEntry(date: Date(), subscriptions: items, themeMode: repo.loadThemeMode()))
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<LimitWidgetEntry>) -> Void) {
        let now = Date()
        let repo = SubscriptionRepository()
        let items = loadActiveSubscriptions(from: repo, now: now)
        let entry = LimitWidgetEntry(date: now, subscriptions: items, themeMode: repo.loadThemeMode())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: now) ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    nonisolated private func loadActiveSubscriptions(
        from repo: SubscriptionRepository = SubscriptionRepository(),
        now: Date = Date()
    ) -> [AISubscription] {
        repo
            .loadOrSeed(now: now)
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

/// Masaüstü widget görünümü; küçük, orta ve büyük boyutlara stüdyo estetiğiyle uyum sağlar.
struct LimitDesktopWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var systemColorScheme
    let entry: LimitWidgetEntry

    private var colorScheme: ColorScheme {
        entry.themeMode.preferredColorScheme ?? systemColorScheme
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .environment(\.colorScheme, colorScheme)
        .containerBackground(for: .widget) {
            StudioPalette.windowCanvas(for: colorScheme)
        }
    }

    private var smallLayout: some View {
        let items = Array(entry.subscriptions.prefix(3))
        return VStack(alignment: .leading, spacing: 7) {
            widgetHeader(title: "LIMITWIDGET", shownCount: items.count)

            if items.isEmpty {
                emptyState
            } else {
                ForEach(items) { subscription in
                    SubscriptionProgressRow(subscription: subscription, style: .widgetSmall)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(StudioPalette.recessedWell(for: colorScheme))
                        )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumLayout: some View {
        let items = Array(entry.subscriptions.prefix(4))
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            widgetHeader(title: "LIMITWIDGET TELEMETRİ", shownCount: items.count)

            if items.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(items) { subscription in
                        VStack(alignment: .leading, spacing: 4) {
                            SubscriptionProgressRow(subscription: subscription, style: .widgetSmall)

                            HStack(spacing: 4) {
                                Text(subscription.compactSummaryText)
                                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer(minLength: 2)

                                Text(subscription.formattedResetCountdown())
                                    .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(StudioPalette.recessedWell(for: colorScheme))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(
                                    colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06),
                                    lineWidth: 0.75
                                )
                        )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeLayout: some View {
        let items = Array(entry.subscriptions.prefix(4))
        return VStack(alignment: .leading, spacing: 8) {
            widgetHeader(title: "LIMITWIDGET TELEMETRİ", shownCount: items.count)

            if items.isEmpty {
                emptyState
            } else {
                VStack(spacing: 7) {
                    ForEach(items) { subscription in
                        SubscriptionProgressRow(subscription: subscription, style: .widgetRegular)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(StudioPalette.recessedWell(for: colorScheme))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06),
                                        lineWidth: 0.75
                                    )
                            )
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func widgetHeader(title: String, shownCount: Int) -> some View {
        let remaining = max(entry.subscriptions.count - shownCount, 0)
        let peak = entry.subscriptions.map(\.usagePercentage).max() ?? 0
        let peakSeverity: UsageSeverity = peak >= 90 ? .critical : (peak >= 70 ? .warning : .normal)

        return HStack(spacing: 6) {
            StudioStatusDot(color: StudioPalette.statusColor(for: peakSeverity), size: 5.5)

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(0.8)
                .lineLimit(1)

            Spacer(minLength: 4)

            if remaining > 0 {
                Text("+\(remaining)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                Text("TAVAN %\(peak)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(StudioPalette.statusColor(for: peakSeverity))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aktif sağlayıcı yok")
                .font(.system(size: 11, weight: .semibold))
            Text("LimitWidget üzerinden yapılandırın.")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

/// macOS Masaüstü WidgetKit giriş noktası.
@main
struct LimitDesktopWidget: Widget {
    let kind: String = "LimitDesktopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LimitTimelineProvider()) { entry in
            LimitDesktopWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("LimitWidget Studio")
        .description("Yapay zeka abonelik kotalarını hassas enstrüman çubuklarıyla masaüstünde izleyin.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
