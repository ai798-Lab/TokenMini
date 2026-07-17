# MacPulse(Mac监控器)

Swift 菜单栏系统监控 app:系统指标(CPU/内存/网络/磁盘/温度/风扇)+ AI token 用量与费用预估(解析 ~/.claude/projects 与 ~/.codex/sessions 的会话 JSONL)。

## 构建

- 只用 `./scripts/build.sh`(编译 + 打包 dist/MacPulse.app + ad-hoc 签名),不要直接裸跑 `swift build`。
- 本机 CLT 损坏(两个旧版残留文件),build.sh 内置无 sudo workaround(`.clt-fix/`);永久修复方案见 README。2026-07 起本机已装 Xcode 26.6(xcode-select 指向 Xcode,SDK MacOSX26),workaround 段在 CLT 残留文件存在时仍会激活但无害。
- 目标 macOS 14+,Swift 5 语言模式(tools-version 5.10)。

## 发布(官网分发,不上 MAS)

- `./scripts/release.sh <版本> <递增构建号>`:构建 → Sparkle 嵌套签名 → Developer ID 签名(hardened runtime)→ notarytool 公证 → staple → DMG → 公证 DMG → 签名 appcast。一次性前置见 `docs/发布指南.md`。
- 不上 App Store 的原因:沙盒禁 SMC(温度/风扇)、清理功能需授权目录改造;如日后做 MAS 精简版,是独立目标。

## 架构约定

- 所有共享类型在 `Sources/MacPulse/Models.swift`,不要在模块文件里重复定义。
- 采样调度:`SystemMonitor`(2s 快 tick / 6s 慢 tick)与 `UsageStore`(60s)都是 @MainActor ObservableObject,实际采样在各自串行 GCD 队列上做,读取器(Reader/Scanner)的跨 tick 状态只允许在对应队列上访问。
- SMC:`flt ` 类型是小端 float32,ui16/ui32 是大端——别改反。M5 温度键前缀 Tp/Te/Tf(CPU)、Tg(GPU),风扇 F{i}Ac。
- AI 计价:PricingTable 是 2026-07-06 快照;Sonnet 5 介绍价 2026-08-31 到期后要把 2.00/10.00 改成 3.00/15.00(cacheW 3.75 / cacheR 0.30)。
- 去重语义对齐 ccusage v18:文件按最早时间戳升序,全局 Set 按 `messageId:requestId`,任一缺失不去重。
- 清理功能(删文件,安全第一):`CleanupScanner.isSafeToDelete` 三重守卫是防线,改动务必重跑沙盒测试(见下)。白名单只含可再生缓存,`protectedPaths` 绝不能放 home 本身(会用 hasPrefix 把 home 下全拒)。路径归一化必须纯词法(不能用 `NSString.standardizingPath`,它解析符号链接、对存在与否行为不一致)。枚举顶层项用 FileManager(不能用 `du -d 1`,只列子目录漏文件)。
- 内存回收(MemoryReleaser)用 mmap 申请+触碰+munmap,上限 min(3GB, 空闲一半);purge 需 root 不用。

## 清理安全测试(改 CleanupScanner 后必跑)

`/private/tmp/.../scratchpad/safety_test.swift`(23 条守卫用例)+ `e2e_test.swift`(假 home 端到端)。
核心不变量:危险路径(文档/偏好/pnpm store/SSH/iCloud/路径穿越/系统文件)必须全部拒删,合法缓存项可删,符号链接只删链接不碰目标。

## 验证

改动后:`./scripts/build.sh && open dist/MacPulse.app`,确认菜单栏出现 `C.. M.. $..` 标签;
AI 费用可用独立脚本重算对比(解析 JSONL 今日事件 × 价格表,误差应在分钟级自然增量内)。
