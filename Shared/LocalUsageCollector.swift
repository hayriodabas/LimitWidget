import Darwin
import Foundation
import SQLite3

/// Claude Code, Antigravity, Codex ve OpenCode aboneliklerinin canlı kota ve yerel kullanım verilerini okur.
struct LocalUsageCollector: Sendable {
    let homeDirectoryURL: URL
    let allowLiveProbes: Bool

    init(
        homeDirectoryURL: URL = LocalUsageCollector.realHomeDirectoryURL(),
        allowLiveProbes: Bool? = nil
    ) {
        self.homeDirectoryURL = homeDirectoryURL
        if let allowLiveProbes {
            self.allowLiveProbes = allowLiveProbes
        } else {
            self.allowLiveProbes =
                homeDirectoryURL.standardizedFileURL.path == Self.realHomeDirectoryURL().standardizedFileURL.path
        }
    }

    static func realHomeDirectoryURL() -> URL {
        if let pw = getpwuid(getuid()), let dirPtr = pw.pointee.pw_dir {
            let path = String(cString: dirPtr)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Tüm yerel otomatik abonelikleri günceller; manuel ve API kayıtlarına dokunmaz.
    func refresh(_ subscriptions: [AISubscription], now: Date = Date()) -> [AISubscription] {
        let localAutoCount = subscriptions.reduce(0) { $0 + ($1.dataSource == .localAuto ? 1 : 0) }
        guard allowLiveProbes, localAutoCount > 1 else {
            return subscriptions.map { subscription in
                guard subscription.dataSource == .localAuto else {
                    return subscription
                }
                return collectUsage(for: subscription, now: now)
            }
        }

        let box = LockedSubscriptionBox(items: subscriptions)
        DispatchQueue.concurrentPerform(iterations: subscriptions.count) { index in
            let item = subscriptions[index]
            guard item.dataSource == .localAuto else { return }
            let updated = collectUsage(for: item, now: now)
            box.set(updated, at: index)
        }
        return box.snapshot()
    }

    /// Tek bir abonelik için uygun kota/kullanım okuyucusunu çalıştırır.
    func collectUsage(for subscription: AISubscription, now: Date = Date()) -> AISubscription {
        let effectiveKey = subscription.providerKey == LocalProviderKey.custom.rawValue
            ? AISubscription.inferProviderKey(from: subscription.providerName)
            : subscription.providerKey

        switch effectiveKey {
        case LocalProviderKey.claudeCode.rawValue:
            return collectClaudeUsage(subscription, now: now)
        case LocalProviderKey.antigravity.rawValue:
            return collectAntigravityUsage(subscription, now: now)
        case LocalProviderKey.codex.rawValue:
            return collectCodexUsage(subscription, now: now)
        case LocalProviderKey.opencode.rawValue:
            return collectOpenCodeUsage(subscription, now: now)
        default:
            return subscription
        }
    }

    // MARK: - Claude Code

    private func collectClaudeUsage(_ subscription: AISubscription, now: Date) -> AISubscription {
        if allowLiveProbes,
           let liveData = fetchClaudeLiveControlResponse(),
           let liveUpdated = applyClaudeControlResponseData(liveData, to: subscription, now: now) {
            return liveUpdated
        }

        let planHistoryURL = homeDirectoryURL
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        if let historyData = try? Data(contentsOf: planHistoryURL),
           let cachedUpdated = applyClaudePlanHistoryData(historyData, to: subscription, now: now) {
            return cachedUpdated
        }

        return collectClaudeLocalTranscriptFallback(subscription, now: now)
    }

    func applyClaudeControlResponseData(
        _ data: Data,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription? {
        guard let controlObj = firstMatchingJSONLine(in: data, matchingType: "control_response"),
              let outerResponse = controlObj["response"] as? [String: Any],
              (outerResponse["subtype"] as? String) == "success",
              let payload = outerResponse["response"] as? [String: Any],
              let rateLimits = payload["rate_limits"] as? [String: Any] else {
            return nil
        }

        if let available = payload["rate_limits_available"] as? Bool, !available {
            return nil
        }

        let isoWithFractional = makeISOFormatter(fractionalSeconds: true)
        let isoBasic = makeISOFormatter(fractionalSeconds: false)

        let sevenDayDict = rateLimits["seven_day"] as? [String: Any]
        let fiveHourDict = rateLimits["five_hour"] as? [String: Any]

        var weeklyUtil = doubleValueIfPresent(sevenDayDict?["utilization"])
        var weeklyReset = (sevenDayDict?["resets_at"] as? String).flatMap {
            parseISODate($0, fractional: isoWithFractional, basic: isoBasic)
        }

        var fiveHourUtil = doubleValueIfPresent(fiveHourDict?["utilization"])
        var fiveHourReset = (fiveHourDict?["resets_at"] as? String).flatMap {
            parseISODate($0, fractional: isoWithFractional, basic: isoBasic)
        }

        if let limits = rateLimits["limits"] as? [[String: Any]] {
            for item in limits {
                let kind = item["kind"] as? String
                if kind == "weekly_all" {
                    if weeklyUtil == nil { weeklyUtil = doubleValueIfPresent(item["percent"]) }
                    if weeklyReset == nil, let rawReset = item["resets_at"] as? String {
                        weeklyReset = parseISODate(rawReset, fractional: isoWithFractional, basic: isoBasic)
                    }
                } else if kind == "session" {
                    if fiveHourUtil == nil { fiveHourUtil = doubleValueIfPresent(item["percent"]) }
                    if fiveHourReset == nil, let rawReset = item["resets_at"] as? String {
                        fiveHourReset = parseISODate(rawReset, fractional: isoWithFractional, basic: isoBasic)
                    }
                }
            }
        }

        guard weeklyUtil != nil || fiveHourUtil != nil else {
            return nil
        }

        let resolvedFiveHour = fiveHourUtil ?? 0.0
        let resolvedWeekly = weeklyUtil ?? 0.0

        var modelSummary: String?
        if let scopedModels = rateLimits["model_scoped"] as? [[String: Any]],
           let firstScoped = scopedModels.first,
           let modelName = firstScoped["display_name"] as? String,
           let modelPercent = doubleValueIfPresent(firstScoped["utilization"]) {
            modelSummary = "\(modelName): %\(Int(modelPercent.rounded()))"
        }

        var subtitleParts = [
            "5sa: %\(Int(resolvedFiveHour.rounded()))",
            "Haftalık: %\(Int(resolvedWeekly.rounded()))"
        ]
        if let modelSummary {
            subtitleParts.append(modelSummary)
        }

        var updated = subscription
        if subscription.windowType == .fiveHour {
            updated.usedAmount = roundTwoDecimals(resolvedFiveHour)
            updated.resetsAt = fiveHourReset
            updated.resetDescription = fiveHourReset == nil ? "5 saatlik pencere" : nil
        } else {
            updated.usedAmount = roundTwoDecimals(resolvedWeekly)
            updated.resetsAt = weeklyReset
            updated.resetDescription = weeklyReset == nil ? "Haftalık pencere" : nil
        }
        updated.totalLimit = 100
        updated.unitLabel = "%"
        updated.subtitle = subtitleParts.joined(separator: " • ")
        updated.lastUpdated = now
        return updated
    }

    func applyClaudePlanHistoryData(
        _ data: Data,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]],
              let latest = samples.last,
              let usageMap = latest["u"] as? [String: Any] else {
            return nil
        }

        if let tsMs = doubleValueIfPresent(latest["t"]) {
            let sampleDate = Date(timeIntervalSince1970: tsMs / 1000.0)
            if now.timeIntervalSince(sampleDate) > 7 * 24 * 3600 {
                return nil
            }
        }

        let weekly = doubleValueIfPresent(usageMap["sd"])
        let fiveHour = doubleValueIfPresent(usageMap["fh"])
        guard weekly != nil || fiveHour != nil else {
            return nil
        }

        let resolvedFiveHour = fiveHour ?? 0.0
        let resolvedWeekly = weekly ?? 0.0

        var updated = subscription
        updated.usedAmount = roundTwoDecimals(subscription.windowType == .fiveHour ? resolvedFiveHour : resolvedWeekly)
        updated.totalLimit = 100
        updated.unitLabel = "%"
        updated.resetsAt = nil
        updated.resetDescription = subscription.windowType == .fiveHour ? "5 saatlik pencere (Önbellek)" : "Haftalık pencere (Önbellek)"
        updated.subtitle = "5sa: %\(Int(resolvedFiveHour.rounded())) • Haftalık: %\(Int(resolvedWeekly.rounded())) (Önbellek)"
        updated.lastUpdated = now
        return updated
    }

    private func fetchClaudeLiveControlResponse() -> Data? {
        let candidates = [
            homeDirectoryURL.appendingPathComponent(".local/bin/claude").path,
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            homeDirectoryURL.appendingPathComponent("homebrew/bin/claude").path
        ]
        guard let claudeURL = resolveExecutable(candidates: candidates) else {
            return nil
        }

        let req = "{\"type\":\"control_request\",\"request_id\":\"usage-1\",\"request\":{\"subtype\":\"get_usage\",\"skip_behaviors\":true}}\n"
        return runOneShotProcess(
            executable: claudeURL,
            arguments: [
                "--print",
                "--input-format", "stream-json",
                "--output-format", "stream-json",
                "--verbose",
                "--no-session-persistence",
                "--strict-mcp-config",
                "--mcp-config", "{\"mcpServers\":{}}",
                "--setting-sources", "",
                "--settings", "{\"disableAllHooks\":true}"
            ],
            stdinString: req,
            timeout: 10.0
        )
    }

    private func collectClaudeLocalTranscriptFallback(_ subscription: AISubscription, now: Date) -> AISubscription {
        let projectsDir = homeDirectoryURL
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)

        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            return subscription
        }

