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
            glassWidgetCanvas
        }
    }

    /// Google Liquid Glass / Buzlu Prizmatik Cam arka plan katmanı.
    private var glassWidgetCanvas: some View {
        ZStack {
            // Masaüstü duvar kağıdını flulaştıran yarı saydam buzlu cam tabanı
            Rectangle()
                .fill(.ultraThinMaterial)

            // Kontrast ve derinlik için çok hafif cam tonu
            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color(red: 0.05, green: 0.07, blue: 0.13).opacity(0.32)
                        : Color.white.opacity(0.24)
                )

            // Sol-üst Google Aura camgöbeği/mavi ışık kırılması
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.76, blue: 0.96).opacity(colorScheme == .dark ? 0.22 : 0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 210
            )

            // Sağ-alt prizmatik indigo/zümrüt ışık yansıması
            RadialGradient(
                colors: [
                    Color(red: 0.42, green: 0.38, blue: 0.98).opacity(colorScheme == .dark ? 0.20 : 0.14),
                    Color(red: 0.06, green: 0.75, blue: 0.52).opacity(colorScheme == .dark ? 0.10 : 0.08),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 230
            )

            // Diyagonal cam yüzey parlaması (Specular Glass Sheen)
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.52),
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.12),
                    Color.white.opacity(colorScheme == .dark ? 0.08 : 0.26)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Dış çerçeve prizmatik cam kenarlığı
            ContainerRelativeShape()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.42 : 0.85),
                            Color(red: 0.35, green: 0.82, blue: 0.98).opacity(0.28),
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
        }
    }

    /// Her sağlayıcı satırını yarı şeffaf, ışığı kıran 3B cam kapsül içinde sarmalar.
    private func glassCard<Content: View>(
        for subscription: AISubscription,
        cornerRadius: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let brand = ProviderBrand.resolve(for: subscription)
        let tipColor = StudioPalette.progressiveColor(for: subscription.usageRatio)

        return content()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.14 : 0.62),
                                    Color.white.opacity(colorScheme == .dark ? 0.05 : 0.30)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    // Sağlayıcı renginde hafif iç cam kırılması
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    brand.primary.opacity(colorScheme == .dark ? 0.12 : 0.09),
                                    tipColor.opacity(colorScheme == .dark ? 0.08 : 0.06),
                                    Color.clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.38 : 0.82),
                                brand.secondary.opacity(colorScheme == .dark ? 0.30 : 0.25),
                                Color.white.opacity(colorScheme == .dark ? 0.07 : 0.24)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.06),
                radius: 5,
                x: 0,
                y: 2
            )
    }

    private var smallLayout: some View {
        let items = Array(entry.subscriptions.prefix(3))
        return VStack(alignment: .leading, spacing: 7) {
            widgetHeader(title: "LIMITWIDGET", shownCount: items.count)

            if items.isEmpty {
                emptyState
            } else {
                ForEach(items) { subscription in
                    glassCard(for: subscription, cornerRadius: 9) {
                        SubscriptionProgressRow(subscription: subscription, style: .widgetSmall)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 5)
                    }
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
                        glassCard(for: subscription, cornerRadius: 10) {
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
                        }
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
                        glassCard(for: subscription, cornerRadius: 11) {
                            SubscriptionProgressRow(subscription: subscription, style: .widgetRegular)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                        }
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
        let peakColor = StudioPalette.progressiveColor(for: Double(peak) / 100.0)

        return HStack(spacing: 6) {
            StudioStatusDot(color: peakColor, size: 6)

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
                    .foregroundStyle(peakColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.45))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.25 : 0.65), lineWidth: 0.75)
                    )
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
