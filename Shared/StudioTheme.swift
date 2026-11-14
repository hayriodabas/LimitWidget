import SwiftUI

// MARK: - App Theme Mode SwiftUI Extension

extension AppThemeMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Studio Palette & Brand Identity

/// Profesyonel masaüstü yardımcı uygulaması (iStat / Raycast / Linear tarzı) renk ve yüzey sistemi.
enum StudioPalette {
    // Durum (Severity) Renkleri — Çiğ sistem renkleri yerine kalibre edilmiş stüdyo tonları
    static let normalStart = Color(red: 0.06, green: 0.73, blue: 0.51)   // #10B981
    static let normalEnd   = Color(red: 0.20, green: 0.83, blue: 0.60)   // #34D399

    static let warningStart = Color(red: 0.96, green: 0.62, blue: 0.04)  // #F59E0B
    static let warningEnd   = Color(red: 0.98, green: 0.75, blue: 0.14)  // #FBBF24

    static let criticalStart = Color(red: 0.96, green: 0.25, blue: 0.37) // #F43F5E
    static let criticalEnd   = Color(red: 0.98, green: 0.44, blue: 0.52) // #FB7185

    static func statusColor(for severity: UsageSeverity) -> Color {
        switch severity {
        case .normal: return normalEnd
        case .warning: return warningEnd
        case .critical: return criticalStart
        }
    }

