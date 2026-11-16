import SwiftUI

/// Menü çubuğu paneli ve büyük widget için tek sağlayıcı satırı:
/// simge, ad, yüzde, çubuk ve alt bilgi.
struct ProviderSummaryRow: View {
    let subscription: AISubscription
    var iconSize: CGFloat = 28
    var now: Date = Date()

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            ProviderIcon(subscription: subscription, size: iconSize)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(subscription.providerName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(subscription.percentText)
                        .numericStyle(size: 13)
                        .foregroundStyle(UsageTone.textStyle(for: subscription.severity))
                }

                UsageBar(ratio: subscription.usageRatio, height: 5)

                HStack(spacing: 6) {
                    Text(subscription.metricsSummary ?? subscription.secondaryLine)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 6)

                    if let phrase = subscription.resetPhrase(relativeTo: now) {
                        Label(phrase, systemImage: "arrow.clockwise")
                            .labelStyle(CompactLabelStyle())
                            .lineLimit(1)
                            .fixedSize()
                            .help(subscription.resetSentence(relativeTo: now) ?? "")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Alt kotaları küçük etiket, yüzde ve ince çubukla yan yana gösterir.
struct MetricStrip: View {
    let metrics: [DisplayMetric]
    var barWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 18) {
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(metric.label)
                            .foregroundStyle(metric.isPrimary ? .primary : .secondary)
                            .fontWeight(metric.isPrimary ? .medium : .regular)
                        Text(AISubscription.percentText(metric.percentage))
                            .monospacedDigit()
                            .foregroundStyle(UsageTone.textStyle(forRatio: metric.ratio))
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 11))
                    .lineLimit(1)

                    UsageBar(ratio: metric.ratio, height: 3)
                        .frame(width: barWidth)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Simge ile metin arasında dar boşluk bırakan etiket stili.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .imageScale(.small)
            configuration.title
        }
    }
}
