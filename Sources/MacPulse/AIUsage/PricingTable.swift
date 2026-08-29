import Foundation

/// 内置模型价格表 + 模型名归一化 / 精确匹配。
/// 契约(见 UsageStore.swift 顶部):`static func pricing(for model: String) -> ModelPricing?`。
/// 未匹配返回 nil,调用方按 0 计——宁可少算也不默默套错价。
enum PricingTable {

    /// 随排行榜日汇总一起上报，便于后台识别不同版本价格表造成的估值差异。
    static let snapshotVersion = "2026-07-30"

    // 计价热路径:每次 pricing(for:) 都做 normalize(多个正则)+ 前缀匹配,
    // 而 distinct 模型只有几十个。memo 把十几万次调用降到几十次实算。
    // 计价发生在串行 scanQueue 上,但仍用锁兜底以防未来多线程调用。
    private static let memoLock = NSLock()
    nonisolated(unsafe) private static var memo: [String: ModelPricing?] = [:]

    static func pricing(for model: String) -> ModelPricing? {
        memoLock.lock()
        if let hit = memo[model] { memoLock.unlock(); return hit }
        memoLock.unlock()
        let result = match(normalize(model))
        memoLock.lock(); memo[model] = result; memoLock.unlock()
        return result
    }

    /// fast 模式(usage.speed == "fast")的费用倍率;不支持 fast 的模型返回 1。
    /// 数据来源:Anthropic 官方页 —— Opus 5/4.8 fast $10/$50(2x),Opus 4.7 fast $30/$150(6x,2026-07-24 移除)。
    static func fastMultiplier(for model: String) -> Double {
        let m = normalize(model)
        if m == "claude-opus-5" { return 2.0 }
        if m.hasPrefix("claude-opus-4-8") { return 2.0 }
        if m.hasPrefix("claude-opus-4-7") { return 6.0 }
        return 1.0
    }

    // MARK: - 归一化(内部纯函数,可测)

