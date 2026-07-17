import Foundation
let scanner = UsageScanner(); let codex = CodexScanner()
var events = scanner.scanAll(); events += codex.scanAll()
let priced = events.map { PricedEvent.from($0) }
print("总事件: \(priced.count)")
var cal = Calendar.current; cal.timeZone = .current
let now = Date()

func check(_ name: String, _ d: DashboardData) {
    let mSum = d.byModel.reduce(0.0){$0+$1.costUSD}
    let pSum = d.byProject.reduce(0.0){$0+$1.costUSD}
    let tSum = d.byTool.reduce(0.0){$0+$1.costUSD}
    let tot = d.overview.totalCostUSD
    func ok(_ a: Double) -> String { abs(a-tot) < 0.01 ? "✅" : "❌ 差\(a-tot)" }
    print(String(format: "[%@] 总$%.2f | 模型和%@ 项目和%@ 工具和%@ | token %d | 缓存命中%.0f%% | 事件%d",
        name, tot, ok(mSum), ok(pSum), ok(tSum), d.overview.totalTokens, d.cache.hitRate*100, d.overview.eventCount))
}

for r in [UsageFilter.TimeRange.today, .last7Days, .last30Days] {
    var f = UsageFilter(); f.time = r
    check(r.label, UsageAggregator.run(priced, filter: f, now: now, calendar: cal))
}
// 30天 top 模型/项目
var f30 = UsageFilter(); f30.time = .last30Days
let d = UsageAggregator.run(priced, filter: f30, now: now, calendar: cal)
print("\n30天 Top 模型:")
for s in d.byModel.prefix(5) { print(String(format: "  %-22@ $%.2f (%.0f%%)", s.key as NSString, s.costUSD, s.share*100)) }
print("30天 Top 项目:")
for s in d.byProject.prefix(5) { print(String(format: "  %-26@ $%.2f", s.key as NSString, s.costUSD)) }
print("按工具:")
for s in d.byTool { print(String(format: "  %-14@ $%.2f", s.key as NSString, s.costUSD)) }
// 筛选交叉验证:只 codex,应等于按工具里的 Codex
var fc = UsageFilter(); fc.time = .last30Days; fc.tools = [.codex]
let dc = UsageAggregator.run(priced, filter: fc, now: now, calendar: cal)
let codexInAll = d.byTool.first{$0.key=="Codex CLI"}?.costUSD ?? 0
print(String(format: "\n筛选 codex 总$%.2f  vs  全量里的Codex $%.2f  → %@",
    dc.overview.totalCostUSD, codexInAll, abs(dc.overview.totalCostUSD-codexInAll)<0.01 ? "✅一致" : "❌不一致"))
print("Top 会话数: \(d.topSessions.count), 趋势桶: \(d.trend.count), 5h块: \(d.block != nil ? "有" : "无")")
