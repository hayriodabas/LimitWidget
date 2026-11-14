import SwiftUI

/// Tek bir aboneliğin limit doluluğunu stüdyo kalitesinde enstrüman çubuğu ve alt telemetri hücreleriyle gösterir.
struct SubscriptionProgressRow: View {
    enum Style {
        case compact
        case detailed
        case widgetSmall
        case widgetRegular
    }

    @Environment(\.colorScheme) private var colorScheme

    let subscription: AISubscription
    var style: Style = .compact

    private var brand: ProviderBrand {
        ProviderBrand.resolve(for: subscription)
    }

    private var statusColor: Color {
        StudioPalette.progressiveColor(for: subscription.usageRatio)
    }

    var body: some View {
        switch style {
        case .widgetSmall:
            smallWidgetBody
        case .widgetRegular:
            regularWidgetBody
        case .compact:
            compactBody
        case .detailed:
            detailedBody
        }
    }

    // MARK: - Detailed Studio Row (Main Window)

    private var detailedBody: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 12) {
                ProviderBrandBadge(subscription: subscription, size: 38)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(subscription.providerName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        StudioTagPill(text: brand.tierTag, accent: brand.primary)
                        StudioTagPill(text: subscription.windowType.displayName)

                        if subscription.dataSource != .localAuto {
                            StudioTagPill(text: subscription.dataSource.displayName)
                        }
                    }

                    Text(subscription.compactSummaryText)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        StudioStatusDot(color: statusColor, size: 6.5)
                        Text("%\(subscription.usagePercentage)")
                            .font(.system(size: 21, weight: .bold, design: .monospaced))
                            .foregroundStyle(statusColor)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(subscription.formattedResetCountdown())
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(StudioPalette.recessedWell(for: colorScheme))
                    )
                }
            }

            StudioMeterBar(
                ratio: subscription.usageRatio,
                severity: subscription.severity,
                height: 9,
                showTicks: true
            )

            if !subscription.subQuotaMetrics.isEmpty {
                subQuotaTelemetryGrid(metrics: subscription.subQuotaMetrics, isCompact: false)
            }
        }
    }

    // MARK: - Compact Studio Row (Menu Bar Popover)

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 9) {
                ProviderBrandBadge(subscription: subscription, size: 28)

                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text(subscription.providerName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        StudioTagPill(text: subscription.windowType.shortLabel, accent: brand.primary)
                    }

                    if subscription.subQuotaMetrics.isEmpty {
                        Text(subscription.compactSummaryText)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 6)

                HStack(spacing: 3.5) {
                    Image(systemName: "clock")
                        .font(.system(size: 9, weight: .semibold))
                    Text(subscription.formattedResetCountdown())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(
                    Capsule(style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )

                HStack(spacing: 5) {
                    StudioStatusDot(color: statusColor, size: 5.5)
                    Text("%\(subscription.usagePercentage)")
                        .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(statusColor)
                }
            }

            StudioMeterBar(
                ratio: subscription.usageRatio,
                severity: subscription.severity,
                height: 7,
                showTicks: true
            )

            if !subscription.subQuotaMetrics.isEmpty {
                subQuotaTelemetryGrid(metrics: subscription.subQuotaMetrics, isCompact: true)
            }
        }
    }

    // MARK: - Widget Rows

    private var regularWidgetBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                ProviderBrandBadge(subscription: subscription, size: 20)

                Text(subscription.providerName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text(subscription.formattedResetCountdown())
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("%\(subscription.usagePercentage)")
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            StudioMeterBar(
                ratio: subscription.usageRatio,
                severity: subscription.severity,
                height: 6,
                showTicks: false
            )

            Text(subscription.compactSummaryText)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var smallWidgetBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ProviderBrandBadge(subscription: subscription, size: 17)

                Text(subscription.providerName)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer(minLength: 3)

                Text("%\(subscription.usagePercentage)")
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(statusColor)
            }

            StudioMeterBar(
                ratio: subscription.usageRatio,
                severity: subscription.severity,
                height: 5,
                showTicks: false
            )
        }
    }

    // MARK: - Sub-Quota Telemetry Modules

    private func subQuotaTelemetryGrid(metrics: [SubQuotaMetric], isCompact: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(metrics.enumerated()), id: \.offset) { _, metric in
                let metricColor = StudioPalette.progressiveColor(for: metric.ratio)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(metric.label.uppercased())
                            .font(.system(size: isCompact ? 9 : 9.5, weight: .semibold, design: .rounded))
                            .kerning(0.4)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        StudioStatusDot(color: metricColor, size: 4)

                        Text("%\(metric.percentage)")
                            .font(.system(size: isCompact ? 10 : 10.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(metricColor)
                    }

                    StudioMeterBar(
                        ratio: metric.ratio,
                        severity: metric.severity,
                        height: isCompact ? 3.5 : 4,
                        showTicks: false
                    )
                }
                .padding(.horizontal, isCompact ? 7 : 9)
                .padding(.vertical, isCompact ? 5 : 6)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(StudioPalette.recessedWell(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark
                                ? Color.white.opacity(0.05)
                                : Color.black.opacity(0.05),
                            lineWidth: 0.75
                        )
                )
            }
        }
    }
}

/// Geriye dönük uyumluluk için LimitProgressBar sarmalayıcısı.
struct LimitProgressBar: View {
    let ratio: Double
    let tint: Color
    var height: CGFloat = 7

    private var inferredSeverity: UsageSeverity {
        if ratio >= 0.90 { return .critical }
        if ratio >= 0.70 { return .warning }
        return .normal
    }

    var body: some View {
        StudioMeterBar(ratio: ratio, severity: inferredSeverity, height: height, showTicks: false)
    }
}