    static func statusGradient(for severity: UsageSeverity) -> LinearGradient {
        switch severity {
        case .normal:
            return LinearGradient(
                colors: [normalStart, normalEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .warning:
            return LinearGradient(
                colors: [warningStart, warningEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .critical:
            return LinearGradient(
                colors: [criticalStart, criticalEnd],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    // Yüzey Tokenları
    static func windowCanvas(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.063, blue: 0.082) // #0E1015
            : Color(red: 0.955, green: 0.961, blue: 0.973) // #F4F5F8
    }

    static func elevatedHeader(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.086, blue: 0.112) // #13161C
            : Color(red: 0.980, green: 0.984, blue: 0.992)
    }

    static func cardFill(for scheme: ColorScheme, isHovered: Bool = false) -> LinearGradient {
        if scheme == .dark {
            let top = isHovered
                ? Color(red: 0.125, green: 0.142, blue: 0.184)
                : Color(red: 0.102, green: 0.116, blue: 0.150)
            let bottom = isHovered
                ? Color(red: 0.098, green: 0.112, blue: 0.146)
                : Color(red: 0.078, green: 0.090, blue: 0.118)
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        } else {
            let top = isHovered
                ? Color.white
                : Color(red: 0.995, green: 0.996, blue: 1.0)
            let bottom = isHovered
                ? Color(red: 0.975, green: 0.980, blue: 0.990)
                : Color(red: 0.985, green: 0.988, blue: 0.995)
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
    }

    static func cardBorder(for scheme: ColorScheme, accent: Color? = nil, isHovered: Bool = false) -> LinearGradient {
        if let accent, isHovered {
            return LinearGradient(
                colors: [accent.opacity(0.45), accent.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if scheme == .dark {
            return LinearGradient(
                colors: [
                    Color.white.opacity(isHovered ? 0.18 : 0.12),
                    Color.white.opacity(isHovered ? 0.06 : 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            return LinearGradient(
                colors: [
                    Color.black.opacity(isHovered ? 0.13 : 0.08),
                    Color.black.opacity(isHovered ? 0.08 : 0.04)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    static func recessedWell(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.047, green: 0.055, blue: 0.072) // #0C0E12
            : Color(red: 0.925, green: 0.935, blue: 0.953) // #ECEFF3
    }

    static func meterTrack(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.038, green: 0.044, blue: 0.058)
            : Color(red: 0.890, green: 0.904, blue: 0.928)
    }
}

/// Her yapay zeka sağlayıcısının kendine özgü marka kimliği ve vektör amblemi.
struct ProviderBrand: Sendable {
    let primary: Color
    let secondary: Color
    let badgeCode: String
    let tierTag: String

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func resolve(for subscription: AISubscription) -> ProviderBrand {
        let key = subscription.providerKey == LocalProviderKey.custom.rawValue
            ? AISubscription.inferProviderKey(from: subscription.providerName)
            : subscription.providerKey

        switch key {
        case LocalProviderKey.claudeCode.rawValue:
            return ProviderBrand(
                primary: Color(red: 0.85, green: 0.47, blue: 0.34),   // #D97757 Anthropic Terracotta
                secondary: Color(red: 0.93, green: 0.62, blue: 0.46), // #ED9E75
                badgeCode: "CC",
                tierTag: "ANTHROPIC"
            )
        case LocalProviderKey.antigravity.rawValue:
            return ProviderBrand(
                primary: Color(red: 0.39, green: 0.40, blue: 0.95),   // #6366F1 Deep Indigo
                secondary: Color(red: 0.22, green: 0.74, blue: 0.97), // #38BDF8 Sky Cyan
                badgeCode: "AG",
                tierTag: "GOOGLE CLOUD"
            )
        case LocalProviderKey.codex.rawValue:
            return ProviderBrand(
                primary: Color(red: 0.06, green: 0.64, blue: 0.50),   // #10A37F OpenAI Emerald
                secondary: Color(red: 0.20, green: 0.83, blue: 0.69), // #34D3B0
                badgeCode: "CX",
                tierTag: "OPENAI"
            )
        case LocalProviderKey.opencode.rawValue:
            return ProviderBrand(
                primary: Color(red: 0.96, green: 0.62, blue: 0.04),   // #F59E0B Cyber Amber
                secondary: Color(red: 0.99, green: 0.78, blue: 0.22), // #FCC738
                badgeCode: "OC",
                tierTag: "OPENCODE GO"
            )
        default:
            return ProviderBrand(
                primary: Color(red: 0.45, green: 0.52, blue: 0.64),
                secondary: Color(red: 0.60, green: 0.67, blue: 0.78),
                badgeCode: String(subscription.providerName.prefix(2)).uppercased(),
                tierTag: "CUSTOM"
            )
        }
    }
}

// MARK: - Bespoke Vector Provider Emblem

/// Standart SF Symbol kutusu yerine her sağlayıcıya özel çizilen vektör stüdyo rozeti.
struct ProviderBrandBadge: View {
    let subscription: AISubscription
    var size: CGFloat = 32

    private var brand: ProviderBrand {
        ProviderBrand.resolve(for: subscription)
    }

    private var effectiveKey: String {
        subscription.providerKey == LocalProviderKey.custom.rawValue
            ? AISubscription.inferProviderKey(from: subscription.providerName)
            : subscription.providerKey
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            brand.primary.opacity(0.24),
                            brand.secondary.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            brand.secondary.opacity(0.55),
                            brand.primary.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )

            vectorGlyph
                .frame(width: size * 0.54, height: size * 0.54)
        }
        .frame(width: size, height: size)
        .shadow(color: brand.primary.opacity(0.18), radius: 4, x: 0, y: 2)
    }

    @ViewBuilder
    private var vectorGlyph: some View {
        switch effectiveKey {
        case LocalProviderKey.claudeCode.rawValue:
            ClaudeSunburstGlyph(gradient: brand.gradient)
        case LocalProviderKey.antigravity.rawValue:
            AntigravityOrbitalGlyph(gradient: brand.gradient)
        case LocalProviderKey.codex.rawValue:
            CodexPromptGlyph(gradient: brand.gradient)
        case LocalProviderKey.opencode.rawValue:
            OpenCodeBracketGlyph(gradient: brand.gradient)
        default:
            Image(systemName: subscription.iconName)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(brand.gradient)
        }
    }
}

/// Claude Code için özel 8-ışınlı geometrik yıldız amblemi.
private struct ClaudeSunburstGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerR = min(size.width, size.height) * 0.48
            let innerR = outerR * 0.24
            let rayCount = 8

            for i in 0..<rayCount {
                let angle = Double(i) * (.pi / Double(rayCount / 2)) - (.pi / 8)
                var path = Path()
                let p1 = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * innerR,
                    y: center.y + CGFloat(sin(angle)) * innerR
                )
                let p2 = CGPoint(
                    x: center.x + CGFloat(cos(angle)) * outerR,
                    y: center.y + CGFloat(sin(angle)) * outerR
                )
                path.move(to: p1)
                path.addLine(to: p2)
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.95, green: 0.66, blue: 0.50),
                            Color(red: 0.85, green: 0.47, blue: 0.34)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ),
                    style: StrokeStyle(lineWidth: max(size.width * 0.13, 1.6), lineCap: .round)
                )
            }

            let coreRect = CGRect(
                x: center.x - innerR * 0.75,
                y: center.y - innerR * 0.75,
                width: innerR * 1.5,
                height: innerR * 1.5
            )
            context.fill(
                Path(ellipseIn: coreRect),
                with: .color(Color(red: 0.93, green: 0.62, blue: 0.46))
            )
        }
    }
}

/// Antigravity için özel yörünge halkası ve çekirdek amblemi.
private struct AntigravityOrbitalGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(gradient, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(-28))

            Ellipse()
                .stroke(gradient.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: 16, height: 8)
                .rotationEffect(.degrees(32))

            Circle()
                .fill(gradient)
                .frame(width: 4.5, height: 4.5)
        }
    }
}

/// Codex için özel terminal chevron `>_` amblemi.
private struct CodexPromptGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var chevron = Path()
            chevron.move(to: CGPoint(x: w * 0.14, y: h * 0.24))
            chevron.addLine(to: CGPoint(x: w * 0.48, y: h * 0.50))
            chevron.addLine(to: CGPoint(x: w * 0.14, y: h * 0.76))

            var underscore = Path()
            underscore.move(to: CGPoint(x: w * 0.54, y: h * 0.76))
            underscore.addLine(to: CGPoint(x: w * 0.88, y: h * 0.76))

            let stroke = StrokeStyle(lineWidth: max(w * 0.14, 1.7), lineCap: .round, lineJoin: .round)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    Color(red: 0.20, green: 0.86, blue: 0.70),
                    Color(red: 0.06, green: 0.64, blue: 0.50)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: w, y: h)
            )
            context.stroke(chevron, with: shading, style: stroke)
            context.stroke(underscore, with: shading, style: stroke)
        }
    }
}

