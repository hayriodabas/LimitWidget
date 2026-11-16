import SwiftUI
import WidgetKit

// MARK: - Theme

extension AppThemeMode {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

// MARK: - Usage tone

/// Kullanım seviyesini sistemin anlamsal renkleriyle eşler: rahat yeşil, yaklaşıyor turuncu, kritik kırmızı.
enum UsageTone {
    static func color(for severity: UsageSeverity) -> Color {
        switch severity {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    static func color(forRatio ratio: Double) -> Color {
        color(for: severity(forRatio: ratio))
    }

    /// Rakamlar için: rahatken normal metin rengi, sınıra yaklaşınca uyarı rengi.
    static func textStyle(for severity: UsageSeverity) -> AnyShapeStyle {
        severity == .normal ? AnyShapeStyle(.primary) : AnyShapeStyle(color(for: severity))
    }

    static func textStyle(forRatio ratio: Double) -> AnyShapeStyle {
        textStyle(for: severity(forRatio: ratio))
    }

    static func severity(forRatio ratio: Double) -> UsageSeverity {
        if ratio >= 0.90 { return .critical }
        if ratio >= 0.70 { return .warning }
        return .normal
    }
}

// MARK: - Provider logos

/// Sağlayıcının gerçek logosu (LobeHub Icons koleksiyonundan; markalar sahiplerine aittir).
struct ProviderLogo: Sendable {
    /// Renkli logo görseli; yoksa tek renkli logo `markOnTile` rengiyle boyanır.
    let colorAsset: String?
    /// Tek renkli (şablon) logo; masaüstü tek renk modunda ve renkli görseli olmayanlarda kullanılır.
    let monoAsset: String
    /// Simge karesinin zemin rengi.
    let tile: Color
    /// Tek renkli logonun kare üzerindeki rengi.
    let markOnTile: Color
    /// Logonun kare içindeki boyu (kenar uzunluğuna oran).
    let markScale: CGFloat
    /// Açık renkli zeminlerde ince kenar çizgisi gerekir.
    let isLightTile: Bool

    static func resolve(key: String, name: String) -> ProviderLogo? {
        let lower = name.lowercased()
        switch key {
        case LocalProviderKey.claudeCode.rawValue:
            return ProviderLogo(
                colorAsset: "logo-claudecode",
                monoAsset: "logo-claudecode-mono",
                tile: Color(red: 0.96, green: 0.94, blue: 0.90),
                markOnTile: Color(red: 0.85, green: 0.47, blue: 0.34),
                markScale: 0.70,
                isLightTile: true
            )
        case LocalProviderKey.antigravity.rawValue:
            return ProviderLogo(
                colorAsset: "logo-antigravity",
                monoAsset: "logo-antigravity-mono",
                tile: .white,
                markOnTile: .black,
                markScale: 0.62,
                isLightTile: true
            )
        case LocalProviderKey.codex.rawValue:
            return ProviderLogo(
                colorAsset: "logo-codex",
                monoAsset: "logo-codex-mono",
                tile: .white,
                markOnTile: .black,
                markScale: 0.70,
                isLightTile: true
            )
        case LocalProviderKey.opencode.rawValue:
            return ProviderLogo(
                colorAsset: nil,
                monoAsset: "logo-opencode-mono",
                tile: Color(red: 0.09, green: 0.09, blue: 0.10),
                markOnTile: .white,
                markScale: 0.56,
                isLightTile: false
            )
        default:
            break
        }

        if lower.contains("cursor") {
            return ProviderLogo(
                colorAsset: nil,
                monoAsset: "logo-cursor-mono",
                tile: Color(red: 0.08, green: 0.08, blue: 0.08),
                markOnTile: .white,
                markScale: 0.58,
                isLightTile: false
            )
        }
        if lower.contains("copilot") {
            return ProviderLogo(
                colorAsset: nil,
                monoAsset: "logo-githubcopilot-mono",
                tile: Color(red: 0.14, green: 0.16, blue: 0.18),
                markOnTile: .white,
                markScale: 0.64,
                isLightTile: false
            )
        }
        if lower.contains("windsurf") {
            return ProviderLogo(
                colorAsset: nil,
                monoAsset: "logo-windsurf-mono",
                tile: Color(red: 0.04, green: 0.07, blue: 0.08),
                markOnTile: .white,
                markScale: 0.66,
                isLightTile: false
            )
        }
        if lower.contains("deepseek") {
            return ProviderLogo(
                colorAsset: "logo-deepseek",
                monoAsset: "logo-deepseek-mono",
                tile: .white,
                markOnTile: .black,
                markScale: 0.70,
                isLightTile: true
            )
        }
        return nil
    }
}

// MARK: - Provider brand

/// Sağlayıcının logo, yedek simge rengi ve kısa satıcı adı.
struct ProviderBrand: Sendable {
    let key: String
    let tint: Color
    let highlight: Color
    let vendor: String
    let logo: ProviderLogo?

    /// Nötr zemin üzerinde (halka ortası gibi) yedek işaret rengi.
    var glyphStyle: AnyShapeStyle {
        AnyShapeStyle(tint)
    }

    static func resolve(for subscription: AISubscription) -> ProviderBrand {
        resolve(key: subscription.effectiveProviderKey, name: subscription.providerName)
    }

    static func resolve(key: String, name: String) -> ProviderBrand {
        let logo = ProviderLogo.resolve(key: key, name: name)
        switch key {
        case LocalProviderKey.claudeCode.rawValue:
            return ProviderBrand(
                key: key,
                tint: Color(red: 0.80, green: 0.42, blue: 0.29),
                highlight: Color(red: 0.91, green: 0.56, blue: 0.42),
                vendor: "Anthropic",
                logo: logo
            )
        case LocalProviderKey.antigravity.rawValue:
            return ProviderBrand(
                key: key,
                tint: Color(red: 0.25, green: 0.38, blue: 0.93),
                highlight: Color(red: 0.36, green: 0.58, blue: 1.00),
                vendor: "Google",
                logo: logo
            )
        case LocalProviderKey.codex.rawValue:
            return ProviderBrand(
                key: key,
                tint: Color(red: 0.23, green: 0.30, blue: 1.00),
                highlight: Color(red: 0.48, green: 0.62, blue: 1.00),
                vendor: "OpenAI",
                logo: logo
            )
        case LocalProviderKey.opencode.rawValue:
            return ProviderBrand(
                key: key,
                tint: Color(red: 0.91, green: 0.55, blue: 0.05),
                highlight: Color(red: 0.98, green: 0.72, blue: 0.22),
                vendor: "OpenCode",
                logo: logo
            )
        default:
            return ProviderBrand(
                key: key,
                tint: Color(red: 0.42, green: 0.45, blue: 0.52),
                highlight: Color(red: 0.58, green: 0.61, blue: 0.68),
                vendor: "Özel",
                logo: logo
            )
        }
    }
}

// MARK: - Provider glyph & icon

/// Sağlayıcıya özel, tek renkli çizim. Rengi `foregroundStyle` ile belirlenir.
struct ProviderGlyph: View {
    let key: String
    var fallbackSymbol: String = "sparkles"

    var body: some View {
        switch key {
        case LocalProviderKey.claudeCode.rawValue:
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let outer = min(size.width, size.height) * 0.48
                let inner = outer * 0.16
                var path = Path()
                for index in 0..<8 {
                    let angle = Double(index) * .pi / 4 + .pi / 8
                    path.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                    path.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
                }
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: size.width * 0.15, lineCap: .round))
            }
        case LocalProviderKey.antigravity.rawValue:
            Canvas { context, size in
                let w = size.width
                let h = size.height
                var arch = Path()
                arch.move(to: CGPoint(x: w * 0.12, y: h * 0.86))
                arch.addCurve(
                    to: CGPoint(x: w * 0.88, y: h * 0.86),
                    control1: CGPoint(x: w * 0.30, y: h * -0.10),
                    control2: CGPoint(x: w * 0.70, y: h * -0.10)
                )
                context.stroke(arch, with: .foreground, style: StrokeStyle(lineWidth: w * 0.16, lineCap: .round))
                let dot = CGRect(x: w * 0.40, y: h * 0.50, width: w * 0.20, height: w * 0.20)
                context.fill(Path(ellipseIn: dot), with: .foreground)
            }
        case LocalProviderKey.codex.rawValue:
            Canvas { context, size in
                let w = size.width
                let h = size.height
                var path = Path()
                path.move(to: CGPoint(x: w * 0.14, y: h * 0.24))
                path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.76))
                path.move(to: CGPoint(x: w * 0.56, y: h * 0.78))
                path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.78))
                context.stroke(
                    path,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: w * 0.14, lineCap: .round, lineJoin: .round)
                )
            }
        case LocalProviderKey.opencode.rawValue:
            Canvas { context, size in
                let w = size.width
                let h = size.height
                var path = Path()
                path.move(to: CGPoint(x: w * 0.30, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.06, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.78))
                path.move(to: CGPoint(x: w * 0.70, y: h * 0.22))
                path.addLine(to: CGPoint(x: w * 0.94, y: h * 0.50))
                path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.78))
                path.move(to: CGPoint(x: w * 0.58, y: h * 0.16))
                path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.84))
                context.stroke(
                    path,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: w * 0.12, lineCap: .round, lineJoin: .round)
                )
            }
        default:
            GeometryReader { proxy in
                Image(systemName: fallbackSymbol)
                    .font(.system(size: proxy.size.width * 0.86, weight: .semibold))
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

/// macOS uygulama simgeleri gibi yuvarlatılmış kare içinde sağlayıcının gerçek logosu.
struct ProviderIcon: View {
    let key: String
    let name: String
    var fallbackSymbol: String = "sparkles"
    var size: CGFloat = 32

    init(subscription: AISubscription, size: CGFloat = 32) {
        self.key = subscription.effectiveProviderKey
        self.name = subscription.providerName
        self.fallbackSymbol = subscription.iconName
        self.size = size
    }

    init(key: String, name: String, fallbackSymbol: String = "sparkles", size: CGFloat = 32) {
        self.key = key
        self.name = name
        self.fallbackSymbol = fallbackSymbol
        self.size = size
    }

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let brand = ProviderBrand.resolve(key: key, name: name)
        // macOS simge biçimine yakın, sürekli eğimli köşe.
        let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)

        Group {
            if renderingMode != .fullColor {
                // Masaüstü tek renkli çizildiğinde dolu renkli kare gri bir lekeye dönüşür;
                // bunun yerine hafif zemin üzerinde tek renkli logoyu göster.
                ZStack {
                    shape.fill(.quaternary)
                    ProviderMark(key: key, name: name, fallbackSymbol: fallbackSymbol)
                        .frame(width: size * (brand.logo?.markScale ?? 0.52), height: size * (brand.logo?.markScale ?? 0.52))
                        .widgetAccentable()
                }
            } else if let logo = brand.logo {
                logoTile(logo: logo, shape: shape)
            } else {
                fallbackTile(brand: brand, shape: shape)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(name)
    }

    private func logoTile(logo: ProviderLogo, shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(logo.tile)
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(logo.isLightTile ? 0 : 0.10), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            Group {
                if let asset = logo.colorAsset {
                    Image(asset)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(logo.monoAsset)
                        .renderingMode(.template)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(logo.markOnTile)
                }
            }
            .frame(width: size * logo.markScale, height: size * logo.markScale)

            shape.strokeBorder(
                logo.isLightTile ? Color.black.opacity(0.10) : Color.white.opacity(0.14),
                lineWidth: 0.5
            )
        }
        .shadow(color: .black.opacity(0.12), radius: size * 0.04, y: size * 0.02)
    }

    private func fallbackTile(brand: ProviderBrand, shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(
                LinearGradient(
                    colors: [brand.highlight, brand.tint],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
            ProviderGlyph(key: key, fallbackSymbol: fallbackSymbol)
                .foregroundStyle(.white)
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .shadow(color: .black.opacity(0.14), radius: size * 0.04, y: size * 0.02)
    }
}

/// Zeminsiz sağlayıcı logosu (widget halkasının ortası gibi nötr yüzeyler için).
struct ProviderMark: View {
    let key: String
    let name: String
    var fallbackSymbol: String = "sparkles"

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let brand = ProviderBrand.resolve(key: key, name: name)
        if let logo = brand.logo {
            if renderingMode == .fullColor, let asset = logo.colorAsset {
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(logo.monoAsset)
                    .renderingMode(.template)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        } else {
            ProviderGlyph(key: key, fallbackSymbol: fallbackSymbol)
                .foregroundStyle(renderingMode == .fullColor ? brand.glyphStyle : AnyShapeStyle(.primary))
        }
    }
}

// MARK: - Meters

/// Kapsül biçimli, düz renkli kullanım çubuğu.
struct UsageBar: View {
    let ratio: Double
    var tint: Color? = nil
    var height: CGFloat = 6

    var body: some View {
        let clamped = min(max(ratio, 0), 1)
        let color = tint ?? UsageTone.color(forRatio: clamped)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.quaternary)
                if clamped > 0 {
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: max(proxy.size.width * clamped, height))
                        .widgetAccentable()
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(AISubscription.percentText(Int((clamped * 100).rounded()))))
    }
}

/// Pil widget'ındaki gibi dairesel kullanım halkası.
struct UsageRing<Center: View>: View {
    let ratio: Double
    var lineWidth: CGFloat = 5
    @ViewBuilder var center: () -> Center

    var body: some View {
        let clamped = min(max(ratio, 0), 1)
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(
                    UsageTone.color(forRatio: clamped),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .opacity(clamped > 0 ? 1 : 0)
                .widgetAccentable()
            center()
        }
        .padding(lineWidth / 2)
    }
}

extension UsageRing where Center == EmptyView {
    init(ratio: Double, lineWidth: CGFloat = 5) {
        self.init(ratio: ratio, lineWidth: lineWidth) { EmptyView() }
    }
}

// MARK: - Typography helpers

extension View {
    /// Büyük yüzde rakamları için yuvarlak hatlı, eşit genişlikli rakam stili.
    func numericStyle(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
    }
}
