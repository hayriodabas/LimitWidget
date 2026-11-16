import Foundation

/// Abonelik limitinin sıfırlanma veya ölçüm penceresi türü.
enum SubscriptionWindowType: String, Codable, CaseIterable, Identifiable, Sendable {
    case fiveHour = "five_hour"
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"
    case creditBalance = "credit_balance"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveHour: return "5 Saatlik"
        case .daily: return "Günlük"
        case .weekly: return "Haftalık"
        case .monthly: return "Aylık"
        case .creditBalance: return "Kredi Bakiyesi"
        }
    }

    var shortLabel: String {
        switch self {
        case .fiveHour: return "5sa"
        case .daily: return "Gün"
        case .weekly: return "Hft"
        case .monthly: return "Ay"
        case .creditBalance: return "Kredi"
        }
    }

    var windowSeconds: TimeInterval {
        switch self {
        case .fiveHour: return 5 * 3600
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        case .monthly, .creditBalance: return 30 * 24 * 3600
        }
    }
}

/// Doluluk oranına göre görsel uyarı seviyesi.
enum UsageSeverity: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case critical

    var label: String {
        switch self {
        case .normal: return "Rahat"
        case .warning: return "Yaklaşıyor"
        case .critical: return "Kritik"
        }
    }
}

/// Bir aboneliğin alt pencere veya model bazlı kota göstergesi (örn. 5sa: %8, Haftalık: %66).
struct SubQuotaMetric: Equatable, Sendable {
    let label: String
    let percentage: Int

    var ratio: Double {
        min(max(Double(percentage) / 100.0, 0.0), 1.0)
    }

    var severity: UsageSeverity {
        if ratio >= 0.90 {
            return .critical
        } else if ratio >= 0.70 {
            return .warning
        } else {
            return .normal
        }
    }
}

/// Abonelik kullanım verisinin kaynağı.
enum SubscriptionDataSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case localAuto = "local_auto"
    case manual = "manual"
    case api = "api"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .localAuto: return "Yerel Otomatik"
        case .manual: return "Manuel"
        case .api: return "API / Gateway"
        }
    }
}

/// Uygulama ve widget görünüm teması (Sistem / Koyu / Açık).
enum AppThemeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case dark = "dark"
    case light = "light"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "Sistem"
        case .dark: return "Koyu"
        case .light: return "Açık"
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .dark: return "moon.stars.fill"
        case .light: return "sun.max.fill"
        }
    }

    var nextMode: AppThemeMode {
        switch self {
        case .system: return .dark
        case .dark: return .light
        case .light: return .system
        }
    }
}

/// Yerel otomatik veri okuyucusuyla eşleştirilen sağlayıcı anahtarları.
enum LocalProviderKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case custom = "custom"
    case claudeCode = "claude_code"
    case antigravity = "antigravity"
    case codex = "codex"
    case opencode = "opencode"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .custom: return "Özel / Manuel"
        case .claudeCode: return "Claude Code"
        case .antigravity: return "Antigravity"
        case .codex: return "Codex"
        case .opencode: return "OpenCode"
        }
    }
}