/// OpenCode için özel `< / >` geometrik kod amblemi.
private struct OpenCodeBracketGlyph: View {
    let gradient: LinearGradient

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            var left = Path()
            left.move(to: CGPoint(x: w * 0.30, y: h * 0.26))
            left.addLine(to: CGPoint(x: w * 0.08, y: h * 0.50))
            left.addLine(to: CGPoint(x: w * 0.30, y: h * 0.74))

            var right = Path()
            right.move(to: CGPoint(x: w * 0.70, y: h * 0.26))
            right.addLine(to: CGPoint(x: w * 0.92, y: h * 0.50))
            right.addLine(to: CGPoint(x: w * 0.70, y: h * 0.74))

            var slash = Path()
            slash.move(to: CGPoint(x: w * 0.57, y: h * 0.20))
            slash.addLine(to: CGPoint(x: w * 0.43, y: h * 0.80))

            let stroke = StrokeStyle(lineWidth: max(w * 0.12, 1.5), lineCap: .round, lineJoin: .round)
            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    Color(red: 0.99, green: 0.80, blue: 0.24),
                    Color(red: 0.96, green: 0.62, blue: 0.04)
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: w, y: h)
            )
            context.stroke(left, with: shading, style: stroke)
            context.stroke(right, with: shading, style: stroke)
            context.stroke(slash, with: shading, style: stroke)
        }
    }
}

// MARK: - Precision Instrument Meter Bar

/// Stüdyo kalitesinde ölçek çizgili, gömülü kanallı ve ışıklı uç imleçli hassas kota çubuğu.
struct StudioMeterBar: View {
    @Environment(\.colorScheme) private var colorScheme

    let ratio: Double
    let severity: UsageSeverity
    var height: CGFloat = 8
    var showTicks: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let clamped = min(max(ratio, 0.0), 1.0)
            let fillWidth = clamped > 0 ? max(width * clamped, height * 0.85) : 0
            let statusColor = StudioPalette.statusColor(for: severity)

            ZStack(alignment: .leading) {
                // Gömülü kanal (Recessed Track)
                RoundedRectangle(cornerRadius: height * 0.45, style: .continuous)
                    .fill(StudioPalette.meterTrack(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: height * 0.45, style: .continuous)
                            .strokeBorder(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.07)
                                    : Color.black.opacity(0.08),
                                lineWidth: 0.75
                            )
                    )

                // Ölçek Çentikleri (%25, %50, %75 ve %90 kritik eşik çizgisi)
                if showTicks && width > 80 {
                    ForEach([0.25, 0.50, 0.75], id: \.self) { tick in
                        Rectangle()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.06)
                                    : Color.black.opacity(0.06)
                            )
                            .frame(width: 1, height: height - 2)
                            .offset(x: width * tick)
                    }

                    // %90 Kritik eşik işaretçisi
                    Rectangle()
                        .fill(StudioPalette.criticalStart.opacity(colorScheme == .dark ? 0.28 : 0.22))
                        .frame(width: 1, height: height)
                        .offset(x: width * 0.90)
                }

                // Aktif Doluluk Katmanı
                if clamped > 0 {
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: height * 0.45, style: .continuous)
                            .fill(StudioPalette.statusGradient(for: severity))
                            .overlay(
                                // Üst speküler parlama çizgisi
                                RoundedRectangle(cornerRadius: height * 0.45, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.38), Color.clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )
                            )

                        // Sağ uçtaki parlak gösterge çizgisi (Leading-edge specular cap)
                        if fillWidth > 6 {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 1.5, height: max(height - 2.5, 3))
                                .padding(.trailing, 1.5)
                        }
                    }
                    .frame(width: min(fillWidth, width), height: height)
                    .shadow(
                        color: statusColor.opacity(severity == .critical ? 0.42 : 0.22),
                        radius: severity == .critical ? 5 : 3,
                        x: 0,
                        y: 0
                    )
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Studio Pill & Card Modifiers

/// Küçük teknik rozet (Örn. HAFTALIK, 5 SAAT, CANLI).
struct StudioTagPill: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var accent: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .kerning(0.5)
            .foregroundStyle(accent ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        accent != nil
                            ? accent!.opacity(colorScheme == .dark ? 0.14 : 0.10)
                            : StudioPalette.recessedWell(for: colorScheme)
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(
                        accent != nil
                            ? accent!.opacity(0.28)
                            : (colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)),
                        lineWidth: 0.75
                    )
            )
    }
}

/// Parlayan canlı durum noktası.
struct StudioStatusDot: View {
    let color: Color
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.55), radius: 3, x: 0, y: 0)
    }
}

/// Menü çubuğu ikonu için özel mini gösterge kapsülü.
struct StudioMenuBarBadge: View {
    let percentage: Int
    let severity: UsageSeverity

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 11, weight: .semibold))
            Text("%\(percentage)")
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
        }
    }
}
