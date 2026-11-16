import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Abonelik verilerini Application Support JSON dosyasına okuyup yazar.
struct SubscriptionRepository: Sendable {
    static let appGroupIdentifier = "group.com.hayriodabas.LimitWidget"
    static let fileName = "subscriptions.json"

    let fileURL: URL

    init(fileURL: URL = SubscriptionRepository.defaultFileURL()) {
        self.fileURL = fileURL
    }

    static func defaultFileURL() -> URL {
        let realHome = LocalUsageCollector.realHomeDirectoryURL()
        return realHome
            .appendingPathComponent("Library/Application Support/LimitWidget", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    static func widgetContainerFileURL(named name: String = fileName) -> URL {
        let realHome = LocalUsageCollector.realHomeDirectoryURL()
        return realHome
            .appendingPathComponent(
                "Library/Containers/com.hayriodabas.LimitWidget.Widget/Data/Library/Application Support/LimitWidget",
                isDirectory: true
            )
            .appendingPathComponent(name)
    }

    /// Diskten abonelik listesini okur; dosya yoksa nil döner.
    func load() throws -> [AISubscription]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let items = try? decoder.decode([AISubscription].self, from: data) {
            return items
        }

        if fileURL == Self.defaultFileURL() {
            let fallbackURL = Self.widgetContainerFileURL()
            if FileManager.default.fileExists(atPath: fallbackURL.path),
               let data = try? Data(contentsOf: fallbackURL),
               let items = try? decoder.decode([AISubscription].self, from: data) {
                return items
            }
        }
        return nil
    }

    /// Diskten okur; dosya yoksa, Adım 1 şablonuysa veya eski sezgisel birimlerden kalmışsa günceller.
    func loadOrSeed(now: Date = Date()) -> [AISubscription] {
        if let existing = try? load(), !existing.isEmpty {
            if Self.isLegacyStep1Sample(existing) {
                let updatedDefaults = AISubscription.makeDefaultSubscriptions(now: now)
                try? save(updatedDefaults)
                return updatedDefaults
            }
            let upgraded = Self.upgradeHeuristicDefaultsIfNeeded(existing, now: now)
            if upgraded.didUpgrade {
                try? save(upgraded.items)
            }
            return upgraded.items.sorted { $0.sortOrder < $1.sortOrder }
        }
        let defaults = AISubscription.makeDefaultSubscriptions(now: now)
        try? save(defaults)
        return defaults
    }

    /// Abonelik listesini atomik olarak JSON dosyasına kaydeder.
    func save(_ subscriptions: [AISubscription]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(subscriptions)
        try data.write(to: fileURL, options: .atomic)

        if fileURL == Self.defaultFileURL() {
            let widgetURL = Self.widgetContainerFileURL()
            try? FileManager.default.createDirectory(
                at: widgetURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: widgetURL, options: .atomic)
        }
    }

    var themeFileURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("theme.json")
    }

    /// Kayıtlı görünüm temasını (Sistem / Koyu / Açık) okur; yoksa .system döner.
    func loadThemeMode() -> AppThemeMode {
        if FileManager.default.fileExists(atPath: themeFileURL.path),
           let data = try? Data(contentsOf: themeFileURL),
           let mode = try? JSONDecoder().decode(AppThemeMode.self, from: data) {
            return mode
        }
        if fileURL == Self.defaultFileURL() {
            let fallbackThemeURL = Self.widgetContainerFileURL(named: "theme.json")
            if FileManager.default.fileExists(atPath: fallbackThemeURL.path),
               let data = try? Data(contentsOf: fallbackThemeURL),
               let mode = try? JSONDecoder().decode(AppThemeMode.self, from: data) {
                return mode
            }
        }
        return .system
    }

    /// Seçilen görünüm temasını (Sistem / Koyu / Açık) kaydeder.
    func saveThemeMode(_ mode: AppThemeMode) throws {
        let directory = themeFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(mode)
        try data.write(to: themeFileURL, options: .atomic)

        if fileURL == Self.defaultFileURL() {
            let widgetThemeURL = Self.widgetContainerFileURL(named: "theme.json")
            try? FileManager.default.createDirectory(
                at: widgetThemeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: widgetThemeURL, options: .atomic)
        }
    }

    private static func isLegacyStep1Sample(_ items: [AISubscription]) -> Bool {
        let legacyIDs: Set<UUID> = [
            UUID(uuidString: "11111111-1111-1111-1111-111111111105")!,
            UUID(uuidString: "11111111-1111-1111-1111-111111111106")!
        ]
        let ids = Set(items.map(\.id))
        return items.count == 6 && legacyIDs.isSubset(of: ids)
    }