/// Tek bir yapay zeka aboneliğinin kullanım ve limit durumunu temsil eder.
struct AISubscription: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var providerKey: String
    var providerName: String
    var subtitle: String
    var iconName: String
    var windowType: SubscriptionWindowType
    var usedAmount: Double
    var totalLimit: Double
    var unitLabel: String
    var resetsAt: Date?
    var resetDescription: String?
    var dataSource: SubscriptionDataSource
    var isEnabled: Bool
    var sortOrder: Int
    var lastUpdated: Date

    enum CodingKeys: String, CodingKey {
        case id
        case providerKey
        case providerName
        case subtitle
        case iconName
        case windowType
        case usedAmount
        case totalLimit
        case unitLabel
        case resetsAt
        case resetDescription
        case dataSource
        case isEnabled
        case sortOrder
        case lastUpdated
    }

    init(
        id: UUID = UUID(),
        providerKey: String = LocalProviderKey.custom.rawValue,
        providerName: String,
        subtitle: String = "",
        iconName: String = "sparkles",
        windowType: SubscriptionWindowType = .monthly,
        usedAmount: Double,
        totalLimit: Double,
        unitLabel: String = "%",
        resetsAt: Date? = nil,
        resetDescription: String? = nil,
        dataSource: SubscriptionDataSource = .manual,
        isEnabled: Bool = true,
        sortOrder: Int = 0,
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.providerKey = providerKey
        self.providerName = providerName
        self.subtitle = subtitle
        self.iconName = iconName
        self.windowType = windowType
        self.usedAmount = usedAmount
        self.totalLimit = totalLimit
        self.unitLabel = unitLabel
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
        self.dataSource = dataSource
        self.isEnabled = isEnabled
        self.sortOrder = sortOrder
        self.lastUpdated = lastUpdated
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        providerName = try container.decode(String.self, forKey: .providerName)
        providerKey = try container.decodeIfPresent(String.self, forKey: .providerKey)
            ?? Self.inferProviderKey(from: providerName)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "sparkles"
        windowType = try container.decodeIfPresent(SubscriptionWindowType.self, forKey: .windowType) ?? .monthly
        usedAmount = try container.decode(Double.self, forKey: .usedAmount)
        totalLimit = try container.decode(Double.self, forKey: .totalLimit)
        unitLabel = try container.decodeIfPresent(String.self, forKey: .unitLabel) ?? "%"
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        resetDescription = try container.decodeIfPresent(String.self, forKey: .resetDescription)
        dataSource = try container.decodeIfPresent(SubscriptionDataSource.self, forKey: .dataSource) ?? .manual
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
    }

    /// 0.0 ile 1.0 arasına sıkıştırılmış doluluk oranı.
    var usageRatio: Double {
        guard totalLimit > 0 else {
            return usedAmount > 0 ? 1.0 : 0.0
        }
        return min(max(usedAmount / totalLimit, 0.0), 1.0)
    }

    /// Sıkıştırılmamış gerçek oran (limit aşımı kontrolü için).
    var rawRatio: Double {
        guard totalLimit > 0 else { return 0.0 }
        return max(usedAmount / totalLimit, 0.0)
    }

    /// Yuvarlanmış yüzde değeri (0-100).
    var usagePercentage: Int {
        Int((usageRatio * 100.0).rounded())
    }

    /// Kalan miktar (negatife düşmez).
    var remainingAmount: Double {
        max(totalLimit - usedAmount, 0.0)
    }

    /// Doluluk oranına göre renk/uyarı eşiği (<%70 yeşil, %70-%89 kehribar, >=%90 kırmızı).
    var severity: UsageSeverity {
        if usageRatio >= 0.90 {
            return .critical
        } else if usageRatio >= 0.70 {
            return .warning
        } else {
            return .normal
        }
    }

    /// Kullanılan ve toplam değeri birimiyle biçimlendirir.
    var formattedUsageSummary: String {
        let usedText = Self.formatNumber(usedAmount)
        let totalText = Self.formatNumber(totalLimit)
        if unitLabel == "$" {
            return "$\(usedText) / $\(totalText)"
        }
        if unitLabel == "%" && totalLimit == 100 {
            return "%\(usedText) / %100"
        }
        return "\(usedText) / \(totalText) \(unitLabel)"
    }

    /// Menü çubuğu ve widget görünümleri için alt detay metni.
    var compactSummaryText: String {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return formattedUsageSummary
        }
        if unitLabel == "%" && totalLimit == 100 {
            return trimmed
        }
        return "\(formattedUsageSummary) • \(trimmed)"
    }

    /// Alt başlıktaki çoklu pencere/model yüzdelerini ayrıştırır (en az 2 alt metrik varsa döner).
    var subQuotaMetrics: [SubQuotaMetric] {
        let parts = subtitle.split(separator: "•")
        guard parts.count >= 2 else { return [] }

        var metrics: [SubQuotaMetric] = []
        for part in parts {
            let pair = part.split(separator: ":", maxSplits: 1)
            guard pair.count == 2 else { continue }
            let label = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let valueSegment = pair[1]
            guard !label.isEmpty,
                  let pctIndex = valueSegment.firstIndex(of: "%") else {
                continue
            }
            let afterPct = valueSegment[valueSegment.index(after: pctIndex)...]
            let digits = afterPct.prefix { $0.isNumber || $0 == "." }
            guard let number = Double(digits) else { continue }
            metrics.append(SubQuotaMetric(label: label, percentage: Int(number.rounded())))
        }

        return metrics.count >= 2 ? metrics : []
    }

    /// Sıfırlanma geri sayımını okunabilir Türkçe metne çevirir.
    func formattedResetCountdown(relativeTo now: Date = Date()) -> String {
        if let resetsAt {
            let interval = resetsAt.timeIntervalSince(now)
            if interval <= 0 {
                return resetDescription ?? "Sıfırlandı"
            }
            let totalMinutes = max(Int(interval / 60), 1)
            let days = totalMinutes / (60 * 24)
            let hours = (totalMinutes % (60 * 24)) / 60
            let minutes = totalMinutes % 60

            if days > 0 {
                return hours > 0 ? "\(days)g \(hours)sa" : "\(days)g"
            }
            if hours > 0 {
                return minutes > 0 ? "\(hours)sa \(minutes)dk" : "\(hours)sa"
            }
            return "\(minutes)dk"
        }
        return resetDescription ?? windowType.displayName
    }

    static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func inferProviderKey(from providerName: String) -> String {
        let lower = providerName.lowercased()
        if lower.contains("claude") { return LocalProviderKey.claudeCode.rawValue }
        if lower.contains("antigravity") || lower.contains("gemini") { return LocalProviderKey.antigravity.rawValue }
        if lower.contains("codex") || lower.contains("chatgpt") { return LocalProviderKey.codex.rawValue }
        if lower.contains("opencode") { return LocalProviderKey.opencode.rawValue }
        return LocalProviderKey.custom.rawValue
    }
}

