# Mac监控器(MacPulse)

一款面向 Apple Silicon 与 macOS 14+的菜单栏工具:系统监控 + AI 编程助手的用量/费用/额度监控,
灵感来自 SystemPal,架构参考开源项目 [exelban/stats](https://github.com/exelban/stats) 与 [ccusage](https://github.com/ryoppippi/ccusage)。

> 当前为免费公开 Beta 0.9.0，中文优先，MIT 开源。官网:
> [macpulse-monitor.peaceaii.chatgpt.site](https://macpulse-monitor.peaceaii.chatgpt.site)。
> 使用前请阅读 [隐私说明](PRIVACY.md)；暂不支持 Intel Mac 和 Mac App Store。

## 功能总览

**菜单栏常驻**:`C12 M85 ¥52` —— CPU 使用率 / 内存使用率 / 今日 AI API 等价预估,2 秒刷新;
可选追加最紧张的额度(`◔78%` 已用 + 重置倒计时)。

**弹窗两种模式**(右上角一键切换)
- **简单模式**(默认):不出现 token/burn rate 等术语,用大白话回答三个问题——
  额度还能用多久 / 今天会不会超支 / 电脑扛得住吗。
- **专业模式**:系统 / AI 用量 / Skills 三个页签,细节全量展开。

**三套 UI 主题**(设置菜单切换,覆盖弹窗、监控台、灵动岛全部界面)
- **经典**:系统原生风,控件一律走系统原生。
- **HUD**(默认):俄式影视包装 / FUI 风——深空底 + 示波青 + 中英双层代号 + 切角面板 + 四角取景框。
- **LED**:复古健身器材仪表风——近黑底 + LED 点阵 + 七段数码管大读数(Canvas 真绘制,含残影)+
  圆点灯珠电平条;单色琥珀亮度阶梯,多系列靠亮度区分。
- 微交互全套:开机充能、扫描线、页签滑动、按钮 hover 辉光、鼠标跟随扫光(`SweepEffects`),
  全部尊重 `accessibilityReduceMotion`。

**系统页签**
- CPU:总使用率 + 系统/用户拆分 + 60 点实时折线图 + CPU 温度
- 内存:已用/总量、联动/已压缩、压力配色进度条
- 网络/磁盘:实时收发与读写速率
- 传感器:CPU/GPU 温度(SMC Tp*/Tg* 键)、双风扇转速(F0Ac/F1Ac)
- 电池健康:健康度/循环次数/温度/充电状态(IOKit AppleSmartBattery)
- 进程 Top 6 按 CPU 排序;含清理与内存回收(见下)

**清理与内存回收**(删文件,安全第一)
- 磁盘空间进度条 + 一键回收内存:免 root 的有界方案(mmap 申请并释放促使系统回收非活跃内存),
  上限 = min(3GB, 空闲一半),诚实显示回收量;真想腾内存优先结束应用(内存 Top 进程一键 SIGTERM,先弹确认)
- 垃圾清理:安全白名单只清可再生缓存——废纸篓 / 应用缓存(~/Library/Caches)/ 系统日志 /
  开发者缓存(npm _cacache、Xcode 派生数据),扫描后按类目勾选
- **绝不触碰**:文档/桌面/下载、偏好设置、Application Support、pnpm store、SSH/iCloud 等——
  三重路径守卫(在 home 下 + 归属白名单根 + 不命中保护目录),经 23 条生产守卫用例 + 符号链接/假 Home 端到端测试验证
- 本机实测可清理约 13GB,并行扫描 ~1.3 秒

**AI 用量页签**(双数据源,逻辑对齐 ccusage v18)
- 数据源:Claude Code(`~/.claude/projects` 会话 JSONL)+ Codex CLI(`~/.codex/sessions` rollout JSONL,
  按 `last_token_usage` 增量计数,经本机 190M token 实测校准)
- 今日 API 等价预估(非订阅实际扣款)+ token 构成 + 调用次数;近 1 小时燃烧率 / 本月已用 / 整月外推预估
- 近 7 天费用柱状图 + 本月按模型明细
- 去重:跨文件 `messageId:requestId` 全局去重,文件按最早时间戳排序;
  流式多行快照取组内最大 output(比 ccusage v18 的 keep-first 更准,实测它少算 ~30% output)
- 计价:内置 2026-07-06 双源验证价格表(LiteLLM + Anthropic 官方页),区分 5m/1h 缓存写入、
  读取 0.1x、200K 分层价、fast 模式倍率;JSONL 自带 costUSD 时优先采用

**额度中心**(菜单栏/简单模式/灵动岛共用)
- Claude:OAuth 端点,权威、实时(5 分钟一刷防 429)
- Codex:rollout 文件解析,截至上次会话(90 秒一刷)
- 额度重置自动探测 → 刘海提醒「满血复活」;快用完也会提醒(每周期一次防重复)

**Skills 管理页签**
- 列出本机各 AI 工具已装的 skills,支持安装 / 卸载 / 跨工具复制
- 安装对齐开源生态(skills.sh):支持 `owner/repo`、子路径、完整 GitHub URL,
  单仓多 skill 自动发现并弹窗挑选
- 卸载比生态更安全:移入废纸篓(可恢复),不做 rm

**Token 监控台**(独立大窗口,760×560 起)
- 信息模式与视觉主题解耦:**一眼看懂**只保留决策信息;**分析模式**展开 Token 构成、模型和项目明细
- 顶部筛选时间/工具/项目/模型/Token 构成;项目与模型排行可点击下钻,选中态、占比和重置入口一致
- 首屏四项:筛选范围内的 API 等价预估(明确环比基准和绝对差额)、最紧张额度、固定近 1 小时速度、缓存复用率
- 自动洞察主要模型/项目/峰值时段;本月外推明确使用固定月度窗口,不会随顶部时间范围跳变
- 分析模式把“新增处理量 = 输入 + 输出 + 缓存写”与“缓存复用”分列,避免总 Token 与明细口径误解
- 数据状态显示刷新时间、Claude/Codex 来源覆盖、未知模型告警;隐私模式用稳定别名隐藏真实项目名
- 可选等价成本提醒(默认关闭),每小时/每日阈值可配置且按周期去重
- 跟随三主题,深色皮肤用自绘发光滚动条
- LED Canvas 数码读数提供完整辅助功能语义,VoiceOver 可读金额、额度、速度和缓存率

**灵动岛(刘海)**
- 平时完全隐藏,鼠标移到刘海 → 无缝长出黑色下拉面板(高度随内容自适应),移开自动收起
- 刘海强提醒 + Vibe 时刻:开工大吉(每天首次 AI 活动)/ 满血复活(额度重置)/
  喝口水(久坐关怀)/ 电脑体温(过热提醒),各自有防打扰节流,受总开关约束

**显示设置**
- Token 单位:中文单位(万/亿)或 K/M/B;货币:¥(可设汇率)/ $
- 主题切换、隐私模式、额度重置提醒、等价成本提醒阈值、菜单栏额度开关等

## 构建与运行

```bash
./scripts/build.sh 0.9.0 2  # 编译 + 打包 dist/MacPulse.app + ad-hoc 签名
./scripts/test.sh           # 生产代码回归测试(含清理安全守卫)
open dist/MacPulse.app      # 启动
```

真实 Claude/Codex 会话回归(只读本机 JSONL,显式开启):

```bash
MACPULSE_LIVE_TEST=1 swift test --filter CoreRegressionTests/testLiveAggregationInvariantsWhenRequested
```

**双版本约定**:日常从 `/Applications` 启动;每次 `build.sh` 之后要把 `dist/MacPulse.app`
拷贝覆盖 `/Applications`,否则桌面启动的仍是旧版(两版可同时运行,容易误判"改动没生效")。

本机 2026-07 起已装 Xcode 26.6(xcode-select 指向 Xcode,SDK MacOSX26)。

### 本机 CLT 残留说明(历史问题)

这台机器的 CLT 有两个旧版本残留文件,曾导致任何 `swift build` 失败。
`build.sh` 已内置无 sudo 的绕过方案(`.clt-fix/`,自动生成);残留文件存在时 workaround
仍会激活但无害。永久修复(二选一):

```bash
# 方案 A:精准删除两个残留文件
sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI/PackageDescription.swiftmodule/*.private.swiftinterface
sudo rm /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap

# 方案 B:重装 CLT
sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install
```

## 发布(GitHub Releases + 官网，不上 MAS)

```bash
./scripts/preflight-release.sh       # 当前源码 + 全部 Git 历史的发布闸门
./scripts/release.sh 0.9.0 2         # 版本号 + 单调递增构建号
SKIP_NOTARIZE=1 ./scripts/release.sh 0.9.0 2  # 本地干跑，绝不能公开分发
```

正式脚本会从内到外签名 Sparkle helper/framework 与主应用，开启 Hardened Runtime，
公证 App 与 DMG，然后产出 DMG、SHA-256、签名 appcast、发布说明和私下保留的 dSYM。
一次性前置(Developer ID、`macpulse-notary`、Sparkle 密钥备份)及完整上线顺序见
[`docs/发布指南.md`](docs/发布指南.md)。
不上 App Store 的原因:沙盒禁 SMC(温度/风扇)、清理功能需授权目录改造。

## 应用图标

唯一设计源是根目录 `logo icon.svg`(满 1024 出血、透明底、不画圆角);
`scripts/make-icon.swift` 用 WKWebView 渲染 SVG 再套 Apple 规范 squircle
(1024 画布 / 824 主体 / 半径 185.4 / continuous 连续曲率)生成 `Resources/AppIcon.icns`。
`build.sh` 检测到 svg 比 icns 新会自动重新生成——换图标只改 svg 即可。

## 登录自启(可选)

```bash
cat > ~/Library/LaunchAgents/com.liangheping.macpulse.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.liangheping.macpulse</string>
    <key>ProgramArguments</key>
    <array><string>/Applications/MacPulse.app/Contents/MacOS/MacPulse</string></array>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.liangheping.macpulse.plist
```

停用:`launchctl bootout gui/$(id -u)/com.liangheping.macpulse`

## 实测指标(M5 Pro,1.6GB 会话数据,2026-07-17)

- 最新回归:34,349 条事件冷扫描 + 聚合检查约 17.0 秒;热扫描(文件 size/mtime 缓存命中)约 0.16 秒
- 内存:安装版冷扫描完成物理占用 60.4MB,实测峰值 70.9MB(`vmmap -summary`)
- 实现:会话文件只读映射,避免把 1.6GB JSONL 反复拷进 malloc 脏页
- 今日费用与独立脚本重算误差 < 时间窗口内的自然增量

## 技术要点

- 纯 SwiftUI `MenuBarExtra`(.window 样式)+ Swift Charts,SPM 构建,无 Xcode 工程
- CPU/内存:`host_processor_info` / `host_statistics64`(Mach API)
- 网络:`getifaddrs` 增量;磁盘:IOKit `IOBlockStorageDriver` Statistics 增量
- 温度/风扇:AppleSMC IOKit 用户客户端(M5 上 `flt ` 小端 float32,
  温度键 Tp*/Te*/Tf*/Tg* 前缀筛选 + 合理区间过滤;无需 sudo、无需 entitlement)
- 主题系统:弹窗三套独立视图树(`UI/Classic` / `HUD*` / `UI/LED`),监控台与灵动岛在组件内按主题分支,
  共享逻辑只有一份;系统原生控件(分段/按钮)在深色主题下由 `ThemedControls` 自绘替代
- 刘海面板:NSPanel + 全局鼠标监听驱动(非激活浮层上 SwiftUI hover 不可靠),
  高度由内容测量上报(`NotchContentHeight` preference)
- 非沙盒(SMC 与 `~/.claude` 读取都不允许沙盒)；本地构建使用 ad-hoc，公开包使用 Developer ID + Apple 公证

## 文档索引

- `AGENTS.md` / `CLAUDE.md` —— 构建约定、架构红线与安全测试要求
- `docs/PRD.md`、`docs/追加需求.md` —— 产品需求
- `docs/发布指南.md` —— 发布一次性前置配置
- `PRIVACY.md`、`SECURITY.md`、`CONTRIBUTING.md` —— 公开隐私、安全与贡献政策
