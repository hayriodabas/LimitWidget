import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// Ayarlar penceresindeki tercihler (UserDefaults üzerinde saklanır).
@MainActor
@Observable
final class AppPreferences {
    enum MenuBarDisplay: String, CaseIterable, Identifiable {
        case peakPercent
        case iconOnly

        var id: String { rawValue }

        var title: String {
            switch self {
            case .peakPercent: return "Simge ve en yüksek yüzde"
            case .iconOnly: return "Yalnızca simge"
            }
        }
    }

    static let refreshOptions: [(seconds: Int, title: String)] = [
        (60, "Her dakika"),
        (300, "5 dakikada bir"),
        (900, "15 dakikada bir"),
        (1800, "30 dakikada bir")
    ]

    static let alertThresholdOptions: [Int] = [80, 90, 95]

    @ObservationIgnored private let defaults: UserDefaults

    var refreshInterval: Int {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: Keys.menuBarDisplay) }
    }

    var opensOnHover: Bool {
        didSet { defaults.set(opensOnHover, forKey: Keys.opensOnHover) }
    }

    var notifiesNearLimit: Bool {
        didSet { defaults.set(notifiesNearLimit, forKey: Keys.notifiesNearLimit) }
    }

    var alertThreshold: Int {
        didSet { defaults.set(alertThreshold, forKey: Keys.alertThreshold) }
    }

    private(set) var launchesAtLogin: Bool
    var launchAtLoginMessage: String?
    var notificationMessage: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedInterval = defaults.integer(forKey: Keys.refreshInterval)
        refreshInterval = storedInterval > 0 ? storedInterval : 60
        menuBarDisplay = MenuBarDisplay(rawValue: defaults.string(forKey: Keys.menuBarDisplay) ?? "") ?? .peakPercent
        opensOnHover = defaults.object(forKey: Keys.opensOnHover) as? Bool ?? true
        notifiesNearLimit = defaults.bool(forKey: Keys.notifiesNearLimit)
        let storedThreshold = defaults.integer(forKey: Keys.alertThreshold)
        alertThreshold = storedThreshold > 0 ? storedThreshold : 90
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Launch at login

    func setLaunchesAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginMessage = "Değiştirilemedi: \(error.localizedDescription)"
        }
        let status = SMAppService.mainApp.status
        launchesAtLogin = status == .enabled
        if enabled && status == .requiresApproval {
            launchAtLoginMessage = "Sistem Ayarları › Genel › Giriş Öğeleri bölümünden onay vermeniz gerekiyor."
        }
    }

    func refreshLaunchAtLoginStatus() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notifications

    func setNotifiesNearLimit(_ enabled: Bool) {
        notificationMessage = nil
        guard enabled else {
            notifiesNearLimit = false
            return
        }
        Task {
            let center = UNUserNotificationCenter.current()
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                notifiesNearLimit = granted
                if !granted {
                    notificationMessage = "Bildirim izni verilmedi. Sistem Ayarları › Bildirimler bölümünden açabilirsiniz."
                }
            } catch {
                notifiesNearLimit = false
                notificationMessage = "Bildirim izni alınamadı: \(error.localizedDescription)"
            }
        }
    }

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let menuBarDisplay = "menuBarDisplay"
        static let opensOnHover = "opensOnHover"
        static let notifiesNearLimit = "notifiesNearLimit"
        static let alertThreshold = "alertThreshold"
    }
}

/// Bir kota eşiği geçtiğinde, her dönem için yalnızca bir kez bildirim gönderir.
@MainActor
final class UsageAlertNotifier {
    private let defaults: UserDefaults
    private let storageKey = "notifiedUsageKeys"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func evaluate(_ subscriptions: [AISubscription], threshold: Int, isEnabled: Bool) {
        var notified = Set(defaults.stringArray(forKey: storageKey) ?? [])
        var validKeys = Set<String>()

        for item in subscriptions where item.isEnabled {
            let key = alertKey(for: item)
            if item.usagePercentage >= threshold {
                validKeys.insert(key)
                if isEnabled && !notified.contains(key) {
                    post(for: item)
                    notified.insert(key)
                }
            }
        }

        // Kullanım eşiğin altına düştüğünde (yeni dönem) anahtarı unut; böylece bir sonraki dönemde yeniden bildirilir.
        notified = notified.intersection(validKeys)
        defaults.set(Array(notified), forKey: storageKey)
    }

    private func alertKey(for item: AISubscription) -> String {
        let resetStamp = item.resetsAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? "na"
        return "\(item.id.uuidString)|\(item.windowType.rawValue)|\(resetStamp)"
    }

    private func post(for item: AISubscription) {
        let content = UNMutableNotificationContent()
        content.title = "\(item.providerName) kotası \(item.percentText) dolu"
        let resetPart = item.resetSentence().map { " \($0)." } ?? ""
        content.body = "\(item.quotaKindLabel)nız sınıra yaklaştı.\(resetPart)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "usage-\(item.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
