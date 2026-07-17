import Foundation
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
        let pricing = try XCTUnwrap(PricingTable.pricing(for: "gpt-5.6-sol"))
        let cost = pricing.cost(input: 273_000, output: 1_000_000,
                                cacheWrite: 0, cacheWrite1h: 0, cacheRead: 0)
        XCTAssertEqual(cost, 47.73, accuracy: 0.000_001)
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
        let raw = "-Users-liangheping-Documents-Secret-Client"
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
                    cost: CostBreakdown(input: cost), cacheSavedUSD: 0)
    }
}
