import Foundation
import LocalAuthentication
import Security
import XCTest
@testable import MacPulse

final class CoreRegressionTests: XCTestCase {
    func testCleanupGuardMatrix() {
        let home = "/private/tmp/macpulse-policy-home"
        let cases: [(String, Bool)] = [
            (home + "/Library/Caches/Google", true),
            (home + "/Library/Caches/com.apple.Safari", true),
            (home + "/.Trash/old.zip", true),
            (home + "/Library/Logs/DiagnosticReports", true),
            (home + "/.npm/_cacache/content-v2", true),
            (home + "/Library/Developer/Xcode/DerivedData/App-abc", true),
            (home + "/Library/Developer/Xcode/iOS DeviceSupport/17.0", true),
            (home + "/Documents/report.docx", false),
            (home + "/Desktop/thesis", false),
            (home + "/Downloads/x.dmg", false),
            (home + "/Library/Application Support/Code", false),
            (home + "/Library/Preferences/com.apple.finder.plist", false),
            (home + "/Library/pnpm/store/v3", false),
            (home + "/.ssh/id_rsa", false),
            (home + "/Library/Mobile Documents/iCloud", false),
            (home, false),
            (home + "/Library", false),
            (home + "/Library/Caches", false),
            ("/System/Library/Caches", false),
            ("/etc/passwd", false),
            (home + "/Library/Caches/../../Documents/secret", false),
            (home + "/Library/Caches/../Preferences/x", false),
            (home + "/.npm/../.ssh/key", false),
            // 即使在白名单根下,也只允许扫描器列出的直接子项。
            (home + "/Library/Caches/Google/nested", false)
        ]
        for (path, expected) in cases {
            XCTAssertEqual(CleanupScanner.isSafeToDelete(path, homeDirectory: home), expected, path)
        }
    }

    func testCleanupRejectsSymlinkedAllowedRoot() throws {
        let fm = FileManager.default
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let outside = sandbox.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: home.appendingPathComponent("Library"), withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Library/Caches"),
                                  withDestinationURL: outside)

