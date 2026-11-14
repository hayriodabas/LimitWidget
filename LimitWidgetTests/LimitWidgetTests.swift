import Foundation
import SQLite3
import XCTest

final class LimitWidgetTests: XCTestCase {
    func testUsageRatioAndPercentageClamping() {
        let normal = AISubscription(providerName: "Claude", usedAmount: 45, totalLimit: 100)
        XCTAssertEqual(normal.usageRatio, 0.45, accuracy: 0.0001)
        XCTAssertEqual(normal.usagePercentage, 45)
        XCTAssertEqual(normal.remainingAmount, 55, accuracy: 0.0001)

        let overLimit = AISubscription(providerName: "Codex", usedAmount: 125, totalLimit: 100)
        XCTAssertEqual(overLimit.usageRatio, 1.0, accuracy: 0.0001)
        XCTAssertEqual(overLimit.rawRatio, 1.25, accuracy: 0.0001)
        XCTAssertEqual(overLimit.usagePercentage, 100)
        XCTAssertEqual(overLimit.remainingAmount, 0, accuracy: 0.0001)

        let zeroLimit = AISubscription(providerName: "Zero", usedAmount: 5, totalLimit: 0)
        XCTAssertEqual(zeroLimit.usageRatio, 1.0, accuracy: 0.0001)

        let zeroAll = AISubscription(providerName: "Empty", usedAmount: 0, totalLimit: 0)
        XCTAssertEqual(zeroAll.usageRatio, 0.0, accuracy: 0.0001)
    }

    func testSeverityThresholds() {
        let normal = AISubscription(providerName: "A", usedAmount: 69, totalLimit: 100)
        XCTAssertEqual(normal.severity, .normal)

        let warningLower = AISubscription(providerName: "B", usedAmount: 70, totalLimit: 100)
        XCTAssertEqual(warningLower.severity, .warning)

        let warningUpper = AISubscription(providerName: "C", usedAmount: 89.9, totalLimit: 100)
        XCTAssertEqual(warningUpper.severity, .warning)

        let critical = AISubscription(providerName: "D", usedAmount: 90, totalLimit: 100)
        XCTAssertEqual(critical.severity, .critical)
    }

    func testFormattedUsageSummaryAndResetCountdown() {
        let dollar = AISubscription(providerName: "OpenCode", usedAmount: 14.5, totalLimit: 20, unitLabel: "$")
        XCTAssertEqual(dollar.formattedUsageSummary, "$14.50 / $20")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let twoHours = AISubscription(
            providerName: "Claude Code",
            usedAmount: 50,
            totalLimit: 100,
            resetsAt: now.addingTimeInterval(2 * 3600 + 15 * 60)
        )
        XCTAssertEqual(twoHours.formattedResetCountdown(relativeTo: now), "2sa 15dk")

        let fallbackDesc = AISubscription(
            providerName: "Codex",
            usedAmount: 100,
            totalLimit: 300,
            unitLabel: "istek",
            resetsAt: nil,
            resetDescription: "Ayın 1'i"
        )
        XCTAssertEqual(fallbackDesc.formattedResetCountdown(relativeTo: now), "Ayın 1'i")
        XCTAssertEqual(fallbackDesc.formattedUsageSummary, "100 / 300 istek")
    }

    func testRepositorySaveLoadRoundtripAndLegacyMigration() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("subscriptions.json")
        let repo = SubscriptionRepository(fileURL: fileURL)

        XCTAssertNil(try repo.load())