extension AISubscription {
    /// İlk açılışta gösterilecek 4 temel yapay zeka aboneliği.
    static func makeDefaultSubscriptions(now: Date = Date()) -> [AISubscription] {
        [
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,
                providerKey: LocalProviderKey.claudeCode.rawValue,
                providerName: "Claude Code",
                subtitle: "Max Plan • Haftalık Kota",
                iconName: "sparkles",
                windowType: .weekly,
                usedAmount: 0,
                totalLimit: 100,
                unitLabel: "%",
                resetsAt: nil,
                resetDescription: "Haftalık pencere",
                dataSource: .localAuto,
                isEnabled: true,
                sortOrder: 0,
                lastUpdated: now
            ),
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111102")!,
                providerKey: LocalProviderKey.antigravity.rawValue,
                providerName: "Antigravity",
                subtitle: "Gemini & Claude/GPT Kota",
                iconName: "atom",
                windowType: .fiveHour,
                usedAmount: 0,
                totalLimit: 100,
                unitLabel: "%",
                resetsAt: nil,
                resetDescription: "5 saatlik pencere",
                dataSource: .localAuto,
                isEnabled: true,
                sortOrder: 1,
                lastUpdated: now
            ),
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111103")!,
                providerKey: LocalProviderKey.codex.rawValue,
                providerName: "Codex",
                subtitle: "ChatGPT Plus • CLI",
                iconName: "terminal",
                windowType: .weekly,
                usedAmount: 0,
                totalLimit: 100,
                unitLabel: "%",
                resetsAt: nil,
                resetDescription: "Haftalık pencere",
                dataSource: .localAuto,
                isEnabled: true,
                sortOrder: 2,
                lastUpdated: now
            ),
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111104")!,
                providerKey: LocalProviderKey.opencode.rawValue,
                providerName: "OpenCode",
                subtitle: "OpenCode Go",
                iconName: "chevron.left.forwardslash.chevron.right",
                windowType: .monthly,
                usedAmount: 0,
                totalLimit: 100,
                unitLabel: "%",
                resetsAt: nil,
                resetDescription: "Aylık pencere",
                dataSource: .localAuto,
                isEnabled: true,
                sortOrder: 3,
                lastUpdated: now
            )
        ]
    }
}

// MARK: - Presentation helpers

/// Arayüzde gösterilen, okunabilir etiketli alt kota değeri.
struct DisplayMetric: Identifiable, Equatable, Sendable {
    let id: Int
    let label: String
    let percentage: Int
    let isPrimary: Bool

    var ratio: Double {
        min(max(Double(percentage) / 100.0, 0.0), 1.0)
    }
}

