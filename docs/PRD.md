# Token 监控台 — PRD(开发参照版)

> 面向开发的精简版。完整可视化版见 docs/PRD.html。依据:docs/调研报告.html(2026-07-06)。

## 1. 目标
在 MacPulse 把「AI 用量」tab 升级为 Token 监控台:多维度筛选、实时看消耗与花费、给省钱信号、burn rate/额度预测。
非目标:云端同步/多机聚合、团队 per-user 账单、与厂商官方账单分毫一致、Copilot 企业数据、思考 token 分离。

## 2. 数据源与工具支持
全部本地读取,离线计价(复用 PricingTable)。归一化到统一 `UsageEvent`。

| 工具 | 期次 | 数据源 | 说明 |
|---|---|---|---|
| Claude Code | 已上线 | `~/.claude/projects/**/*.jsonl` | 复用现有 UsageScanner |
| Codex CLI | 一期 | `~/.codex/sessions/**/*.jsonl` | 取每会话末条 `total_token_usage`,勿逐行求和;字段:input/cached_input/output/reasoning tokens、turn_context.model、session_meta.cwd/git、顶层 timestamp |
| Cursor | 二期 | `state.vscdb`(SQLite,cursorDiskKV 表 bubble 的 tokenCount) | 只读快照/复制后读;无官方成本→标注"本地估算";composerData.modelName 取模型 |
| Roo Code | 二期 | task history 文件 | 字段最全(含 totalCost+缓存+workspace);有历史才有数据 |
| Gemini CLI | 不支持 | — | 默认不落盘,需 OTEL 遥测 |
| GitHub Copilot | 不支持 | — | 本地无 per-request token,仅企业 Metrics API |

**口径坑**:成本不在文件里,按 token×分模型分类型单价算;订阅用户美元是名义值,真实约束是 5h 块额度,两口径不混。

## 3. 筛选维度
- P0(一期):时间(24h/今日/7天/30天/自定义)、工具、项目(cwd)、模型、token 类型(输入/输出/缓存写/缓存读)、会话·5h 块
- P1(二期):时段(小时×星期热力图)
- P2(三期):git 分支/子目录、工具调用(Bash/Read/Edit/MCP)

## 4. 展示指标
总成本(¥/$,含环比 delta)、总 token 四类拆分、缓存命中率 %+已省额、burn rate($/h 或 token/min)、预测(本月预估/5h 块耗尽 ETA)、额度使用率 %、每会话均成本+最贵会话 Top N、上下文体量(每请求均/P95 输入 token)。

## 5. 功能需求
- FR-1 筛选器栏(时间分段 + 工具/项目/模型多选,联动)
- FR-2 概览卡(大字成本+环比;token 四类;缓存命中;调用数;弹簧动画)
- FR-3 趋势图(折线/堆叠面积,可切"按模型/按 token 类型"堆叠)
- FR-4 模型拆分(甜甜圈/堆叠条 + 可排序明细表)
- FR-5 项目/工具拆分(条形排名,点击下钻)
- FR-6 缓存分析(命中率趋势+目标线、已省额、缓存浪费提示)
- FR-7 burn rate 与额度(5h 块进度环 + 燃烧率 + 耗尽 ETA;可选月度预算超阈告警)
- FR-8 Top N 最贵会话表
- FR-9 时段热力图(P1)
- FR-10 菜单栏摘要(今日成本,点击直达)
- FR-11 显示设置(见 §6)

## 6. 显示设置(用户追加需求,@AppStorage 全局持久化)
| 设置项 | 选项 | 默认 |
|---|---|---|
| Token 计量单位 | 中文单位(万/百万/千万/亿)· 国际(K/M/B)· 自动 | 中文单位 |
| 货币 | ¥ 人民币 · $ 美金 | ¥ 人民币 |
| 汇率 USD→CNY | 可编辑(默认≈7.2)· 可选联网自动 | 7.2/自动 |

示例:12,345,678 token → 中文单位「1234.6 万」;123,456,789 → 「1.23 亿」。$8.50 → ¥61.2(7.2 汇率)。
落地:扩展 `ByteFormat.tokens()` 支持中文模式;抽象读全局设置的货币格式化函数替换写死的 `$`。

## 7. UI/UX(用户追加需求)
符合 macOS 最新设计(Tahoe/Liquid Glass),含微交互/微动效。
**工具链约束(已确认):**本机仅 CLT(SDK 15.2),无 Xcode,真 Liquid Glass API(`.glassEffect()`,macOS 26 SDK)编译不了。**已定:用 SDK 15 SwiftUI 逼近**(视觉约 8 成);100% 保真需装 Xcode 26+。
- 视觉:`.regularMaterial`/`.ultraThinMaterial` 玻璃背景+模糊、大圆角卡片、SF 字体、语义色与强调色分离、明暗双主题、概览在前明细在后。
- 微动效:`.spring` 数值动画、`matchedGeometryEffect` 转场、图表入场淡入生长、hover 高亮、按压缩放、平滑加载;尊重 reduce-motion。
- 信息架构:清理已并入「系统」tab;「AI 用量」升级为 Token 监控台(筛选器→概览→趋势→拆分→缓存→burn rate/额度→Top N,齿轮进设置)。

## 8. 技术方案
- 采集层:每工具一个 `UsageSource`(scanAll→[UsageEvent]);ClaudeCodeSource(已有)、CodexSource(新)、CursorSource/RooSource(二期);增量缓存(size+mtime)+ 跨文件去重沿用现有模式。
- 模型层:统一 `UsageEvent`(工具·时间·模型·四类 token·项目·会话·可选成本);`UsageAggregator` 纯函数按筛选条件出各视图数据。
- 计价:复用 PricingTable(含缓存 1h/5m 分档 + 200K 分层);补 gpt-5.x-codex 价目。
- 去重:Claude 用 messageId:requestId;Codex 取会话末条 total_token_usage;各源各自防重再合并。
- 格式化:统一 NumberFormatting(token 单位 + 货币 + 汇率,读 @AppStorage)。
- 刷新:沿用 UsageStore 60s 后台扫描 + 在途保护;筛选变更即时内存重聚合不重扫。
- 性能:冷启动全量解析后常驻内存事件表(90 天窗口),切维度秒开。

## 9. 分期
- 一期:Codex 采集 + 统一模型/聚合器 + 核心筛选维度 + 概览/趋势/模型拆分/缓存/burn rate/Top N + 显示设置 + 玻璃视觉与微动效第一轮
- 二期:Cursor + Roo 采集 + 时段热力图 + git 分支维度 + 月度预算告警 + 导出
- 三期:每千行/每会话成本 + 工具调用维度 + 计费模式切换 + 自定义标签

## 10. 验收
时间段切换秒级联动;Claude+Codex 总成本与 ccusage 口径交叉验证;各维度拆分之和=总量;缓存/burn rate/5h 块口径对齐 ccusage 与官方 /cost;单位货币切换全局即时生效;玻璃+微动效明暗主题正常且尊重 reduce-motion;资源占用不显著升高。