        let seeded = repo.loadOrSeed()
        XCTAssertEqual(seeded.count, 4)
        XCTAssertEqual(seeded.map(\.providerName), ["Claude Code", "Antigravity", "Codex", "OpenCode"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // Eski 6'lı Adım 1 şablonu otomatik 4'lü gerçek abonelik listesine yükseltilmeli
        let legacySix = (1...6).map { index in
            AISubscription(
                id: UUID(uuidString: String(format: "11111111-1111-1111-1111-1111111111%02d", index))!,
                providerName: "Legacy \(index)",
                usedAmount: 10,
                totalLimit: 100,
                sortOrder: index - 1
            )
        }
        try repo.save(legacySix)
        let migrated = repo.loadOrSeed()
        XCTAssertEqual(migrated.count, 4)
        XCTAssertEqual(migrated.map(\.providerKey), ["claude_code", "antigravity", "codex", "opencode"])
        XCTAssertEqual(migrated.map(\.unitLabel), ["%", "%", "%", "%"])

        // Eski sezgisel birimlerden (yanıt / $20) yüzde kotasına yükseltme
        let heuristicFour = [
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111101")!,
                providerKey: LocalProviderKey.claudeCode.rawValue,
                providerName: "Claude Code",
                windowType: .fiveHour,
                usedAmount: 1456,
                totalLimit: 3000,
                unitLabel: "yanıt",
                dataSource: .localAuto,
                sortOrder: 0
            ),
            AISubscription(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111104")!,
                providerKey: LocalProviderKey.opencode.rawValue,
                providerName: "OpenCode",
                windowType: .monthly,
                usedAmount: 3,
                totalLimit: 20,
                unitLabel: "$",
                dataSource: .localAuto,
                sortOrder: 3
            )
        ]
        try repo.save(heuristicFour)
        let upgraded = repo.loadOrSeed()
        XCTAssertEqual(upgraded[0].windowType, .weekly)
        XCTAssertEqual(upgraded[0].unitLabel, "%")
        XCTAssertEqual(upgraded[0].totalLimit, 100)
        XCTAssertEqual(upgraded[1].unitLabel, "%")
        XCTAssertEqual(upgraded[1].totalLimit, 100)

        let custom = [
            AISubscription(
                providerName: "Test AI",
                subtitle: "Pro",
                iconName: "cpu",
                windowType: .daily,
                usedAmount: 35,
                totalLimit: 50,
                unitLabel: "istek",
                dataSource: .manual,
                isEnabled: true,
                sortOrder: 0
            )
        ]
        try repo.save(custom)

        let reloaded = repo.loadOrSeed()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.providerName, "Test AI")
        XCTAssertEqual(reloaded.first?.usagePercentage, 70)
    }

    func testClaudeCodeLocalUsageCollection() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let projectDir = home.appendingPathComponent(".claude/projects/sample", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

        let inWindowOld = iso.string(from: now.addingTimeInterval(-3600))
        let inWindowNew = iso.string(from: now.addingTimeInterval(-600))
        let outOfWindow = iso.string(from: now.addingTimeInterval(-6 * 3600))

        let lines = [
            "{\"timestamp\":\"\(outOfWindow)\",\"message\":{\"id\":\"msg_old\",\"usage\":{\"input_tokens\":500,\"output_tokens\":500}}}",
            "{\"timestamp\":\"\(inWindowOld)\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":500,\"cache_read_input_tokens\":500}}}",
            "{\"timestamp\":\"\(inWindowOld)\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":1000,\"output_tokens\":500,\"cache_read_input_tokens\":500}}}",
            "{\"timestamp\":\"\(inWindowNew)\",\"message\":{\"id\":\"msg_2\",\"usage\":{\"input_tokens\":200,\"output_tokens\":300}}}"
        ].joined(separator: "\n")
        try lines.write(to: projectDir.appendingPathComponent("chat.jsonl"), atomically: true, encoding: .utf8)

        let collector = LocalUsageCollector(homeDirectoryURL: home)
        let base = AISubscription(
            providerKey: LocalProviderKey.claudeCode.rawValue,
            providerName: "Claude Code",
            windowType: .fiveHour,
            usedAmount: 0,
            totalLimit: 3000,
            unitLabel: "yanıt",
            dataSource: .localAuto
        )

        let collected = collector.collectUsage(for: base, now: now)
        XCTAssertEqual(collected.usedAmount, 2, accuracy: 0.001)
        XCTAssertTrue(collected.subtitle.contains("2 yanıt"))
        XCTAssertTrue(collected.subtitle.contains("2.5K tok"))
        XCTAssertEqual(collected.resetsAt?.timeIntervalSince1970 ?? 0, now.addingTimeInterval(4 * 3600).timeIntervalSince1970, accuracy: 1.0)
    }

    func testAntigravityLocalUsageCollection() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let logsDir = home.appendingPathComponent(".gemini/antigravity/brain/conv-1/.system_generated/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let t1 = iso.string(from: now.addingTimeInterval(-1800))
        let t2 = iso.string(from: now.addingTimeInterval(-300))
        let old = iso.string(from: now.addingTimeInterval(-10 * 3600))

        let lines = [
            "{\"type\":\"USER_INPUT\",\"created_at\":\"\(t1)\"}",
            "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(old)\"}",
            "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(t1)\"}",
            "{\"type\":\"PLANNER_RESPONSE\",\"created_at\":\"\(t2)\"}"
        ].joined(separator: "\n")
        try lines.write(to: logsDir.appendingPathComponent("transcript.jsonl"), atomically: true, encoding: .utf8)

        let collector = LocalUsageCollector(homeDirectoryURL: home)
        let base = AISubscription(
            providerKey: LocalProviderKey.antigravity.rawValue,
            providerName: "Antigravity",
            windowType: .fiveHour,
            usedAmount: 0,
            totalLimit: 200,
            unitLabel: "yanıt",
            dataSource: .localAuto
        )

        let collected = collector.collectUsage(for: base, now: now)
        XCTAssertEqual(collected.usedAmount, 2, accuracy: 0.001)
        XCTAssertTrue(collected.subtitle.contains("2 adım"))
        XCTAssertEqual(collected.resetsAt?.timeIntervalSince1970 ?? 0, now.addingTimeInterval(4.5 * 3600).timeIntervalSince1970, accuracy: 1.0)
    }

    func testCodexLocalUsageCollection() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let expiredPrimaryReset = Int(now.addingTimeInterval(-600).timeIntervalSince1970)
        let activeSecondaryReset = Int(now.addingTimeInterval(86400 * 3).timeIntervalSince1970)

        let sessionsDir = home.appendingPathComponent(".codex/sessions/2026/11/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let rolloutURL = sessionsDir.appendingPathComponent("rollout-test.jsonl")

        let eventLine = """
        {"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":48.0,"window_minutes":300,"resets_at":\(expiredPrimaryReset)},"secondary":{"used_percent":59.0,"window_minutes":10080,"resets_at":\(activeSecondaryReset)}}}}
        """
        try eventLine.write(to: rolloutURL, atomically: true, encoding: .utf8)

        let collector = LocalUsageCollector(homeDirectoryURL: home)

        let weeklyCard = AISubscription(
            providerKey: LocalProviderKey.codex.rawValue,
            providerName: "Codex",
            windowType: .weekly,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let weeklyCollected = collector.collectUsage(for: weeklyCard, now: now)
        XCTAssertEqual(weeklyCollected.usedAmount, 59.0, accuracy: 0.001)
        XCTAssertEqual(weeklyCollected.resetsAt?.timeIntervalSince1970 ?? 0, Double(activeSecondaryReset), accuracy: 1.0)
        XCTAssertTrue(weeklyCollected.subtitle.contains("5sa: %0"))
        XCTAssertTrue(weeklyCollected.subtitle.contains("Haftalık: %59"))

        // Süresi dolmuş 5 saatlik pencere 0 göstermeli
        let fiveHourCard = AISubscription(
            providerKey: LocalProviderKey.codex.rawValue,
            providerName: "Codex 5sa",
            windowType: .fiveHour,
            usedAmount: 48,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let fiveHourCollected = collector.collectUsage(for: fiveHourCard, now: now)
        XCTAssertEqual(fiveHourCollected.usedAmount, 0, accuracy: 0.001)
        XCTAssertNil(fiveHourCollected.resetsAt)
    }

    func testOpenCodeLocalUsageCollection() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let openCodeDir = home.appendingPathComponent(".local/share/opencode", isDirectory: true)
        try FileManager.default.createDirectory(at: openCodeDir, withIntermediateDirectories: true)
        let dbURL = openCodeDir.appendingPathComponent("opencode.db")

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let recentMs = Int64(now.addingTimeInterval(-3600).timeIntervalSince1970 * 1000)
        let oldMs = Int64(now.addingTimeInterval(-40 * 86400).timeIntervalSince1970 * 1000)

        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE session (id TEXT PRIMARY KEY, time_updated INTEGER NOT NULL, cost REAL NOT NULL, tokens_input INTEGER NOT NULL, tokens_output INTEGER NOT NULL);
        INSERT INTO session VALUES ('s1', \(recentMs), 1.25, 100000, 50000);
        INSERT INTO session VALUES ('s2', \(recentMs), 2.50, 200000, 50000);
        INSERT INTO session VALUES ('s_old', \(oldMs), 9.99, 500000, 500000);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)

        let collector = LocalUsageCollector(homeDirectoryURL: home)
        let base = AISubscription(
            providerKey: LocalProviderKey.opencode.rawValue,
            providerName: "OpenCode",
            windowType: .monthly,
            usedAmount: 0,
            totalLimit: 20,
            unitLabel: "$",
            dataSource: .localAuto
        )

        let collected = collector.collectUsage(for: base, now: now)
        XCTAssertEqual(collected.usedAmount, 3.75, accuracy: 0.001)
        XCTAssertTrue(collected.subtitle.contains("2 oturum"))
        XCTAssertTrue(collected.subtitle.contains("400.0K tok"))
    }

    func testClaudeLiveControlResponseParsing() {
        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let collector = LocalUsageCollector(homeDirectoryURL: makeTempDir(), allowLiveProbes: false)

        let payload = """
        {"type":"system","subtype":"init"}
        {"type":"control_response","response":{"subtype":"success","request_id":"usage-1","response":{"subscription_type":"max","rate_limits_available":true,"rate_limits":{"five_hour":null,"seven_day":{"utilization":96,"resets_at":"2026-11-16T21:00:00.160297+00:00"},"limits":[{"kind":"weekly_all","percent":96,"resets_at":"2026-11-16T21:00:00.160297+00:00"}],"model_scoped":[{"display_name":"Fable","utilization":100,"resets_at":"2026-11-16T21:00:00.160461+00:00"}]}}}}
        """
        let data = Data(payload.utf8)

        let weeklyCard = AISubscription(
            providerKey: LocalProviderKey.claudeCode.rawValue,
            providerName: "Claude Code",
            windowType: .weekly,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let weeklyUpdated = collector.applyClaudeControlResponseData(data, to: weeklyCard, now: now)
        XCTAssertNotNil(weeklyUpdated)
        XCTAssertEqual(weeklyUpdated?.usedAmount ?? -1, 96.0, accuracy: 0.001)
        XCTAssertEqual(weeklyUpdated?.totalLimit ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(weeklyUpdated?.unitLabel, "%")
        XCTAssertNotNil(weeklyUpdated?.resetsAt)
        XCTAssertEqual(weeklyUpdated?.subtitle, "5sa: %0 • Haftalık: %96 • Fable: %100")

        let fiveHourCard = AISubscription(
            providerKey: LocalProviderKey.claudeCode.rawValue,
            providerName: "Claude Code 5sa",
            windowType: .fiveHour,
            usedAmount: 50,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let fiveHourUpdated = collector.applyClaudeControlResponseData(data, to: fiveHourCard, now: now)
        XCTAssertEqual(fiveHourUpdated?.usedAmount ?? -1, 0.0, accuracy: 0.001)
        XCTAssertNil(fiveHourUpdated?.resetsAt)
    }

    func testClaudePlanUsageHistoryFallback() throws {
        let home = makeTempDir()
        defer { try? FileManager.default.removeItem(at: home) }

        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let claudeDesktopDir = home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDesktopDir, withIntermediateDirectories: true)

        let recentMs = Int64((now.timeIntervalSince1970 - 300) * 1000.0)
        let historyJSON = "{\"version\":2,\"samples\":[{\"t\":\(recentMs),\"org\":\"org-1\",\"u\":{\"sd\":94,\"fh\":12}}]}"
        try historyJSON.write(to: claudeDesktopDir.appendingPathComponent("plan-usage-history.json"), atomically: true, encoding: .utf8)

        let collector = LocalUsageCollector(homeDirectoryURL: home, allowLiveProbes: false)
        let card = AISubscription(
            providerKey: LocalProviderKey.claudeCode.rawValue,
            providerName: "Claude Code",
            windowType: .weekly,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )

        let collected = collector.collectUsage(for: card, now: now)
        XCTAssertEqual(collected.usedAmount, 94.0, accuracy: 0.001)
        XCTAssertEqual(collected.subtitle, "5sa: %12 • Haftalık: %94 (Önbellek)")
    }

    func testCodexAppServerResponseParsing() {
        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let primaryReset = Int(now.addingTimeInterval(3 * 3600).timeIntervalSince1970)
        let secondaryReset = Int(now.addingTimeInterval(4 * 86400).timeIntervalSince1970)
        let collector = LocalUsageCollector(homeDirectoryURL: makeTempDir(), allowLiveProbes: false)

        let payload = """
        {"id":1,"result":{"userAgent":"LimitWidget"}}
        {"method":"account/updated","params":{"planType":"plus"}}
        {"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":8,"windowDurationMins":300,"resetsAt":\(primaryReset)},"secondary":{"usedPercent":66,"windowDurationMins":10080,"resetsAt":\(secondaryReset)},"planType":"plus"}}}
        """
        let data = Data(payload.utf8)

        let weeklyCard = AISubscription(
            providerKey: LocalProviderKey.codex.rawValue,
            providerName: "Codex",
            windowType: .weekly,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let weeklyUpdated = collector.applyCodexAppServerData(data, to: weeklyCard, now: now)
        XCTAssertEqual(weeklyUpdated?.usedAmount ?? -1, 66.0, accuracy: 0.001)
        XCTAssertEqual(weeklyUpdated?.subtitle, "5sa: %8 • Haftalık: %66 (Plus)")
        XCTAssertEqual(weeklyUpdated?.resetsAt?.timeIntervalSince1970 ?? 0, Double(secondaryReset), accuracy: 1.0)

        let fiveHourCard = AISubscription(
            providerKey: LocalProviderKey.codex.rawValue,
            providerName: "Codex 5sa",
            windowType: .fiveHour,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let fiveHourUpdated = collector.applyCodexAppServerData(data, to: fiveHourCard, now: now)
        XCTAssertEqual(fiveHourUpdated?.usedAmount ?? -1, 8.0, accuracy: 0.001)
        XCTAssertEqual(fiveHourUpdated?.resetsAt?.timeIntervalSince1970 ?? 0, Double(primaryReset), accuracy: 1.0)
    }

    func testOpenCodeLiveQuotaParsing() {
        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let collector = LocalUsageCollector(homeDirectoryURL: makeTempDir(), allowLiveProbes: false)

        let payload = """
        {"usage":{"rolling":{"status":"ok","percent":0,"resetsAt":"2026-11-14T01:24:10.587Z"},"weekly":{"status":"ok","percent":6,"resetsAt":"2026-11-16T00:00:00.000Z"},"monthly":{"status":"ok","percent":19,"resetsAt":"2026-11-27T05:10:19.000Z"}}}
        """
        let data = Data(payload.utf8)

        let monthlyCard = AISubscription(
            providerKey: LocalProviderKey.opencode.rawValue,
            providerName: "OpenCode",
            windowType: .monthly,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let updated = collector.applyOpenCodeQuotaData(data, to: monthlyCard, now: now)
        XCTAssertEqual(updated?.usedAmount ?? -1, 19.0, accuracy: 0.001)
        XCTAssertEqual(updated?.totalLimit ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(updated?.subtitle, "5sa: %0 • Hft: %6 • Ay: %19 ($11.40/$60)")
        XCTAssertNotNil(updated?.resetsAt)

        let dollarCard = AISubscription(
            providerKey: LocalProviderKey.opencode.rawValue,
            providerName: "OpenCode ($)",
            windowType: .monthly,
            usedAmount: 0,
            totalLimit: 60,
            unitLabel: "$",
            dataSource: .localAuto
        )
        let dollarUpdated = collector.applyOpenCodeQuotaData(data, to: dollarCard, now: now)
        XCTAssertEqual(dollarUpdated?.usedAmount ?? -1, 11.40, accuracy: 0.001)
        XCTAssertEqual(dollarUpdated?.totalLimit ?? -1, 60.0, accuracy: 0.001)
    }

    func testAntigravityLiveQuotaParsing() {
        let now = Date(timeIntervalSince1970: 1_794_600_000)
        let collector = LocalUsageCollector(homeDirectoryURL: makeTempDir(), allowLiveProbes: false)

        let payload = """
        {
          "summary": {
            "groups": [
              {
                "displayName": "Claude and GPT models",
                "buckets": [
                  {"window": "weekly", "remainingFraction": 1, "resetTime": "2026-11-20T20:30:44Z"},
                  {"window": "5h", "remainingFraction": 1, "resetTime": "2026-11-14T01:30:44Z"}
                ]
              }
            ]
          },
          "quota": {
            "buckets": [
              {"modelId": "claude-opus-5-5-high", "remainingFraction": 1, "resetTime": "2026-11-14T01:30:44Z"},
              {"modelId": "gemini-3.8-flash-tiered", "remainingFraction": 0.89514667, "resetTime": "2026-11-14T00:46:17Z"},
              {"modelId": "tab_flash_lite_preview", "remainingFraction": 0.2}
            ]
          }
        }
        """
        let data = Data(payload.utf8)

        let card = AISubscription(
            providerKey: LocalProviderKey.antigravity.rawValue,
            providerName: "Antigravity",
            windowType: .fiveHour,
            usedAmount: 0,
            totalLimit: 100,
            unitLabel: "%",
            dataSource: .localAuto
        )
        let updated = collector.applyAntigravityQuotaData(data, to: card, now: now)
        XCTAssertNotNil(updated)
        XCTAssertEqual(updated?.usedAmount ?? -1, 10.49, accuracy: 0.01)
        XCTAssertEqual(updated?.totalLimit ?? -1, 100.0, accuracy: 0.001)
        XCTAssertEqual(updated?.subtitle, "Gemini: %10 • Claude/GPT: %0")
        XCTAssertNotNil(updated?.resetsAt)
    }

    @MainActor
    func testStoreAddUpdateDeleteAndSyncPreservesManualEntries() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("subscriptions.json")
        let repo = SubscriptionRepository(fileURL: fileURL)
        let emptyHome = tempDir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)

        let store = SubscriptionStore(
            repository: repo,
            collector: LocalUsageCollector(homeDirectoryURL: emptyHome),
            onDidPersist: {}
        )

        XCTAssertEqual(store.subscriptions.count, 4)

        var manualItem = AISubscription(providerName: "Manuel Servis", usedAmount: 95, totalLimit: 100, dataSource: .manual)
        store.add(manualItem)
        XCTAssertEqual(store.subscriptions.count, 5)
        XCTAssertEqual(store.highestUsagePercentage, 95)

        store.syncLocalUsage()
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == manualItem.id })?.usedAmount, 95)

        manualItem.usedAmount = 20
        store.update(manualItem)
        XCTAssertEqual(store.subscriptions.first(where: { $0.id == manualItem.id })?.usedAmount, 20)

        store.delete(id: manualItem.id)
        XCTAssertEqual(store.subscriptions.count, 4)
    }

    func testSubQuotaMetricsAndCompactSummaryParsing() {
        let claude = AISubscription(
            providerName: "Claude Code",
            subtitle: "5sa: %0 • Haftalık: %96 • Fable: %100",
            usedAmount: 96,
            totalLimit: 100,
            unitLabel: "%"
        )
        XCTAssertEqual(claude.compactSummaryText, "5sa: %0 • Haftalık: %96 • Fable: %100")
        XCTAssertEqual(
            claude.subQuotaMetrics,
            [
                SubQuotaMetric(label: "5sa", percentage: 0),
                SubQuotaMetric(label: "Haftalık", percentage: 96),
                SubQuotaMetric(label: "Fable", percentage: 100)
            ]
        )
        XCTAssertEqual(claude.subQuotaMetrics[0].severity, .normal)
        XCTAssertEqual(claude.subQuotaMetrics[1].severity, .critical)

        let opencode = AISubscription(
            providerName: "OpenCode",
            subtitle: "5sa: %0 • Hft: %6 • Ay: %19 ($11.40/$60)",
            usedAmount: 19,
            totalLimit: 100,
            unitLabel: "%"
        )
        XCTAssertEqual(
            opencode.subQuotaMetrics,
            [
                SubQuotaMetric(label: "5sa", percentage: 0),
                SubQuotaMetric(label: "Hft", percentage: 6),
                SubQuotaMetric(label: "Ay", percentage: 19)
            ]
        )

        let customDollar = AISubscription(
            providerName: "Özel API",
            subtitle: "Pro",
            usedAmount: 14,
            totalLimit: 20,
            unitLabel: "$"
        )
        XCTAssertEqual(customDollar.compactSummaryText, "$14 / $20 • Pro")
        XCTAssertTrue(customDollar.subQuotaMetrics.isEmpty)
    }

    @MainActor
    func testThemeModePersistenceAndCycling() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("subscriptions.json")
        let repo = SubscriptionRepository(fileURL: fileURL)
        let emptyHome = tempDir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyHome, withIntermediateDirectories: true)

        XCTAssertEqual(repo.loadThemeMode(), .system)

        let store = SubscriptionStore(
            repository: repo,
            collector: LocalUsageCollector(homeDirectoryURL: emptyHome),
            onDidPersist: {}
        )
        XCTAssertEqual(store.themeMode, .system)

        store.cycleThemeMode()
        XCTAssertEqual(store.themeMode, .dark)
        XCTAssertEqual(repo.loadThemeMode(), .dark)

        store.cycleThemeMode()
        XCTAssertEqual(store.themeMode, .light)
        XCTAssertEqual(repo.loadThemeMode(), .light)

        store.cycleThemeMode()
        XCTAssertEqual(store.themeMode, .system)
        XCTAssertEqual(repo.loadThemeMode(), .system)
    }

    private func makeTempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LimitWidgetTests-\(UUID().uuidString)", isDirectory: true)
    }
}