    private static func needsHeuristicUpgrade(_ item: AISubscription) -> Bool {
        let claudeID = UUID(uuidString: "11111111-1111-1111-1111-111111111101")!
        let antigravityID = UUID(uuidString: "11111111-1111-1111-1111-111111111102")!
        let opencodeID = UUID(uuidString: "11111111-1111-1111-1111-111111111104")!

        if (item.id == claudeID || item.id == antigravityID) && item.unitLabel == "yanıt" {
            return true
        }
        if item.id == opencodeID
            && item.providerKey == LocalProviderKey.opencode.rawValue
            && item.totalLimit == 20
            && item.unitLabel == "$" {
            return true
        }
        return false
    }

    private static func upgradeHeuristicDefaultsIfNeeded(
        _ items: [AISubscription],
        now: Date
    ) -> (items: [AISubscription], didUpgrade: Bool) {
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: AISubscription.makeDefaultSubscriptions(now: now).map { ($0.id, $0) }
        )
        var didUpgrade = false
        let updated = items.map { item -> AISubscription in
            guard needsHeuristicUpgrade(item), var replacement = defaultsByID[item.id] else {
                return item
            }
            didUpgrade = true
            replacement.isEnabled = item.isEnabled
            replacement.sortOrder = item.sortOrder
            replacement.dataSource = item.dataSource
            return replacement
        }
        return (updated, didUpgrade)
    }
}

/// Ana uygulama ve menü çubuğu arayüzleri için reaktif abonelik deposu.
@MainActor
@Observable
final class SubscriptionStore {
    var subscriptions: [AISubscription]
    var themeMode: AppThemeMode
    var lastRefreshedAt: Date
    var isSyncing = false
    var lastErrorMessage: String?

    private let repository: SubscriptionRepository
    private let collector: LocalUsageCollector
    private let onDidPersist: @Sendable () -> Void
    private var autoSyncTask: Task<Void, Never>?
    private var needsResync = false

    init(
        repository: SubscriptionRepository = SubscriptionRepository(),
        collector: LocalUsageCollector = LocalUsageCollector(),
        onDidPersist: @escaping @Sendable () -> Void = { SubscriptionStore.reloadWidgets() }
    ) {
        self.repository = repository
        self.collector = collector
        self.onDidPersist = onDidPersist
        self.subscriptions = repository.loadOrSeed()
        self.themeMode = repository.loadThemeMode()
        self.lastRefreshedAt = Date()
    }