        XCTAssertFalse(CleanupScanner.isSafeToDelete(
            home.appendingPathComponent("Library/Caches/secret").path,
            homeDirectory: home.path))
        let scan = CleanupScanner(homeDirectory: home.path).scan()
        XCTAssertEqual(scan.first { $0.category == .appCaches }?.items.count, 0,
                       "符号链接白名单根连扫描都不应进入目标目录")
    }

    func testCleanupDeletesCandidateSymlinkWithoutTouchingTarget() throws {
        let fm = FileManager.default
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let home = sandbox.appendingPathComponent("home", isDirectory: true)
        let cache = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let outside = sandbox.appendingPathComponent("outside", isDirectory: true)
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        let secret = outside.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: secret)
        let link = cache.appendingPathComponent("outside-link")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let disposable = cache.appendingPathComponent("disposable.txt")
        try Data("delete".utf8).write(to: disposable)

        let scanner = CleanupScanner(homeDirectory: home.path)
        let results = scanner.scan()
        let cacheItems = results.first { $0.category == .appCaches }?.items ?? []
        XCTAssertEqual(cacheItems.count, 2)
        for item in cacheItems {
            XCTAssertTrue(item.path.hasPrefix(home.path + "/"), "home=\(home.path), item=\(item.path)")
            XCTAssertEqual((item.path as NSString).deletingLastPathComponent,
                           home.appendingPathComponent("Library/Caches").path)
            XCTAssertTrue(CleanupScanner.isSafeToDelete(item.path, homeDirectory: home.path),
                          "home=\(home.path), item=\(item.path)")
        }
        let report = scanner.clean(categories: [.appCaches], scan: results)

        XCTAssertEqual(report.failedCount, 0)
        XCTAssertFalse(fm.fileExists(atPath: link.path))
        XCTAssertFalse(fm.fileExists(atPath: disposable.path))
        XCTAssertTrue(fm.fileExists(atPath: secret.path), "符号链接目标绝不能被删除")
    }

    func testPricingRequiresKnownModelAndHandlesGPT56LongRequest() throws {
        XCTAssertNil(PricingTable.match("gpt"))
        XCTAssertNil(PricingTable.match("gpt-5.6-sol-unknown"))
        XCTAssertEqual(PricingTable.normalize("openai/gpt-5.6-sol-2026-07-01"), "gpt-5.6-sol")
        XCTAssertEqual(shortModel("claude-sonnet-5-2026-07-01"), "sonnet-5")
        let opus5 = try XCTUnwrap(PricingTable.pricing(for: "anthropic.claude-opus-5"))
        XCTAssertEqual(opus5.inputPerMTok, 5.00)
        XCTAssertEqual(opus5.outputPerMTok, 25.00)
        XCTAssertEqual(opus5.cacheWritePerMTok, 6.25)
        XCTAssertEqual(opus5.cacheWrite1hPerMTok, 10.00)
        XCTAssertEqual(opus5.cacheReadPerMTok, 0.50)
        XCTAssertEqual(PricingTable.fastMultiplier(for: "claude-opus-5"), 2.0)
        let pricing = try XCTUnwrap(PricingTable.pricing(for: "gpt-5.6-sol"))
        let cost = pricing.cost(input: 273_000, output: 1_000_000,
                                cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0)
        XCTAssertEqual(cost, 32.184, accuracy: 0.000_001)
    }

    func testModelNameDisplayAndRecentActivityFreshness() {
        XCTAssertEqual(ModelName.display("openai/gpt-5.6-sol-2026-07-01"), "GPT-5.6 Sol")
        XCTAssertEqual(ModelName.display("claude-opus-5"), "Opus 5")
        XCTAssertEqual(ModelName.display("claude-opus-4-8-20260701"), "Opus 4.8")
        XCTAssertEqual(ModelName.display("unknown"), "模型未知")

        let now = Date(timeIntervalSince1970: 2_000_000)
        let current = RecentAIActivity(tool: .codex, model: "gpt-5.6-sol",
                                       timestamp: now.addingTimeInterval(-90))
        XCTAssertTrue(current.isCurrent(now: now))
        XCTAssertEqual(current.statusLabel(now: now), "正在使用")

        let recent = RecentAIActivity(tool: .claude, model: "claude-sonnet-5",
                                      timestamp: now.addingTimeInterval(-12 * 60))
        XCTAssertFalse(recent.isCurrent(now: now))
        XCTAssertEqual(recent.statusLabel(now: now), "最近使用 · 12分钟前")
    }

    func testLatestActivityUsesNewestActualEvent() throws {
        let old = priced(at: Date(timeIntervalSince1970: 1_000), cost: 1,
                         model: "claude-sonnet-5", tool: .claude)
        let latest = priced(at: Date(timeIntervalSince1970: 2_000), cost: 1,
                            model: "gpt-5.6-sol", tool: .codex)

        let activity = try XCTUnwrap(UsageStore.latestActivity(in: [latest, old]))
        XCTAssertEqual(activity.tool, .codex)
        XCTAssertEqual(activity.model, "gpt-5.6-sol")
        XCTAssertEqual(activity.timestamp, latest.timestamp)
    }

    func testCompanionMoodKeepsRisksFirstAndAddsContext() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let late = date(2026, 7, 17, 23, calendar)
        let activity = RecentAIActivity(tool: .codex, model: "gpt-5.6-sol",
                                        timestamp: late.addingTimeInterval(-60))

        let critical = CompanionMood.resolve(
            activity: activity, quotaUsedPercent: 20, quotaReset: false,
            health: .critical, now: late, calendar: calendar)
        XCTAssertEqual(critical.tone, .urgent)
        XCTAssertEqual(critical.text, "电脑也累了，先照顾一下它")

        let constrained = CompanionMood.resolve(
            activity: activity, quotaUsedPercent: 90, quotaReset: false,
            health: .good, now: late, calendar: calendar)
        XCTAssertEqual(constrained.tone, .urgent)
        XCTAssertEqual(constrained.text, "快到边了，我替你盯着")

        let night = CompanionMood.resolve(
            activity: activity, quotaUsedPercent: 20, quotaReset: false,
            health: .good, now: late, calendar: calendar)
        XCTAssertEqual(night.tone, .warm)
        XCTAssertEqual(night.text, "夜深了，我陪你写完这一段")
    }

    func testVibeGreetingIncludesActualModelIdentity() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let morning = date(2026, 7, 17, 9, calendar)
        let activity = RecentAIActivity(tool: .codex, model: "gpt-5.6-sol",
                                        timestamp: morning)

        let greeting = VibeCopy.greeting(at: morning, activity: activity, calendar: calendar)
        XCTAssertEqual(greeting.title, "早呀，慢慢进入状态 ☕")
        XCTAssertTrue(greeting.subtitle.contains("Codex · GPT-5.6 Sol"))
    }

    func testMonthProjectionDoesNotDependOnSelectedTimeRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 7, 17, 12, calendar)
        let events = [
            priced(at: date(2026, 7, 1, 12, calendar), cost: 10),
            priced(at: date(2026, 7, 17, 10, calendar), cost: 5)
        ]
        var today = UsageFilter(); today.time = .today
        var monthView = UsageFilter(); monthView.time = .last30Days
        let a = UsageAggregator.run(events, filter: today, now: now, calendar: calendar)
        let b = UsageAggregator.run(events, filter: monthView, now: now, calendar: calendar)
        XCTAssertEqual(a.burn.monthProjectionUSD, b.burn.monthProjectionUSD, accuracy: 0.000_001)
        XCTAssertEqual(a.burn.monthProjectionUSD, 15.0 / 17.0 * 31.0, accuracy: 0.000_001)
    }

    func testComparisonLabelsAndTodayUsesYesterdaySamePeriod() {
        XCTAssertEqual(UsageFilter.TimeRange.today.comparisonLabel, "较昨日同期")
        XCTAssertEqual(UsageFilter.TimeRange.last24h.comparisonLabel, "较前 24 小时")
        XCTAssertEqual(UsageFilter.TimeRange.last7Days.comparisonLabel, "较前 7 天")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 7, 17, 12, calendar)
        let events = [
            priced(at: date(2026, 7, 17, 10, calendar), cost: 9),
            priced(at: date(2026, 7, 16, 10, calendar), cost: 3),
            // 昨日后半天不属于“昨日同期”，不能被误算进比较基准。
            priced(at: date(2026, 7, 16, 20, calendar), cost: 100)
        ]
        var filter = UsageFilter(); filter.time = .today
        let data = UsageAggregator.run(events, filter: filter, now: now, calendar: calendar)
        XCTAssertEqual(data.overview.totalCostUSD, 9, accuracy: 0.000_001)
        XCTAssertEqual(data.overview.prevCostUSD, 3, accuracy: 0.000_001)
        XCTAssertEqual(data.overview.deltaUSD, 6, accuracy: 0.000_001)
        XCTAssertEqual(data.overview.deltaPct ?? .nan, 2, accuracy: 0.000_001)
    }

    func testBurnRateIsFixedHourIndependentOfSelectedRange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 7, 17, 12, calendar)
        let events = [priced(at: date(2026, 7, 17, 11, calendar), cost: 4)]
        var custom = UsageFilter()
        custom.time = .custom(date(2026, 7, 1, 0, calendar), date(2026, 7, 2, 0, calendar))
        let data = UsageAggregator.run(events, filter: custom, now: now, calendar: calendar)
        XCTAssertEqual(data.overview.totalCostUSD, 0, accuracy: 0.000_001)
        XCTAssertEqual(data.burn.perHourUSD, 4, accuracy: 0.000_001)
    }

    func testTokenCompositionSeparatesNewAndReusedTokens() {
        var metrics = OverviewMetrics()
        metrics.input = 10
        metrics.output = 5
        metrics.cacheWrite = 20
        metrics.cacheRead = 100
        metrics.totalCostUSD = 7
        metrics.prevCostUSD = 2
        XCTAssertEqual(metrics.newTokens, 35)
        XCTAssertEqual(metrics.reusedTokens, 100)
        XCTAssertEqual(metrics.totalTokens, 135)
        XCTAssertEqual(metrics.deltaUSD, 5)
    }

    func testPrivacyAliasIsStableAndDoesNotLeakProjectName() {
        let raw = "-Users-example-Documents-Sample-Project"
        let first = ProjectName.display(raw, privacy: true)
        XCTAssertEqual(first, ProjectName.display(raw, privacy: true))
        XCTAssertNotEqual(first, ProjectName.display(raw, privacy: false))
        XCTAssertTrue(first.hasPrefix("项目 "))
        XCTAssertFalse(first.localizedCaseInsensitiveContains("Secret"))
        XCTAssertNotEqual(first, ProjectName.display(raw + "-Two", privacy: true))
    }

    func testAggregatorBuildsInsightAndDataQuality() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 7, 17, 12, calendar)
        let events = [
            priced(at: date(2026, 7, 17, 9, calendar), cost: 6,
                   model: "gpt-5.6-sol", project: "Alpha", tool: .codex),
            priced(at: date(2026, 7, 17, 10, calendar), cost: 2,
                   model: "gpt-5.6-sol", project: "Alpha", tool: .claude),
            priced(at: date(2026, 7, 17, 11, calendar), cost: 2,
                   model: "future-model", project: "Beta", tool: .claude)
        ]
        var filter = UsageFilter(); filter.time = .today
        let data = UsageAggregator.run(events, filter: filter, now: now, calendar: calendar)
        XCTAssertEqual(data.insight.topModel, "gpt-5.6-sol")
        XCTAssertEqual(data.insight.topModelShare, 0.8, accuracy: 0.000_001)
        XCTAssertEqual(data.insight.topProject, "Alpha")
        XCTAssertEqual(data.insight.topProjectShare, 0.8, accuracy: 0.000_001)
        XCTAssertNotNil(data.insight.peakLabel)
        XCTAssertEqual(Set(data.quality.sources), Set([.claude, .codex]))
        XCTAssertEqual(data.quality.unknownModels, ["future-model"])
    }

    func testCostAlertThresholdDecisions() {
        XCTAssertEqual(CostAlertEvaluator.evaluate(
            hourlyUSD: 19.99, todayUSD: 99.99,
            hourlyThresholdUSD: 20, dailyThresholdUSD: 100), [])
        XCTAssertEqual(CostAlertEvaluator.evaluate(
            hourlyUSD: 20, todayUSD: 150,
            hourlyThresholdUSD: 20, dailyThresholdUSD: 100), [.hourly, .daily])
        XCTAssertEqual(CostAlertEvaluator.evaluate(
            hourlyUSD: 999, todayUSD: 999,
            hourlyThresholdUSD: 0, dailyThresholdUSD: -1), [])
    }

    func testExternalNumbersAreClamped() {
        XCTAssertEqual(UsageValueSanitizer.tokens(NSNumber(value: -1)), 0)
        XCTAssertEqual(UsageValueSanitizer.tokens(NSNumber(value: Double.infinity)), 0)
        XCTAssertEqual(UsageValueSanitizer.tokens(NSNumber(value: 9e20)), UsageValueSanitizer.maxTokensPerEvent)
        XCTAssertNil(UsageValueSanitizer.cost(NSNumber(value: -0.01)))
        XCTAssertEqual(UsageValueSanitizer.cost(NSNumber(value: 9e20)), UsageValueSanitizer.maxCostPerEvent)
    }

    func testISO8601TimestampParser() {
        XCTAssertEqual(ISO8601TimestampParser.parse("1970-01-01T00:00:00Z")?.timeIntervalSince1970, 0)
        XCTAssertEqual(ISO8601TimestampParser.parse("1970-01-01T08:00:00+08:00")?.timeIntervalSince1970, 0)
        let leapDay = try? XCTUnwrap(
            ISO8601TimestampParser.parse("2000-02-29T12:34:56.125Z")?.timeIntervalSince1970)
        XCTAssertEqual(leapDay ?? .nan, 951_827_696.125, accuracy: 0.000_001)
        XCTAssertNil(ISO8601TimestampParser.parse("2000-02-30T00:00:00Z"))
        XCTAssertNil(ISO8601TimestampParser.parse("not-a-date"))
    }

    func testRepositorySpecRejectsTraversalAndMalformedNames() {
        XCTAssertNotNil(SkillManagerStore.parseRepoSpec("owner/repo/skills/demo"))
        XCTAssertNotNil(SkillManagerStore.parseRepoSpec("https://github.com/owner/repo/tree/main/skills/demo"))
        XCTAssertNil(SkillManagerStore.parseRepoSpec("owner/repo/../../outside"))
        XCTAssertNil(SkillManagerStore.parseRepoSpec("../repo"))
        XCTAssertNil(SkillManagerStore.parseRepoSpec("owner/repo//demo"))
        XCTAssertNil(SkillManagerStore.parseRepoSpec("owner/repo?tab=readme"))
    }

    func testClaudeQuotaPercentIsClamped() throws {
        let reset = "2026-07-18T00:00:00Z"
        let quota = try XCTUnwrap(ClaudeQuotaReader.parse([
            "five_hour": ["utilization": 150, "resets_at": reset],
            "seven_day": ["utilization": -3, "resets_at": reset]
        ], plan: "pro"))
        XCTAssertEqual(quota.fiveHour?.usedPercent, 100)
        XCTAssertEqual(quota.weekly?.usedPercent, 0)
    }

    func testClaudeQuotaBackgroundKeychainReadCannotShowAuthenticationUI() throws {
        let background = ClaudeQuotaReader.keychainQuery(accessMode: .background)
        let context = try XCTUnwrap(background[kSecUseAuthenticationContext] as? LAContext)
        XCTAssertTrue(context.interactionNotAllowed)
        XCTAssertEqual(background[kSecUseAuthenticationUI] as? String,
                       kSecUseAuthenticationUISkip as String)
        XCTAssertEqual(background[kSecAttrService] as? String, "Claude Code-credentials")

        let userInitiated = ClaudeQuotaReader.keychainQuery(accessMode: .userInitiated)
        XCTAssertNil(userInitiated[kSecUseAuthenticationContext])
        XCTAssertNil(userInitiated[kSecUseAuthenticationUI])
    }

    func testCodexQuotaReadsOnlyTailAndClampsPercent() throws {
        let fm = FileManager.default
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }
        let file = sandbox.appendingPathComponent("rollout-test.jsonl")
        var data = Data(repeating: 0x78, count: 2 * 1024 * 1024 + 128)
        data.append(0x0A)
        let line = #"{"timestamp":"2026-07-17T00:00:00Z","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":125,"resets_at":1784246400,"window_minutes":300},"secondary":{"used_percent":-5,"resets_at":1784851200,"window_minutes":10080},"plan_type":"plus"}}}"#
        data.append(contentsOf: line.utf8)
        data.append(0x0A)
        try data.write(to: file)

        let quota = try XCTUnwrap(CodexQuotaReader.latestRateLimits(in: file))
        XCTAssertEqual(quota.plan, "plus")
        XCTAssertEqual(quota.fiveHour?.usedPercent, 100)
        XCTAssertEqual(quota.weekly?.usedPercent, 0)
    }

    func testCodexQuotaChoosesNewestIdentifiedSnapshotAcrossSessions() throws {
        let fm = FileManager.default
        let sandbox = try makeSandbox()
        defer { try? fm.removeItem(at: sandbox) }

        func write(_ name: String, timestamp: String, used: Double, plan: String?) throws -> URL {
            var rateLimits: [String: Any] = [
                "primary": [
                    "used_percent": used,
                    "resets_at": 1_784_822_681,
                    "window_minutes": 10_080
                ]
            ]
            if let plan { rateLimits["plan_type"] = plan }
            let event: [String: Any] = [
                "timestamp": timestamp,
                "payload": ["type": "token_count", "rate_limits": rateLimits]
            ]
            let url = sandbox.appendingPathComponent(name)
            var data = try JSONSerialization.data(withJSONObject: event)
            data.append(0x0A)
            try data.write(to: url)
            return url
        }

        let olderPro = try write("older-pro.jsonl", timestamp: "2026-07-17T06:38:06Z",
                                 used: 60, plan: "pro")
        let anonymous = try write("newer-anonymous.jsonl", timestamp: "2026-07-17T06:38:30Z",
                                  used: 0, plan: nil)
        let newestPro = try write("newest-pro.jsonl", timestamp: "2026-07-17T06:38:40Z",
                                  used: 61, plan: "pro")

        let quota = try XCTUnwrap(CodexQuotaReader.mostRecentRateLimits(
            in: [anonymous, olderPro, newestPro]))
        XCTAssertEqual(quota.plan, "pro")
        XCTAssertEqual(quota.weekly?.usedPercent, 61)
        XCTAssertEqual(quota.asOf, ISO8601TimestampParser.parse("2026-07-17T06:38:40Z"))
    }

    func testQuotaResetDetectorIgnoresPrematureDriftAndSnapshotOscillation() {
        var detector = QuotaResetDetector()
        let now = Date(timeIntervalSince1970: 1_784_270_400)

        func quota(used: Double, reset: TimeInterval, asOf: TimeInterval) -> ToolQuota {
            let window = QuotaWindow(tool: .codex, kind: .weekly, usedPercent: used,
                                     resetsAt: Date(timeIntervalSince1970: reset),
                                     asOf: Date(timeIntervalSince1970: asOf))
            return ToolQuota(tool: .codex, plan: "pro", windows: [window],
                             authoritative: true, asOf: window.asOf)
        }

        let normalReset: TimeInterval = 1_784_822_681
        let driftingReset: TimeInterval = 1_784_875_076
        XCTAssertTrue(detector.observe([
            quota(used: 60, reset: normalReset, asOf: now.timeIntervalSince1970 - 30)
        ], now: now).isEmpty)
        XCTAssertTrue(detector.observe([
            quota(used: 0, reset: driftingReset, asOf: now.timeIntervalSince1970 - 20)
        ], now: now).isEmpty, "旧周期未到期时,resetsAt 向后漂移不是重置")
        XCTAssertTrue(detector.observe([
            quota(used: 60, reset: normalReset, asOf: now.timeIntervalSince1970 - 10)
        ], now: now).isEmpty)
        XCTAssertTrue(detector.observe([
            quota(used: 0, reset: driftingReset + 90, asOf: now.timeIntervalSince1970)
        ], now: now).isEmpty, "旧→新→旧→新快照振荡不应反复提醒")
    }

    func testQuotaResetDetectorEmitsOnceAfterPreviousBoundary() {
        var detector = QuotaResetDetector()
        let oldBoundary = Date(timeIntervalSince1970: 2_000_000)

        func quota(reset: Date, asOf: Date) -> ToolQuota {
            let window = QuotaWindow(tool: .codex, kind: .weekly, usedPercent: 1,
                                     resetsAt: reset, asOf: asOf)
            return ToolQuota(tool: .codex, plan: "pro", windows: [window],
                             authoritative: true, asOf: asOf)
        }

        XCTAssertTrue(detector.observe([
            quota(reset: oldBoundary, asOf: oldBoundary.addingTimeInterval(-60))
        ], now: oldBoundary.addingTimeInterval(-60)).isEmpty)

        let nextBoundary = oldBoundary.addingTimeInterval(7 * 24 * 3600)
        let next = quota(reset: nextBoundary, asOf: oldBoundary.addingTimeInterval(1))
        XCTAssertEqual(detector.observe([next], now: oldBoundary.addingTimeInterval(1)).count, 1)
        XCTAssertTrue(detector.observe([next], now: oldBoundary.addingTimeInterval(2)).isEmpty,
                      "同一周期只提醒一次")
    }

    func testRankingAggregateUsesShanghaiDayAndOnlySummaryFields() throws {
        let now = try XCTUnwrap(ISO8601TimestampParser.parse("2026-07-16T16:30:00Z"))
        let before = try XCTUnwrap(ISO8601TimestampParser.parse("2026-07-16T15:59:00Z"))
        let insideA = try XCTUnwrap(ISO8601TimestampParser.parse("2026-07-16T16:01:00Z"))
        let insideB = try XCTUnwrap(ISO8601TimestampParser.parse("2026-07-17T15:59:00Z"))
        let nextDay = try XCTUnwrap(ISO8601TimestampParser.parse("2026-07-17T16:00:00Z"))
        let aggregate = UsageStore.rankingDailyAggregate(
            events: [
                priced(at: before, cost: 99),
                priced(at: insideA, cost: 1.25),
                priced(at: insideB, cost: 2.50),
                priced(at: nextDay, cost: 99),
            ],
            now: now,
            appVersion: "0.10.0 (3)")

        XCTAssertEqual(aggregate.localDay, "2026-07-17")
        XCTAssertEqual(aggregate.totalTokens, 2)
        XCTAssertEqual(aggregate.estimatedCostMicroUSD, 3_750_000)
        XCTAssertEqual(aggregate.pricingVersion, PricingTable.snapshotVersion)
        XCTAssertEqual(aggregate.appVersion, "0.10.0 (3)")

        let json = try XCTUnwrap(String(data: JSONEncoder().encode(aggregate), encoding: .utf8))
        XCTAssertTrue(json.contains("estimated_cost_micro_usd"))
        XCTAssertFalse(json.contains("project"))
        XCTAssertFalse(json.contains("model"))
        XCTAssertFalse(json.contains("session"))
    }

    func testRankingNicknameDefaultsToFixedMask() {
        XCTAssertEqual(RankingProfile.masked("示例用户"), "＊＊＊户")
        XCTAssertEqual(RankingProfile.masked("A"), "＊＊＊")
        XCTAssertEqual(RankingProfile.masked(""), "＊＊＊")
    }

    func testLiveAggregationInvariantsWhenRequested() throws {
        guard ProcessInfo.processInfo.environment["MACPULSE_LIVE_TEST"] == "1" else {
            throw XCTSkip("仅在显式设置 MACPULSE_LIVE_TEST=1 时读取本机会话")
        }
        let started = Date()
        let claudeScanner = UsageScanner(), codexScanner = CodexScanner()
        var raw = claudeScanner.scanAll()
        raw.append(contentsOf: codexScanner.scanAll())
        let hotStarted = Date()
        var hot = claudeScanner.scanAll()
        hot.append(contentsOf: codexScanner.scanAll())
        let hotElapsed = Date().timeIntervalSince(hotStarted)
        XCTAssertLessThan(hotElapsed, 10, "缓存热扫描不应再次整读所有 JSONL")
        let priced = raw.map(PricedEvent.from)
        XCTAssertTrue(priced.allSatisfy { $0.cost.total.isFinite && $0.cost.total >= 0 })
        var calendar = Calendar.current; calendar.timeZone = .current
        for range in [UsageFilter.TimeRange.today, .last7Days, .last30Days] {
            var filter = UsageFilter(); filter.time = range
            let dashboard = UsageAggregator.run(priced, filter: filter, now: Date(), calendar: calendar)
            for slices in [dashboard.byModel, dashboard.byProject, dashboard.byTool] {
                XCTAssertEqual(slices.reduce(0) { $0 + $1.costUSD },
                               dashboard.overview.totalCostUSD, accuracy: 0.01)
            }
        }
        let unknown = Set(raw.map(\.model).filter { PricingTable.pricing(for: $0) == nil }).sorted()
        let fallbackProjects = raw.filter { $0.project.hasPrefix("-Users-") }.count
        print("LIVE events=\(raw.count), hotEvents=\(hot.count), unknownModels=\(unknown), encodedProjects=\(fallbackProjects), cold+checks=\(Date().timeIntervalSince(started))s, hot=\(hotElapsed)s")
    }

    private func makeSandbox() throws -> URL {
        let url = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("macpulse-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func priced(at timestamp: Date, cost: Double,
                        model: String = "gpt-5.6-sol", project: String = "P",
                        tool: ToolKind = .codex) -> PricedEvent {
        PricedEvent(timestamp: timestamp, tool: tool, model: model, project: project,
                    session: UUID().uuidString, input: 1, output: 0, cacheWrite: 0, cacheRead: 0,
                    cost: CostBreakdown(input: cost), cacheSavedUSD: 0,
                    isPriced: PricingTable.pricing(for: model) != nil)
    }
}
