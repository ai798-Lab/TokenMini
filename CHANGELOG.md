# Changelog

## 0.13.1 — 2026-09-23

- 移除 Prism AI 用量页重复的外观与监控台入口，保留统一外观和「打开完整的中控台」。
- 同步官网中英文下载入口、应用版本与签名更新信息至构建 22。

## 0.13.0 — 2026-09-23

- 菜单栏默认只显示品牌图标和今日 Token，采用三位有效数字；CPU、内存、费用和剩余额度可在外观设置中自行开启。
- 恢复标准 TokenMini 品牌组合与 Beta 标识，统一菜单栏页签宽度、内容对齐、一级与二级 Tab 的层级。
- 统一工具、项目、模型和 Token 多选筛选，改进搜索、选中状态、计数、外观设置、数据源、社区排行和维护页面的主题一致性。
- 恢复跟随鼠标的局部描边扫光，避免悬停时整个边框同时点亮。
- 改善趋势图稀疏刻度、跨天日期和时间明细，保留完整统计数据。
- 新增签名模型目录和自动重算；目录验证失败或离线时保留已验证的价格。未知模型继续标为未定价。
- 支持 GPT-6 Sol、GPT-6 Luna、Claude Opus 5.5 的精确模型计价和生效日期。
- Claude 额度实验默认关闭，凭证读取需用户主动开启确认。
- 更新提示收在菜单栏浮层中，支持查看说明、主动下载和跳过版本；后台检查不主动弹窗。

需要 Apple Silicon 与 macOS 14 或更新版本。费用为 API 等价估算，不是订阅实际扣款。社区排行的在线可用性取决于服务配置；本地监控无需账号。


## 0.11.0 — 2026-09-20

- Rebrand MacPulse as TokenMini; keep application identity, settings, callback and update-key compatibility.
- Adopt the selected four-slice logo across app icons, menu bar, native headers, website and repository.
- Rebuild tokenmini.cc around the approved editorial layout, layered mechanical hero and optional motion.
- Carry forward locally accepted 0.10.1 maintenance safety and usability fixes; include their regression tests.


本项目采用语义化版本号；构建号单独递增，用于 Sparkle 比较更新。

## [0.10.0] - 2026-08-29

### Added

- 可选 Google 登录；登录成功即以打码昵称加入 Token 与 API 等价费用周榜。
- 游客无需登录即可浏览公开榜单，且所有本地监控功能保持可用。
- 登录用户可查看个人名次、主动公开完整昵称、立即同步或退出并删除榜单数据。
- 轻量运营后台：排行榜成员、日活、次日/7 日/30 日留存、版本分布和异常用户隐藏。
- 官网公开榜单与独立隐私说明页。

### Fixed

- 菜单栏改为固定尺寸原生模板图，修复数值刷新时弹窗抖动、重新锚定或偶发裁切；额度明确显示“剩余”。
- Claude 额度后台刷新改为禁止交互，不再在启动或定时刷新时突然弹出钥匙串认证框；关闭功能后也不会被迟到请求重新写回。
- 补全 Claude Opus 5 的精确计价、缓存价与 fast 模式倍率，避免显示未知模型或漏算费用。

### Privacy and security

- 排行榜只同步上海时区每日 Token 总量、费用汇总、价格表版本和 App 版本。
- Google 会话保存在 macOS Keychain；服务端只保存哈希后的刷新凭据。
- 非管理员无法通过后台登录误加入榜单，后台登录不创建长期刷新凭据。

## [0.9.0] - 2026-07-17

### Added

- 首个免费公开 Beta，支持 Apple Silicon 与 macOS 14+。
- 系统、AI 用量、额度、Skills、清理、三主题与刘海提醒。
- 首次启动隐私说明，Claude 额度和通知均改为主动开启。
- Sparkle 2.9.4 应用内更新、EdDSA 签名 feed、Developer ID 公证发布链。
- MIT 许可证、公开隐私与安全政策、下载站与 CI。

### Known limitations

- 暂不支持 Intel Mac 与 Mac App Store。
- Claude 额度依赖实验性端点。
- 不同 M 系列芯片的温度与风扇键可用性可能不同。