    func setThemeMode(_ mode: AppThemeMode) {
        themeMode = mode
        do {
            try repository.saveThemeMode(mode)
            onDidPersist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func cycleThemeMode() {
        setThemeMode(themeMode.nextMode)
    }

    /// Etkin abonelikleri sıralı döndürür.
    var activeSubscriptions: [AISubscription] {
        subscriptions
            .filter(\.isEnabled)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// En yüksek aktif doluluk yüzdesi (menü çubuğu rozeti için).
    var highestUsagePercentage: Int {
        activeSubscriptions.map(\.usagePercentage).max() ?? 0
    }

    /// Kritik (%90+) abonelik sayısı.
    var criticalCount: Int {
        activeSubscriptions.filter { $0.severity == .critical }.count
    }

    /// Uyarı (%70-%89) abonelik sayısı.
    var warningCount: Int {
        activeSubscriptions.filter { $0.severity == .warning }.count
    }

    /// Ortalama doluluk yüzdesi.
    var averageUsagePercentage: Int {
        guard !activeSubscriptions.isEmpty else { return 0 }
        let total = activeSubscriptions.reduce(0) { $0 + $1.usagePercentage }
        return total / activeSubscriptions.count
    }

    func reload() {
        subscriptions = repository.loadOrSeed()
        syncLocalUsage()
    }

    /// Yerel araç loglarından ve veritabanlarından kullanım verilerini senkron okur.
    func syncLocalUsage(now: Date = Date()) {
        subscriptions = collector.refresh(subscriptions, now: now)
        persist()
    }

    /// Ana iş parçacığını kilitlemeden arka planda yerel kullanım verilerini yeniler.
    func syncLocalUsageAsync(now: Date = Date()) async {
        guard !isSyncing else {
            needsResync = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }

        let snapshot = subscriptions
        let collector = self.collector
        let refreshed = await Task.detached(priority: .utility) {
            collector.refresh(snapshot, now: now)
        }.value

        let refreshedByID = Dictionary(uniqueKeysWithValues: refreshed.map { ($0.id, $0) })
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        for index in subscriptions.indices {
            let current = subscriptions[index]
            guard current.dataSource == .localAuto,
                  let measured = refreshedByID[current.id],
                  let before = snapshotByID[current.id] else {
                continue
            }
            // Ölçüm sürerken kullanıcı sağlayıcıyı veya dönemini değiştirdiyse eski ölçümü yazma; yeniden ölç.
            guard before.providerKey == current.providerKey,
                  before.windowType == current.windowType else {
                needsResync = true
                continue
            }
            var merged = current
            merged.usedAmount = measured.usedAmount
            merged.totalLimit = measured.totalLimit
            merged.unitLabel = measured.unitLabel
            merged.resetsAt = measured.resetsAt
            merged.resetDescription = measured.resetDescription
            merged.subtitle = measured.subtitle
            merged.lastUpdated = measured.lastUpdated
            subscriptions[index] = merged
        }
        persist()

        if needsResync {
            needsResync = false
            isSyncing = false
            await syncLocalUsageAsync()
        }
    }

    /// Menü çubuğu çalışırken belirli aralıklarla yerel verileri otomatik tazeler.
    func startAutoSync(interval: TimeInterval = 60) {
        autoSyncTask?.cancel()
        autoSyncTask = Task { [weak self] in
            guard let self else { return }
            await self.syncLocalUsageAsync()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self.syncLocalUsageAsync()
            }
        }
    }

    func add(_ subscription: AISubscription) {
        var newItem = subscription
        newItem.sortOrder = (subscriptions.map(\.sortOrder).max() ?? -1) + 1
        newItem.lastUpdated = Date()
        subscriptions.append(newItem)
        persist()
        if newItem.dataSource == .localAuto {
            Task { await syncLocalUsageAsync() }
        }
    }

    func update(_ subscription: AISubscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else {
            return
        }
        var updated = subscription
        updated.lastUpdated = Date()
        subscriptions[index] = updated
        persist()
        if updated.dataSource == .localAuto {
            Task { await syncLocalUsageAsync() }
        }
    }

    func delete(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        normalizeSortOrder()
        persist()
    }

    func resetToDefaults() {
        subscriptions = AISubscription.makeDefaultSubscriptions()
        persist()
        Task { await syncLocalUsageAsync() }
    }

    /// Tüm abonelikler kullanıcı sırasıyla.
    var orderedSubscriptions: [AISubscription] {
        subscriptions.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// En yüksek doluluktaki etkin abonelik.
    var peakSubscription: AISubscription? {
        activeSubscriptions.max { $0.usageRatio < $1.usageRatio }
    }

    /// Yenilenmesi en yakın olan etkin abonelik.
    func nextResettingSubscription(now: Date = Date()) -> AISubscription? {
        activeSubscriptions
            .compactMap { item -> (AISubscription, Date)? in
                guard let date = item.resetsAt, date > now else { return nil }
                return (item, date)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    /// Menü çubuğu ve widget'ta gösterimi açar/kapatır (yeniden ölçüm yapmadan).
    func setEnabled(_ isEnabled: Bool, id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].isEnabled = isEnabled
        persist()
    }

    /// Ana kota dönemini değiştirir ve yalnız bu sağlayıcıyı arka planda yeniden okur.
    func setWindowType(_ windowType: SubscriptionWindowType, id: UUID) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].windowType = windowType
        persist()
        guard subscriptions[index].dataSource == .localAuto else { return }
        Task { await syncLocalUsageAsync() }
    }

    func canMove(id: UUID, by offset: Int) -> Bool {
        let ordered = orderedSubscriptions
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return false }
        return ordered.indices.contains(position + offset)
    }

    /// Sağlayıcıyı listede yukarı (-1) veya aşağı (+1) taşır.
    func move(id: UUID, by offset: Int) {
        var ordered = orderedSubscriptions
        guard let position = ordered.firstIndex(where: { $0.id == id }),
              ordered.indices.contains(position + offset) else {
            return
        }
        ordered.swapAt(position, position + offset)
        for index in ordered.indices {
            ordered[index].sortOrder = index
        }
        subscriptions = ordered
        persist()
    }

    func refreshWidgets() {
        lastRefreshedAt = Date()
        onDidPersist()
    }

    private func normalizeSortOrder() {
        for index in subscriptions.indices {
            subscriptions[index].sortOrder = index
        }
    }

    private func persist() {
        do {
            try repository.save(subscriptions)
            lastRefreshedAt = Date()
            lastErrorMessage = nil
            onDidPersist()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    nonisolated static func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