        let windowSeconds = subscription.windowType.windowSeconds
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let files = recentFiles(in: projectsDir, suffix: ".jsonl", modifiedAfter: cutoff)

        let isoWithFractional = makeISOFormatter(fractionalSeconds: true)
        let isoBasic = makeISOFormatter(fractionalSeconds: false)

        var uniqueResponses: [String: (date: Date, tokens: Int)] = [:]
        var fallbackIndex = 0

        for file in files {
            enumerateMatchingLines(in: file, containing: "\"usage\"") { line in
                guard let obj = parseJSONDictionary(line),
                      let tsString = obj["timestamp"] as? String,
                      let date = parseISODate(tsString, fractional: isoWithFractional, basic: isoBasic),
                      date >= cutoff,
                      date <= now.addingTimeInterval(60),
                      let message = obj["message"] as? [String: Any],
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let responseKey: String
                if let msgID = message["id"] as? String, !msgID.isEmpty {
                    responseKey = msgID
                } else if let reqID = obj["requestId"] as? String, !reqID.isEmpty {
                    responseKey = reqID
                } else {
                    fallbackIndex += 1
                    responseKey = "row_\(fallbackIndex)"
                }

                let tokens = intValue(usage["input_tokens"])
                    + intValue(usage["output_tokens"])
                    + intValue(usage["cache_creation_input_tokens"])
                    + intValue(usage["cache_read_input_tokens"])

                if let existing = uniqueResponses[responseKey] {
                    uniqueResponses[responseKey] = (min(existing.date, date), max(existing.tokens, tokens))
                } else {
                    uniqueResponses[responseKey] = (date, tokens)
                }
            }
        }

        let turns = uniqueResponses.count
        let totalTokens = uniqueResponses.values.reduce(0) { $0 + $1.tokens }
        let earliestInWindow = uniqueResponses.values.map(\.date).min()