    /// 各来源实际出现的模型名形态:claude-sonnet-4-5-20250929、us.anthropic.claude-opus-4-8、
    /// vertex_ai/claude-fable-5@20260201、anthropic.claude-3-5-sonnet-20241022-v2:0、
    /// gemini-3-pro-preview、claude-sonnet-4-5[1m]。
    static func normalize(_ raw: String) -> String {
        var m = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // 去 provider 前缀:anthropic/、openai/、vertex_ai/ 等,取 "/" 最后一段
        if let slash = m.lastIndex(of: "/") {
            m = String(m[m.index(after: slash)...])
        }
        m.replace(#/^(us|eu|au|jp|apac|global)\.anthropic\./#, with: "")
        m.replace(#/^anthropic\./#, with: "")
        // 去后缀:顺序有讲究——日期快照规则的 .*$ 会顺带吃掉其后的 -v1:0 等尾巴
        m.replace(#/\[1m\]$/#, with: "")
        m.replace(#/[-@](?:20\d{6}|20\d{2}-\d{2}-\d{2}).*$/#, with: "")
        m.replace(#/-v\d+(:\d+)?$/#, with: "")
        m.replace(#/-(latest|preview)$/#, with: "")
        return m
    }

    // MARK: - 匹配(内部纯函数,可测)

    static func match(_ normalized: String) -> ModelPricing? {
        guard !normalized.isEmpty else { return nil }
        // 未知后缀/短前缀绝不套用近似价格;否则 gpt-5.6-sol 会被旧版误算成 gpt-5。
        return table[normalized]
    }

    // MARK: - 价格表(USD / 1M token)

    /// Anthropic:cacheWrite = 5 分钟 TTL 写入价(1.25x 输入),cacheWrite1h = 1 小时 TTL(2x 输入),
    /// cacheRead = 0.1x 输入。Claude Code 的缓存写入以 1h 为主,两档必须分开计。
    /// OpenAI 常规模型 / Gemini 无 cache 写入费；GPT-5.6 的延长缓存写入按官方倍率单列。
    static let table: [String: ModelPricing] = [
        // ---- Anthropic ----
        "claude-fable-5": ModelPricing(
            inputPerMTok: 10.00, outputPerMTok: 50.00,
            cacheWritePerMTok: 12.50, cacheReadPerMTok: 1.00,
            cacheWrite1hPerMTok: 20.00),
        // mythos-5 仅见于 Anthropic 官方页(LiteLLM 无此 key),与 fable-5 同价
        "claude-mythos-5": ModelPricing(
            inputPerMTok: 10.00, outputPerMTok: 50.00,
            cacheWritePerMTok: 12.50, cacheReadPerMTok: 1.00,
            cacheWrite1hPerMTok: 20.00),
        "claude-opus-5": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 25.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            cacheWrite1hPerMTok: 10.00),
        "claude-opus-4-8": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 25.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            cacheWrite1hPerMTok: 10.00),
        "claude-opus-4-7": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 25.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            cacheWrite1hPerMTok: 10.00),
        "claude-opus-4-6": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 25.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            cacheWrite1hPerMTok: 10.00),
        // 介绍价,2026-08-31 到期,见文件底部提醒
        "claude-sonnet-5": ModelPricing(
            inputPerMTok: 2.00, outputPerMTok: 10.00,
            cacheWritePerMTok: 2.50, cacheReadPerMTok: 0.20,
            cacheWrite1hPerMTok: 4.00),
        "claude-sonnet-4-6": ModelPricing(
            inputPerMTok: 3.00, outputPerMTok: 15.00,
            cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30,
            cacheWrite1hPerMTok: 6.00),
        "claude-sonnet-4-5": ModelPricing(
            inputPerMTok: 3.00, outputPerMTok: 15.00,
            cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30,
            cacheWrite1hPerMTok: 6.00,
            above200kInputPerMTok: 6.00, above200kOutputPerMTok: 22.50),
        "claude-haiku-4-5": ModelPricing(
            inputPerMTok: 1.00, outputPerMTok: 5.00,
            cacheWritePerMTok: 1.25, cacheReadPerMTok: 0.10,
            cacheWrite1hPerMTok: 2.00),
        // 已 deprecated,2026-08-05 退役,留着算历史账
        "claude-opus-4-1": ModelPricing(
            inputPerMTok: 15.00, outputPerMTok: 75.00,
            cacheWritePerMTok: 18.75, cacheReadPerMTok: 1.50,
            cacheWrite1hPerMTok: 30.00),
        "claude-sonnet-4": ModelPricing(
            inputPerMTok: 3.00, outputPerMTok: 15.00,
            cacheWritePerMTok: 3.75, cacheReadPerMTok: 0.30,
            cacheWrite1hPerMTok: 6.00,
            above200kInputPerMTok: 6.00, above200kOutputPerMTok: 22.50),

        // ---- OpenAI(含 Codex CLI 实际用到的 5.x / codex 系列)----
        // GPT-5.6:官方定价页;输入超过 272K 时整次请求 input 2x / output 1.5x。
        "gpt-5.6-sol": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 30.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            fullRequestThreshold: 272_000,
            fullRequestInputMultiplier: 2, fullRequestOutputMultiplier: 1.5),
        // 官方说明 gpt-5.6 别名路由到 Sol,显式列出以保持精确匹配。
        "gpt-5.6": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 30.00,
            cacheWritePerMTok: 6.25, cacheReadPerMTok: 0.50,
            fullRequestThreshold: 272_000,
            fullRequestInputMultiplier: 2, fullRequestOutputMultiplier: 1.5),
        "gpt-5.6-terra": ModelPricing(
            inputPerMTok: 2.50, outputPerMTok: 15.00,
            cacheWritePerMTok: 3.125, cacheReadPerMTok: 0.25,
            fullRequestThreshold: 272_000,
            fullRequestInputMultiplier: 2, fullRequestOutputMultiplier: 1.5),
        "gpt-5.5": ModelPricing(
            inputPerMTok: 5.00, outputPerMTok: 30.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.50),
        "gpt-5.4": ModelPricing(
            inputPerMTok: 2.50, outputPerMTok: 15.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.25),
        "gpt-5.3-codex": ModelPricing(
            inputPerMTok: 1.75, outputPerMTok: 14.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.175),
        "gpt-5.2-codex": ModelPricing(
            inputPerMTok: 1.75, outputPerMTok: 14.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.175),
        "gpt-5-codex": ModelPricing(
            inputPerMTok: 1.25, outputPerMTok: 10.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.125),
        // Codex 自动审查用的内部模型,LiteLLM 无价,按 gpt-5-codex 档估算
        "codex-auto-review": ModelPricing(
            inputPerMTok: 1.25, outputPerMTok: 10.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.125),
        "gpt-5.2": ModelPricing(
            inputPerMTok: 1.75, outputPerMTok: 14.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.175),
        "gpt-5.1": ModelPricing(
            inputPerMTok: 1.25, outputPerMTok: 10.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.125),
        "gpt-5-mini": ModelPricing(
            inputPerMTok: 0.25, outputPerMTok: 2.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.025),
        "gpt-5-nano": ModelPricing(
            inputPerMTok: 0.05, outputPerMTok: 0.40,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.005),
        "gpt-5": ModelPricing(
            inputPerMTok: 1.25, outputPerMTok: 10.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.125),
        // o3-mini 的 cacheRead(0.55)高于 o4-mini(0.275),原始数据如此,不是笔误
        "o3-mini": ModelPricing(
            inputPerMTok: 1.10, outputPerMTok: 4.40,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.55),
        // o3-pro 无 cache 读取价(mode=responses)
        "o3-pro": ModelPricing(
            inputPerMTok: 20.00, outputPerMTok: 80.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0),
        "o4-mini": ModelPricing(
            inputPerMTok: 1.10, outputPerMTok: 4.40,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.275),
        "o3": ModelPricing(
            inputPerMTok: 2.00, outputPerMTok: 8.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.50),

        // ---- Google Gemini(LiteLLM 里 gemini-3 系只有 -preview key,归一化会剥掉后缀落到这里)----
        "gemini-3-pro": ModelPricing(
            inputPerMTok: 2.00, outputPerMTok: 12.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.20,
            above200kInputPerMTok: 4.00, above200kOutputPerMTok: 18.00,
            above200kCacheReadPerMTok: 0.40),
        "gemini-3-flash": ModelPricing(
            inputPerMTok: 0.50, outputPerMTok: 3.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.05),
        "gemini-2.5-pro": ModelPricing(
            inputPerMTok: 1.25, outputPerMTok: 10.00,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.125,
            above200kInputPerMTok: 2.50, above200kOutputPerMTok: 15.00,
            above200kCacheReadPerMTok: 0.25),
        "gemini-2.5-flash": ModelPricing(
            inputPerMTok: 0.30, outputPerMTok: 2.50,
            cacheWritePerMTok: 0, cacheReadPerMTok: 0.03),
    ]
}

// MARK: - 价格数据来源与维护提醒
// 复核日期:2026-07-30。
// 来源:LiteLLM model_prices_and_context_window.json(raw.githubusercontent.com/BerriAI/litellm/main)
//      + OpenAI / Anthropic 官方模型与定价页交叉验证。
// 注意:claude-sonnet-5 当前为介绍价(in 2.00 / out 10.00 / cacheW 2.50 / cacheR 0.20),
//      2026-08-31 到期;2026-09-01 起须改为标准价 in 3.00 / out 15.00(cacheW 3.75 / cacheR 0.30)。