extension AISubscription {
    /// Özel kayıtlar için addan çıkarılan, aksi halde kayıtlı sağlayıcı anahtarı.
    var effectiveProviderKey: String {
        providerKey == LocalProviderKey.custom.rawValue
            ? Self.inferProviderKey(from: providerName)
            : providerKey
    }

    /// Türkçe yüzde yazımı: "%53".
    static func percentText(_ value: Int) -> String {
        "%\(value)"
    }

    var percentText: String {
        Self.percentText(usagePercentage)
    }

    /// Alt kotaları okunur etiketlerle döndürür ("5sa" → "5 saat", "Hft" → "Haftalık").
    var displayMetrics: [DisplayMetric] {
        subQuotaMetrics.enumerated().map { index, metric in
            DisplayMetric(
                id: index,
                label: Self.friendlyMetricLabel(metric.label),
                percentage: metric.percentage,
                isPrimary: Self.metricLabel(metric.label, matches: windowType)
            )
        }
    }

    /// Alt kotaların tek satırlık özeti: "5 saat %0 · Haftalık %53".
    var metricsSummary: String? {
        let metrics = displayMetrics
        guard !metrics.isEmpty else { return nil }
        return metrics
            .map { "\($0.label) \(Self.percentText($0.percentage))" }
            .joined(separator: " · ")
    }

    /// Alt başlığın sonundaki parantez içi not: "(Plus)" → "Plus".
    var detailNote: String? {
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(")"),
              let open = trimmed.lastIndex(of: "(") else {
            return nil
        }
        let inner = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let note = inner.trimmingCharacters(in: .whitespaces)
        guard !note.isEmpty else { return nil }
        if note == "Önbellek" { return "Önbellekten" }
        return note
    }

    /// Sağlayıcı adının altında gösterilen kısa açıklama.
    var secondaryLine: String {
        if !subQuotaMetrics.isEmpty {
            let base = quotaKindLabel
            if let note = detailNote {
                return "\(base) · \(note)"
            }
            return base
        }
        let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return quotaKindLabel
        }
        return trimmed.replacingOccurrences(of: " • ", with: " · ")
    }

    /// Yenilenmeye kalan süre ("2 sa 14 dk", "3 g 4 sa"); bilinmiyorsa nil.
    func resetPhrase(relativeTo now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        guard interval > 0 else { return "şimdi" }
        let totalMinutes = max(Int(interval / 60), 1)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "\(days) g \(hours) sa" : "\(days) g"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours) sa \(minutes) dk" : "\(hours) sa"
        }
        return "\(minutes) dk"
    }

    /// "2 sa 14 dk sonra yenilenir" gibi tam cümle; yenilenme zamanı bilinmiyorsa nil.
    func resetSentence(relativeTo now: Date = Date()) -> String? {
        guard let phrase = resetPhrase(relativeTo: now) else { return nil }
        return phrase == "şimdi" ? "Yenilendi" : "\(phrase) sonra yenilenir"
    }

    /// Cümle içinde kullanılacak dönem adı: "Haftalık kota", "5 saatlik kota".
    var quotaKindLabel: String {
        let lower = windowType.displayName.lowercased(with: Locale(identifier: "tr_TR"))
        guard let first = lower.first else { return "Kota" }
        return String(first).uppercased(with: Locale(identifier: "tr_TR")) + lower.dropFirst() + " kota"
    }

    var sourceLabel: String {
        dataSource == .localAuto ? "Otomatik" : "Manuel"
    }

    static func friendlyMetricLabel(_ raw: String) -> String {
        switch raw.lowercased() {
        case "5sa": return "5 saat"
        case "hft", "haftalık": return "Haftalık"
        case "ay", "aylık": return "Aylık"
        case "gün", "günlük": return "Günlük"
        default: return raw
        }
    }

    static func metricLabel(_ raw: String, matches window: SubscriptionWindowType) -> Bool {
        switch (raw.lowercased(), window) {
        case ("5sa", .fiveHour): return true
        case ("hft", .weekly), ("haftalık", .weekly): return true
        case ("ay", .monthly), ("aylık", .monthly): return true
        case ("gün", .daily), ("günlük", .daily): return true
        default: return false
        }
    }
}