        var updated = subscription
        if subscription.unitLabel == "M token" {
            updated.usedAmount = roundTwoDecimals(Double(totalTokens) / 1_000_000.0)
        } else if subscription.unitLabel == "%" {
            let estimatedCap = subscription.windowType == .fiveHour ? 3000.0 : 15000.0
            updated.usedAmount = roundTwoDecimals(min(Double(turns) / estimatedCap * 100.0, 100.0))
        } else {
            updated.usedAmount = Double(turns)
        }
        updated.subtitle = "Yerel kayıt (\(subscription.windowType.shortLabel)): \(turns) yanıt • \(Self.formatTokenCount(totalTokens))"
        updated.resetsAt = earliestInWindow?.addingTimeInterval(windowSeconds)
        updated.resetDescription = turns == 0 ? "Pencerede kullanım yok" : nil
        updated.lastUpdated = now
        return updated
    }

    // MARK: - Antigravity

    private func collectAntigravityUsage(_ subscription: AISubscription, now: Date) -> AISubscription {
        if allowLiveProbes,
           let liveData = fetchAntigravityLiveQuotaData(),
           let liveUpdated = applyAntigravityQuotaData(liveData, to: subscription, now: now) {
            return liveUpdated
        }

        return collectAntigravityLocalFallback(subscription, now: now)
    }

    func applyAntigravityQuotaData(
        _ data: Data,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let isoWithFractional = makeISOFormatter(fractionalSeconds: true)
        let isoBasic = makeISOFormatter(fractionalSeconds: false)

        var claudeGptFiveHourUsed: Double?
        var claudeGptFiveHourReset: Date?
        var claudeGptWeeklyUsed: Double?
        var claudeGptWeeklyReset: Date?

        if let summary = root["summary"] as? [String: Any],
           let groups = summary["groups"] as? [[String: Any]] {
            for group in groups {
                let buckets = group["buckets"] as? [[String: Any]] ?? []
                for bucket in buckets {
                    guard let remaining = doubleValueIfPresent(bucket["remainingFraction"]) else { continue }
                    let usedPct = max(0.0, min(100.0, (1.0 - remaining) * 100.0))
                    let resetDate = (bucket["resetTime"] as? String).flatMap {
                        parseISODate($0, fractional: isoWithFractional, basic: isoBasic)
                    }
                    let windowRaw = (bucket["window"] as? String ?? "").lowercased()
                    if windowRaw == "weekly" || windowRaw == "7d" {
                        claudeGptWeeklyUsed = max(claudeGptWeeklyUsed ?? 0.0, usedPct)
                        if claudeGptWeeklyReset == nil { claudeGptWeeklyReset = resetDate }
                    } else if windowRaw == "5h" || windowRaw == "session" {
                        claudeGptFiveHourUsed = max(claudeGptFiveHourUsed ?? 0.0, usedPct)
                        if claudeGptFiveHourReset == nil { claudeGptFiveHourReset = resetDate }
                    }
                }
            }
        }

        var geminiUsed: Double?
        var geminiReset: Date?
        var bucketClaudeGptUsed: Double?
        var bucketClaudeGptReset: Date?

        if let quota = root["quota"] as? [String: Any],
           let buckets = quota["buckets"] as? [[String: Any]] {
            for bucket in buckets {
                guard let modelID = bucket["modelId"] as? String else { continue }
                let lowerID = modelID.lowercased()
                if lowerID.hasPrefix("chat_") || lowerID.hasPrefix("tab_") {
                    continue
                }
                guard let remaining = doubleValueIfPresent(bucket["remainingFraction"]) else { continue }
                let usedPct = max(0.0, min(100.0, (1.0 - remaining) * 100.0))
                let resetDate = (bucket["resetTime"] as? String).flatMap {
                    parseISODate($0, fractional: isoWithFractional, basic: isoBasic)
                }

                if lowerID.contains("gemini") {
                    if let current = geminiUsed {
                        if usedPct > current {
                            geminiUsed = usedPct
                            geminiReset = resetDate
                        }
                    } else {
                        geminiUsed = usedPct
                        geminiReset = resetDate
                    }
                } else if lowerID.contains("claude") || lowerID.contains("gpt") {
                    if let current = bucketClaudeGptUsed {
                        if usedPct > current {
                            bucketClaudeGptUsed = usedPct
                            bucketClaudeGptReset = resetDate
                        }
                    } else {
                        bucketClaudeGptUsed = usedPct
                        bucketClaudeGptReset = resetDate
                    }
                }
            }
        }

        let effectiveClaudeGpt = subscription.windowType == .weekly
            ? (claudeGptWeeklyUsed ?? bucketClaudeGptUsed ?? claudeGptFiveHourUsed)
            : (claudeGptFiveHourUsed ?? bucketClaudeGptUsed)
        let effectiveClaudeGptReset = subscription.windowType == .weekly
            ? (claudeGptWeeklyReset ?? bucketClaudeGptReset ?? claudeGptFiveHourReset)
            : (claudeGptFiveHourReset ?? bucketClaudeGptReset)

        guard geminiUsed != nil || effectiveClaudeGpt != nil else {
            return nil
        }

        let resolvedGemini = geminiUsed ?? 0.0
        let resolvedClaudeGpt = effectiveClaudeGpt ?? 0.0
        let primaryUsed = max(resolvedGemini, resolvedClaudeGpt)
        let primaryReset: Date? = resolvedGemini >= resolvedClaudeGpt
            ? (geminiReset ?? effectiveClaudeGptReset)
            : (effectiveClaudeGptReset ?? geminiReset)

        var updated = subscription
        updated.usedAmount = roundTwoDecimals(primaryUsed)
        updated.totalLimit = 100
        updated.unitLabel = "%"
        updated.resetsAt = primaryReset
        updated.resetDescription = primaryReset == nil ? "Antigravity kotası" : nil
        updated.subtitle = "Gemini: %\(Int(resolvedGemini.rounded())) • Claude/GPT: %\(Int(resolvedClaudeGpt.rounded()))"
        updated.lastUpdated = now
        return updated
    }

    private func fetchAntigravityLiveQuotaData() -> Data? {
        let omniRouteDir = homeDirectoryURL.appendingPathComponent(".omniroute", isDirectory: true)
        let dbURL = omniRouteDir.appendingPathComponent("storage.sqlite")
        let envURL = omniRouteDir.appendingPathComponent(".env")
        let serverJSCandidates = [
            homeDirectoryURL.appendingPathComponent(".npm-global/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js").path,
            "/opt/homebrew/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js",
            "/usr/local/lib/node_modules/omniroute/dist/open-sse/mcp-server/server.js"
        ]
        guard let serverJSPath = serverJSCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }),
              FileManager.default.fileExists(atPath: dbURL.path),
              FileManager.default.fileExists(atPath: envURL.path) else {
            return nil
        }

        let nodeCandidates = [
            "/usr/local/bin/node",
            homeDirectoryURL.appendingPathComponent(".local/bin/node").path,
            homeDirectoryURL.appendingPathComponent(".hermes/node/bin/node").path,
            homeDirectoryURL.appendingPathComponent("homebrew/bin/node").path,
            "/opt/homebrew/bin/node"
        ]
        guard let nodeURL = resolveExecutable(candidates: nodeCandidates) else {
            return nil
        }

        let jsScript = """
        import fs from "fs";
        import path from "path";
        import crypto from "crypto";
        import { DatabaseSync } from "node:sqlite";

        const home = process.env.LIMITWIDGET_HOME || process.env.HOME;
        const serverPath = process.env.OMNIROUTE_SERVER_JS;
        const srv = fs.readFileSync(serverPath, "utf8");
        const edIdx = srv.indexOf("EMBEDDED_DEFAULTS = {");
        if (edIdx === -1) process.exit(1);
        const edSlice = srv.slice(edIdx, edIdx + 8000);
        const mask = "omniroute-public-v1";
        function extractArr(name) {
          const m = edSlice.match(new RegExp(name + ":\\\\s*\\\\[([0-9,\\\\s]+)\\\\]"));
          if (!m) return null;
          const bytes = m[1].split(",").map(s => parseInt(s.trim(), 10)).filter(n => !Number.isNaN(n));
          return Buffer.from(bytes.map((b, i) => b ^ mask.charCodeAt(i % mask.length))).toString("utf8");
        }
        const cid = extractArr("antigravity_id");
        const csec = extractArr("antigravity_alt");
        if (!cid || !csec) process.exit(1);

        let secret = null;
        for (const line of fs.readFileSync(path.join(home, ".omniroute", ".env"), "utf8").split("\\n")) {
          if (line.trim().startsWith("STORAGE_ENCRYPTION_KEY=")) {
            secret = line.trim().split("=", 2)[1].replace(/^["'](.*)["']$/, "$1");
          }
        }
        if (!secret) process.exit(1);
        const key = crypto.scryptSync(secret, "omniroute-field-encryption-v1", 32);
        function dec(v) {
          if (!v || !v.startsWith("enc:v1:")) return v;
          const [ivHex, encHex, tagHex] = v.slice(7).split(":");
          const d = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(ivHex, "hex"));
          d.setAuthTag(Buffer.from(tagHex, "hex"));
          return d.update(encHex, "hex", "utf8") + d.final("utf8");
        }

        const db = new DatabaseSync(path.join(home, ".omniroute", "storage.sqlite"), { readOnly: true });
        const row = db.prepare(
          "SELECT provider, refresh_token, project_id FROM provider_connections WHERE provider IN ('antigravity', 'agy') AND is_active = 1 AND refresh_token IS NOT NULL ORDER BY CASE WHEN provider = 'antigravity' THEN 0 ELSE 1 END LIMIT 1"
        ).get();
        if (!row) process.exit(1);
        const rt = dec(row.refresh_token);
        if (!rt) process.exit(1);

        const tokRes = await fetch("https://oauth2.googleapis.com/token", {
          method: "POST",
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          body: new URLSearchParams({
            client_id: cid,
            client_secret: csec,
            refresh_token: rt,
            grant_type: "refresh_token"
          }),
          signal: AbortSignal.timeout(6000)
        });
        if (!tokRes.ok) process.exit(1);
        const tokData = await tokRes.json();
        const accessToken = tokData.access_token;
        if (!accessToken) process.exit(1);

        async function postQuota(endpoint) {
          const res = await fetch(`https://daily-cloudcode-pa.googleapis.com/v1internal:${endpoint}`, {
            method: "POST",
            headers: {
              "Authorization": `Bearer ${accessToken}`,
              "Content-Type": "application/json",
              "User-Agent": "antigravity/1.104.0 (darwin; arm64)"
            },
            body: JSON.stringify(row.project_id ? { project: row.project_id } : {}),
            signal: AbortSignal.timeout(6000)
          });
          return res.ok ? await res.json() : null;
        }

        const [summary, quota] = await Promise.all([
          postQuota("retrieveUserQuotaSummary"),
          postQuota("retrieveUserQuota")
        ]);
        process.stdout.write(JSON.stringify({ summary, quota }) + "\\n");
        """

        return runOneShotProcess(
            executable: nodeURL,
            arguments: ["--no-warnings", "--input-type=module", "-e", jsScript],
            stdinString: nil,
            extraEnv: [
                "LIMITWIDGET_HOME": homeDirectoryURL.path,
                "OMNIROUTE_SERVER_JS": serverJSPath
            ],
            timeout: 10.0
        )
    }

    private func collectAntigravityLocalFallback(_ subscription: AISubscription, now: Date) -> AISubscription {
        let brainDir = homeDirectoryURL
            .appendingPathComponent(".gemini", isDirectory: true)
            .appendingPathComponent("antigravity", isDirectory: true)
            .appendingPathComponent("brain", isDirectory: true)

        guard FileManager.default.fileExists(atPath: brainDir.path) else {
            return subscription
        }

        let windowSeconds = subscription.windowType.windowSeconds
        let cutoff = now.addingTimeInterval(-windowSeconds)
        let files = antigravityTranscriptFiles(in: brainDir, modifiedAfter: cutoff)

        let isoWithFractional = makeISOFormatter(fractionalSeconds: true)
        let isoBasic = makeISOFormatter(fractionalSeconds: false)

        var turns = 0
        var earliestInWindow: Date?

        for file in files {
            enumerateMatchingLines(in: file, containing: "PLANNER_RESPONSE") { line in
                guard let obj = parseJSONDictionary(line),
                      (obj["type"] as? String) == "PLANNER_RESPONSE",
                      let createdString = obj["created_at"] as? String,
                      let date = parseISODate(createdString, fractional: isoWithFractional, basic: isoBasic),
                      date >= cutoff,
                      date <= now.addingTimeInterval(60) else {
                    return
                }

                turns += 1
                if let currentEarliest = earliestInWindow {
                    if date < currentEarliest { earliestInWindow = date }
                } else {
                    earliestInWindow = date
                }
            }
        }

        var updated = subscription
        if subscription.unitLabel == "%" {
            updated.usedAmount = roundTwoDecimals(min(Double(turns) / 200.0 * 100.0, 100.0))
        } else {
            updated.usedAmount = Double(turns)
        }
        updated.subtitle = "Yerel ajan kaydı • \(turns) adım (\(subscription.windowType.shortLabel))"
        updated.resetsAt = earliestInWindow?.addingTimeInterval(windowSeconds)
        updated.resetDescription = turns == 0 ? "Pencerede kullanım yok" : nil
        updated.lastUpdated = now
        return updated
    }

    // MARK: - Codex

    private struct CodexRateLimitSnapshot {
        let primaryUsedPercent: Double
        let primaryResetsAt: Date?
        let secondaryUsedPercent: Double
        let secondaryResetsAt: Date?
        let subtitleTag: String?
    }

    private func collectCodexUsage(_ subscription: AISubscription, now: Date) -> AISubscription {
        if allowLiveProbes,
           let liveData = fetchCodexLiveRateLimits(),
           let liveUpdated = applyCodexAppServerData(liveData, to: subscription, now: now) {
            return liveUpdated
        }

        let codexDir = homeDirectoryURL.appendingPathComponent(".codex", isDirectory: true)
        guard FileManager.default.fileExists(atPath: codexDir.path),
              let snapshot = latestCodexSnapshot(in: codexDir) else {
            return subscription
        }

        return applyCodexSnapshot(snapshot, to: subscription, now: now)
    }

    func applyCodexAppServerData(
        _ data: Data,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription? {
        guard let linesText = String(data: data, encoding: .utf8) else {
            return nil
        }

        var targetResult: [String: Any]?
        for rawLine in linesText.split(whereSeparator: \.isNewline) {
            guard let obj = parseJSONDictionary(String(rawLine)),
                  let idNum = obj["id"] as? NSNumber,
                  idNum.intValue == 2,
                  let result = obj["result"] as? [String: Any] else {
                continue
            }
            targetResult = result
            break
        }

        guard let result = targetResult else {
            return nil
        }

        let byLimitID = result["rateLimitsByLimitId"] as? [String: Any]
        guard let rateLimits = (result["rateLimits"] as? [String: Any])
            ?? (byLimitID?["codex"] as? [String: Any]) else {
            return nil
        }

        let primary = rateLimits["primary"] as? [String: Any]
        let secondary = rateLimits["secondary"] as? [String: Any]
        let planType = (rateLimits["planType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let formattedPlan = planType.flatMap { $0.isEmpty ? nil : $0.capitalized }

        let snapshot = CodexRateLimitSnapshot(
            primaryUsedPercent: doubleValue(primary?["usedPercent"]),
            primaryResetsAt: epochDate(primary?["resetsAt"]),
            secondaryUsedPercent: doubleValue(secondary?["usedPercent"]),
            secondaryResetsAt: epochDate(secondary?["resetsAt"]),
            subtitleTag: formattedPlan
        )
        return applyCodexSnapshot(snapshot, to: subscription, now: now)
    }

    private func applyCodexSnapshot(
        _ snapshot: CodexRateLimitSnapshot,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription {
        let activePrimaryPercent: Double
        if let primaryReset = snapshot.primaryResetsAt, primaryReset > now {
            activePrimaryPercent = snapshot.primaryUsedPercent
        } else {
            activePrimaryPercent = 0
        }

        let activeSecondaryPercent: Double
        if let secondaryReset = snapshot.secondaryResetsAt, secondaryReset > now {
            activeSecondaryPercent = snapshot.secondaryUsedPercent
        } else {
            activeSecondaryPercent = 0
        }

        var updated = subscription
        if subscription.windowType == .fiveHour {
            updated.usedAmount = roundTwoDecimals(activePrimaryPercent)
            updated.resetsAt = (snapshot.primaryResetsAt ?? .distantPast) > now ? snapshot.primaryResetsAt : nil
            updated.resetDescription = updated.resetsAt == nil ? "5 saatlik pencere sıfır" : nil
        } else {
            updated.usedAmount = roundTwoDecimals(activeSecondaryPercent)
            updated.resetsAt = (snapshot.secondaryResetsAt ?? .distantPast) > now ? snapshot.secondaryResetsAt : nil
            updated.resetDescription = updated.resetsAt == nil ? "Haftalık pencere sıfır" : nil
        }
        updated.totalLimit = 100
        updated.unitLabel = "%"

        let tagSuffix = snapshot.subtitleTag.map { " (\($0))" } ?? ""
        updated.subtitle = "5sa: %\(Int(activePrimaryPercent.rounded())) • Haftalık: %\(Int(activeSecondaryPercent.rounded()))\(tagSuffix)"
        updated.lastUpdated = now
        return updated
    }

    private func fetchCodexLiveRateLimits() -> Data? {
        let candidates = [
            homeDirectoryURL.appendingPathComponent(".npm-global/bin/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            homeDirectoryURL.appendingPathComponent(".local/bin/codex").path,
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            homeDirectoryURL.appendingPathComponent("homebrew/bin/codex").path
        ]
        guard let codexURL = resolveExecutable(candidates: candidates) else {
            return nil
        }

        let process = Process()
        process.executableURL = codexURL
        process.arguments = ["app-server"]
        process.environment = enrichedEnvironment()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let rpcPayload = [
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"LimitWidget\",\"version\":\"1.0\"}}}",
            "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}",
            "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}"
        ].joined(separator: "\n") + "\n"

        if let data = rpcPayload.data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
        }

        let state = LockedCodexBuffer()
        let semaphore = DispatchSemaphore(value: 0)
        let stdoutHandle = stdoutPipe.fileHandleForReading

        stdoutHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                semaphore.signal()
                return
            }
            if state.appendAndCheckReady(chunk) {
                semaphore.signal()
            }
        }

        _ = semaphore.wait(timeout: .now() + 7.0)
        stdoutHandle.readabilityHandler = nil
        try? stdinPipe.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
        }
        process.waitUntilExit()

        return state.matchedData()
    }

    private func latestCodexSnapshot(in codexDir: URL) -> CodexRateLimitSnapshot? {
        var candidates: [(url: URL, model: String?)] = []
        let dbURL = codexDir.appendingPathComponent("state_5.sqlite")

        if FileManager.default.fileExists(atPath: dbURL.path) {
            withReadOnlySQLite(at: dbURL) { db in
                let sql = "SELECT rollout_path, COALESCE(model, '') FROM threads WHERE rollout_path != '' ORDER BY updated_at DESC LIMIT 10"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                    return
                }
                defer { sqlite3_finalize(stmt) }

                while sqlite3_step(stmt) == SQLITE_ROW {
                    guard let pathPtr = sqlite3_column_text(stmt, 0) else { continue }
                    let rawPath = String(cString: pathPtr)
                    let fileURL = resolveCodexRolloutURL(rawPath, codexDir: codexDir)
                    let modelText = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                    let cleanModel = (modelText?.isEmpty == false) ? modelText : nil
                    candidates.append((fileURL, cleanModel))
                }
            }
        }

        if candidates.isEmpty {
            let sessionsDir = codexDir.appendingPathComponent("sessions", isDirectory: true)
            let files = recentFiles(in: sessionsDir, suffix: ".jsonl", modifiedAfter: .distantPast)
                .sorted { fileModificationDate($0) > fileModificationDate($1) }
            candidates = files.prefix(10).map { ($0, nil) }
        }

        for candidate in candidates {
            guard FileManager.default.fileExists(atPath: candidate.url.path) else { continue }
            var lastRateLimits: [String: Any]?
            enumerateMatchingLines(in: candidate.url, containing: "rate_limits") { line in
                guard let obj = parseJSONDictionary(line),
                      let payload = obj["payload"] as? [String: Any],
                      let rateLimits = payload["rate_limits"] as? [String: Any] else {
                    return
                }
                lastRateLimits = rateLimits
            }

            if let rateLimits = lastRateLimits {
                let primary = rateLimits["primary"] as? [String: Any]
                let secondary = rateLimits["secondary"] as? [String: Any]
                return CodexRateLimitSnapshot(
                    primaryUsedPercent: doubleValue(primary?["used_percent"]),
                    primaryResetsAt: epochDate(primary?["resets_at"]),
                    secondaryUsedPercent: doubleValue(secondary?["used_percent"]),
                    secondaryResetsAt: epochDate(secondary?["resets_at"]),
                    subtitleTag: candidate.model
                )
            }
        }

        return nil
    }

    private func resolveCodexRolloutURL(_ rawPath: String, codexDir: URL) -> URL {
        if FileManager.default.fileExists(atPath: rawPath) {
            return URL(fileURLWithPath: rawPath)
        }
        if let range = rawPath.range(of: "/.codex/") {
            let relative = String(rawPath[range.upperBound...])
            return codexDir.appendingPathComponent(relative)
        }
        return URL(fileURLWithPath: rawPath)
    }

    // MARK: - OpenCode

    private func collectOpenCodeUsage(_ subscription: AISubscription, now: Date) -> AISubscription {
        if allowLiveProbes,
           let liveData = fetchOpenCodeLiveQuota(),
           let liveUpdated = applyOpenCodeQuotaData(liveData, to: subscription, now: now) {
            return liveUpdated
        }

        return collectOpenCodeLocalDBFallback(subscription, now: now)
    }

    func applyOpenCodeQuotaData(
        _ data: Data,
        to subscription: AISubscription,
        now: Date
    ) -> AISubscription? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            return nil
        }

        let isoWithFractional = makeISOFormatter(fractionalSeconds: true)
        let isoBasic = makeISOFormatter(fractionalSeconds: false)

        func parseWindow(_ dict: [String: Any]?) -> (percent: Double, resetAt: Date?)? {
            guard let dict else { return nil }
            let status = (dict["status"] as? String ?? "ok").lowercased()
            let resetAt = (dict["resetsAt"] as? String).flatMap {
                parseISODate($0, fractional: isoWithFractional, basic: isoBasic)
            }
            if status == "rate-limited" {
                return (100.0, resetAt)
            }
            guard let pct = doubleValueIfPresent(dict["percent"]) else {
                return nil
            }
            return (max(0.0, min(100.0, pct)), resetAt)
        }

        let rolling = parseWindow(usage["rolling"] as? [String: Any])
        let weekly = parseWindow(usage["weekly"] as? [String: Any])
        let monthly = parseWindow(usage["monthly"] as? [String: Any])

        guard rolling != nil || weekly != nil || monthly != nil else {
            return nil
        }

        let rPct = rolling?.percent ?? 0.0
        let wPct = weekly?.percent ?? 0.0
        let mPct = monthly?.percent ?? 0.0

        let selected: (percent: Double, resetAt: Date?, capDollars: Double)
        switch subscription.windowType {
        case .fiveHour:
            selected = (rPct, rolling?.resetAt, 12.0)
        case .weekly:
            selected = (wPct, weekly?.resetAt, 30.0)
        default:
            selected = (mPct, monthly?.resetAt, 60.0)
        }

        var updated = subscription
        if subscription.unitLabel == "$" {
            updated.usedAmount = roundTwoDecimals(selected.percent / 100.0 * selected.capDollars)
            updated.totalLimit = selected.capDollars
            updated.unitLabel = "$"
        } else {
            updated.usedAmount = roundTwoDecimals(selected.percent)
            updated.totalLimit = 100
            updated.unitLabel = "%"
        }

        let monthlyUsedDollars = roundTwoDecimals(mPct / 100.0 * 60.0)
        updated.subtitle = "5sa: %\(Int(rPct.rounded())) • Hft: %\(Int(wPct.rounded())) • Ay: %\(Int(mPct.rounded())) ($\(AISubscription.formatNumber(monthlyUsedDollars))/$60)"
        updated.resetsAt = selected.resetAt
        updated.resetDescription = selected.resetAt == nil ? "\(subscription.windowType.shortLabel) penceresi" : nil
        updated.lastUpdated = now
        return updated
    }

    private func fetchOpenCodeLiveQuota() -> Data? {
        let authURL = homeDirectoryURL
            .appendingPathComponent(".local/share/opencode/auth.json")
        guard let authData = try? Data(contentsOf: authURL),
              let authRoot = try? JSONSerialization.jsonObject(with: authData) as? [String: Any] else {
            return nil
        }

        let goEntry = authRoot["opencode-go"] as? [String: Any]
        let defaultEntry = authRoot["opencode"] as? [String: Any]
        guard let apiKey = (goEntry?["key"] as? String) ?? (defaultEntry?["key"] as? String),
              !apiKey.isEmpty,
              let url = URL(string: "https://opencode.ai/zen/go/v1/usage") else {
            return nil
        }

        var request = URLRequest(url: url, timeoutInterval: 8.0)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("opencode/latest/1.4.3/cli", forHTTPHeaderField: "User-Agent")
        request.setValue("desktop", forHTTPHeaderField: "x-opencode-client")
        request.setValue("global", forHTTPHeaderField: "x-opencode-project")
        request.setValue("ses_limitwidget", forHTTPHeaderField: "x-opencode-session")

        let box = LockedDataBox()
        let semaphore = DispatchSemaphore(value: 0)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8.0
        config.timeoutIntervalForResource = 8.0
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            if let http = response as? HTTPURLResponse,
               (200..<300).contains(http.statusCode),
               let data {
                box.set(data)
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 9.0)
        session.finishTasksAndInvalidate()
        return box.get()
    }

    private func collectOpenCodeLocalDBFallback(_ subscription: AISubscription, now: Date) -> AISubscription {
        let dbURL = homeDirectoryURL
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.db")

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return subscription
        }

        let cutoff = now.addingTimeInterval(-subscription.windowType.windowSeconds)
        let cutoffMs = Int64(cutoff.timeIntervalSince1970 * 1000.0)

        var sessionCount = 0
        var totalCost = 0.0
        var totalTokens = 0
        var querySucceeded = false

        withReadOnlySQLite(at: dbURL) { db in
            let sql = """
            SELECT COUNT(*), COALESCE(SUM(cost), 0.0), COALESCE(SUM(tokens_input + tokens_output), 0)
            FROM session
            WHERE time_updated >= ?1
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
                return
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, cutoffMs)
            if sqlite3_step(stmt) == SQLITE_ROW {
                sessionCount = Int(sqlite3_column_int64(stmt, 0))
                totalCost = sqlite3_column_double(stmt, 1)
                totalTokens = Int(sqlite3_column_int64(stmt, 2))
                querySucceeded = true
            }
        }

        guard querySucceeded else {
            return subscription
        }

        var updated = subscription
        switch subscription.unitLabel {
        case "$":
            updated.usedAmount = roundTwoDecimals(totalCost)
        case "M token":
            updated.usedAmount = roundTwoDecimals(Double(totalTokens) / 1_000_000.0)
        case "%":
            updated.usedAmount = roundTwoDecimals(min(totalCost / 60.0 * 100.0, 100.0))
        default:
            updated.usedAmount = Double(sessionCount)
        }

        updated.subtitle = "Yerel DB: \(sessionCount) oturum • \(Self.formatTokenCount(totalTokens))"
        updated.resetDescription = "\(subscription.windowType.shortLabel) ($\(AISubscription.formatNumber(roundTwoDecimals(totalCost))))"
        updated.resetsAt = nil
        updated.lastUpdated = now
        return updated
    }

    // MARK: - Process & Environment Helpers

    private func resolveExecutable(candidates: [String]) -> URL? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func enrichedEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let pathEntries = [
            homeDirectoryURL.appendingPathComponent(".local/bin").path,
            homeDirectoryURL.appendingPathComponent(".npm-global/bin").path,
            homeDirectoryURL.appendingPathComponent(".hermes/node/bin").path,
            homeDirectoryURL.appendingPathComponent("homebrew/bin").path,
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let existingPath = env["PATH"] ?? ""
        let merged = (pathEntries + existingPath.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { acc, entry in
                if !entry.isEmpty, !acc.contains(entry) {
                    acc.append(entry)
                }
            }
            .joined(separator: ":")

        env["PATH"] = merged
        env["HOME"] = homeDirectoryURL.path
        env["DISABLE_TELEMETRY"] = "1"
        env["DISABLE_ERROR_REPORTING"] = "1"
        env["DISABLE_AUTOUPDATER"] = "1"
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        for (k, v) in extra {
            env[k] = v
        }
        return env
    }

    private func runOneShotProcess(
        executable: URL,
        arguments: [String],
        stdinString: String?,
        extraEnv: [String: String] = [:],
        timeout: TimeInterval
    ) -> Data? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = enrichedEnvironment(extra: extraEnv)

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            return nil
        }

        if let stdinString, let inputData = stdinString.data(using: .utf8) {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let box = LockedDataBox()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            let output = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            box.set(output)
            readGroup.leave()
        }

        let waitResult = readGroup.wait(timeout: .now() + timeout)
        if waitResult == .timedOut {
            if process.isRunning {
                process.terminate()
            }
            return nil
        }

        process.waitUntilExit()
        return process.terminationStatus == 0 ? box.get() : nil
    }

    private func firstMatchingJSONLine(in data: Data, matchingType: String) -> [String: Any]? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"),
                  let obj = parseJSONDictionary(trimmed),
                  (obj["type"] as? String) == matchingType else {
                continue
            }
            return obj
        }
        return nil
    }

    // MARK: - Shared Helpers

    private func recentFiles(in directory: URL, suffix: String, modifiedAfter cutoff: Date) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasSuffix(suffix) else { continue }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            let modified = values.contentModificationDate ?? .distantPast
            if modified >= cutoff {
                results.append(fileURL)
            }
        }
        return results
    }

    private func antigravityTranscriptFiles(in brainDir: URL, modifiedAfter cutoff: Date) -> [URL] {
        guard let convDirs = try? FileManager.default.contentsOfDirectory(
            at: brainDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for convDir in convDirs {
            let transcriptURL = convDir
                .appendingPathComponent(".system_generated", isDirectory: true)
                .appendingPathComponent("logs", isDirectory: true)
                .appendingPathComponent("transcript.jsonl")
            guard FileManager.default.fileExists(atPath: transcriptURL.path) else { continue }
            if fileModificationDate(transcriptURL) >= cutoff {
                results.append(transcriptURL)
            }
        }
        return results
    }

    private func fileModificationDate(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func enumerateMatchingLines(in fileURL: URL, containing needle: String, handler: (String) -> Void) {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return
        }
        for rawLine in content.split(whereSeparator: \.isNewline) where rawLine.contains(needle) {
            handler(String(rawLine))
        }
    }

    private func parseJSONDictionary(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func makeISOFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    private func parseISODate(
        _ raw: String,
        fractional: ISO8601DateFormatter,
        basic: ISO8601DateFormatter
    ) -> Date? {
        fractional.date(from: raw) ?? basic.date(from: raw)
    }

    private func withReadOnlySQLite(at dbURL: URL, _ body: (OpaquePointer) -> Void) {
        var db: OpaquePointer?
        let rwFlags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(dbURL.path, &db, rwFlags, nil) == SQLITE_OK, let openedDB = db {
            sqlite3_busy_timeout(openedDB, 300)
            sqlite3_exec(openedDB, "PRAGMA query_only = ON;", nil, nil, nil)
            defer { sqlite3_close(openedDB) }
            body(openedDB)
            return
        }
        if let partialDB = db {
            sqlite3_close(partialDB)
        }

        // Salt-okunur dosya/dizin durumunda immutable URI ile yeniden dene
        var fallbackDB: OpaquePointer?
        let uriPath = "file:\(dbURL.path)?immutable=1"
        let roFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(uriPath, &fallbackDB, roFlags, nil) == SQLITE_OK, let openedFallback = fallbackDB else {
            if let fallbackDB { sqlite3_close(fallbackDB) }
            return
        }
        defer { sqlite3_close(openedFallback) }
        body(openedFallback)
    }

    private func intValue(_ raw: Any?) -> Int {
        if let number = raw as? NSNumber { return number.intValue }
        return 0
    }

    private func doubleValue(_ raw: Any?) -> Double {
        if let number = raw as? NSNumber { return number.doubleValue }
        return 0
    }

    private func doubleValueIfPresent(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        return nil
    }

    private func epochDate(_ raw: Any?) -> Date? {
        guard let number = raw as? NSNumber else { return nil }
        let value = number.doubleValue
        guard value > 0 else { return nil }
        return Date(timeIntervalSince1970: value)
    }

    private func roundTwoDecimals(_ value: Double) -> Double {
        (value * 100.0).rounded() / 100.0
    }

    static func formatTokenCount(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.2fM tok", locale: Locale(identifier: "en_US_POSIX"), Double(tokens) / 1_000_000.0)
        }
        if tokens >= 1_000 {
            return String(format: "%.1fK tok", locale: Locale(identifier: "en_US_POSIX"), Double(tokens) / 1_000.0)
        }
        return "\(tokens) tok"
    }
}

private final class LockedSubscriptionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [AISubscription]

    init(items: [AISubscription]) {
        self.items = items
    }

    func set(_ item: AISubscription, at index: Int) {
        lock.lock()
        items[index] = item
        lock.unlock()
    }

    func snapshot() -> [AISubscription] {
        lock.lock()
        let copy = items
        lock.unlock()
        return copy
    }
}

private final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Data?

    func set(_ data: Data?) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data? {
        lock.lock()
        let copy = value
        lock.unlock()
        return copy
    }
}

private final class LockedCodexBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var foundLineData: Data?

    func appendAndCheckReady(_ chunk: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(chunk)
        guard let text = String(data: buffer, encoding: .utf8) else {
            return false
        }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("{"),
                  let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let idNum = obj["id"] as? NSNumber,
                  idNum.intValue == 2 else {
                continue
            }
            foundLineData = lineData
            return true
        }
        return false
    }

    func matchedData() -> Data? {
        lock.lock()
        let copy = foundLineData
        lock.unlock()
        return copy
    }
}
