import SwiftUI
import WidgetKit

/// Masaüstü widget zaman çizelgesi girdisi.
struct LimitWidgetEntry: TimelineEntry {
    let date: Date
    let subscriptions: [AISubscription]
}

/// Abonelik dosyasından widget zaman çizelgesi üretir.
struct LimitTimelineProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> LimitWidgetEntry {
        LimitWidgetEntry(date: Date(), subscriptions: Self.sampleSubscriptions())
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (LimitWidgetEntry) -> Void) {
        if context.isPreview {
            completion(LimitWidgetEntry(date: Date(), subscriptions: Self.sampleSubscriptions()))
            return
        }
        completion(LimitWidgetEntry(date: Date(), subscriptions: loadActiveSubscriptions()))
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<LimitWidgetEntry>) -> Void) {
        let now = Date()
        let items = loadActiveSubscriptions(now: now)
        // Geri sayımlar güncel kalsın diye önümüzdeki bir saat için 15 dakikalık girdiler üret.
        let entries = (0..<4).map { step in
            LimitWidgetEntry(date: now.addingTimeInterval(TimeInterval(step) * 900), subscriptions: items)
        }
        let nextRefresh = now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(nextRefresh)))
    }

    nonisolated private func loadActiveSubscriptions(now: Date = Date()) -> [AISubscription] {
        SubscriptionRepository()
            .loadOrSeed(now: now)
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Widget galerisinde gösterilen örnek değerler.
    nonisolated static func sampleSubscriptions(now: Date = Date()) -> [AISubscription] {
        let samples: [(Double, String, TimeInterval)] = [
            (53, "5sa: %12 • Haftalık: %53", 2 * 86_400 + 4 * 3600),
            (34, "Gemini: %34 • Claude/GPT: %18", 3 * 3600 + 20 * 60),
            (86, "5sa: %41 • Haftalık: %86 (Plus)", 26 * 3600),
            (22, "5sa: %3 • Hft: %9 • Ay: %22", 12 * 86_400)
        ]
        return AISubscription.makeDefaultSubscriptions(now: now).enumerated().map { index, item in
            var copy = item
            copy.usedAmount = samples[index].0
            copy.subtitle = samples[index].1
            copy.resetsAt = now.addingTimeInterval(samples[index].2)
            return copy
        }
    }
}

/// Masaüstü widget görünümü: Pil widget'ı düzeninde halkalar ve satırlar.
struct LimitDesktopWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LimitWidgetEntry

    var body: some View {
        Group {
            if entry.subscriptions.isEmpty {
                emptyState
            } else {
                switch family {
                case .systemSmall:
                    SmallRingsLayout(items: Array(entry.subscriptions.prefix(4)))
                case .systemLarge:
                    LargeListLayout(entry: entry)
                default:
                    MediumRingsLayout(items: Array(entry.subscriptions.prefix(4)))
                }
            }
        }
        .containerBackground(.background, for: .widget)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("Sağlayıcı yok")
                .font(.system(size: 12, weight: .semibold))
            Text("LimitWidget'tan ekleyin")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ring cell

/// Ortasında sağlayıcı işareti olan kullanım halkası.
private struct ProviderRingCell: View {
    let subscription: AISubscription
    var lineWidth: CGFloat = 5.5
    var showsName: Bool = false

    var body: some View {
        let brand = ProviderBrand.resolve(for: subscription)
        VStack(spacing: 5) {
            UsageRing(ratio: subscription.usageRatio, lineWidth: lineWidth) {
                GeometryReader { proxy in
                    ProviderGlyph(key: subscription.effectiveProviderKey, fallbackSymbol: subscription.iconName)
                        .foregroundStyle(brand.glyphStyle)
                        .frame(width: proxy.size.width * 0.42, height: proxy.size.width * 0.42)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Text(subscription.percentText)
                .numericStyle(size: 12.5)
                .foregroundStyle(.primary)

            if showsName {
                Text(subscription.providerName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(subscription.providerName) \(subscription.percentText)")
    }
}

// MARK: - Small

private struct SmallRingsLayout: View {
    let items: [AISubscription]

    var body: some View {
        if items.count == 1, let item = items.first {
            VStack(spacing: 8) {
                ProviderRingCell(subscription: item, lineWidth: 9)
                    .frame(maxHeight: .infinity)
                Text(item.resetPhrase().map { "\($0) sonra yenilenir" } ?? item.providerName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            GeometryReader { proxy in
                // İki satır halka + yüzde etiketi kutuya sığacak şekilde halka çapını hesapla.
                let labelHeight: CGFloat = 20
                let rowSpacing: CGFloat = 8
                let byHeight = (proxy.size.height - rowSpacing - labelHeight * 2) / 2
                let byWidth = (proxy.size.width - 16) / 2
                let ring = max(min(byHeight, byWidth), 24)
                let columns = [
                    GridItem(.fixed(ring), spacing: 16),
                    GridItem(.fixed(ring), spacing: 16)
                ]
                LazyVGrid(columns: columns, spacing: rowSpacing) {
                    ForEach(items) { item in
                        ProviderRingCell(subscription: item, lineWidth: 4.5)
                            .frame(width: ring)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

// MARK: - Medium

private struct MediumRingsLayout: View {
    let items: [AISubscription]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ForEach(items) { item in
                ProviderRingCell(subscription: item, lineWidth: 6, showsName: true)
                    .frame(maxWidth: 72)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large

private struct LargeListLayout: View {
    let entry: LimitWidgetEntry

    var body: some View {
        let items = Array(entry.subscriptions.prefix(5))
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LimitWidget")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if let peak = entry.subscriptions.max(by: { $0.usageRatio < $1.usageRatio }) {
                    Text("En yüksek \(peak.percentText)")
                        .numericStyle(size: 11.5, weight: .medium)
                        .foregroundStyle(UsageTone.color(for: peak.severity))
                }
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ProviderSummaryRow(subscription: item, iconSize: 30, now: entry.date)
                        .padding(.vertical, 11)
                    if index < items.count - 1 {
                        Divider()
                            .padding(.leading, 41)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

/// macOS masaüstü widget'ı.
@main
struct LimitDesktopWidget: Widget {
    let kind: String = "LimitDesktopWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LimitTimelineProvider()) { entry in
            LimitDesktopWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Kotalar")
        .description("Yapay zekâ aboneliklerinizin kalan kotasını bir bakışta görün.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
